/**
 * DamuLink Cloud Functions
 *
 * - placesAutocomplete: Google Places proxy (kept as-is from your existing code)
 * - onBloodRequestDeleted: cascade-delete related docs server-side
 * - onResponseCreated: atomically increment response_count
 * - onResponseDeleted: atomically decrement response_count
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { onDocumentDeleted, onDocumentCreated } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

// Initialize the admin SDK once
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// =============================================================
// EXISTING: placesAutocomplete (unchanged)
// =============================================================

const GOOGLE_PLACES_API_KEY = defineSecret("GOOGLE_PLACES_API_KEY");

exports.placesAutocomplete = onCall(
  {
    secrets: [GOOGLE_PLACES_API_KEY],
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "You must be signed in to search hospitals."
      );
    }

    const input = (request.data?.input || "").toString().trim();

    if (input.length < 2) {
      return { suggestions: [] };
    }

    if (input.length > 100) {
      throw new HttpsError(
        "invalid-argument",
        "Search term is too long."
      );
    }

    try {
      const response = await fetch(
        "https://places.googleapis.com/v1/places:autocomplete",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Goog-Api-Key": GOOGLE_PLACES_API_KEY.value(),
            "X-Goog-FieldMask":
              "suggestions.placePrediction.placeId," +
              "suggestions.placePrediction.structuredFormat",
          },
          body: JSON.stringify({
            input: input,
            includedRegionCodes: ["KE"],
            includedPrimaryTypes: ["hospital"],
          }),
        }
      );

      if (!response.ok) {
        const errorBody = await response.text();
        logger.error("Places API returned non-OK status", {
          status: response.status,
          body: errorBody,
          uid: request.auth.uid,
        });
        throw new HttpsError(
          "internal",
          "Hospital search is temporarily unavailable. Please try again."
        );
      }

      const data = await response.json();

      logger.info("placesAutocomplete success", {
        uid: request.auth.uid,
        inputLength: input.length,
        suggestionsReturned: (data.suggestions || []).length,
      });

      return { suggestions: data.suggestions || [] };
    } catch (error) {
      if (error instanceof HttpsError) throw error;

      logger.error("Unexpected error in placesAutocomplete", {
        message: error.message,
        stack: error.stack,
        uid: request.auth?.uid,
      });

      throw new HttpsError(
        "internal",
        "Something went wrong. Please try again."
      );
    }
  }
);

// =============================================================
// NEW: Cascade-delete on blood request deletion
// =============================================================

/**
 * Fired when a /blood_requests/{requestId} document is deleted.
 * Cleans up the private companion doc, all responses, and all
 * notifications associated with that request.
 *
 * This is the FIX for "delete doesn't work" — clients cannot delete
 * /responses or /notifications (per Firestore rules), so cascading
 * deletes must happen server-side with admin privileges.
 */
exports.onBloodRequestDeleted = onDocumentDeleted(
  {
    document: "blood_requests/{requestId}",
    maxInstances: 10,
  },
  async (event) => {
    const requestId = event.params.requestId;
    logger.info(`[cascade-delete] starting for request=${requestId}`);

    const batch = db.batch();
    let opCount = 0;

    // 1. Delete the private companion doc
    const privateRef = db.collection("blood_request_private").doc(requestId);
    batch.delete(privateRef);
    opCount++;

    // 2. Delete all responses for this request
    try {
      const responses = await db
        .collection("responses")
        .where("request_id", "==", requestId)
        .get();
      responses.forEach((doc) => {
        batch.delete(doc.ref);
        opCount++;
      });
    } catch (err) {
      logger.error("[cascade-delete] responses query failed", {
        requestId,
        error: err.message,
      });
    }

    // 3. Delete all notifications for this request
    try {
      const notifications = await db
        .collection("notifications")
        .where("request_id", "==", requestId)
        .get();
      notifications.forEach((doc) => {
        batch.delete(doc.ref);
        opCount++;
      });
    } catch (err) {
      logger.error("[cascade-delete] notifications query failed", {
        requestId,
        error: err.message,
      });
    }

    // Firestore batch limit is 500 ops. Warn if approaching.
    if (opCount > 500) {
      logger.warn(
        `[cascade-delete] op count ${opCount} exceeds batch limit; some cleanup skipped`,
        { requestId, opCount }
      );
    }

    try {
      await batch.commit();
      logger.info(`[cascade-delete] complete`, { requestId, opCount });
    } catch (err) {
      logger.error("[cascade-delete] commit failed", {
        requestId,
        error: err.message,
      });
    }
  }
);

// =============================================================
// NEW: Auto-increment response_count on response creation
// =============================================================

/**
 * Fired when a donor offers to help (creates a /responses/{id} doc).
 * Atomically increments the parent request's response_count using
 * FieldValue.increment, which is safe under concurrent writes.
 *
 * This is the trusted source for the "View responses (N)" counter.
 * Clients are blocked from writing this field directly (see firestore.rules).
 */
exports.onResponseCreated = onDocumentCreated(
  {
    document: "responses/{responseId}",
    maxInstances: 10,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const response = snap.data();
    const requestId = response?.request_id;

    if (!requestId) {
      logger.warn(`[response-count] missing request_id`, {
        responseId: event.params.responseId,
      });
      return;
    }

    try {
      await db.collection("blood_requests").doc(requestId).update({
        response_count: admin.firestore.FieldValue.increment(1),
        last_response_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      logger.info(`[response-count] +1`, {
        requestId,
        responseId: event.params.responseId,
      });
    } catch (err) {
      logger.error(`[response-count] increment failed`, {
        requestId,
        error: err.message,
      });
    }
  }
);

// =============================================================
// NEW: Auto-decrement response_count on response deletion
// =============================================================

/**
 * Fired when a /responses/{id} doc is deleted (either by withdrawal
 * or by cascade-delete from the parent request being deleted).
 * Decrements response_count, with safety checks:
 *   - Skips if parent request is already deleted (cascade scenario)
 *   - Skips if count is already 0 (defensive)
 */
exports.onResponseDeleted = onDocumentDeleted(
  {
    document: "responses/{responseId}",
    maxInstances: 10,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const response = snap.data();
    const requestId = response?.request_id;

    if (!requestId) return;

    try {
      const reqDoc = await db.collection("blood_requests").doc(requestId).get();

      if (!reqDoc.exists) {
        logger.info(`[response-count] parent already deleted; skipping`, {
          requestId,
        });
        return;
      }

      const currentCount = reqDoc.data()?.response_count || 0;
      if (currentCount <= 0) {
        logger.info(`[response-count] count already 0; skipping`, {
          requestId,
        });
        return;
      }

      await db.collection("blood_requests").doc(requestId).update({
        response_count: admin.firestore.FieldValue.increment(-1),
      });
      logger.info(`[response-count] -1`, { requestId });
    } catch (err) {
      logger.error(`[response-count] decrement failed`, {
        requestId,
        error: err.message,
      });
    }
  }
);