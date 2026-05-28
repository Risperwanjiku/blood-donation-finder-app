import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/services/places_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:damulink/configs/location_utils.dart';

class RequestFormScreen extends StatefulWidget {
  const RequestFormScreen({super.key});

  @override
  State<RequestFormScreen> createState() => _RequestFormScreenState();
}

class _RequestFormScreenState extends State<RequestFormScreen> {
  String _requestingFor = 'myself';
  String? _relationship;

  final patientNameController = TextEditingController();
  final unitsController = TextEditingController(text: '1');
  final hospitalController = TextEditingController();
  final contactController = TextEditingController();

  String? selectedBloodType;
  String _urgency = 'normal';
  String? _neededBy;

  String? _hospitalPlaceId;
  String? _hospitalArea;
  List<PlaceSuggestion> _hospitalSuggestions = [];
  bool _hospitalLoading = false;
  Timer? _hospitalDebounce;
  bool _suppressNextHospitalLookup = false;

  bool isLoading = false;

  String? _patientNameError;
  String? _relationshipError;
  String? _bloodTypeError;
  String? _unitsError;
  String? _hospitalError;
  String? _contactError;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _store = GetStorage();

  late String _userFullName;
  late String _userFirstName;
  late String _userPhone;

  final List<String> _bloodTypes = const [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-',
  ];

  final List<String> _relationships = const [
    'Family Member', 'Friend', 'Other',
  ];

  @override
  void initState() {
    super.initState();
    _userFullName = _store.read('user_name') ?? '';
    _userFirstName =
        _userFullName.isEmpty ? '' : _userFullName.trim().split(' ').first;
    _userPhone = _store.read('user_phone') ?? '';
    _applyRequestingForMode();
  }

  @override
  void dispose() {
    _hospitalDebounce?.cancel();
    patientNameController.dispose();
    unitsController.dispose();
    hospitalController.dispose();
    contactController.dispose();
    super.dispose();
  }

  void _applyRequestingForMode() {
    if (_requestingFor == 'myself') {
      patientNameController.text = _userFullName;
      contactController.text = _userPhone;
      _relationship = null;
    } else {
      patientNameController.clear();
      contactController.text = _userPhone;
    }
  }

