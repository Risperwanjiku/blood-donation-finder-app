/**
 * DamuLink Cloud Functions
 *
 * - placesAutocomplete: Google Places proxy
 * - onBloodRequestDeleted: cascade-delete related docs server-side
 * - onResponseCreated: atomically increment response_count
 * - onResponseDeleted: atomically decrement response_count
 * - onBloodRequestCreated: fan out notifications to compatible donors
 */

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const {
  onDocumentDeleted,
  onDocumentCreated,
} = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

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
// EXISTING: Cascade-delete on blood request deletion (unchanged)
// =============================================================

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

    const privateRef = db.collection("blood_request_private").doc(requestId);
    batch.delete(privateRef);
    opCount++;

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
// EXISTING: Auto-increment response_count (unchanged)
// =============================================================

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
// EXISTING: Auto-decrement response_count (unchanged)
// =============================================================

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

// =============================================================
// NEW: Fan out notifications to compatible donors on request creation
// =============================================================

/**
 * Blood-type compatibility map.
 * Key = recipient (patient) blood type.
 * Value = donor blood types that can give to that recipient.
 *
 * Mirrors lib/configs/blood_compatibility.dart so client and server
 * agree on who's eligible. The standard medical compatibility rules:
 *   - O- donors give to anyone (universal donor)
 *   - AB+ recipients receive from anyone (universal recipient)
 *   - Rh- recipients can only receive Rh- blood
 */
const COMPATIBLE_DONORS = {
  "A+":  ["A+", "A-", "O+", "O-"],
  "A-":  ["A-", "O-"],
  "B+":  ["B+", "B-", "O+", "O-"],
  "B-":  ["B-", "O-"],
  "AB+": ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"],
  "AB-": ["A-", "B-", "AB-", "O-"],
  "O+":  ["O+", "O-"],
  "O-":  ["O-"],
};

/**
 * Builds the public-safe title + body for a fan-out push.
 *
 * IMPORTANT — privacy contract:
 *   This function ONLY reads from /blood_requests (the public companion
 *   doc). It does NOT touch /blood_request_private. Patient name, full
 *   requester name, and contact phone live there and never enter the
 *   broadcast. The body uses patient_initials (e.g. "D.M."), hospital,
 *   blood_type, and urgency — all of which the requester chose to make
 *   visible to donors when they posted.
 */
function buildNotificationContent(request) {
  const initials = request.patient_initials || "A patient";
  const hospital = request.hospital || "a hospital";
  const bloodType = request.blood_type;
  const urgency = request.urgency || "normal";

  let title;
  let body;
  if (urgency === "critical") {
    title = `🚨 Critical: ${bloodType} Blood Needed`;
    body = `${initials} at ${hospital} urgently needs ${bloodType} blood. Can you help?`;
  } else if (urgency === "urgent") {
    title = `⚠️ Urgent: ${bloodType} Blood Needed`;
    body = `${initials} at ${hospital} needs ${bloodType} blood. Can you help?`;
  } else {
    title = `${bloodType} Blood Needed`;
    body = `${initials} at ${hospital} needs ${bloodType} blood.`;
  }

  return { title, body };
}

/**
 * Fired when a /blood_requests/{requestId} document is created.
 *
 * Pipeline:
 *   1. Read the new request's blood_type, city, urgency, etc.
 *   2. Compute compatible donor blood types via COMPATIBLE_DONORS.
 *   3. Query /public_profiles for available donors in the same city
 *      with a compatible blood_type.
 *   4. For each donor, fetch /users/{uid} to read notifications_enabled
 *      and fcm_token. Skip donors who opted out or are the requester.
 *   5. Write a /notifications doc for each eligible donor (deterministic
 *      ID = `${requestId}_${donorUid}` so retries are idempotent).
 *   6. Send an FCM push to each donor that has a token.
 *
 * Privacy: title/body uses only public fields. PII stays in
 * blood_request_private and is only revealed when a donor offers to
 * help via the existing staged-reveal flow.
 */
