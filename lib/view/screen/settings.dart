import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:test_app/services/notification_service.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  bool notificationsEnabled = true;

  final store = GetStorage();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    notificationsEnabled = store.read("notifications_enabled") ?? true;
  }

  void toggleNotifications(bool value) {
    setState(() {
      notificationsEnabled = value;
    });
    store.write("notifications_enabled", value);
    Get.snackbar(
      "Notifications",
      value ? "Notifications enabled" : "Notifications disabled",
      snackPosition: SnackPosition.TOP,
      duration: const Duration(seconds: 2),
    );
  }

  void showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.lock, color: primaryColor),
              SizedBox(width: 10),
              Text("Privacy Policy"),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPrivacySection(
                  "Data Collection",
                  "We collect your name, phone number, location, and blood type to connect donors with recipients.",
                ),
                SizedBox(height: 15),
                _buildPrivacySection(
                  "Data Usage",
                  "Your information is used solely to facilitate blood donation connections and emergency requests.",
                ),
                SizedBox(height: 15),
                _buildPrivacySection(
                  "Data Sharing",
                  "Your contact details are only shared when you respond to a blood request or when someone needs your blood type.",
                ),
                SizedBox(height: 15),
                _buildPrivacySection(
                  "Data Security",
                  "All data is stored securely using Firebase and is protected with industry-standard encryption.",
                ),
                SizedBox(height: 15),
                _buildPrivacySection(
                  "Account Deletion",
                  "You can delete your account at any time by contacting support. All your data will be permanently removed.",
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close", style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPrivacySection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        SizedBox(height: 5),
        Text(
          content,
          style: TextStyle(fontSize: 13, color: Colors.grey[700]),
        ),
      ],
    );
  }

  void showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 10),
              Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.bloodtype,
                  color: primaryColor,
                  size: 50,
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Blood Donation Finder",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 15),
              Text(
                "Connecting blood donors with those in need. Find nearby donors, request blood, and save lives.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
              ),
              SizedBox(height: 10),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Close", style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void showLogoutConfirmation() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.logout, color: Colors.red),
              SizedBox(width: 10),
              Text("Logout"),
            ],
          ),
          content: Text("Are you sure you want to logout?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                logout();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text('Logout', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void logout() async {
    try {
      // Remove FCM token from Firestore before logout
      await _notificationService.removeToken();

      // Sign out from Firebase
      await _auth.signOut();

      // Clear local storage
      store.remove("user_id");
      store.remove("user_name");
      store.remove("user_email");
      store.remove("user_phone");
      store.remove("user_location");
      store.remove("blood_type");
      store.remove("profile_image");
      store.remove("is_available");

      // Navigate to login
      Get.offAllNamed('/login');

      Get.snackbar(
        "Logged out",
        "You have been logged out successfully",
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      Get.snackbar(
        "Error",
        "Failed to logout: $e",
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Notifications
          ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.notifications, color: primaryColor, size: 24),
            ),
            title: Text(
              "Notifications",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: Switch(
              value: notificationsEnabled,
              onChanged: toggleNotifications,
              activeColor: primaryColor,
            ),
          ),
          Divider(),

          // Language
          ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.language, color: primaryColor, size: 24),
            ),
            title: Text(
              "Language",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            subtitle: Text("English"),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: () {
              Get.snackbar(
                "Language",
                "Only English is available currently",
                snackPosition: SnackPosition.TOP,
              );
            },
          ),
          Divider(),

          // Privacy
          ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.lock, color: primaryColor, size: 24),
            ),
            title: Text(
              "Privacy",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: showPrivacyDialog,
          ),
          Divider(),

          // About
          ListTile(
            leading: Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.info_outline, color: primaryColor, size: 24),
            ),
            title: Text(
              "About",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            trailing: Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            onTap: showAboutDialog,
          ),

          SizedBox(height: 40),
          // Logout Button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              onPressed: showLogoutConfirmation,
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(Icons.logout, color: Colors.white),
              label: Text(
                "Logout",
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}