  void _onHospitalChanged(String value) {
    if (_suppressNextHospitalLookup) {
      _suppressNextHospitalLookup = false;
      return;
    }

    _hospitalPlaceId = null;
    _hospitalArea = null;
    _hospitalError = null;
    _hospitalDebounce?.cancel();

    if (value.trim().length < 2) {
      setState(() {
        _hospitalSuggestions = [];
        _hospitalLoading = false;
      });
      return;
    }

    setState(() => _hospitalLoading = true);

    _hospitalDebounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await PlacesService.autocompleteHospitals(value);
      if (!mounted) return;
      setState(() {
        _hospitalSuggestions = results;
        _hospitalLoading = false;
      });
    });
  }

  void _onHospitalSuggestionTapped(PlaceSuggestion s) {
    _hospitalDebounce?.cancel();
    _suppressNextHospitalLookup = true;
    setState(() {
      hospitalController.text = s.mainText;
      _hospitalPlaceId = s.placeId;
      _hospitalArea = s.secondaryText;
      _hospitalSuggestions = [];
      _hospitalLoading = false;
      _hospitalError = null;
    });
  }

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    if (cleaned.startsWith('+254')) return '0${cleaned.substring(4)}';
    return cleaned;
  }

  bool _isValidKenyanPhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    final local = RegExp(r'^(07|01)\d{8}$');
    final international = RegExp(r'^\+254[71]\d{8}$');
    return local.hasMatch(cleaned) || international.hasMatch(cleaned);
  }

  String _computeInitials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return '${parts[0][0].toUpperCase()}.';
    return '${parts.first[0].toUpperCase()}.${parts.last[0].toUpperCase()}.';
  }

  Timestamp? _computeNeededByTimestamp() {
    if (_urgency != 'normal' || _neededBy == null) return null;
    final now = DateTime.now();
    final endOfDay = DateTime(now.year, now.month, now.day, 23, 59);
    switch (_neededBy) {
      case 'today':
        return Timestamp.fromDate(endOfDay);
      case 'tomorrow':
        return Timestamp.fromDate(endOfDay.add(const Duration(days: 1)));
      case '3days':
        return Timestamp.fromDate(endOfDay.add(const Duration(days: 3)));
      case 'week':
        return Timestamp.fromDate(endOfDay.add(const Duration(days: 7)));
      default:
        return null;
    }
  }

  bool _validateAll() {
    setState(() {
      _patientNameError = null;
      _relationshipError = null;
      _bloodTypeError = null;
      _unitsError = null;
      _hospitalError = null;
      _contactError = null;
    });

    bool ok = true;

    final patientName = patientNameController.text.trim();
    if (patientName.isEmpty) {
      setState(() => _patientNameError = 'Please enter the patient name');
      ok = false;
    } else if (patientName.length < 2) {
      setState(() =>
          _patientNameError = 'Name must be at least 2 characters');
      ok = false;
    }

    if (_requestingFor == 'someone_else' && _relationship == null) {
      setState(() => _relationshipError =
          'Please select your relationship to the patient');
      ok = false;
    }

    if (selectedBloodType == null) {
      setState(
          () => _bloodTypeError = 'Please select the blood type needed');
      ok = false;
    }

    final units = int.tryParse(unitsController.text.trim());
    if (units == null) {
      setState(() => _unitsError = 'Enter a number');
      ok = false;
    } else if (units < 1) {
      setState(() => _unitsError = 'At least 1 unit');
      ok = false;
    } else if (units > 10) {
      setState(() => _unitsError = 'Maximum 10 units');
      ok = false;
    }

    final hospital = hospitalController.text.trim();
    if (hospital.isEmpty) {
      setState(() => _hospitalError = 'Please enter the hospital name');
      ok = false;
    } else if (hospital.length < 3) {
      setState(() =>
          _hospitalError = 'Hospital name must be at least 3 characters');
      ok = false;
    }

    final contact = contactController.text.trim();
    if (contact.isEmpty) {
      setState(() => _contactError = 'Please enter a contact number');
      ok = false;
    } else if (!_isValidKenyanPhone(contact)) {
      setState(() => _contactError =
          'Use 0712345678 or +254712345678 format');
      ok = false;
    }

    return ok;
  }

  Future<void> _submit() async {
    if (!_validateAll()) return;

    final user = _auth.currentUser;
    if (user == null) {
      _showError('You must be signed in to create a request');
      return;
    }

    setState(() => isLoading = true);

    try {
      final patientName = patientNameController.text.trim();
      final initials = _computeInitials(patientName);
      final units = int.parse(unitsController.text.trim());
      final hospitalName = hospitalController.text.trim();

      final relationship =
          _requestingFor == 'myself' ? 'Self' : (_relationship ?? 'Other');

      final neededByTs = _computeNeededByTimestamp();

      final requestRef = _firestore.collection('blood_requests').doc();
      final privateRef = _firestore
          .collection('blood_request_private')
          .doc(requestRef.id);

      final batch = _firestore.batch();

      batch.set(requestRef, {
        'requester_id': user.uid,
        'patient_initials': initials,
        'posted_by_first_name': _userFirstName,
        'relationship': relationship,
        'blood_type': selectedBloodType,
        'units_needed': units,
        'hospital': hospitalName,
        'hospital_place_id': _hospitalPlaceId,
        'hospital_area': _hospitalArea,
        'city': LocationUtils.extractCity(_hospitalArea ?? ''),
        'urgency': _urgency,
        'needed_by': neededByTs,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      batch.set(privateRef, {
        'requester_id': user.uid,
        'patient_name': patientName,
        'contact_phone': _normalizePhone(contactController.text.trim()),
        'requester_full_name': _userFullName,
      });

      await batch.commit();

      if (!mounted) return;
      setState(() => isLoading = false);

      Get.snackbar(
        'Request Created',
        'Your blood request has been sent to nearby donors.',
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.successSoft,
        colorText: AppColors.success,
        duration: const Duration(seconds: 4),
      );

      Get.back();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      if (e.code == 'permission-denied') {
        _showError(
            'Permission denied. Please make sure you are signed in.');
      } else {
        _showError("Couldn't create request. Please try again.");
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showError("Something went wrong. Please try again.");
    }
  }

  void _showError(String message) {
    Get.snackbar(
      'Error',
      message,
      snackPosition: SnackPosition.TOP,
      backgroundColor: AppColors.primarySoft,
      colorText: AppColors.primaryDark,
      duration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.primary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'Request Blood',
          style: AppText.heading.copyWith(color: AppColors.primary),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.lg,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Requesting for', style: AppText.label),
                const SizedBox(height: AppSpace.xs),
                _buildRequestingForToggle(),
                const SizedBox(height: AppSpace.md),

                _Field(
                  label: 'Patient Name',
                  helper: _requestingFor == 'someone_else'
                      ? 'Shown as initials (e.g. "D.M.") until someone offers to help.'
                      : 'Shown as initials until someone offers to help.',
                  errorText: _patientNameError,
                  child: TextField(
                    controller: patientNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _inputDecoration(
                      hint: 'Enter full name',
                      hasError: _patientNameError != null,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                if (_requestingFor == 'someone_else') ...[
                  _Field(
                    label: 'Your relationship to the patient',
                    errorText: _relationshipError,
                    child: DropdownButtonFormField<String>(
                      value: _relationship,
                      decoration: _inputDecoration(
                        hint: 'Select relationship',
                        prefixIcon: Icons.people_outline,
                        hasError: _relationshipError != null,
                      ),
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppColors.textSecondary),
                      items: _relationships.map((r) {
                        return DropdownMenuItem(
                          value: r,
                          child: Text(r, style: AppText.body),
                        );
                      }).toList(),
                      onChanged: (value) => setState(() {
                        _relationship = value;
                        if (value != null) _relationshipError = null;
                      }),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),
                ],

                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: _Field(
                        label: 'Blood Type',
                        errorText: _bloodTypeError,
                        child: DropdownButtonFormField<String>(
                          value: selectedBloodType,
                          decoration: _inputDecoration(
                            hint: 'Select',
                            prefixIcon: Icons.bloodtype_outlined,
                            hasError: _bloodTypeError != null,
                          ),
                          icon: const Icon(Icons.arrow_drop_down,
                              color: AppColors.textSecondary),
                          items: _bloodTypes.map((type) {
                            return DropdownMenuItem(
                              value: type,
                              child: Text(type, style: AppText.body),
                            );
                          }).toList(),
                          onChanged: (value) => setState(() {
                            selectedBloodType = value;
                            if (value != null) _bloodTypeError = null;
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.md),
                    Expanded(
                      flex: 2,
                      child: _Field(
                        label: 'Units Needed',
                        errorText: _unitsError,
                        child: TextField(
                          controller: unitsController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: _inputDecoration(
                            hint: 'Qty',
                            hasError: _unitsError != null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpace.md),

                _Field(
                  label: 'Hospital',
                  helper: 'Start typing to find Kenyan hospitals.',
                  errorText: _hospitalError,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: hospitalController,
                        onChanged: _onHospitalChanged,
                        textCapitalization: TextCapitalization.words,
                        decoration: _inputDecoration(
                          hint: 'Search hospital...',
                          prefixIcon: Icons.local_hospital_outlined,
                          hasError: _hospitalError != null,
                          suffix: _hospitalLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : (_hospitalPlaceId != null
                                  ? const Icon(Icons.check_circle,
                                      color: AppColors.success)
                                  : null),
                        ),
                      ),

                      if (_hospitalSuggestions.isNotEmpty) ...[
                        const SizedBox(height: AppSpace.xs),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Column(
                            children: _hospitalSuggestions.map((s) {
                              return InkWell(
                                onTap: () => _onHospitalSuggestionTapped(s),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.md),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.all(AppSpace.md),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.local_hospital_outlined,
                                        size: 18,
                                        color: AppColors.primary,
                                      ),
                                      const SizedBox(width: AppSpace.sm),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.mainText,
                                              style: AppText.body,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                            if (s.secondaryText.isNotEmpty)
                                              Text(
                                                s.secondaryText,
                                                style: AppText.caption
                                                    .copyWith(
                                                  color: AppColors
                                                      .textTertiary,
                                                ),
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpace.xs),
                          child: Text(
                            'Powered by Google',
                            style: AppText.caption.copyWith(
                              color: AppColors.textTertiary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpace.md),

                _Field(
                  label: 'Contact Number',
                  helper: 'Visible to donors only after they offer to help.',
                  errorText: _contactError,
                  child: TextField(
                    controller: contactController,
                    keyboardType: TextInputType.phone,
                    decoration: _inputDecoration(
                      hint: '0712345678',
                      prefixIcon: Icons.phone_outlined,
                      hasError: _contactError != null,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpace.lg),

                Text('Urgency Level', style: AppText.label),
                const SizedBox(height: AppSpace.xs),
                Row(
                  children: [
                    Expanded(
                      child: _urgencyPill(
                        label: 'Critical',
                        icon: Icons.warning_amber_outlined,
                        value: 'critical',
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: _urgencyPill(
                        label: 'Urgent',
                        icon: Icons.priority_high,
                        value: 'urgent',
                      ),
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: _urgencyPill(
                        label: 'Normal',
                        icon: Icons.schedule,
                        value: 'normal',
                      ),
                    ),
                  ],
                ),

                if (_urgency == 'normal') ...[
                  const SizedBox(height: AppSpace.md),
                  Text('When is it needed?', style: AppText.label),
                  const SizedBox(height: AppSpace.xs),
                  Wrap(
                    spacing: AppSpace.sm,
                    runSpacing: AppSpace.sm,
                    children: [
                      _neededByChip(label: 'Today', value: 'today'),
                      _neededByChip(label: 'Tomorrow', value: 'tomorrow'),
                      _neededByChip(label: 'Within 3 days', value: '3days'),
                      _neededByChip(label: 'Within a week', value: 'week'),
                    ],
                  ),
                ],

                const SizedBox(height: AppSpace.xl),

                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    boxShadow: isLoading ? [] : AppShadow.button,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton.icon(
                      onPressed: isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.disabled,
                        disabledForegroundColor: AppColors.textTertiary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      icon: isLoading
                          ? const SizedBox.shrink()
                          : const Icon(Icons.send,
                              color: Colors.white, size: 18),
                      label: isLoading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text('Submit Request', style: AppText.button),
                    ),
                  ),
                ),

                const SizedBox(height: AppSpace.sm),

                Center(
                  child: Text(
                    'Your request will be broadcasted to nearby eligible donors immediately.',
                    style: AppText.caption.copyWith(
                      color: AppColors.textTertiary,
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestingForToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _toggleOption(
              label: 'For myself',
              isSelected: _requestingFor == 'myself',
              onTap: () => setState(() {
                _requestingFor = 'myself';
                _applyRequestingForMode();
                _patientNameError = null;
                _relationshipError = null;
              }),
            ),
          ),
          Expanded(
            child: _toggleOption(
              label: 'For someone else',
              isSelected: _requestingFor == 'someone_else',
              onTap: () => setState(() {
                _requestingFor = 'someone_else';
                _applyRequestingForMode();
                _patientNameError = null;
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: AppText.body.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _urgencyPill({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _urgency == value;
    return GestureDetector(
      onTap: () => setState(() {
        _urgency = value;
        if (value != 'normal') _neededBy = null;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            vertical: AppSpace.sm, horizontal: AppSpace.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.textPrimary.withOpacity(0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isSelected ? AppColors.textPrimary : AppColors.border,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: AppText.caption.copyWith(
                  color: isSelected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight:
                      isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _neededByChip({required String label, required String value}) {
    final isSelected = _neededBy == value;
    return GestureDetector(
      onTap: () => setState(() => _neededBy = isSelected ? null : value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.sm),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            color: isSelected ? Colors.white : AppColors.textSecondary,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffix,
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
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.background,
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

class _Field extends StatelessWidget {
  final String label;
  final String? helper;
  final String? errorText;
  final Widget child;

  const _Field({
    required this.label,
    this.helper,
    this.errorText,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: AppSpace.xs),
        child,
        if (errorText != null) ...[
          const SizedBox(height: AppSpace.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline,
                    size: 14, color: AppColors.critical),
                const SizedBox(width: AppSpace.xs),
                Expanded(
                  child: Text(
                    errorText!,
                    style: AppText.caption.copyWith(
                      color: AppColors.critical,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ] else if (helper != null) ...[
          const SizedBox(height: AppSpace.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
            child: Text(
              helper!,
              style: AppText.caption.copyWith(
                color: AppColors.textTertiary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}