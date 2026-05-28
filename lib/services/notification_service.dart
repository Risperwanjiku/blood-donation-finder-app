import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Blood type compatibility - who can DONATE to whom
  static const Map<String, List<String>> bloodCompatibility = {
    "A+": ["A+", "A-", "O+", "O-"],
    "A-": ["A-", "O-"],
    "B+": ["B+", "B-", "O+", "O-"],
    "B-": ["B-", "O-"],
    "AB+": ["A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"],
    "AB-": ["A-", "B-", "AB-", "O-"],
    "O+": ["O+", "O-"],
    "O-": ["O-"],
  };

  // Initialize notifications
  Future<void> initialize() async {
    NotificationSettings settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('User granted notification permission');

      await _saveTokenToFirestore();

      _messaging.onTokenRefresh.listen((newToken) {
        _updateTokenInFirestore(newToken);
      });

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _handleForegroundMessage(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleNotificationTap(message);
      });

    } else {
      print('User declined notification permission');
    }
  }

  Future<void> _saveTokenToFirestore() async {
    try {
      String? token = await _messaging.getToken();
      print('=== FCM TOKEN: $token ===');

      if (token != null) {
        await _updateTokenInFirestore(token);
        print('=== TOKEN SAVED TO FIRESTORE ===');
      } else {
        print('=== FCM TOKEN IS NULL — token could not be generated ===');
      }
    } catch (e, stackTrace) {
      print('=== ERROR SAVING FCM TOKEN: $e ===');
      print('Stack trace: $stackTrace');
    }
  }

  Future<void> _updateTokenInFirestore(String token) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcm_token': token,
      });
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('Received foreground message: ${message.notification?.title}');

    if (message.notification != null) {
      Get.snackbar(
        message.notification!.title ?? 'Blood Donation Alert',
        message.notification!.body ?? 'Someone needs blood!',
        duration: Duration(seconds: 5),
      );
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    print('Notification tapped: ${message.data}');

    // Check if there's a request_id in the notification data
    String? requestId = message.data['request_id'];
    if (requestId != null) {
      Get.toNamed('/request-details', arguments: requestId);
    } else {
      Get.toNamed('/notifications');
    }
  }

  Future<void> removeToken() async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'fcm_token': null,
      });
    }
  }

  // Send notifications to compatible donors when a blood request is created
  Future<void> notifyCompatibleDonors({
    required String requestId,
    required String bloodType,
    required String hospital,
    required String patientName,
    required String requesterId,
  }) async {
    try {
      // Get compatible donor blood types
      List<String>? compatibleTypes = bloodCompatibility[bloodType];
      if (compatibleTypes == null) {
        print('Unknown blood type: $bloodType');
        return;
      }

      print('Finding donors with blood types: $compatibleTypes');

      // Query compatible donors who are available
      QuerySnapshot usersSnapshot = await _firestore
          .collection('users')
          .where('blood_type', whereIn: compatibleTypes)
          .where('is_available', isEqualTo: true)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        print('No compatible donors found');
        return;
      }

      // Collect compatible donors (exclude the requester themselves).
      // Note: fcm_token is no longer required — donors without a token still
      // get the in-app notification. The token is only used for real push
      // delivery via Cloud Functions (Blaze plan), documented as the
      // production deployment path.
      List<Map<String, String?>> donors = [];
      for (var doc in usersSnapshot.docs) {
        Map<String, dynamic> userData = doc.data() as Map<String, dynamic>;
        if (doc.id != requesterId) {
          donors.add({
            'id': doc.id,
            'token': userData['fcm_token'], // may be null — that's OK
          });
        }
      }

      if (donors.isEmpty) {
        print('No compatible donors found (excluding requester)');
        return;
      }

      print('Creating in-app notifications for ${donors.length} compatible donors');

      // Create an in-app notification document for each donor.
      // If they have an fcm_token, it's included so a future Cloud Function
      // can pick it up and send a real push. Without a token, the donor still
      // sees the notification in their in-app list.
      for (var donor in donors) {
        await _sendPushNotification(
          token: donor['token'] ?? '',
          recipientId: donor['id']!,
          requestId: requestId,
          title: '🚨 Urgent: $bloodType Blood Needed',
          body: '$patientName needs blood at $hospital. Can you help?',
        );
      }

      print('In-app notifications created successfully');
    } catch (e) {
      print('Error notifying donors: $e');
    }
  }

  // Send push notification - store in Firestore with recipient info
  Future<void> _sendPushNotification({
    required String token,
    required String recipientId,
    required String requestId,
    required String title,
    required String body,
  }) async {
    try {
      await _firestore.collection('notifications').add({
        'token': token,
        'recipient_id': recipientId,
        'request_id': requestId,
        'title': title,
        'body': body,
        'created_at': FieldValue.serverTimestamp(),
        'read': false,
      });
    } catch (e) {
      print('Error sending notification: $e');
    }
  }
}