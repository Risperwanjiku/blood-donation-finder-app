import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/blood_compatibility.dart';

class RequestDetailsScreen extends StatefulWidget {
  const RequestDetailsScreen({super.key});

  @override
  State<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends State<RequestDetailsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  late final String _requestId;
  String? _donorBloodType;
  bool _isCommitting = false;
  bool _isWithdrawing = false;

  @override
  void initState() {
    super.initState();
    final args = Get.arguments as Map?;
    _requestId = args?['requestId']?.toString() ?? '';
    _loadDonorBloodType();
  }

  Future<void> _loadDonorBloodType() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final doc =
          await _firestore.collection('public_profiles').doc(uid).get();
      if (mounted && doc.exists) {
        setState(() {
          _donorBloodType = doc.data()?['blood_type'] as String?;
        });
      }
    } catch (_) {}
  }

  Future<void> _commitToHelp(Map<String, dynamic> request) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    HapticFeedback.mediumImpact();
    setState(() => _isCommitting = true);

    try {
      final responseId = '${_requestId}_$uid';
      await _firestore.collection('responses').doc(responseId).set({
        'donor_id': uid,
        'request_id': _requestId,
        'requester_id': request['requester_id'],
        'status': 'offered',
        'created_at': FieldValue.serverTimestamp(),
      });
      HapticFeedback.mediumImpact();
      if (mounted) {
        _showSnack(
          "Thank you. The patient's family will be notified.",
          isError: false,
        );
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        _showSnack(
          e.code == 'permission-denied'
              ? 'Permission denied. Please sign in again.'
              : 'Could not commit. Please try again.',
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Could not commit. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isCommitting = false);
    }
  }

  Future<void> _withdrawHelp() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Withdraw your offer?'),
        content: const Text(
          'The family will be informed that you can no longer help. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Keep my offer',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.critical,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: const Text(
              'Withdraw',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isWithdrawing = true);

    try {
      final responseId = '${_requestId}_$uid';
      await _firestore.collection('responses').doc(responseId).update({
        'status': 'withdrawn',
        'withdrawn_at': FieldValue.serverTimestamp(),
      });
      HapticFeedback.lightImpact();
      if (mounted) {
        _showSnack('Your offer has been withdrawn', isError: false);
      }
    } catch (_) {
      if (mounted) {
        _showSnack('Could not withdraw. Please try again.', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isWithdrawing = false);
    }
  }

  Future<void> _callPhone(String phone) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showSnack('Could not open dialer', isError: true);
    }
  }

  Future<void> _openWhatsApp(String phone) async {
    HapticFeedback.lightImpact();
    // wa.me needs full international format, no '+' and no leading 0.
    // Stored numbers are Kenyan local format (e.g. 0785236442).
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '254${digits.substring(1)}';
    } else if (!digits.startsWith('254') && digits.length == 9) {
      digits = '254$digits';
    }
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('WhatsApp is not installed', isError: true);
    }
  }

  Future<void> _openDirections(
      String hospital, String area, String placeId) async {
    HapticFeedback.lightImpact();
    final dest = Uri.encodeComponent(
      area.isNotEmpty ? '$hospital, $area' : hospital,
    );
    var url = 'https://www.google.com/maps/dir/?api=1&destination=$dest';
    if (placeId.isNotEmpty) {
      url += '&destination_place_id=$placeId';
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnack('Could not open maps', isError: true);
    }
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

  @override
  Widget build(BuildContext context) {
    if (_requestId.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Request Details')),
        body: _buildErrorState('Request not found'),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Request Details',
          style: AppText.heading.copyWith(
            color: AppColors.primary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _firestore
            .collection('blood_requests')
            .doc(_requestId)
            .snapshots(),
        builder: (context, publicSnap) {
          if (publicSnap.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          if (publicSnap.hasError || !publicSnap.hasData) {
            return _buildErrorState('Could not load this request');
          }
          if (!publicSnap.data!.exists) {
            return _buildErrorState('This request no longer exists');
          }

          final publicData =
              publicSnap.data!.data() as Map<String, dynamic>;

          final uid = _auth.currentUser?.uid;
          if (uid == null) {
            return _buildErrorState('Please sign in');
          }
          final responseId = '${_requestId}_$uid';

          return StreamBuilder<DocumentSnapshot>(
            stream: _firestore
                .collection('responses')
                .doc(responseId)
                .snapshots(),
            builder: (context, responseSnap) {
              final hasOffered = responseSnap.data?.exists ?? false;
              String? responseStatus;
              if (hasOffered) {
                final responseData =
                    responseSnap.data!.data() as Map<String, dynamic>?;
                responseStatus = responseData?['status']?.toString();
              }
              final isActiveOffer =
                  hasOffered && responseStatus != 'withdrawn';

              if (isActiveOffer) {
                return _buildPostCommitView(publicData);
              }
              return _buildPreCommitView(publicData, responseStatus);
            },
          );
        },
      ),
    );
  }

  // ─── PRE-COMMIT VIEW ─────────────────────────────────────

  Widget _buildPreCommitView(
    Map<String, dynamic> publicData,
    String? responseStatus,
  ) {
    final urgency =
        (publicData['urgency'] ?? 'normal').toString().toLowerCase();
    final bloodType = (publicData['blood_type'] ?? '?').toString();
    final hospital =
        (publicData['hospital'] ?? 'Unknown hospital').toString();
    final hospitalArea = (publicData['hospital_area'] ?? '').toString();
    final units =
        _readInt(publicData['units_needed'] ?? publicData['units']);
    final initials = (publicData['patient_initials'] ?? '').toString();
    final createdAt = publicData['created_at'] as Timestamp?;
    final neededBy = publicData['needed_by'] as Timestamp?;
    final timeAgo = createdAt != null
        ? timeago.format(createdAt.toDate())
        : 'just now';

    final isCompatible = _donorBloodType != null &&
        BloodCompatibility.canDonate(
          donorType: _donorBloodType!,
          recipientType: bloodType,
        );

    final canOffer = isCompatible && responseStatus != 'withdrawn';

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBloodTypeHero(bloodType, urgency, units),
          const SizedBox(height: AppSpace.lg),
          if (_donorBloodType != null)
            _buildCompatibilityBanner(isCompatible),
          if (_donorBloodType != null) const SizedBox(height: AppSpace.lg),
          _buildInfoCard([
            _InfoRow(
              icon: Icons.local_hospital_outlined,
              label: 'Hospital',
              value: hospital,
              caption: hospitalArea.isNotEmpty ? hospitalArea : null,
            ),
            _InfoRow(
              icon: Icons.person_outline,
              label: 'Patient',
              value: initials.isNotEmpty ? initials : '—',
              caption:
                  'Initials only — full name shared after you offer',
            ),
            _InfoRow(
              icon: Icons.access_time,
              label: 'Posted',
              value: timeAgo,
            ),
            if (neededBy != null)
              _InfoRow(
                icon: Icons.event_outlined,
                label: 'Needed by',
                value: _formatNeededBy(neededBy.toDate()),
              ),
          ]),
          const SizedBox(height: AppSpace.lg),
          _buildPrivacyNotice(),
          const SizedBox(height: AppSpace.xl),
          if (responseStatus == 'withdrawn')
            _buildWithdrawnNotice()
          else
            _buildOfferButton(
              canOffer: canOffer,
              onTap: () => _commitToHelp(publicData),
            ),
        ],
      ),
    );
  }

  Widget _buildBloodTypeHero(
    String bloodType,
    String urgency,
    int units,
  ) {
    final urgencyColor = _urgencyColor(urgency);
    final isCritical = urgency == 'critical';

    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface,
            isCritical
                ? AppColors.primarySoft.withOpacity(0.4)
                : AppColors.background,
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Blood Type Needed',
                style: AppText.caption.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              _buildUrgencyBadge(urgency),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            bloodType,
            style: TextStyle(
              color: urgencyColor,
              fontSize: 64,
              fontWeight: FontWeight.w800,
              letterSpacing: -2,
              height: 1,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border:
                  Border.all(color: AppColors.border.withOpacity(0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.water_drop, size: 14, color: urgencyColor),
                const SizedBox(width: 6),
                Text(
                  '$units ${units == 1 ? 'Unit' : 'Units'} Needed',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Compact version used in the post-commit view, where the donor has
  // already committed and the priority shifts to contact + directions.
  Widget _buildCompactBloodSummary(
    String bloodType,
    String urgency,
    int units,
  ) {
    final urgencyColor = _urgencyColor(urgency);
    final hasBadge = urgency == 'critical' || urgency == 'urgent';

    return Container(
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
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: urgencyColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            alignment: Alignment.center,
            child: Text(
              bloodType,
              style: TextStyle(
                color: urgencyColor,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Blood Type Needed',
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildUrgencyBadge(urgency),
                    if (hasBadge) const SizedBox(width: AppSpace.sm),
                    Icon(Icons.water_drop, size: 13, color: urgencyColor),
                    const SizedBox(width: 4),
                    Text(
                      '$units ${units == 1 ? 'Unit' : 'Units'}',
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUrgencyBadge(String urgency) {
    if (urgency != 'critical' && urgency != 'urgent') {
      return const SizedBox.shrink();
    }
    final isCritical = urgency == 'critical';
    final color =
        isCritical ? AppColors.critical : const Color(0xFFFF9800);
    final label = isCritical ? 'CRITICAL' : 'URGENT';
    final icon =
        isCritical ? Icons.warning_amber_rounded : Icons.priority_high;

    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.sm, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
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

  Widget _buildCompatibilityBanner(bool isCompatible) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: isCompatible
            ? AppColors.successSoft.withOpacity(0.4)
            : AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: isCompatible
              ? AppColors.success.withOpacity(0.3)
              : AppColors.border,
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isCompatible ? Icons.check_circle : Icons.info_outline,
            size: 20,
            color:
                isCompatible ? AppColors.success : AppColors.textTertiary,
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              isCompatible
                  ? (_donorBloodType == 'O-'
                      ? "You're a universal donor — you can help anyone"
                      : 'Your blood type is compatible')
                  : 'Your blood type is not compatible with this request',
              style: TextStyle(
                color: isCompatible
                    ? AppColors.success
                    : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(List<_InfoRow> rows) {
    return Container(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.sm,
        ),
        child: Column(
          children: [
            for (int i = 0; i < rows.length; i++) ...[
              rows[i],
              if (i < rows.length - 1)
                Divider(
                  height: 1,
                  color: AppColors.border.withOpacity(0.5),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNotice() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline,
              size: 18, color: AppColors.textSecondary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Why some details are hidden",
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "To protect the family's privacy, we share the patient's "
                  "full name and contact details only after you offer to help.",
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfferButton({
    required bool canOffer,
    required VoidCallback onTap,
  }) {
    if (_isCommitting) {
      return SizedBox(
        height: 56,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.7),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.5,
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 56,
      child: ElevatedButton.icon(
        onPressed: canOffer ? onTap : null,
        icon: const Icon(Icons.water_drop, color: Colors.white, size: 20),
        label: Text(
          canOffer ? 'I Want to Help' : 'Not compatible',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor:
              canOffer ? AppColors.primary : AppColors.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildWithdrawnNotice() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              'You previously withdrew your offer for this request.',
              style: AppText.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── POST-COMMIT VIEW ────────────────────────────────────

  Widget _buildPostCommitView(Map<String, dynamic> publicData) {
    return FutureBuilder<DocumentSnapshot>(
      future: _firestore
          .collection('blood_request_private')
          .doc(_requestId)
          .get(),
      builder: (context, privateSnap) {
        if (privateSnap.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        Map<String, dynamic> privateData = {};
        if (privateSnap.hasData && privateSnap.data!.exists) {
          privateData =
              privateSnap.data!.data() as Map<String, dynamic>;
        }

        return _buildPostCommitContent(publicData, privateData);
      },
    );
  }

  Widget _buildPostCommitContent(
    Map<String, dynamic> publicData,
    Map<String, dynamic> privateData,
  ) {
    final bloodType = (publicData['blood_type'] ?? '?').toString();
    final hospital =
        (publicData['hospital'] ?? 'Unknown hospital').toString();
    final hospitalArea = (publicData['hospital_area'] ?? '').toString();
    final placeId = (publicData['hospital_place_id'] ?? '').toString();
    final relationship = (publicData['relationship'] ?? '').toString();
    final units =
        _readInt(publicData['units_needed'] ?? publicData['units']);
    final urgency =
        (publicData['urgency'] ?? 'normal').toString().toLowerCase();

    final patientName =
        (privateData['patient_name'] ?? 'Patient').toString();
    final phone = (privateData['contact_phone'] ?? '').toString();
    final requesterName =
        (privateData['requester_full_name'] ?? 'Family member').toString();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
          AppSpace.lg, AppSpace.lg, AppSpace.lg, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildThankYouBanner(),
          const SizedBox(height: AppSpace.lg),
          _buildCompactBloodSummary(bloodType, urgency, units),
          const SizedBox(height: AppSpace.lg),
          _buildContactCard(
            patientName: patientName,
            requesterName: requesterName,
            relationship: relationship,
            phone: phone,
            hospital: hospital,
            hospitalArea: hospitalArea,
            placeId: placeId,
          ),
          const SizedBox(height: AppSpace.lg),
          _buildNextStepsCard(),
          const SizedBox(height: AppSpace.xl),
          _buildWithdrawButton(),
        ],
      ),
    );
  }

  Widget _buildThankYouBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withOpacity(0.15),
            AppColors.success.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "You've offered to help",
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "The family has been notified. Please contact them soon.",
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard({
    required String patientName,
    required String requesterName,
    required String relationship,
    required String phone,
    required String hospital,
    required String hospitalArea,
    required String placeId,
  }) {
    final showRelationship =
        relationship.isNotEmpty && relationship.toLowerCase() != 'self';

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contact Information',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpace.md),
            _InfoRow(
              icon: Icons.person,
              label: 'Patient',
              value: patientName,
            ),
            Divider(color: AppColors.border.withOpacity(0.5)),
            _InfoRow(
              icon: Icons.contact_phone,
              label: 'Contact person',
              value: requesterName,
              caption: showRelationship ? relationship : null,
            ),
            if (phone.isNotEmpty) ...[
              Divider(color: AppColors.border.withOpacity(0.5)),
              _InfoRow(
                icon: Icons.phone_outlined,
                label: 'Phone',
                value: phone,
              ),
            ],
            Divider(color: AppColors.border.withOpacity(0.5)),
            _InfoRow(
              icon: Icons.local_hospital_outlined,
              label: 'Hospital',
              value: hospital,
              caption: hospitalArea.isNotEmpty ? hospitalArea : null,
            ),
            const SizedBox(height: AppSpace.md),
            if (phone.isNotEmpty) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _callPhone(phone),
                      icon: const Icon(Icons.phone,
                          size: 18, color: AppColors.success),
                      label: Text(
                        'Call',
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.success),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openWhatsApp(phone),
                      icon: const Icon(Icons.chat_bubble_outline,
                          size: 18, color: AppColors.primary),
                      label: Text(
                        'WhatsApp',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () =>
                    _openDirections(hospital, hospitalArea, placeId),
                icon: const Icon(Icons.directions_outlined,
                    size: 18, color: AppColors.primary),
                label: Text(
                  'Get Directions',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primarySoft.withOpacity(0.4),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNextStepsCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.3),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                'Before you go',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.sm),
          _buildTip('Call to confirm before heading to the hospital'),
          _buildTip('Bring your national ID'),
          _buildTip('Eat well and stay hydrated 24h before donating'),
          _buildTip(
              'You must be 18+ and at least 56 days since last donation'),
        ],
      ),
    );
  }

  Widget _buildTip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fiber_manual_record,
              size: 6, color: AppColors.primary),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWithdrawButton() {
    if (_isWithdrawing) {
      return SizedBox(
        height: 48,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              color: AppColors.critical,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: TextButton.icon(
        onPressed: _withdrawHelp,
        icon: const Icon(Icons.cancel_outlined,
            size: 18, color: AppColors.critical),
        label: Text(
          'I can no longer help',
          style: TextStyle(
            color: AppColors.critical,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // ─── SHARED ──────────────────────────────────────────────

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(
        color: AppColors.primary,
        strokeWidth: 3,
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 56,
              color: AppColors.textTertiary,
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              message,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpace.lg),
            TextButton.icon(
              onPressed: () {
                HapticFeedback.lightImpact();
                Get.back();
              },
              icon: const Icon(Icons.arrow_back,
                  size: 18, color: AppColors.primary),
              label: Text(
                'Go back',
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

  int _readInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? 0;
  }

  String _formatNeededBy(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff < 7) return 'In $diff days';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  Color _urgencyColor(String urgency) {
    switch (urgency) {
      case 'critical':
        return AppColors.critical;
      case 'urgent':
        return const Color(0xFFFF9800);
      default:
        return AppColors.primary;
    }
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? caption;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 16, color: AppColors.textSecondary),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: AppText.caption.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: AppText.body.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}