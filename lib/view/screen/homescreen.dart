import 'package:flutter/material.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/view/screen/dashboard.dart';
import 'package:damulink/view/screen/blood_requests/blood_requests.dart';
import 'package:damulink/view/screen/edit_profile.dart';
import 'package:damulink/view/screen/settings.dart' as app_settings;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:damulink/services/notification_service.dart';

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
  final NotificationService _notificationService = NotificationService();
  final _store = GetStorage();

  @override
  void initState() {
    super.initState();
    if (_auth.currentUser != null) {
      _notificationService.initialize();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowWelcomeBack();
    });
  }

  void _maybeShowWelcomeBack() {
    if (!mounted) return;

    final shouldShow = _store.read('show_welcome_back') ?? false;
    if (!shouldShow) return;

    _store.remove('show_welcome_back');

    final name = _store.read('user_name') as String?;
    final message = name != null && name.isNotEmpty
        ? 'Welcome back, $name'
        : "You're signed in";

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: AppSpace.sm),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        margin: const EdgeInsets.all(AppSpace.md),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    var screens = [
      const Dashboard(),
      const BloodRequests(),
      EditProfile(key: profileKey),
      const app_settings.Settings(),
    ];

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: const Padding(
          padding: EdgeInsets.only(left: AppSpace.lg),
          child: Center(child: _DamuLinkLogo(size: 22)),
        ),
        leadingWidth: 56,
        title: Text(
          "DamuLink",
          style: AppText.heading.copyWith(
            color: AppColors.primary,
          ),
        ),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: _auth.currentUser != null
                ? _firestore
                    .collection('notifications')
                    .where('recipient_id',
                        isEqualTo: _auth.currentUser!.uid)
                    .where('read', isEqualTo: false)
                    .snapshots()
                : null,
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.length;
              }

              return Padding(
                padding: const EdgeInsets.only(right: AppSpace.sm),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.notifications_outlined,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () => Get.toNamed('/notifications'),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.surface,
                              width: 1.5,
                            ),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: AppColors.border,
          ),
        ),
      ),
      body: screens[selectedScreenIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(
            top: BorderSide(color: AppColors.border, width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: selectedScreenIndex,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textTertiary,
          backgroundColor: AppColors.surface,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          showSelectedLabels: true,
          showUnselectedLabels: true,
          selectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
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
              icon: Icon(Icons.home_outlined),
              activeIcon: _ActiveNavIcon(icon: Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.bloodtype_outlined),
              activeIcon: _ActiveNavIcon(icon: Icons.bloodtype),
              label: 'Requests',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: _ActiveNavIcon(icon: Icons.person),
              label: 'Profile',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.settings_outlined),
              activeIcon: _ActiveNavIcon(icon: Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}

class _ActiveNavIcon extends StatelessWidget {
  final IconData icon;
  const _ActiveNavIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(7),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: 18,
      ),
    );
  }
}

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