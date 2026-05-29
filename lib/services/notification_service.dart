import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

/// Handles FCM (Firebase Cloud Messaging) for DamuLink.
///
/// Responsibilities:
///   * Request notification permission on first run.
///   * Get the device's FCM token and store it at /users/{uid}.fcm_token
///     (which the server-side onBloodRequestCreated Cloud Function reads
///     when fanning out alerts to compatible donors).
///   * Refresh the stored token whenever Firebase rotates it.
///   * Show an in-app heads-up when a push arrives while the app is open.
///   * Route the user to the matching request when they tap a push.
///   * Clear the token from /users on sign-out (so the next person on
///     this device doesn't inherit alerts).
///
/// Deciding WHICH donors to notify is intentionally NOT done here. That
/// runs server-side in the onBloodRequestCreated Cloud Function, where:
///   * admin privileges allow writes to other users' /notifications,
///   * the privacy split is enforced (patient name stays in the private
///     companion doc and never enters the broadcast body),
///   * the donor's notifications_enabled flag can be respected, and
///   * the result is reliable even if the requester closes the app.
class NotificationService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> initialize() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional;

    if (!granted) {
      debugPrint('NotificationService: permission not granted');
      return;
    }

    await _saveTokenToFirestore();

    // Tokens rotate (OS updates, reinstalls, manual clears). Without this
    // listener, the stored token goes stale and pushes silently fail.
    _messaging.onTokenRefresh.listen(_updateTokenInFirestore);

    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);
  }

  Future<void> _saveTokenToFirestore() async {
    try {
      final token = await _messaging.getToken();
      if (token == null) {
        debugPrint('NotificationService: FCM returned a null token');
        return;
      }
      await _updateTokenInFirestore(token);
      debugPrint('NotificationService: token saved');
    } catch (e) {
      debugPrint('NotificationService: error saving token: $e');
    }
  }

  Future<void> _updateTokenInFirestore(String token) async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fcm_token': token,
      });
    } catch (e) {
      debugPrint('NotificationService: token update failed: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    Get.snackbar(
      notification.title ?? 'Blood Donation Alert',
      notification.body ?? 'Someone may need your help.',
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 5),
    );
  }

  void _handleNotificationTap(RemoteMessage message) {
    final requestId = message.data['request_id'];
    if (requestId != null && requestId.toString().isNotEmpty) {
      // Match the modernized route + arguments shape used by the
      // notifications screen and dashboard.
      Get.toNamed(
        '/requestDetails',
        arguments: {'requestId': requestId, 'fromBrowse': true},
      );
    } else {
      Get.toNamed('/notifications');
    }
  }

  /// Clears the FCM token from /users so this device stops being treated
  /// as the current user's notification target. Must be called BEFORE
  /// FirebaseAuth.signOut() — we need auth permission to write /users.
  Future<void> removeToken() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).update({
        'fcm_token': null,
      });
    } catch (e) {
      debugPrint('NotificationService: token clear failed: $e');
    }
  }
}