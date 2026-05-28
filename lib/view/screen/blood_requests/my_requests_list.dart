import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:damulink/configs/theme.dart';

class MyRequestsList extends StatefulWidget {
  const MyRequestsList({super.key});

  @override
  State<MyRequestsList> createState() => _MyRequestsListState();
}

class _MyRequestsListState extends State<MyRequestsList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  final Map<String, _CachedPrivate> _privateCache = {};
  static const Duration _cacheTTL = Duration(minutes: 5);

  static const int _streamLimit = 50;

  Stream<List<Map<String, dynamic>>> _requestsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _firestore
        .collection('blood_requests')
        .where('requester_id', isEqualTo: uid)
        .orderBy('created_at', descending: true)
        .limit(_streamLimit) // PERF: cap at 50 most recent
        .snapshots()
        .asyncMap((snapshot) async {
      final now = DateTime.now();
      final idsToFetch = <String>[];

      for (final doc in snapshot.docs) {
        final status =
            (doc.data()['status'] ?? 'pending').toString().toLowerCase();
        final cached = _privateCache[doc.id];

        final canSkipFulfilled =
            (status == 'fulfilled' || status == 'expired') && cached != null;

        final cacheValid = cached != null &&
            now.difference(cached.fetchedAt) < _cacheTTL;

        if (!canSkipFulfilled && !cacheValid) {
          idsToFetch.add(doc.id);
        }
      }

      // Fetch only what's needed, in parallel
      if (idsToFetch.isNotEmpty) {
        final futures = idsToFetch.map((id) async {
          try {
            final privateDoc = await _firestore
                .collection('blood_request_private')
                .doc(id)
                .get();
            _privateCache[id] = _CachedPrivate(
              data: privateDoc.exists
                  ? (privateDoc.data() ?? {})
                  : <String, dynamic>{},
              fetchedAt: now,
            );
          } catch (_) {
            _privateCache[id] = _CachedPrivate(
              data: <String, dynamic>{},
              fetchedAt: now,
            );
          }
        });
        await Future.wait(futures);
      }

      // Build merged list
      final merged = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final public = doc.data();
        final private =
            _privateCache[doc.id]?.data ?? const <String, dynamic>{};
        final createdAt = public['created_at'] as Timestamp?;

        merged.add({
          'id': doc.id,
          ...public,
          'patient_name':
              private['patient_name'] ?? public['patient_initials'],
          'contact_phone': private['contact_phone'],
          'requester_full_name': private['requester_full_name'],
          '_is_incomplete': _isIncompleteRequest(public, private),
          // PERF: precompute timeago string once per stream emission
          '_time_ago': createdAt != null
              ? timeago.format(createdAt.toDate())
              : 'just now',
        });
      }

      // Cache cleanup: drop entries for deleted docs (bound memory)
      final currentIds = snapshot.docs.map((d) => d.id).toSet();
      _privateCache.removeWhere((id, _) => !currentIds.contains(id));

      // Critical pending requests rise to the top
      merged.sort((a, b) {
        final aCritical = _isHighPriority(a);
        final bCritical = _isHighPriority(b);
        if (aCritical && !bCritical) return -1;
        if (!aCritical && bCritical) return 1;
        return 0;
      });

      return merged;
    });
  }

  bool _isIncompleteRequest(
    Map<String, dynamic> public,
    Map<String, dynamic> private,
  ) {
    final hasBloodType =
        (public['blood_type'] ?? '').toString().trim().isNotEmpty;
    final hasHospital =
        ((public['hospital'] ?? public['location']) ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    final hasPatientName =
        ((private['patient_name'] ?? public['patient_initials']) ?? '')
            .toString()
            .trim()
            .isNotEmpty;
    return !hasBloodType || !hasHospital || !hasPatientName;
  }

  bool _isHighPriority(Map<String, dynamic> request) {
    final urgency = (request['urgency'] ?? '').toString().toLowerCase();
    final status = (request['status'] ?? '').toString().toLowerCase();
    return urgency == 'critical' && status == 'pending';
  }

  // ─────────────────────────────────────────────────────────────
  // ACTIONS
  // ─────────────────────────────────────────────────────────────

  void _showMarkDoneDialog(Map<String, dynamic> request) {
    HapticFeedback.lightImpact();

    if (request['status']?.toString().toLowerCase() == 'fulfilled') {
      _showSnack('This request is already marked done', isError: false);
      return;
    }

    final patientName = request['patient_name'] ?? 'this patient';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: AppColors.success),
            SizedBox(width: AppSpace.sm),
            Text('Found a donor?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mark $patientName\'s request as done only if:',
              style: AppText.body,
            ),
            const SizedBox(height: AppSpace.sm),
            _buildBullet('A donor has been confirmed'),
            _buildBullet('Blood is no longer needed'),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Donors will stop seeing this request.',
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Not yet',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _markAsFulfilled(request);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: const Text(
              'Yes, mark done',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ',
              style:
                  AppText.body.copyWith(color: AppColors.textSecondary)),
          Expanded(
            child: Text(text,
                style:
                    AppText.body.copyWith(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _markAsFulfilled(Map<String, dynamic> request) async {
    final requestId = request['id'] as String;
    final previousStatus =
        (request['status'] ?? 'pending').toString();

    try {
      await _firestore.collection('blood_requests').doc(requestId).update({
        'status': 'fulfilled',
        'fulfilled_at': FieldValue.serverTimestamp(),
      });
      HapticFeedback.lightImpact();

      _showUndoSnack(
        message: 'Marked as done',
        onUndo: () => _undoMarkAsFulfilled(requestId, previousStatus),
      );
    } catch (_) {
      _showSnack('Could not update. Please check your connection.',
          isError: true);
    }
  }

  Future<void> _undoMarkAsFulfilled(
    String requestId,
    String previousStatus,
  ) async {
    try {
      await _firestore.collection('blood_requests').doc(requestId).update({
        'status': previousStatus,
        'fulfilled_at': FieldValue.delete(),
      });
      HapticFeedback.lightImpact();
      _showSnack('Mark done undone', isError: false);
    } catch (_) {
      _showSnack(
        'Could not undo. You can change status manually.',
        isError: true,
      );
    }
  }

  void _showDeleteDialog(Map<String, dynamic> request) {
    HapticFeedback.lightImpact();
    final patientName = request['patient_name'] ?? 'this patient';
    final isIncomplete = request['_is_incomplete'] == true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Row(
          children: const [
            Icon(Icons.delete_outline, color: AppColors.critical),
            SizedBox(width: AppSpace.sm),
            Text('Delete request?'),
          ],
        ),
        content: Text(
          isIncomplete
              ? 'This will permanently delete this incomplete request. '
                  'This cannot be undone.'
              : 'This will permanently delete $patientName\'s blood request '
                  'and all donor responses. This cannot be undone.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteRequest(request['id']);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.critical,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child:
                const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Delete the public doc only. The Cloud Function
  /// `onBloodRequestDeleted` cascades the rest server-side.
  Future<void> _deleteRequest(String requestId) async {
    try {
      _privateCache.remove(requestId);
      await _firestore
          .collection('blood_requests')
          .doc(requestId)
          .delete();
      HapticFeedback.mediumImpact();
      _showSnack('Request deleted', isError: false);
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _showSnack(
            'Permission denied. You can only delete your own requests.',
            isError: true);
      } else {
        _showSnack('Could not delete. Please check your connection.',
            isError: true);
      }
    } catch (_) {
      _showSnack('Could not delete. Please try again.', isError: true);
    }
  }

  void _viewResponses(Map<String, dynamic> request) {
    HapticFeedback.lightImpact();
    Get.toNamed('/responses', arguments: {
      'requestId': request['id'],
      'patientName': request['patient_name'] ?? 'Patient',
    });
  }

 void _openRequestDetails(Map<String, dynamic> request) {
  // For now, tapping a card on My Requests does nothing.
  // The card already shows all needed info (status, responses, mark done).
  // A dedicated requester details screen can be added later if needed.
  if (request['_is_incomplete'] == true) {
    _showSnack(
      'This request is incomplete. Please delete it and post a new one.',
      isError: true,
    );
    return;
  }
  HapticFeedback.selectionClick();
}

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.critical : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showUndoSnack({
    required String message,
    required VoidCallback onUndo,
  }) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: Colors.white, size: 20),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          textColor: Colors.white,
          onPressed: onUndo,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _requestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // PERF: Show skeleton instead of generic spinner
          return _buildSkeletonList();
        }

        if (snapshot.hasError) {
          return _buildErrorState();
        }

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
          return _buildEmptyState();
        }

        return RefreshIndicator(
          color: AppColors.primary,
          backgroundColor: AppColors.surface,
          onRefresh: () async {
            HapticFeedback.lightImpact();
            _privateCache.clear();
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              AppSpace.md,
              AppSpace.lg,
              120,
            ),
            itemCount: requests.length,
            // PERF: physics + cache helps scroll performance
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 600,
            itemBuilder: (context, index) {
              final request = requests[index];
              // PERF: ValueKey lets Flutter reuse widgets instead of rebuilding
              return _RequestCardWrapper(
                key: ValueKey(request['id']),
                request: request,
                onMarkDone: () => _showMarkDoneDialog(request),
                onDelete: () => _showDeleteDialog(request),
                onViewResponses: () => _viewResponses(request),
                onOpenDetails: () => _openRequestDetails(request),
              );
            },
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // SKELETON LOADER (perceived performance)
  // ─────────────────────────────────────────────────────────────

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.md,
        AppSpace.lg,
        120,
      ),
      itemCount: 3,
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // STATES
  // ─────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.water_drop_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              'You have no active requests',
              style: AppText.heading.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              "When you or someone you know needs blood,\npost a request and we'll notify nearby donors\nwith matching blood types instantly.",
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpace.xl),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.lightImpact();
                  Get.toNamed('/request-form');
                },
                icon: const Icon(Icons.add, color: Colors.white, size: 20),
                label: Text('Post a request', style: AppText.button),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.xl),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              "We couldn't load your requests",
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Check your internet connection and try again.',
              style:
                  AppText.caption.copyWith(color: AppColors.textTertiary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.lg),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {});
              },
              icon: const Icon(Icons.refresh,
                  size: 18, color: AppColors.primary),
              label: Text(
                'Try again',
                style: TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Cached private doc with timestamp for TTL expiry
class _CachedPrivate {
  final Map<String, dynamic> data;
  final DateTime fetchedAt;

  const _CachedPrivate({required this.data, required this.fetchedAt});
}

// ─────────────────────────────────────────────────────────────
// REQUEST CARD WIDGETS (extracted for PERF — only rebuilds when
// the specific request's data changes, not the whole list)
// ─────────────────────────────────────────────────────────────

class _RequestCardWrapper extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onMarkDone;
  final VoidCallback onDelete;
  final VoidCallback onViewResponses;
  final VoidCallback onOpenDetails;

  const _RequestCardWrapper({
    super.key,
    required this.request,
    required this.onMarkDone,
    required this.onDelete,
    required this.onViewResponses,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    if (request['_is_incomplete'] == true) {
      return _IncompleteCard(request: request, onDelete: onDelete);
    }
    return _NormalCard(
      request: request,
      onMarkDone: onMarkDone,
      onDelete: onDelete,
      onViewResponses: onViewResponses,
      onOpenDetails: onOpenDetails,
    );
  }
}

class _IncompleteCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onDelete;

  const _IncompleteCard({required this.request, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final timeAgoText = request['_time_ago'] as String? ?? 'unknown time';

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: AppColors.border.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.background,
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppColors.textTertiary, width: 1.5),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.help_outline,
                color: AppColors.textTertiary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Incomplete request',
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Missing details from $timeAgoText. This request is not '
                    'visible to donors.',
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),
                  GestureDetector(
                    onTap: onDelete,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline,
                            size: 14, color: AppColors.critical),
                        const SizedBox(width: 4),
                        Text(
                          'Delete this request',
                          style: TextStyle(
                            color: AppColors.critical,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NormalCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onMarkDone;
  final VoidCallback onDelete;
  final VoidCallback onViewResponses;
  final VoidCallback onOpenDetails;

  const _NormalCard({
    required this.request,
    required this.onMarkDone,
    required this.onDelete,
    required this.onViewResponses,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final urgency =
        (request['urgency'] ?? 'normal').toString().toLowerCase();
    final status =
        (request['status'] ?? 'pending').toString().toLowerCase();
    final isFulfilled = status == 'fulfilled';
    final isExpired = status == 'expired';
    final isPending = status == 'pending';
    final isCriticalPending = urgency == 'critical' && isPending;

    final urgencyColor = _urgencyColor(urgency);
    final timeAgoText = request['_time_ago'] as String? ?? 'just now';

    final relationship = (request['relationship'] ?? 'Self').toString();
    final showRelationshipChip = relationship != 'Self';

    final responseCount = _readInt(request['response_count']);
    final hasResponses = responseCount > 0;

    final bloodTypeText =
        (request['blood_type'] ?? '').toString().trim().isEmpty
            ? '?'
            : request['blood_type'].toString();

    final cardBackground = isCriticalPending
        ? AppColors.primarySoft.withOpacity(0.3)
        : (isFulfilled
            ? AppColors.successSoft.withOpacity(0.2)
            : AppColors.surface);
    final cardBorderColor = isCriticalPending
        ? AppColors.primary.withOpacity(0.15)
        : Colors.transparent;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cardBorderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color:
                Colors.black.withOpacity(isCriticalPending ? 0.08 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenDetails,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          splashColor: AppColors.primary.withOpacity(0.05),
          highlightColor: AppColors.primary.withOpacity(0.03),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBloodTypeCircle(
                      bloodTypeText,
                      isFulfilled
                          ? AppColors.textTertiary
                          : urgencyColor,
                      isFulfilled: isFulfilled,
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          (request['hospital'] ??
                                  request['location'] ??
                                  'Unknown hospital')
                              .toString(),
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isFulfilled
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        onPressed: onDelete,
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        tooltip: 'Delete request',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Text(
                  (request['patient_name'] ?? 'Patient').toString(),
                  style: AppText.heading.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: isFulfilled
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                    decoration: isFulfilled
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showRelationshipChip) ...[
                  const SizedBox(height: AppSpace.xs),
                  _buildRelationshipChip(relationship),
                ],
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _buildInfoItem(
                      icon: Icons.bloodtype_outlined,
                      text: _unitsLabel(request),
                      color: AppColors.textSecondary,
                    ),
                    _buildDot(),
                    _buildInfoItem(
                      icon: _urgencyIcon(urgency),
                      text: _urgencyLabel(urgency),
                      color: isFulfilled
                          ? AppColors.textTertiary
                          : urgencyColor,
                      bold: !isFulfilled &&
                          (urgency == 'critical' || urgency == 'urgent'),
                    ),
                    _buildDot(),
                    _buildInfoItem(
                      icon: Icons.access_time,
                      text: timeAgoText,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                _buildStatusBadge(status, isCritical: isCriticalPending),
                const SizedBox(height: AppSpace.md),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _buildResponsesView(
                        responseCount: responseCount,
                        hasResponses: hasResponses,
                        isFulfilled: isFulfilled,
                        isExpired: isExpired,
                        onTap: hasResponses ? onViewResponses : null,
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      flex: 2,
                      child: _buildDoneButton(
                        isFulfilled: isFulfilled,
                        isExpired: isExpired,
                        onTap: onMarkDone,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // helpers (kept inside the card class to keep file scoped)

  Widget _buildBloodTypeCircle(
    String bloodType,
    Color color, {
    bool isFulfilled = false,
  }) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: isFulfilled
            ? []
            : [
                BoxShadow(
                  color: color.withOpacity(0.25),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      alignment: Alignment.center,
      child: Text(
        bloodType,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: 15,
          letterSpacing: -0.3,
        ),
      ),
    );
  }

  Widget _buildRelationshipChip(String relationship) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.border, width: 0.5),
      ),
      child: Text(
        relationship,
        style: AppText.caption.copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String text,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppText.caption.copyWith(
            color: color,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildDot() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Text(
        '·',
        style: TextStyle(
          color: AppColors.textTertiary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          height: 1,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, {bool isCritical = false}) {
    final config = _statusConfig(status);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: config.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCritical) ...[
            Icon(Icons.circle, size: 8, color: config.foreground),
            const SizedBox(width: 6),
          ],
          Text(
            config.label,
            style: TextStyle(
              color: config.foreground,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsesView({
    required int responseCount,
    required bool hasResponses,
    required bool isFulfilled,
    required bool isExpired,
    required VoidCallback? onTap,
  }) {
    if (isFulfilled) {
      return _buildStaticIndicator(
        icon: Icons.check_circle_outline,
        label: 'Request closed',
        color: AppColors.success,
        background: AppColors.successSoft.withOpacity(0.5),
      );
    }

    if (isExpired) {
      return _buildStaticIndicator(
        icon: Icons.cancel_outlined,
        label: 'Request expired',
        color: AppColors.textTertiary,
        background: AppColors.background,
      );
    }

    if (hasResponses) {
      return SizedBox(
        height: 42,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.people,
              size: 16, color: AppColors.primary),
          label: Text(
            'View responses ($responseCount)',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: AppColors.primary, width: 1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
          ),
        ),
      );
    }

    return _buildWaitingIndicator();
  }

  Widget _buildStaticIndicator({
    required IconData icon,
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingIndicator() {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation<Color>(
                AppColors.textTertiary,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.xs),
          Flexible(
            child: Text(
              'Waiting for donors',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoneButton({
    required bool isFulfilled,
    required bool isExpired,
    required VoidCallback onTap,
  }) {
    final disabled = isFulfilled || isExpired;
    final color = disabled ? AppColors.textTertiary : AppColors.success;
    final label = isFulfilled ? 'Done' : 'Mark done';

    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: disabled ? null : onTap,
        icon: Icon(
          isFulfilled ? Icons.check_circle : Icons.check,
          size: 16,
          color: color,
        ),
        label: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: disabled ? AppColors.border : AppColors.success,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm),
        ),
      ),
    );
  }

  int _readInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    return int.tryParse(value.toString()) ?? 0;
  }

  String _unitsLabel(Map<String, dynamic> request) {
    final units = _readInt(request['units_needed'] ?? request['units']);
    return '$units ${units == 1 ? 'unit' : 'units'}';
  }

  Color _urgencyColor(String urgency) {
    switch (urgency) {
      case 'critical':
        return AppColors.critical;
      case 'urgent':
        return const Color(0xFFFF9800);
      case 'normal':
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _urgencyIcon(String urgency) {
    switch (urgency) {
      case 'critical':
        return Icons.local_fire_department;
      case 'urgent':
        return Icons.priority_high;
      case 'normal':
      default:
        return Icons.schedule;
    }
  }

  String _urgencyLabel(String urgency) {
    switch (urgency) {
      case 'critical':
        return 'Critical';
      case 'urgent':
        return 'Urgent';
      case 'normal':
      default:
        return 'Normal';
    }
  }

  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'fulfilled':
        return _StatusConfig(
          label: 'FULFILLED',
          background: AppColors.successSoft,
          foreground: AppColors.success,
        );
      case 'expired':
        return _StatusConfig(
          label: 'EXPIRED',
          background: AppColors.background,
          foreground: AppColors.textTertiary,
        );
      case 'pending':
      default:
        return _StatusConfig(
          label: 'PENDING',
          background: AppColors.primarySoft,
          foreground: AppColors.primary,
        );
    }
  }
}

/// Skeleton placeholder shown during initial load — improves perceived speed.
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpace.md),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _shimmer(width: 48, height: 48, isCircle: true),
              const SizedBox(width: AppSpace.md),
              Expanded(child: _shimmer(width: double.infinity, height: 14)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _shimmer(width: 180, height: 18),
          const SizedBox(height: AppSpace.md),
          _shimmer(width: 220, height: 12),
          const SizedBox(height: AppSpace.md),
          _shimmer(width: 80, height: 20),
          const SizedBox(height: AppSpace.md),
          Row(
            children: [
              Expanded(flex: 3, child: _shimmer(width: 0, height: 42)),
              const SizedBox(width: AppSpace.sm),
              Expanded(flex: 2, child: _shimmer(width: 0, height: 42)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shimmer({
    required double width,
    required double height,
    bool isCircle = false,
  }) {
    return Container(
      width: width == 0 ? double.infinity : width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius:
            isCircle ? null : BorderRadius.circular(AppRadius.sm),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}

class _StatusConfig {
  final String label;
  final Color background;
  final Color foreground;

  _StatusConfig({
    required this.label,
    required this.background,
    required this.foreground,
  });
}