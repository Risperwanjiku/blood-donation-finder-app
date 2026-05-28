import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/legal_content.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // Form state
  String? selectedBloodType;
  String? selectedGender;
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _agreedToTerms = false;

  // Controllers
  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final locationController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  // Focus nodes — so we can move between fields with "Next" on the keyboard
  final nameFocus = FocusNode();
  final emailFocus = FocusNode();
  final phoneFocus = FocusNode();
  final locationFocus = FocusNode();
  final passwordFocus = FocusNode();
  final confirmPasswordFocus = FocusNode();

  // Per-field error messages (null = no error, string = show this error)
  String? _nameError;
  String? _emailError;
  String? _phoneError;
  String? _locationError;
  String? _passwordError;
  String? _confirmPasswordError;
  // New inline errors for the dropdowns + terms checkbox (instead of snackbars)
  String? _bloodTypeError;
  String? _genderError;
  String? _termsError;

  // Validity flags — used to show green border when input is valid
  bool _emailValid = false;
  bool _phoneValid = false;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Blood types
  final List<String> _bloodTypes = const [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-',
  ];

  @override
  void initState() {
    super.initState();
    // Listen for typing to do real-time validation on email and phone
    emailController.addListener(_validateEmailLive);
    phoneController.addListener(_validatePhoneLive);
  }

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    locationController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    nameFocus.dispose();
    emailFocus.dispose();
    phoneFocus.dispose();
    locationFocus.dispose();
    passwordFocus.dispose();
    confirmPasswordFocus.dispose();
    super.dispose();
  }

  // ============================================================
  // Real-time validation (runs as user types)
  // ============================================================
  void _validateEmailLive() {
    final text = emailController.text.trim();
    final valid = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(text);
    if (valid != _emailValid || (_emailError != null && valid)) {
      setState(() {
        _emailValid = valid;
        if (valid) _emailError = null;
      });
    }
  }

  void _validatePhoneLive() {
    final text = phoneController.text.trim();
    final valid = _isValidKenyanPhone(text);
    if (valid != _phoneValid || (_phoneError != null && valid)) {
      setState(() {
        _phoneValid = valid;
        if (valid) _phoneError = null;
      });
    }
  }

  // ============================================================
  // Validation helpers
  // ============================================================
  bool _isValidKenyanPhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    final local = RegExp(r'^(07|01)\d{8}$');
    final international = RegExp(r'^\+254[71]\d{8}$');
    return local.hasMatch(cleaned) || international.hasMatch(cleaned);
  }

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    if (cleaned.startsWith('+254')) {
      return '0${cleaned.substring(4)}';
    }
    return cleaned;
  }

  bool _isValidPassword(String password) {
    if (password.length < 8) return false;
    final hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
    final hasNumber = RegExp(r'\d').hasMatch(password);
    return hasLetter && hasNumber;
  }

  // Returns true if all fields pass validation. Sets per-field errors.
  bool _validateAll() {
    setState(() {
      _nameError = null;
      _emailError = null;
      _phoneError = null;
      _locationError = null;
      _passwordError = null;
      _confirmPasswordError = null;
      _bloodTypeError = null;
      _genderError = null;
      _termsError = null;
    });

    bool ok = true;

    if (nameController.text.trim().isEmpty) {
      setState(() => _nameError = "Please enter your full name");
      ok = false;
    } else if (nameController.text.trim().length < 3) {
      setState(() => _nameError = "Name must be at least 3 characters");
      ok = false;
    }

    if (emailController.text.trim().isEmpty) {
      setState(() => _emailError = "Please enter your email");
      ok = false;
    } else if (!_emailValid) {
      setState(() => _emailError = "Please enter a valid email");
      ok = false;
    }

    if (phoneController.text.trim().isEmpty) {
      setState(() => _phoneError = "Please enter your phone number");
      ok = false;
    } else if (!_phoneValid) {
      setState(() =>
          _phoneError = "Use 0712345678 or +254712345678 format");
      ok = false;
    }

    if (locationController.text.trim().isEmpty) {
      setState(() => _locationError = "Please enter your location");
      ok = false;
    }

    if (passwordController.text.isEmpty) {
      setState(() => _passwordError = "Please enter a password");
      ok = false;
    } else if (!_isValidPassword(passwordController.text)) {
      setState(() => _passwordError =
          "At least 8 characters with letters and numbers");
      ok = false;
    }

    if (confirmPasswordController.text != passwordController.text) {
      setState(() => _confirmPasswordError = "Passwords do not match");
      ok = false;
    }

    // Inline errors for dropdowns + terms — no more stacked snackbars
    if (selectedBloodType == null) {
      setState(() => _bloodTypeError = "Please select your blood type");
      ok = false;
    }

    if (selectedGender == null) {
      setState(() => _genderError = "Please select your gender");
      ok = false;
    }

    if (!_agreedToTerms) {
      setState(() =>
          _termsError = "Please agree to the Terms and Privacy Policy");
      ok = false;
    }

    return ok;
  }

  // ============================================================
  // Submit — writes /users + /public_profiles atomically.
  // If the Firestore write fails after auth user is created, we
  // roll back the auth user so we don't leave an orphaned account.
  // ============================================================
  Future<void> signUp() async {
    if (!_validateAll()) return;

    setState(() => isLoading = true);

    try {
      // 1. Create the auth user
      final userCredential = await _auth.createUserWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final uid = userCredential.user!.uid;

      // 2. Send verification email (non-blocking — fake/test emails fail silently)
      try {
        await userCredential.user?.sendEmailVerification();
      } catch (_) {
        // Continue silently
      }

      // 3. Atomic batch write — private profile + public profile together.
      //    Wrapped in its own try/catch so we can roll back the auth user
      //    if Firestore write fails (otherwise we'd leave an orphan account
      //    that can log in but has no profile).
      final batch = _firestore.batch();

      // 3a. Private profile — full PII (incl. gender), only owner can read.
      //     Gender lives ONLY here, never in public_profiles (data minimization).
      //     email_verified removed — Firebase Auth is the source of truth via
      //     FirebaseAuth.instance.currentUser?.emailVerified.
      final userRef = _firestore.collection('users').doc(uid);
      batch.set(userRef, {
        'uid': uid,
        'name': nameController.text.trim(),
        'email': emailController.text.trim(),
        'phone': _normalizePhone(phoneController.text.trim()),
        'location': locationController.text.trim(),
        'blood_type': selectedBloodType,
        'gender': selectedGender,
        'is_available': true,
        'profile_image': '',
        'created_at': FieldValue.serverTimestamp(),
        'total_donations': 0,
        'lives_saved': 0,
        'notifications_enabled': true,
        'terms_accepted_at': FieldValue.serverTimestamp(),
        'terms_version': LegalContent.termsVersion,
      });

      // 3b. Public profile — minimum fields for donor matching only.
      //     Gender deliberately NOT included here.
      final publicRef = _firestore.collection('public_profiles').doc(uid);
      batch.set(publicRef, {
        'blood_type': selectedBloodType,
        'is_available': true,
        'first_name': nameController.text.trim().split(' ').first,
        'profile_pic': '',
      });

      try {
        await batch.commit();
      } catch (firestoreError) {
        // Roll back: delete the orphan auth user so the email is freed
        // up for retry and we don't leave a half-created account.
        try {
          await userCredential.user?.delete();
        } catch (_) {
          // Best-effort. If we can't delete, the user can't sign up again
          // with this email until support intervenes — but that's better
          // than silently letting them think it worked.
        }
        if (!mounted) return;
        setState(() => isLoading = false);
        _showError(
          "Couldn't save your profile. Your sign-up was reverted — "
          "please try again.",
        );
        return;
      }

      if (!mounted) return;
      setState(() => isLoading = false);

      Get.snackbar(
        "Welcome to DamuLink",
        "Account created. Check your email to verify your account.",
        snackPosition: SnackPosition.TOP,
        backgroundColor: AppColors.successSoft,
        colorText: AppColors.success,
        duration: const Duration(seconds: 5),
      );

      Get.offAllNamed('/login');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);

      if (e.code == 'weak-password') {
        setState(() => _passwordError = "Password is too weak");
      } else if (e.code == 'email-already-in-use') {
        setState(() =>
            _emailError = "An account already exists with this email");
      } else if (e.code == 'invalid-email') {
        setState(() => _emailError = "Invalid email address");
      } else {
        _showError("Registration failed. Please try again.");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
      _showError("Something went wrong. Please try again.");
    }
  }

  void _showError(String message) {
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DamuLinkLogo(size: 28),
            const SizedBox(width: AppSpace.sm),
            Text(
              "DamuLink",
              style: AppText.heading.copyWith(color: AppColors.primary),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.lg, AppSpace.sm, AppSpace.lg, AppSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: AppSpace.md),

              // Header
              Center(
                child: Column(
                  children: [
                    Text("Create Account", style: AppText.title),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      "Sign up to give or receive blood support.",
                      style: AppText.caption,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // Full Name
              _Field(
                label: "Full Name",
                errorText: _nameError,
                child: TextField(
                  controller: nameController,
                  focusNode: nameFocus,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => emailFocus.requestFocus(),
                  decoration: _inputDecoration(
                    hint: "Enter your full name",
                    hasError: _nameError != null,
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Email
              _Field(
                label: "Email",
                errorText: _emailError,
                child: TextField(
                  controller: emailController,
                  focusNode: emailFocus,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => phoneFocus.requestFocus(),
                  decoration: _inputDecoration(
                    hint: "you@example.com",
                    hasError: _emailError != null,
                    isValid: _emailValid && emailController.text.isNotEmpty,
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Phone
              _Field(
                label: "Phone Number",
                helper: "Used to contact you if a donor responds. "
                    "Never shared until you act.",
                errorText: _phoneError,
                child: TextField(
                  controller: phoneController,
                  focusNode: phoneFocus,
                  keyboardType: TextInputType.phone,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => locationFocus.requestFocus(),
                  decoration: _inputDecoration(
                    hint: "0712345678 or +254712345678",
                    hasError: _phoneError != null,
                    isValid: _phoneValid && phoneController.text.isNotEmpty,
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Location
              _Field(
                label: "Location",
                errorText: _locationError,
                child: TextField(
                  controller: locationController,
                  focusNode: locationFocus,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => passwordFocus.requestFocus(),
                  decoration: _inputDecoration(
                    hint: "e.g. Westlands, Nairobi",
                    prefixIcon: Icons.location_on_outlined,
                    hasError: _locationError != null,
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Blood Type
              _Field(
                label: "Blood Type",
                helper: "Helps us match you with compatible blood requests.",
                errorText: _bloodTypeError,
                child: DropdownButtonFormField<String>(
                  value: selectedBloodType,
                  decoration: _inputDecoration(
                    hint: "Select your blood type",
                    prefixIcon: Icons.bloodtype_outlined,
                    hasError: _bloodTypeError != null,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.textSecondary,
                  ),
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

              const SizedBox(height: AppSpace.md),

              // Gender — used only to calculate the donor's safe interval
              _Field(
                label: "Gender",
                helper: "Kenya recommends men donate every 3 months and "
                    "women every 4 months. We use this only to remind you "
                    "when you can safely donate again.",
                errorText: _genderError,
                child: DropdownButtonFormField<String>(
                  value: selectedGender,
                  decoration: _inputDecoration(
                    hint: "Select your gender",
                    prefixIcon: Icons.person_outline,
                    hasError: _genderError != null,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: AppColors.textSecondary,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                    DropdownMenuItem(
                      value: 'Prefer not to say',
                      child: Text('Prefer not to say'),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    selectedGender = value;
                    if (value != null) _genderError = null;
                  }),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Password
              _Field(
                label: "Password",
                helper: "At least 8 characters, with letters and numbers.",
                errorText: _passwordError,
                child: TextField(
                  controller: passwordController,
                  focusNode: passwordFocus,
                  obscureText: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => confirmPasswordFocus.requestFocus(),
                  decoration: _inputDecoration(
                    hint: "Create a password",
                    prefixIcon: Icons.lock_outline,
                    hasError: _passwordError != null,
                    suffix: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Confirm Password
              _Field(
                label: "Confirm Password",
                errorText: _confirmPasswordError,
                child: TextField(
                  controller: confirmPasswordController,
                  focusNode: confirmPasswordFocus,
                  obscureText: _obscureConfirmPassword,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => signUp(),
                  decoration: _inputDecoration(
                    hint: "Re-enter your password",
                    prefixIcon: Icons.lock_outline,
                    hasError: _confirmPasswordError != null,
                    suffix: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textSecondary,
                      ),
                      onPressed: () => setState(
                        () => _obscureConfirmPassword = !_obscureConfirmPassword,
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // Terms & Privacy consent
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: _termsError != null
                        ? AppColors.critical
                        : AppColors.border,
                  ),
                ),
                child: InkWell(
                  onTap: () => setState(() {
                    _agreedToTerms = !_agreedToTerms;
                    if (_agreedToTerms) _termsError = null;
                  }),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: Checkbox(
                            value: _agreedToTerms,
                            onChanged: (v) => setState(() {
                              _agreedToTerms = v ?? false;
                              if (_agreedToTerms) _termsError = null;
                            }),
                            activeColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: AppText.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            children: [
                              const TextSpan(text: "I agree to DamuLink's "),
                              TextSpan(
                                text: "Terms of Service",
                                style: AppText.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(text: " and "),
                              TextSpan(
                                text: "Privacy Policy",
                                style: AppText.caption.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const TextSpan(
                                text:
                                    ". I understand my blood type and contact "
                                    "details are used to match me with blood "
                                    "requests.",
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Inline terms error — same pattern as other field errors
              if (_termsError != null)
                Padding(
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
                          _termsError!,
                          style: AppText.caption.copyWith(
                            color: AppColors.critical,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Tappable Terms / Privacy buttons (kept simple — separate row)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.sm),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: LegalContent.showTerms,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        "Read Terms",
                        style: AppText.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpace.xs),
                    TextButton(
                      onPressed: LegalContent.showPrivacy,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.sm,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 32),
                      ),
                      child: Text(
                        "Read Privacy Policy",
                        style: AppText.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.lg),

              // Sign Up button
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  boxShadow:
                      (_agreedToTerms && !isLoading) ? AppShadow.button : [],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed:
                        (isLoading || !_agreedToTerms) ? null : signUp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.disabled,
                      disabledForegroundColor: AppColors.textTertiary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
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
                        : Text("Sign Up", style: AppText.button),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.lg),

              // Login link
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Already have an account? ",
                      style: AppText.caption,
                    ),
                    GestureDetector(
                      onTap: () => Get.offAllNamed('/login'),
                      child: Text(
                        "Log in",
                        style: AppText.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpace.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Input decoration helper — supports error and valid states
  // ============================================================
  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffix,
    bool hasError = false,
    bool isValid = false,
  }) {
    Color borderColor;
    if (hasError) {
      borderColor = AppColors.critical;
    } else if (isValid) {
      borderColor = AppColors.success;
    } else {
      borderColor = AppColors.border;
    }

    Color focusedBorderColor = hasError
        ? AppColors.critical
        : (isValid ? AppColors.success : AppColors.primary);

    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: AppColors.textSecondary, size: 20)
          : null,
      suffixIcon: suffix,
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
        borderSide: BorderSide(color: focusedBorderColor, width: 1.5),
      ),
    );
  }
}

// ============================================================
// Field block — label + input + optional helper / error text
// ============================================================
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
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppColors.critical,
                ),
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

// ============================================================
// DamuLink logo — pure Flutter, no image file needed
// ============================================================
class _DamuLinkLogo extends StatelessWidget {
  final double size;
  const _DamuLinkLogo({this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.2,
      child: CustomPaint(painter: _BloodDropPainter()),
    );
  }
}

class _BloodDropPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final path = Path();
    final w = size.width;
    final h = size.height;

    path.moveTo(w * 0.5, h * 0.08);
    path.cubicTo(
      w * 0.5, h * 0.08,
      w * 0.2, h * 0.45,
      w * 0.2, h * 0.68,
    );
    path.cubicTo(
      w * 0.2, h * 0.86,
      w * 0.34, h * 0.95,
      w * 0.5, h * 0.95,
    );
    path.cubicTo(
      w * 0.66, h * 0.95,
      w * 0.8, h * 0.86,
      w * 0.8, h * 0.68,
    );
    path.cubicTo(
      w * 0.8, h * 0.45,
      w * 0.5, h * 0.08,
      w * 0.5, h * 0.08,
    );
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}