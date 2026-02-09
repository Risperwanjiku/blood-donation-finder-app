import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:test_app/configs/colors.dart';
import 'package:test_app/controller/login_contoller.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:test_app/services/notification_service.dart';

LoginController loginController = Get.put(LoginController());
var store = GetStorage();

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  TextEditingController emailController = TextEditingController();
  TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool _obscurePassword = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    var storedEmail = store.read("user_email") ?? '';
    emailController.text = storedEmail;
  }

  // Login function
  Future<void> login() async {
    if (emailController.text.trim().isEmpty) {
      Get.snackbar("Error", "Please enter your email");
      return;
    }
    if (passwordController.text.isEmpty) {
      Get.snackbar("Error", "Please enter your password");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

        store.write("user_id", userCredential.user!.uid);
        store.write("user_name", userData['name'] ?? '');
        store.write("user_email", userData['email'] ?? '');
        store.write("user_phone", userData['phone'] ?? '');
        store.write("blood_type", userData['blood_type'] ?? '');
        store.write("user_location", userData['location'] ?? '');
        store.write("profile_image", userData['profile_image'] ?? '');
        store.write("is_available", userData['is_available'] ?? true);

        await _notificationService.initialize();

        loginController.setItsLoginIn(true);

        setState(() {
          isLoading = false;
        });

        Get.snackbar("Success", "Welcome back, ${userData['name']}!");
        Get.offAllNamed('/homeScreen');
      } else {
        setState(() {
          isLoading = false;
        });
        Get.snackbar("Error", "User data not found");
      }
    } on FirebaseAuthException catch (e) {
      setState(() {
        isLoading = false;
      });

      String errorMessage = "Login failed";
      if (e.code == 'user-not-found') {
        errorMessage = "No account found with this email";
      } else if (e.code == 'wrong-password') {
        errorMessage = "Incorrect password";
      } else if (e.code == 'invalid-email') {
        errorMessage = "Invalid email address";
      } else if (e.code == 'user-disabled') {
        errorMessage = "This account has been disabled";
      }
      Get.snackbar("Error", errorMessage);
    } catch (e) {
      setState(() {
        isLoading = false;
      });
      Get.snackbar("Error", "Something went wrong: $e");
    }
  }

  // Forgot Password function
  void showForgotPasswordDialog() {
    TextEditingController resetEmailController = TextEditingController();
    resetEmailController.text = emailController.text.trim();

    showDialog(
      context: context,
      builder: (context) {
        bool isSending = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Row(
                children: [
                  Icon(Icons.lock_reset, color: primaryColor),
                  SizedBox(width: 10),
                  Text("Reset Password"),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Enter your email address and we'll send you a link to reset your password.",
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  SizedBox(height: 20),
                  TextField(
                    controller: resetEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: "Enter your email",
                      prefixIcon: Icon(Icons.email_outlined, color: primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: primaryColor, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                    String email = resetEmailController.text.trim();

                    if (email.isEmpty) {
                      Get.snackbar("Error", "Please enter your email");
                      return;
                    }

                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$')
                        .hasMatch(email)) {
                      Get.snackbar("Error", "Please enter a valid email");
                      return;
                    }

                    setDialogState(() {
                      isSending = true;
                    });

                    try {
                      await _auth.sendPasswordResetEmail(email: email);

                      setDialogState(() {
                        isSending = false;
                      });

                      Navigator.pop(context);

                      // Show success dialog
                      showDialog(
                        context: this.context,
                        builder: (context) => AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(height: 10),
                              Container(
                                padding: EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.mark_email_read,
                                  color: Colors.green,
                                  size: 50,
                                ),
                              ),
                              SizedBox(height: 20),
                              Text(
                                "Email Sent!",
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                "We've sent a password reset link to:",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[600]),
                              ),
                              SizedBox(height: 5),
                              Text(
                                email,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor,
                                ),
                              ),
                              SizedBox(height: 10),
                              Text(
                                "Check your inbox and follow the link to reset your password.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          actions: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => Navigator.pop(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryColor,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: Text(
                                  "OK",
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    } on FirebaseAuthException catch (e) {
                      setDialogState(() {
                        isSending = false;
                      });

                      String errorMessage = "Failed to send reset email";
                      if (e.code == 'user-not-found') {
                        errorMessage = "No account found with this email";
                      } else if (e.code == 'invalid-email') {
                        errorMessage = "Invalid email address";
                      }
                      Get.snackbar("Error", errorMessage);
                    } catch (e) {
                      setDialogState(() {
                        isSending = false;
                      });
                      Get.snackbar("Error", "Something went wrong: $e");
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSending
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                      : Text(
                    "Send Link",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        title: Text("Login Screen"),
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(30, 0, 30, 5),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: primaryColor.withOpacity(0.1),
                      border: Border.all(color: primaryColor, width: 3),
                    ),
                    child: Icon(
                      Icons.bloodtype,
                      size: 60,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              Center(
                child: Column(
                  children: [
                    Text(
                      "Save Lives",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                    Text(
                      "Donate Blood",
                      style: TextStyle(
                        fontSize: 16,
                        color: lightTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 40),
              // Email Field
              Text(
                "Enter email",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: "enter your email",
                  prefixIcon: Icon(Icons.email_outlined, color: primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: primaryColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Password Field
              Text(
                "Enter password",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                ),
              ),
              SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: "enter password",
                  prefixIcon: Icon(Icons.lock_outline, color: primaryColor),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.grey,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(color: Colors.grey[400]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide(
                      color: primaryColor,
                      width: 2,
                    ),
                  ),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Forgot Password Link
              Align(
                alignment: Alignment.centerRight,
                child: GestureDetector(
                  onTap: showForgotPasswordDialog,
                  child: Text(
                    "Forgot Password?",
                    style: TextStyle(
                      fontSize: 14,
                      color: primaryColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 30),
              // Login Button
              Center(
                child: GestureDetector(
                  onTap: isLoading ? null : login,
                  child: Container(
                    alignment: Alignment.center,
                    height: 55,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isLoading ? Colors.grey : primaryColor,
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withOpacity(0.3),
                          spreadRadius: 1,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: isLoading
                        ? CircularProgressIndicator(color: Colors.white)
                        : Text(
                      "Login",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),
              // Signup Link
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Not Registered? ",
                    style: TextStyle(fontSize: 14, color: textColor),
                  ),
                  GestureDetector(
                    onTap: () {
                      Get.toNamed('/signup');
                    },
                    child: Text(
                      "Signup",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }
}