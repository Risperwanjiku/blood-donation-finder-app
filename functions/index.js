const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// Initialize Firebase Admin
initializeApp();

const db = getFirestore();
const messaging = getMessaging();

// Blood type compatibility chart - who can donate to whom
const bloodCompatibility = {
  "A+": ["A+", "A-", "O+", "O-"],
  "A-": ["A-", "O-"],
  "B+": ["B+", "B-", "O+", "O-"],
  "B-": ["B-", "O-"],
  "AB+": ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"], // Universal recipient
  "AB-": ["A-", "B-", "AB-", "O-"],
  "O+": ["O+", "O-"],
  "O-": ["O-"], // Universal donor
};

// This function triggers when a new blood request is created
exports.sendBloodRequestNotification = onDocumentCreated(
  "blood_requests/{requestId}",
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log("No data associated with the event");
      return;
    }

    const requestData = snapshot.data();
    const requestedBloodType = requestData.blood_type;
    const hospital = requestData.hospital;
    const patientName = requestData.patient_name;
    const urgency = requestData.urgency || "urgent";
    const requesterId = requestData.requester_id;

    console.log(`New blood request: ${requestedBloodType} at ${hospital}`);

    // Find compatible donor blood types
    const compatibleTypes = bloodCompatibility[requestedBloodType];
    if (!compatibleTypes) {
      console.log(`Unknown blood type: ${requestedBloodType}`);
      return;
    }

    console.log(`Compatible donor types: ${compatibleTypes.join(", ")}`);

    // Query users who can donate (matching blood type + available + has FCM token)
    // Firestore 'in' query supports max 10 values, so we're fine
    const usersSnapshot = await db
      .collection("users")
      .where("blood_type", "in", compatibleTypes)
      .where("is_available", "==", true)
      .get();

    if (usersSnapshot.empty) {
      console.log("No compatible donors found");
      return;
    }

    // Collect FCM tokens (exclude the requester)
    const tokens = [];
    usersSnapshot.forEach((doc) => {
      const userData = doc.data();
      if (userData.fcm_token && doc.id !== requesterId) {
        tokens.push(userData.fcm_token);
      }
    });

    if (tokens.length === 0) {
      console.log("No donors with FCM tokens found");
      return;
    }

    console.log(`Sending notifications to ${tokens.length} donors`);

    // Create notification message
    const message = {
      notification: {
        title: `🚨 Urgent: ${requestedBloodType} Blood Needed`,
        body: `${patientName} needs blood at ${hospital}. Can you help?`,
      },
      data: {
        requestId: event.params.requestId,
        bloodType: requestedBloodType,
        hospital: hospital,
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
      tokens: tokens,
    };

    // Send notifications
    try {
      const response = await messaging.sendEachForMulticast(message);
      console.log(
        `Successfully sent ${response.successCount} notifications, ${response.failureCount} failed`
      );

      // Log any failures
      if (response.failureCount > 0) {
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            console.log(`Failed to send to token ${idx}: ${resp.error}`);
          }
        });
      }
    } catch (error) {
      console.log("Error sending notifications:", error);
    }
  }
);