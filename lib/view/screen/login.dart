import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/controller/login_controller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

LoginController loginController = Get.put(LoginController());
var store = GetStorage();

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  // Focus nodes — for keyboard "Next" navigation
  final emailFocus = FocusNode();
  final passwordFocus = FocusNode();

  // UI state
  bool isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  // Per-field errors
  String? _emailError;
  String? _passwordError;

  // Firebase
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();

    // Honor "remember me" preference — only pre-fill if the user
    // explicitly opted in on a previous login.
    final remember = store.read("remember_me") ?? false;
    _rememberMe = remember;
    if (remember) {
      final storedEmail = store.read("user_email") ?? '';
      emailController.text = storedEmail;
    }

    // Clear field errors as soon as user starts retyping.
    emailController.addListener(_clearEmailErrorOnType);
    passwordController.addListener(_clearPasswordErrorOnType);
  }

  void _clearEmailErrorOnType() {
    if (_emailError != null) {
      setState(() => _emailError = null);
    }
  }

  void _clearPasswordErrorOnType() {
    if (_passwordError != null) {
      setState(() => _passwordError = null);
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    emailFocus.dispose();
    passwordFocus.dispose();
    super.dispose();
  }

  // ============================================================
  // Login
  // ============================================================
  Future<void> login() async {
    setState(() {
      _emailError = null;
      _passwordError = null;
    });

    bool hasError = false;
    if (emailController.text.trim().isEmpty) {
      setState(() => _emailError = "Please enter your email");
      hasError = true;
    }
    if (passwordController.text.isEmpty) {
      setState(() => _passwordError = "Please enter your password");
      hasError = true;
    }
    if (hasError) return;

    setState(() => isLoading = true);

    try {
      final userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      final userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;
        setState(() => isLoading = false);
        _showError("User data not found. Please contact support.");
        return;
      }

      final userData = userDoc.data() as Map<String, dynamic>;

      // Session data — always stored, cleared on logout
      store.write("user_id", userCredential.user!.uid);
      store.write("user_name", userData['name'] ?? '');
      store.write("user_phone", userData['phone'] ?? '');
      store.write("blood_type", userData['blood_type'] ?? '');
      store.write("user_location", userData['location'] ?? '');
      store.write("profile_image", userData['profile_image'] ?? '');
      store.write("is_available", userData['is_available'] ?? true);

      // Only persist email if user opted in
      if (_rememberMe) {
        store.write("remember_me", true);
        store.write("user_email", userData['email'] ?? '');
      } else {
        store.write("remember_me", false);
        store.remove("user_email");
      }

      loginController.setItsLoginIn(true);

      // NOTE: email_verified sync block removed.
      // FirebaseAuth.instance.currentUser.emailVerified is the
      // source of truth — duplicating it on Firestore was pointless
      // and recreated the field we deliberately removed from signup.

      if (!mounted) return;
      setState(() => isLoading = false);

      // ============================================================
      // Navigate to home.
      //
      // The "Welcome back" snackbar was removed because Get.snackbar()
      // called around Get.offAllNamed() reliably triggers
      // "No Overlay widget found" — the snackbar can't attach to either
      // the dying LoginScreen's overlay or the freshly-mounted
      // HomeScreen's overlay. Future.delayed didn't fix it either.
      //
      // To welcome the user, do it from HomeScreen's initState using
      // WidgetsBinding.instance.addPostFrameCallback. That's the only
      // reliably safe place because by then the HomeScreen is fully
      // mounted with its own overlay.
      // ============================================================
      store.write('show_welcome_back', true);
      Get.offAllNamed('/homeScreen');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);

      switch (e.code) {
        case 'user-not-found':
        case 'wrong-password':
        case 'invalid-credential':
        case 'invalid-email':
          setState(() {
            _emailError = "Email or password is incorrect";
            _passwordError = "Email or password is incorrect";
          });
          break;
        case 'user-disabled':
          _showError("This account has been disabled. Contact support.");
          break;
        case 'too-many-requests':
          _showError(
              "Too many failed attempts. Please wait a moment and try again.");
          break;
        case 'network-request-failed':
          _showError("Network error. Check your connection and try again.");
          break;
        default:
          _showError("Login failed. Please try again.");
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
  // Forgot Password — uses showDialog + Navigator.pop for reliable
  // button-driven dismissal. Controller disposed via whenComplete
  // so we don't leak one on every dialog open.
  // ============================================================
  void showForgotPasswordDialog() {
    final resetEmailController = TextEditingController(
      text: emailController.text.trim(),
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        String? resetError;
        bool isSending = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Resolve border colors from current error state so the
            // dialog's email field looks like the login fields when
            // something's wrong.
            final dialogBorderColor = resetError != null
                ? AppColors.critical
                : AppColors.border;
            final dialogFocusedColor = resetError != null
                ? AppColors.critical
                : AppColors.primary;

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lock_reset,
                            color: AppColors.primary),
                        const SizedBox(width: AppSpace.sm),
                        Text("Reset Password", style: AppText.title),
                      ],
                    ),
                    const SizedBox(height: AppSpace.md),
                    Text(
                      "Enter your email and we'll send you a link to reset "
                      "your password.",
                      style: AppText.caption,
                    ),
                    const SizedBox(height: AppSpace.md),
                    TextField(
                      controller: resetEmailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        hintText: "you@example.com",
                        hintStyle: AppText.body
                            .copyWith(color: AppColors.textTertiary),
                        prefixIcon: const Icon(
                          Icons.email_outlined,
                          color: AppColors.textSecondary,
                          size: 22,
                        ),
                        filled: true,
                        fillColor: AppColors.surface,
                        border: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          borderSide:
                              BorderSide(color: dialogBorderColor),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          borderSide:
                              BorderSide(color: dialogBorderColor),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(AppRadius.md),
                          borderSide: BorderSide(
                            color: dialogFocusedColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    if (resetError != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 14,
                            color: AppColors.critical,
                          ),
                          const SizedBox(width: AppSpace.xs),
                          Expanded(
                            child: Text(
                              resetError!,
                              style: AppText.caption
                                  .copyWith(color: AppColors.critical),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: AppSpace.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isSending
                              ? null
                              : () => Navigator.of(dialogContext).pop(),
                          child: Text(
                            "Cancel",
                            style: AppText.button.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpace.sm),
                        ElevatedButton(
                          onPressed: isSending
                              ? null
                              : () async {
                                  final email =
                                      resetEmailController.text.trim();
                                  setDialogState(() => resetError = null);

                                  if (email.isEmpty) {
                                    setDialogState(() => resetError =
                                        "Please enter your email");
                                    return;
                                  }
                                  if (!RegExp(
                                          r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                                      .hasMatch(email)) {
                                    setDialogState(() => resetError =
                                        "Please enter a valid email");
                                    return;
                                  }

                                  setDialogState(() => isSending = true);

                                  try {
                                    await _auth.sendPasswordResetEmail(
                                        email: email);
                                    if (dialogContext.mounted) {
                                      Navigator.of(dialogContext).pop();
                                    }
                                    _showResetSuccess(email);
                                  } on FirebaseAuthException catch (e) {
                                    setDialogState(() {
                                      isSending = false;
                                      if (e.code == 'user-not-found' ||
                                          e.code == 'invalid-email') {
                                        resetError =
                                            "If this email is registered, "
                                            "you'll receive a reset link "
                                            "shortly";
                                      } else {
                                        resetError =
                                            "Couldn't send reset email. "
                                            "Try again.";
                                      }
                                    });
                                  } catch (_) {
                                    setDialogState(() {
                                      isSending = false;
                                      resetError = "Something went wrong";
                                    });
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.lg,
                              vertical: AppSpace.sm,
                            ),
                          ),
                          child: isSending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text("Send Link", style: AppText.button),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() => resetEmailController.dispose());
  }

  void _showResetSuccess(String email) {
    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: const BoxDecoration(
                  color: AppColors.successSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppColors.success,
                  size: 44,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              Text("Check Your Email", style: AppText.title),
              const SizedBox(height: AppSpace.sm),
              Text(
                "If an account exists for this email, you'll receive a "
                "password reset link shortly:",
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                email,
                style: AppText.bodyStrong.copyWith(
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: AppSpace.md),
              // Spam folder reminder — helps users find the email
              Container(
                padding: const EdgeInsets.all(AppSpace.sm),
                decoration: BoxDecoration(
                  color: AppColors.primarySoft,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: AppSpace.sm),
                    Expanded(
                      child: Text(
                        "Don't see it? Check your Spam or Junk folder.",
                        style: AppText.caption.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpace.md),
                  ),
                  child: Text("OK", style: AppText.button),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Build
  // ============================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpace.lg),

              // Logo
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: AppShadow.card,
                  ),
                  child: const Center(
                    child: _DamuLinkLogo(size: 64),
                  ),
                ),
              ),

              const SizedBox(height: AppSpace.md),

              // Brand
              Center(
                child: Text(
                  "DamuLink",
                  style: AppText.title.copyWith(
                    fontSize: 28,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Center(
                child: Text(
                  "Sign in to continue",
                  style: AppText.caption,
                ),
              ),

              const SizedBox(height: AppSpace.xl),

              // Card
              Container(
                padding: const EdgeInsets.all(AppSpace.lg),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  boxShadow: AppShadow.card,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Field(
                      label: "Email",
                      errorText: _emailError,
                      child: TextField(
                        controller: emailController,
                        focusNode: emailFocus,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        onSubmitted: (_) => passwordFocus.requestFocus(),
                        decoration: _inputDecoration(
                          hint: "you@example.com",
                          prefixIcon: Icons.email_outlined,
                          hasError: _emailError != null,
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpace.md),

                    _Field(
                      label: "Password",
                      errorText: _passwordError,
                      child: TextField(
                        controller: passwordController,
                        focusNode: passwordFocus,
                        obscureText: _obscurePassword,
                        autofillHints: const [AutofillHints.password],
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => login(),
                        decoration: _inputDecoration(
                          hint: "Enter your password",
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

                    const SizedBox(height: AppSpace.sm),

                    // Remember me + Forgot Password row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () =>
                              setState(() => _rememberMe = !_rememberMe),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: Checkbox(
                                    value: _rememberMe,
                                    onChanged: (v) => setState(
                                      () => _rememberMe = v ?? false,
                                    ),
                                    activeColor: AppColors.primary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: AppSpace.sm),
                                Text(
                                  "Remember me",
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: showForgotPasswordDialog,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpace.sm,
                              vertical: 0,
                            ),
                            minimumSize: const Size(0, 32),
                          ),
                          child: Text(
                            "Forgot Password?",
                            style: AppText.caption.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: AppSpace.lg),

                    // Sign In button
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: isLoading ? [] : AppShadow.button,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: isLoading ? null : login,
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
                              : Text("Sign In", style: AppText.button),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpace.lg),

                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            "Don't have an account? ",
                            style: AppText.caption,
                          ),
                          GestureDetector(
                            onTap: () => Get.toNamed('/signup'),
                            child: Text(
                              "Sign up",
                              style: AppText.caption.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
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

  InputDecoration _inputDecoration({
    required String hint,
    IconData? prefixIcon,
    Widget? suffix,
    bool hasError = false,
  }) {
    final borderColor = hasError ? AppColors.critical : AppColors.border;
    final focusedColor = hasError ? AppColors.critical : AppColors.primary;

    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, color: AppColors.textSecondary, size: 22)
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
        borderSide: BorderSide(color: focusedColor, width: 1.5),
      ),
    );
  }
}

// ============================================================
// Reusable field block
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
                const Icon(
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
// DamuLink logo — pure Flutter
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