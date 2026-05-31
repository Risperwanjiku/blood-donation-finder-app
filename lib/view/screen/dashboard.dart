import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/donation_rules.dart';
import 'package:damulink/configs/location_utils.dart';
import 'package:damulink/configs/blood_compatibility.dart';
import 'package:damulink/view/screen/blood_requests/blood_requests.dart';
import 'package:damulink/view/widgets/record_donation_dialog.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final GetStorage store = GetStorage();

  String userName = "User";
  String bloodType = "O+";
  bool isAvailable = true;
  String? userCity;

  int livesSaved = 0;
  int totalDonations = 0;
  int daysUntilNextDonation = 0;

  List<Map<String, dynamic>> bloodRequests = [];

  bool isLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  Future<void> loadAllData() async {
    setState(() => isLoading = true);
    await loadUserData();
    await loadBloodRequests();
    await loadDonationStats();
    if (mounted) setState(() => isLoading = false);
  }

  Future<void> loadUserData() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() ?? {};
        setState(() {
          userName = userData['name'] ?? store.read("user_name") ?? "User";
          bloodType =
              userData['blood_type'] ?? store.read("blood_type") ?? "O+";
          isAvailable =
              userData['is_available'] ?? store.read("is_available") ?? true;
          livesSaved = userData['lives_saved'] ?? 0;
          totalDonations = userData['total_donations'] ?? 0;
          userCity = LocationUtils.extractCity(
              (userData['location'] as String?) ?? '');
        });
      }
    } catch (e) {
      debugPrint("Error loading user data: $e");
    }
  }

  // Syncs availability to BOTH /users and /public_profiles atomically,
  // so other donors never see a stale state when browsing for matches.
  void updateAvailability(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final batch = _firestore.batch();

      batch.update(
        _firestore.collection('users').doc(user.uid),
        {'is_available': value},
      );

      batch.update(
        _firestore.collection('public_profiles').doc(user.uid),
        {'is_available': value},
      );

      await batch.commit();
      store.write("is_available", value);
    } catch (e) {
      // Revert the local UI flip so the donor knows the sync failed.
      if (mounted) {
        setState(() => isAvailable = !value);
        Get.snackbar(
          "Couldn't update availability",
          "Please check your connection and try again.",
          snackPosition: SnackPosition.TOP,
          backgroundColor: AppColors.primarySoft,
          colorText: AppColors.primaryDark,
        );
      }
    }
  }

  // Loads compatible pending requests, filtered by the donor's city.
  // Compatibility uses the shared BloodCompatibility utility.
  Future<void> loadBloodRequests() async {
    try {
      final user = _auth.currentUser;

      Query<Map<String, dynamic>> query = _firestore
          .collection('blood_requests')
          .where('status', isEqualTo: 'pending');

      // Filter by city if set; otherwise show all pending and let the
      // compatibility filter below narrow it.
      if (userCity != null && userCity!.isNotEmpty) {
        query = query.where('city', isEqualTo: userCity);
      }

      final allSnapshot = await query
          .orderBy('created_at', descending: true)
          .limit(50)
          .get();

      List<Map<String, dynamic>> requests = allSnapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).toList();

      // Keep only compatible types, and drop the donor's own requests.
      final canDonateToTypes =
          BloodCompatibility.compatibleRecipientsFor(bloodType);
      requests = requests.where((request) {
        final canHelp = canDonateToTypes.contains(request['blood_type']);
        final isOwnRequest = request['requester_id'] == user?.uid;
        return canHelp && !isOwnRequest;
      }).toList();

      if (mounted) {
        setState(() => bloodRequests = requests);
      }
    } catch (e) {
      debugPrint("Error loading blood requests: $e");
    }
  }

  // Donation stats via DonationRules — applies the Kenyan interval by
  // gender (3mo male / 4mo female / 4mo unknown). Standalone so it can
  // be passed as the refresh callback to showRecordDonation().
  Future<void> loadDonationStats() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists && mounted) {
        final userData = userDoc.data() ?? {};

        int daysRemaining = 0;
        if (userData['last_donation_date'] != null) {
          final Timestamp lastDonation = userData['last_donation_date'];
          final lastDate = lastDonation.toDate();
          final userGender = userData['gender'] as String?;
          daysRemaining =
              DonationRules.daysUntilEligible(lastDate, userGender);
        }

        setState(() {
          livesSaved = userData['lives_saved'] ?? 0;
          totalDonations = userData['total_donations'] ?? 0;
          daysUntilNextDonation = daysRemaining;
        });
      }
    } catch (e) {
      debugPrint("Error loading donation stats: $e");
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return "Good morning";
    if (hour < 17) return "Good afternoon";
    return "Good evening";
  }

  void _navigateToRequestDetails(String requestId) {
    Get.toNamed('/requestDetails', arguments: {
      'requestId': requestId,
      'fromBrowse': true,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasCity = userCity != null && userCity!.isNotEmpty;

    return RefreshIndicator(
      onRefresh: loadAllData,
      color: AppColors.primary,
      child: Container(
        color: AppColors.background,
        child: isLoading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              )
            : SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Greeting + blood type badge
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "${_greeting()},",
                                  style: AppText.caption,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  userName,
                                  style: AppText.title,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.md,
                              vertical: AppSpace.sm,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            child: Text(
                              bloodType,
                              style: AppText.subheading.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: AppSpace.lg),

                      // Availability card
                      Container(
                        padding: const EdgeInsets.all(AppSpace.md),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          boxShadow: AppShadow.card,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: isAvailable
                                    ? AppColors.successSoft
                                    : AppColors.disabled,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                              ),
                              child: Icon(
                                Icons.volunteer_activism_outlined,
                                color: isAvailable
                                    ? AppColors.success
                                    : AppColors.textTertiary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: AppSpace.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Available to Donate",
                                    style: AppText.subheading,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isAvailable
                                        ? "You are eligible to donate blood today."
                                        : "You won't receive request alerts.",
                                    style: AppText.caption,
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: isAvailable,
                              onChanged: (value) {
                                setState(() => isAvailable = value);
                                updateAvailability(value);
                              },
                              activeColor: AppColors.success,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: AppSpace.md),

                      // Request Blood button
                      Container(
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          boxShadow: AppShadow.button,
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const BloodRequests(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                    AppRadius.md),
                              ),
                            ),
                            icon: const Icon(
                              Icons.monitor_heart_outlined,
                              size: 20,
                            ),
                            label: Text(
                              "Request Blood",
                              style: AppText.button,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpace.md),

                      // Stats card
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.md,
                          vertical: AppSpace.lg,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.lg),
                          boxShadow: AppShadow.card,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.favorite,
                                    color: AppColors.primary,
                                    size: 28,
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    "$livesSaved",
                                    style: AppText.title.copyWith(
                                      fontSize: 24,
                                    ),
                                  ),
                                  Text(
                                    "Lives Saved",
                                    style: AppText.caption,
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 56,
                              color: AppColors.border,
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.history,
                                    color: AppColors.textSecondary,
                                    size: 28,
                                  ),
                                  const SizedBox(height: AppSpace.xs),
                                  Text(
                                    "$totalDonations",
                                    style: AppText.title.copyWith(
                                      fontSize: 24,
                                    ),
                                  ),
                                  Text(
                                    "Total Donations",
                                    style: AppText.caption,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Eligibility pill — tap to record a donation
                      const SizedBox(height: AppSpace.sm),
                      Center(
                        child: GestureDetector(
                          onTap: () => showRecordDonation(
                            context,
                            loadDonationStats,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.md,
                              vertical: AppSpace.sm,
                            ),
                            decoration: BoxDecoration(
                              color: daysUntilNextDonation > 0
                                  ? AppColors.disabled
                                  : AppColors.successSoft,
                              borderRadius: BorderRadius.circular(
                                  AppRadius.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  daysUntilNextDonation > 0
                                      ? Icons.schedule
                                      : Icons.check_circle_outline,
                                  size: 14,
                                  color: daysUntilNextDonation > 0
                                      ? AppColors.textSecondary
                                      : AppColors.success,
                                ),
                                const SizedBox(width: AppSpace.xs),
                                Text(
                                  daysUntilNextDonation > 0
                                      ? "Next donation in $daysUntilNextDonation day${daysUntilNextDonation == 1 ? '' : 's'}"
                                      : totalDonations == 0
                                          ? "Tap to record your first donation"
                                          : "Eligible to donate today",
                                  style: AppText.caption.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: AppSpace.lg),

                      // People who need blood — city-filtered
                      Text(
                        "People Who Need Blood",
                        style: AppText.heading,
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        hasCity
                            ? "Compatible requests in $userCity."
                            : "Compatible requests matching your blood type.",
                        style: AppText.caption,
                      ),
                      const SizedBox(height: AppSpace.md),

                      bloodRequests.isEmpty
                          ? _buildEmptyState(hasCity)
                          : Column(
                              children: List.generate(
                                bloodRequests.length > 5
                                    ? 5
                                    : bloodRequests.length,
                                (index) {
                                  final request = bloodRequests[index];
                                  final Timestamp? createdAt =
                                      request['created_at'];
                                  return _buildRequestCard(
                                    request: request,
                                    createdAt: createdAt,
                                  );
                                },
                              ),
                            ),

                      if (bloodRequests.length > 5) ...[
                        const SizedBox(height: AppSpace.sm),
                        Center(
                          child: TextButton(
                            onPressed: () =>
                                Get.toNamed('/notifications'),
                            child: Text(
                              "View All Requests",
                              style: AppText.label.copyWith(
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: AppSpace.lg),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildEmptyState(bool hasCity) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadow.card,
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.successSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: AppColors.success,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            "All clear right now",
            style: AppText.subheading,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            hasCity
                ? "No one in $userCity needs your blood type right now. We'll alert you the moment they do."
                : "No one matching your blood type needs help. We'll alert you the moment they do.",
            style: AppText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard({
    required Map<String, dynamic> request,
    required Timestamp? createdAt,
  }) {
    final urgency = request['urgency'] ?? 'normal';
    final urgencyColor = urgency == 'critical'
        ? AppColors.critical
        : urgency == 'urgent'
            ? AppColors.warning
            : AppColors.success;

    final bloodTypeNeeded = request['blood_type'] ?? '';
    final hospital = request['hospital'] ?? 'Hospital';
    final units = request['units_needed'] ?? request['units'] ?? 1;

    return GestureDetector(
      onTap: () => _navigateToRequestDetails(request['id']),
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpace.sm),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadow.card,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: bloodTypeNeeded.contains('-')
                    ? AppColors.disabled
                    : AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  bloodTypeNeeded,
                  style: AppText.caption.copyWith(
                    color: bloodTypeNeeded.contains('-')
                        ? AppColors.textPrimary
                        : Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpace.md),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "$bloodTypeNeeded blood needed",
                    style: AppText.bodyStrong,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.local_hospital_outlined,
                        size: 12,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          hospital,
                          style: AppText.caption,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      "$units unit${units > 1 ? 's' : ''} • ${timeago.format(createdAt.toDate())}",
                      style: AppText.caption.copyWith(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: AppSpace.sm),

            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.sm,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: urgencyColor,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    urgency.toUpperCase(),
                    style: AppText.caption.copyWith(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}