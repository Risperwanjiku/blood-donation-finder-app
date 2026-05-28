import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/blood_compatibility.dart';
import 'package:damulink/configs/location_utils.dart';

/// Donor Browse — list of pending blood requests the current donor can help with.
class DonorBrowseScreen extends StatefulWidget {
  const DonorBrowseScreen({super.key});

  @override
  State<DonorBrowseScreen> createState() => _DonorBrowseScreenState();
}

class _DonorBrowseScreenState extends State<DonorBrowseScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _donorBloodType;
  String? _donorCity;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _loadDonorProfile();
  }

  Future<void> _loadDonorProfile() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      setState(() => _loadingProfile = false);
      return;
    }

    try {
      // Load blood type from public_profiles and location from users in parallel
      final results = await Future.wait([
        _firestore.collection('public_profiles').doc(uid).get(),
        _firestore.collection('users').doc(uid).get(),
      ]);

      String? bloodType;
      String? location;

      if (results[0].exists) {
        bloodType = results[0].data()?['blood_type'] as String?;
      }
      if (results[1].exists) {
        location = results[1].data()?['location'] as String?;
      }

      setState(() {
        _donorBloodType = bloodType;
        _donorCity = LocationUtils.extractCity(location ?? '');
        _loadingProfile = false;
      });
    } catch (_) {
      setState(() => _loadingProfile = false);
    }
  }

  Stream<List<Map<String, dynamic>>> _requestsStream() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const Stream.empty();
    if (_donorBloodType == null) return const Stream.empty();

    final compatible =
        BloodCompatibility.compatibleRecipientsFor(_donorBloodType!);
    if (compatible.isEmpty) return const Stream.empty();

    Query<Map<String, dynamic>> query = _firestore
        .collection('blood_requests')
        .where('status', isEqualTo: 'pending')
        .where('blood_type', whereIn: compatible);

    // Filter by city if donor has set their location.
    // Graceful fallback: if no city, show all (honest "Active Requests" mode).
    if (_donorCity != null && _donorCity!.isNotEmpty) {
      query = query.where('city', isEqualTo: _donorCity);
    }

    return query
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      final list = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        final data = doc.data();
        // Don't show donor their own posted requests
        if (data['requester_id'] == uid) continue;

        final createdAt = data['created_at'] as Timestamp?;
        list.add({
          'id': doc.id,
          ...data,
          '_time_ago': createdAt != null
              ? timeago.format(createdAt.toDate())
              : 'just now',
        });
      }

      // Critical first
      list.sort((a, b) {
        final aUrgent =
            (a['urgency'] ?? '').toString().toLowerCase() == 'critical';
        final bUrgent =
            (b['urgency'] ?? '').toString().toLowerCase() == 'critical';
        if (aUrgent && !bUrgent) return -1;
        if (!aUrgent && bUrgent) return 1;
        return 0;
      });

      return list;
    });
  }

  void _openDetails(Map<String, dynamic> request) {
    HapticFeedback.selectionClick();
    Get.toNamed('/requestDetails', arguments: {
      'requestId': request['id'],
      'fromBrowse': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProfile) {
      return _buildLoadingState();
    }

    if (_donorBloodType == null) {
      return _buildSetupBloodTypeState();
    }

    return Column(
      children: [
        _buildHeader(),
        Expanded(child: _buildRequestsList()),
      ],
    );
  }

  Widget _buildHeader() {
    final isUniversalDonor = _donorBloodType == 'O-';
    final hasCity = _donorCity != null && _donorCity!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg,
        AppSpace.sm,
        AppSpace.lg,
        AppSpace.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasCity ? 'Requests in $_donorCity' : 'Active Requests',
                  style: AppText.heading.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isUniversalDonor)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text(
                        'Universal donor',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isUniversalDonor
                ? (hasCity
                    ? 'You can help anyone in $_donorCity who needs blood'
                    : 'You can help anyone — these are all pending requests')
                : 'Pending requests matching your blood type ($_donorBloodType)',
            style: AppText.caption.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsList() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _requestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
            await Future.delayed(const Duration(milliseconds: 600));
          },
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              120,
            ),
            itemCount: requests.length,
            physics: const AlwaysScrollableScrollPhysics(),
            cacheExtent: 600,
            itemBuilder: (context, index) {
              final request = requests[index];
              return _RequestCard(
                key: ValueKey(request['id']),
                request: request,
                donorBloodType: _donorBloodType!,
                onTap: () => _openDetails(request),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 3,
      ),
    );
  }

  Widget _buildSetupBloodTypeState() {
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
                Icons.bloodtype_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              "We need your blood type first",
              style: AppText.heading.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              "Set your blood type in your profile so we can\nshow you compatible blood requests.",
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
                  Get.toNamed('/profile');
                },
                icon:
                    const Icon(Icons.person, color: Colors.white, size: 20),
                label: Text('Set up profile', style: AppText.button),
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

  Widget _buildEmptyState() {
    final hasCity = _donorCity != null && _donorCity!.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.successSoft.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_outline,
                size: 48,
                color: AppColors.success,
              ),
            ),
            const SizedBox(height: AppSpace.lg),
            Text(
              'No requests right now',
              style: AppText.heading.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              hasCity
                  ? "That's a good thing! No pending requests in $_donorCity match your blood type right now. We'll notify you when a compatible one comes in."
                  : "That's a good thing! No pending requests match your blood type right now. We'll notify you when a compatible one comes in.",
              textAlign: TextAlign.center,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
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
              "We couldn't load requests",
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            Text(
              'Check your connection and try again.',
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

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.lg, 0, AppSpace.lg, 120),
      itemCount: 3,
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String donorBloodType;
  final VoidCallback onTap;

  const _RequestCard({
    super.key,
    required this.request,
    required this.donorBloodType,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final urgency =
        (request['urgency'] ?? 'normal').toString().toLowerCase();
    final isCritical = urgency == 'critical';
    final urgencyColor = _urgencyColor(urgency);

    final bloodType = (request['blood_type'] ?? '?').toString();
    final hospital =
        (request['hospital'] ?? 'Unknown hospital').toString();
    final units = _readInt(request['units_needed'] ?? request['units']);
    final timeAgo = (request['_time_ago'] ?? 'just now').toString();
    final initials =
        (request['patient_initials'] ?? '').toString().trim();

    final cardBackground = isCritical
        ? AppColors.primarySoft.withOpacity(0.3)
        : AppColors.surface;
    final cardBorderColor = isCritical
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
            color: Colors.black.withOpacity(isCritical ? 0.08 : 0.06),
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
          onTap: onTap,
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
                    _bloodTypeCircle(bloodType, urgencyColor),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hospital,
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (initials.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Patient: $initials',
                              style: AppText.caption.copyWith(
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isCritical) _criticalBadge(),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Wrap(
                  spacing: AppSpace.sm,
                  runSpacing: AppSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _infoItem(
                      icon: Icons.bloodtype_outlined,
                      text: '$units ${units == 1 ? 'unit' : 'units'}',
                      color: AppColors.textSecondary,
                    ),
                    _dot(),
                    _infoItem(
                      icon: _urgencyIcon(urgency),
                      text: _urgencyLabel(urgency),
                      color: urgencyColor,
                      bold: isCritical,
                    ),
                    _dot(),
                    _infoItem(
                      icon: Icons.access_time,
                      text: timeAgo,
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successSoft.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: 6),
                      Text(
                        'Your $donorBloodType blood is compatible',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      'View details',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward,
                        size: 14, color: AppColors.primary),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bloodTypeCircle(String bloodType, Color color) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
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

  Widget _criticalBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.critical,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.white, size: 11),
          const SizedBox(width: 3),
          const Text(
            'URGENT',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoItem({
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

  Widget _dot() {
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

  int _readInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  Color _urgencyColor(String urgency) {
    switch (urgency) {
      case 'critical':
        return AppColors.critical;
      case 'urgent':
        return const Color(0xFFFF9800);
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
      default:
        return 'Normal';
    }
  }
}

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
        children: [
          Row(
            children: [
              _shimmer(48, 48, isCircle: true),
              const SizedBox(width: AppSpace.md),
              Expanded(child: _shimmer(0, 14)),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          _shimmer(220, 12),
          const SizedBox(height: AppSpace.md),
          _shimmer(180, 24),
        ],
      ),
    );
  }

  Widget _shimmer(double w, double h, {bool isCircle = false}) {
    return Container(
      width: w == 0 ? double.infinity : w,
      height: h,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: isCircle ? null : BorderRadius.circular(AppRadius.sm),
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
      ),
    );
  }
}