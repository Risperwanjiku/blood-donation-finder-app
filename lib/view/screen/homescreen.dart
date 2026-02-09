import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:test_app/view/screen/dashboard.dart';
import 'package:test_app/view/screen/blood_requests/blood_requests.dart';
import 'package:test_app/view/screen/edit_profile.dart';
import 'package:test_app/view/screen/settings.dart' as app_settings;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';

var screenTitles = ["Home", "Requests", "Profile", "Settings"];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int selectedScreenIndex = 0;
  Key profileKey = UniqueKey();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    var screens = [
      const Dashboard(),
      const BloodRequests(),
      EditProfile(key: profileKey),
      const app_settings.Settings()  // Use the alias
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(screenTitles[selectedScreenIndex]),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          // Notification bell icon with badge
          StreamBuilder<QuerySnapshot>(
            stream: _auth.currentUser != null
                ? _firestore
                .collection('notifications')
                .where('recipient_id', isEqualTo: _auth.currentUser!.uid)
                .where('read', isEqualTo: false)
                .snapshots()
                : null,
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.length;
              }

              return Stack(
                children: [
                  IconButton(
                    icon: Icon(Icons.notifications),
                    onPressed: () {
                      Get.toNamed('/notifications');
                    },
                  ),
                  if (unreadCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.yellow,
                          shape: BoxShape.circle,
                        ),
                        constraints: BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          unreadCount > 9 ? '9+' : unreadCount.toString(),
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: screens[selectedScreenIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedScreenIndex,
        selectedItemColor: primaryColor,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            selectedScreenIndex = index;
            if (index == 2) {
              profileKey = UniqueKey();
            }
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bloodtype),
            label: 'Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}