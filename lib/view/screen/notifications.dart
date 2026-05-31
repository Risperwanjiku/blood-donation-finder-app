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
        
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: AppText.heading.copyWith(
            color: AppColors.primary,
            fontSize: 18,
          ),
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
    final String rawTitle = (data['title'] ?? 'Notification').toString();
    final String body = (data['body'] ?? '').toString();
    final Timestamp? ts = data['created_at'] as Timestamp?;
    final String timeAgo = ts != null ? timeago.format(ts.toDate()) : '';
    final String? requestId = data['request_id'] as String?;
    final String urgency = (data['urgency'] as String?) ?? '';

    final String type = (data['type'] as String?) ??
        (requestId != null ? 'request' : 'general');

    final String title = rawTitle
        .replaceAll('🚨 ', '')
        .replaceAll('⚠️ ', '')
        .trim();

    late IconData icon;
    late Color iconColorActive;
    late Color iconBgActive;
    String? actionLabel;

    switch (type) {
      case 'request':
      case 'new_request':
        icon = Icons.bloodtype;
        iconColorActive = AppColors.primary;
        iconBgActive = AppColors.primarySoft;
        actionLabel =
            (urgency == 'critical') ? 'Respond now' : 'View details';
        break;
      case 'response':
        icon = Icons.favorite;
        iconColorActive = AppColors.success;
        iconBgActive = AppColors.successSoft;
        actionLabel = (requestId != null) ? 'View details' : null;
        break;
      case 'eligibility':
      case 'reminder':
        icon = Icons.event_available_outlined;
        iconColorActive = AppColors.textSecondary;
        iconBgActive = AppColors.disabled;
        break;
      case 'donation':
        icon = Icons.check_circle_outline;
        iconColorActive = AppColors.success;
        iconBgActive = AppColors.successSoft;
        break;
      default:
        icon = Icons.notifications_outlined;
        iconColorActive = AppColors.textSecondary;
        iconBgActive = AppColors.disabled;
        actionLabel = (requestId != null) ? 'View details' : null;
    }

    // ─── The single urgency signal: a bold left bar (critical/urgent only) ───
    Color? accent;
    if (urgency == 'critical') {
      accent = AppColors.critical;
    } else if (urgency == 'urgent') {
      accent = AppColors.warning;
    }

    final Color iconColor =
        isRead ? AppColors.textTertiary : iconColorActive;
    final Color iconBg = isRead ? AppColors.disabled : iconBgActive;
    final Color titleColor =
        isRead ? AppColors.textSecondary : AppColors.textPrimary;
    final FontWeight titleWeight =
        isRead ? FontWeight.w600 : FontWeight.w700;

    Widget titleWidget;
    final int colonIdx = title.indexOf(':');
    if (accent != null && colonIdx > 0) {
      final String prefix = title.substring(0, colonIdx + 1);
      final String rest = title.substring(colonIdx + 1);
      titleWidget = Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: prefix,
              style: AppText.bodyStrong.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            TextSpan(
              text: rest,
              style: AppText.bodyStrong.copyWith(
                color: titleColor,
                fontWeight: titleWeight,
              ),
            ),
          ],
        ),
      );
    } else {
      titleWidget = Text(
        title,
        style: AppText.bodyStrong.copyWith(
          color: titleColor,
          fontWeight: titleWeight,
        ),
      );
    }

    final Widget cardBody = Padding(
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
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
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
                        Expanded(child: titleWidget),
                        const SizedBox(width: AppSpace.sm),
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            timeAgo,
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: AppText.caption.copyWith(
                          color: isRead
                              ? AppColors.textTertiary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$actionLabel →',
                style: AppText.label.copyWith(
                  color: isRead
                      ? AppColors.textSecondary
                      : AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _open(doc.id, requestId),
            
            child: accent != null
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(width: 8, color: accent),
                        Expanded(child: cardBody),
                      ],
                    ),
                  )
                : cardBody,
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
              child: Icon(icon, size: 36, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              title,
              style: AppText.subheading,
              textAlign: TextAlign.center,
            ),
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