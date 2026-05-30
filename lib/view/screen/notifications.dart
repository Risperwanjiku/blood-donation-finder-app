import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:damulink/configs/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _firestore
          .collection('notifications')
          .doc(notificationId)
          .update({'read': true});
    } catch (_) {
      // Non-critical — the unread badge will simply update on next load.
    }
  }

  Future<void> _markAllAsRead(String uid) async {
    try {
      final unread = await _firestore
          .collection('notifications')
          .where('recipient_id', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) return;

      final batch = _firestore.batch();
      for (final d in unread.docs) {
        batch.update(d.reference, {'read': true});
      }
      await batch.commit();
    } catch (_) {
      // Ignore — list will reflect actual state on next snapshot.
    }
  }

  // Opens the related request (if any) and marks the notification read.
  void _open(String docId, String? requestId) {
    _markAsRead(docId);
    if (requestId != null && requestId.isNotEmpty) {
      Get.toNamed('/requestDetails', arguments: {
        'requestId': requestId,
        'fromBrowse': true,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          // Native Navigator pop avoids a GetX bug where Get.back() tries
          // to close a non-existent snackbar overlay and crashes.
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style:
              AppText.heading.copyWith(color: AppColors.primary, fontSize: 18),
        ),
        actions: [
          if (user != null)
            TextButton(
              onPressed: () => _markAllAsRead(user.uid),
              child: Text(
                'Mark all read',
                style: AppText.label.copyWith(color: AppColors.primary),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: user == null
          ? _centeredMessage(
              icon: Icons.lock_outline,
              title: 'Please sign in',
              subtitle: 'Sign in to view your notifications.',
            )
          : StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('notifications')
                  .where('recipient_id', isEqualTo: user.uid)
                  .orderBy('created_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child:
                        CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                if (snapshot.hasError) {
                  return _centeredMessage(
                    icon: Icons.error_outline,
                    title: "Couldn't load notifications",
                    subtitle: 'Please check your connection and try again.',
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return _centeredMessage(
                    icon: Icons.notifications_off_outlined,
                    title: 'No notifications yet',
                    subtitle:
                        "We'll alert you when someone needs blood you can give.",
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  itemCount: docs.length,
                  itemBuilder: (context, index) =>
                      _buildNotificationCard(docs[index]),
                );
              },
            ),
    );
  }

  Widget _buildNotificationCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    final bool isRead = data['read'] ?? false;
    final String title = (data['title'] ?? 'Notification').toString();
    final String body = (data['body'] ?? '').toString();
    final Timestamp? ts = data['created_at'] as Timestamp?;
    final String timeAgo = ts != null ? timeago.format(ts.toDate()) : '';
    final String? requestId = data['request_id'] as String?;
    final String urgency = (data['urgency'] as String?) ?? '';

    // type drives the icon/colour. If absent, infer from whether the
    // notification links to a request. Your fan-out should set 'type'
    // (and 'urgency') explicitly.
    final String type = (data['type'] as String?) ??
        (requestId != null ? 'request' : 'general');

    // ─── Visual mapping per type ───
    late IconData icon;
    late Color iconColor;
    late Color iconBg;
    Color? accent; // left priority strip (null = none)
    String? actionLabel; // null = no button

    switch (type) {
      case 'request':
      case 'new_request':
        icon = Icons.bloodtype;
        iconColor = AppColors.primary;
        iconBg = AppColors.primarySoft;
        if (urgency == 'critical') {
          accent = AppColors.critical;
          actionLabel = 'Respond Now';
        } else if (urgency == 'urgent') {
          accent = AppColors.warning;
          actionLabel = 'View Details';
        } else {
          actionLabel = 'View Details';
        }
        break;
      case 'response':
        icon = Icons.favorite;
        iconColor = AppColors.success;
        iconBg = AppColors.successSoft;
        actionLabel = (requestId != null) ? 'View Details' : null;
        break;
      case 'eligibility':
      case 'reminder':
        icon = Icons.event_available_outlined;
        iconColor = AppColors.textSecondary;
        iconBg = AppColors.disabled;
        break;
      case 'donation':
        icon = Icons.check_circle_outline;
        iconColor = AppColors.success;
        iconBg = AppColors.successSoft;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColor = AppColors.textSecondary;
        iconBg = AppColors.disabled;
        actionLabel = (requestId != null) ? 'View Details' : null;
    }

    final Color cardBg = isRead ? AppColors.surface : AppColors.primarySoft;

    final Widget content = Container(
      color: cardBg,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration:
                    BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppText.bodyStrong.copyWith(
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        Text(
                          timeAgo,
                          style: AppText.caption.copyWith(
                            color: AppColors.textTertiary,
                            fontSize: 11,
                          ),
                        ),
                        if (!isRead) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(body, style: AppText.caption),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpace.md),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: actionLabel == 'Respond Now'
                  ? ElevatedButton(
                      onPressed: () => _open(doc.id, requestId),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: Text(actionLabel,
                          style: AppText.button.copyWith(fontSize: 14)),
                    )
                  : OutlinedButton(
                      onPressed: () => _open(doc.id, requestId),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      child: Text(
                        actionLabel,
                        style: AppText.button
                            .copyWith(fontSize: 14, color: AppColors.primary),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(doc.id, requestId),
            // IntrinsicHeight gives the Row a bounded height (the tallest
            // child's natural height) so CrossAxisAlignment.stretch can
            // size the left priority strip. Without this wrapper, the Row
            // inherits the ListView's unbounded vertical constraints and
            // the stretch demand resolves to infinity → render crash.
            child: accent != null
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 4, color: accent),
                        Expanded(child: content),
                      ],
                    ),
                  )
                : content,
          ),
        ),
      ),
    );
  }

  Widget _centeredMessage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(icon, size: 36, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpace.md),
            Text(title, style: AppText.subheading, textAlign: TextAlign.center),
            const SizedBox(height: AppSpace.xs),
            Text(
              subtitle,
              style: AppText.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}