exports.onBloodRequestCreated = onDocumentCreated(
  {
    document: "blood_requests/{requestId}",
    maxInstances: 10,
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const requestId = event.params.requestId;
    const request = snap.data();

    const bloodType = request.blood_type;
    const city = request.city;
    const requesterId = request.requester_id;

    // Required-field guard — fan-out can't proceed without these.
    if (!bloodType || !city) {
      logger.warn("[fan-out] request missing blood_type or city; skipping", {
        requestId,
        hasBloodType: !!bloodType,
        hasCity: !!city,
      });
      return;
    }

    const compatibleTypes = COMPATIBLE_DONORS[bloodType];
    if (!compatibleTypes || compatibleTypes.length === 0) {
      logger.warn("[fan-out] unknown blood_type; skipping", {
        requestId,
        bloodType,
      });
      return;
    }

    logger.info("[fan-out] starting", {
      requestId,
      bloodType,
      city,
      compatibleDonorTypes: compatibleTypes,
    });

    // ── 1. Find candidate donors in /public_profiles ──
    let candidateSnap;
    try {
      candidateSnap = await db
        .collection("public_profiles")
        .where("city", "==", city)
        .where("blood_type", "in", compatibleTypes)
        .where("is_available", "==", true)
        .get();
    } catch (err) {
      logger.error("[fan-out] candidate query failed", {
        requestId,
        error: err.message,
      });
      return;
    }

    if (candidateSnap.empty) {
      logger.info("[fan-out] no compatible donors in city", {
        requestId,
        city,
        compatibleDonorTypes: compatibleTypes,
      });
      return;
    }

    // ── 2. Fetch /users for each candidate in parallel to read
    //       notifications_enabled and fcm_token ──
    const candidateUids = candidateSnap.docs
      .map((d) => d.id)
      .filter((uid) => uid !== requesterId); // never notify the requester

    const userDocs = await Promise.all(
      candidateUids.map((uid) =>
        db
          .collection("users")
          .doc(uid)
          .get()
          .catch((err) => {
            logger.warn("[fan-out] user fetch failed", {
              requestId,
              uid,
              error: err.message,
            });
            return null;
          })
      )
    );

    // ── 3. Filter to eligible donors and collect (uid, fcmToken) ──
    const eligible = [];
    userDocs.forEach((userDoc) => {
      if (!userDoc || !userDoc.exists) return;
      const userData = userDoc.data();
      // Respect the donor's notification preference. Default ON if unset.
      if (userData.notifications_enabled === false) return;
      eligible.push({
        uid: userDoc.id,
        fcmToken: userData.fcm_token || null,
      });
    });

    if (eligible.length === 0) {
      logger.info("[fan-out] no eligible donors after filtering", {
        requestId,
      });
      return;
    }

    logger.info("[fan-out] eligible donors found", {
      requestId,
      count: eligible.length,
      withTokens: eligible.filter((e) => e.fcmToken).length,
    });

    // ── 4. Build the notification content (privacy-safe) ──
    const { title, body } = buildNotificationContent(request);

    // ── 5. Write notification docs in batches of 500 (Firestore limit).
    //       Deterministic IDs (`${requestId}_${uid}`) make this safe
    //       under function retries — a retry overwrites instead of
    //       duplicating. ──
    const BATCH_SIZE = 500;
    for (let i = 0; i < eligible.length; i += BATCH_SIZE) {
      const slice = eligible.slice(i, i + BATCH_SIZE);
      const batch = db.batch();
      slice.forEach(({ uid }) => {
        const notifRef = db
          .collection("notifications")
          .doc(`${requestId}_${uid}`);
        batch.set(notifRef, {
          recipient_id: uid,
          request_id: requestId,
          type: "request",
          urgency: request.urgency || "normal",
          title,
          body,
          read: false,
          created_at: admin.firestore.FieldValue.serverTimestamp(),
        });
      });
      try {
        await batch.commit();
      } catch (err) {
        logger.error("[fan-out] notification batch commit failed", {
          requestId,
          batchStart: i,
          error: err.message,
        });
      }
    }

    // ── 6. Send FCM pushes for donors that have a token ──
    const tokenized = eligible.filter((e) => e.fcmToken);

    if (tokenized.length === 0) {
      logger.info("[fan-out] complete (in-app notifications only)", {
        requestId,
        notificationDocsWritten: eligible.length,
      });
      return;
    }

    const messagePayloadBase = {
      notification: { title, body },
      data: {
        request_id: requestId,
        type: "request",
        urgency: request.urgency || "normal",
      },
      android: {
        // 'high' bypasses Android battery optimizations for emergencies.
        priority: request.urgency === "critical" ? "high" : "normal",
      },
    };

    const pushResults = await Promise.all(
      tokenized.map(({ fcmToken }) =>
        admin
          .messaging()
          .send({ ...messagePayloadBase, token: fcmToken })
          .then(() => ({ ok: true }))
          .catch((err) => {
            logger.warn("[fan-out] push failed for one token", {
              requestId,
              code: err.code,
              error: err.message,
            });
            return { ok: false };
          })
      )
    );

    const pushSuccess = pushResults.filter((r) => r.ok).length;
    const pushFailure = pushResults.length - pushSuccess;

    logger.info("[fan-out] complete", {
      requestId,
      notificationDocsWritten: eligible.length,
      pushSuccess,
      pushFailure,
    });
  }
);