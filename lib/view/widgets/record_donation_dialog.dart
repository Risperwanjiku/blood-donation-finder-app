import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/donation_rules.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ============================================================
// Public entry point — keeps the existing call signature from
// dashboard.dart: showRecordDonation(context, onSuccess)
// ============================================================
void showRecordDonation(BuildContext context, Function onSuccess) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _RecordDonationSheet(onSuccess: onSuccess),
  );
}

// ============================================================
// The actual stateful sheet
// ============================================================
class _RecordDonationSheet extends StatefulWidget {
  final Function onSuccess;
  const _RecordDonationSheet({required this.onSuccess});

  @override
  State<_RecordDonationSheet> createState() => _RecordDonationSheetState();
}

class _RecordDonationSheetState extends State<_RecordDonationSheet> {
  final hospitalController = TextEditingController();
  final unitsController = TextEditingController(text: "1");
  DateTime? selectedDate;
  bool isLoading = false;

  // Per-field error messages
  String? _dateError;
  String? _hospitalError;
  String? _unitsError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void dispose() {
    hospitalController.dispose();
    unitsController.dispose();
    super.dispose();
  }

  // Format date as "12 Nov 2025"
  String _formatDate(DateTime d) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec',
    ];
    return "${d.day} ${months[d.month - 1]} ${d.year}";
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      setState(() {
        selectedDate = picked;
        _dateError = null;
      });
    }
  }

  // ============================================================
  // Validation — sets per-field errors, returns true if all OK
  // ============================================================
  bool _validateAll() {
    setState(() {
      _dateError = null;
      _hospitalError = null;
      _unitsError = null;
    });

    bool ok = true;

    if (selectedDate == null) {
      setState(() => _dateError = "Please select a donation date");
      ok = false;
    } else if (selectedDate!.isAfter(DateTime.now())) {
      setState(() => _dateError = "Donation date cannot be in the future");
      ok = false;
    }

    if (hospitalController.text.trim().isEmpty) {
      setState(() => _hospitalError =
          "Please enter the hospital or blood bank");
      ok = false;
    } else if (hospitalController.text.trim().length < 3) {
      setState(() => _hospitalError = "Name must be at least 3 characters");
      ok = false;
    }

    final units = int.tryParse(unitsController.text.trim());
    if (units == null || units < 1) {
      setState(() => _unitsError = "Enter a number 1 or greater");
      ok = false;
    } else if (units > 3) {
      setState(() => _unitsError =
          "Most donations are 1–3 units. Please check the number.");
      ok = false;
    }

    return ok;
  }

  // ============================================================
  // Save — writes /donations with rule-matching schema and
  // increments user stats atomically.
  // Cooldown now uses centralized DonationRules helper (gender-aware,
  // calendar months, normalized dates).
  // ============================================================
  Future<void> _saveDonation() async {
    if (!_validateAll()) return;

    final user = _auth.currentUser;
    if (user == null) {
      _toastError("Please log in first.");
      return;
    }

    setState(() => isLoading = true);

    try {
      // Read current user data for cooldown check + last_donation_date logic
      final userDoc =
          await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final Timestamp? currentLast =
          userData?['last_donation_date'] as Timestamp?;
      final String? userGender = userData?['gender'] as String?;

      // Cooldown check using centralized DonationRules.
      // Applies the Kenyan interval: 3 months male / 4 months female /
      // 4 months when gender is unknown (most conservative default).
      // Logging an older donation than the last one bypasses the rule
      // because there's no biological cooldown going backwards in time.
      final cooldownError = DonationRules.canDonateOn(
        proposedDate: selectedDate!,
        lastDonation: currentLast?.toDate(),
        gender: userGender,
      );
      if (cooldownError != null) {
        if (!mounted) return;
        setState(() {
          isLoading = false;
          _dateError = currentLast != null
              ? "$cooldownError (last: ${_formatDate(currentLast.toDate())})."
              : "$cooldownError.";
        });
        return;
      }

      final units = int.parse(unitsController.text.trim());
      final newDate = Timestamp.fromDate(selectedDate!);

      // Write donation — matches new Firestore rules:
      // donor_id, requester_id (empty for self-records), donation_date
      await _firestore.collection('donations').add({
        'donor_id': user.uid,
        'requester_id': '',
        'hospital': hospitalController.text.trim(),
        'units': units,
        'donation_date': newDate,
        'is_self_recorded': true,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Update stats. Only update last_donation_date if the new donation
      // is MORE RECENT than the existing one — protects the cooldown
      // calculation from being regressed by an old log.
      final shouldUpdateLast = currentLast == null
          || selectedDate!.isAfter(currentLast.toDate());

      final updates = <String, dynamic>{
        'total_donations': FieldValue.increment(1),
        'lives_saved': FieldValue.increment(units),
      };
      if (shouldUpdateLast) {
        updates['last_donation_date'] = newDate;
      }

      await _firestore.collection('users').doc(user.uid).update(updates);

      if (!mounted) return;
      setState(() => isLoading = false);

      Navigator.pop(context);
      Get.snackbar(
        "Recorded",
        "Donation saved. Thank you for saving lives.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.successSoft,
        colorText: AppColors.success,
        duration: const Duration(seconds: 4),
      );
      widget.onSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      // Friendly error — don't leak the raw exception to the user
      _toastError("Couldn't save the donation. Please try again.");
    }
  }

  void _toastError(String message) {
    Get.snackbar(
      "Error",
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.primarySoft,
      colorText: AppColors.primaryDark,
      duration: const Duration(seconds: 3),
    );
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.md),
                  decoration: BoxDecoration(
                    color: AppColors.disabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header row: title/subtitle + X close
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Record Donation", style: AppText.title),
                        const SizedBox(height: AppSpace.xs),
                        Text(
                          "Log a blood donation you've already made. "
                          "This is for your personal record only.",
                          style: AppText.caption,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                    onPressed:
                        isLoading ? null : () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: AppSpace.lg),

              // Donation Date
              _label("Donation Date"),
              GestureDetector(
                onTap: isLoading ? null : _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.md,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: _dateError != null
                          ? AppColors.critical
                          : AppColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: Text(
                          selectedDate == null
                              ? "DD/MM/YYYY"
                              : _formatDate(selectedDate!),
                          style: AppText.body.copyWith(
                            color: selectedDate == null
                                ? AppColors.textTertiary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.arrow_drop_down,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),
              if (_dateError != null) _errorLine(_dateError!),

              const SizedBox(height: AppSpace.md),

              // Hospital
              _label("Hospital or Blood Bank"),
              TextField(
                controller: hospitalController,
                enabled: !isLoading,
                textCapitalization: TextCapitalization.words,
                decoration: _inputDecoration(
                  hint: "e.g., Kenyatta National Hospital",
                  prefixIcon: Icons.local_hospital_outlined,
                  hasError: _hospitalError != null,
                ),
              ),
              if (_hospitalError != null) _errorLine(_hospitalError!),

              const SizedBox(height: AppSpace.md),

              // Units
              _label("Units Donated"),
              TextField(
                controller: unitsController,
                enabled: !isLoading,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration(
                  hint: "1",
                  prefixIcon: Icons.water_drop_outlined,
                  hasError: _unitsError != null,
                ),
              ),
              if (_unitsError != null)
                _errorLine(_unitsError!)
              else ...[
                const SizedBox(height: AppSpace.xs),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                  child: Text(
                    "1 unit ≈ 450ml of blood. Most donations are 1 unit.",
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: AppSpace.md),

              // Privacy chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.md,
                  vertical: AppSpace.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: AppColors.primaryDark,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        "Private — only you can see your donation history.",
                        style: AppText.caption.copyWith(
                          color: AppColors.primaryDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.lg),

              // Save Donation button
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow: isLoading ? [] : AppShadow.button,
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _saveDonation,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.disabled,
                      disabledForegroundColor: AppColors.textTertiary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text("Save Donation", style: AppText.button),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.sm),

              // Cancel link
              Center(
                child: TextButton(
                  onPressed:
                      isLoading ? null : () => Navigator.pop(context),
                  child: Text(
                    "Cancel",
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Small helpers
  // ============================================================
  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.xs),
      child: Text(text, style: AppText.label),
    );
  }

  Widget _errorLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpace.xs,
        left: AppSpace.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline,
            size: 14,
            color: AppColors.critical,
          ),
          const SizedBox(width: AppSpace.xs),
          Expanded(
            child: Text(
              text,
              style: AppText.caption.copyWith(
                color: AppColors.critical,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    bool hasError = false,
  }) {
    final borderColor =
        hasError ? AppColors.critical : AppColors.border;
    final focusedColor =
        hasError ? AppColors.critical : AppColors.primary;

    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
          : null,
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpace.md,
        vertical: AppSpace.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: focusedColor, width: 1.5),
      ),
    );
  }
}