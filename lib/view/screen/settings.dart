import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/configs/legal_content.dart';
import 'package:damulink/services/notification_service.dart';

class Settings extends StatefulWidget {
  const Settings({super.key});

  @override
  State<Settings> createState() => _SettingsState();
}

class _SettingsState extends State<Settings> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GetStorage _store = GetStorage();

  static const String _appVersion = '1.0.0';

  bool _notificationsEnabled = true;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      // Default to ON if the field has never been set.
      _notificationsEnabled = (data['notifications_enabled'] as bool?) ??
          (_store.read('notifications_enabled') as bool?) ??
          true;
    } catch (_) {
      _notificationsEnabled =
          (_store.read('notifications_enabled') as bool?) ?? true;
    }
    if (mounted) setState(() => _isLoading = false);
  }

  // Writes the preference to /users. Your future onBloodRequestCreated
  // fan-out function will check this flag before pushing an alert, so this
  // toggle genuinely controls whether the donor gets notified.
  Future<void> _toggleNotifications(bool value) async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _notificationsEnabled = value); // optimistic

    try {
      await _firestore
          .collection('users')
          .doc(user.uid)
          .update({'notifications_enabled': value});
      _store.write('notifications_enabled', value);
    } catch (_) {
      if (mounted) {
        setState(() => _notificationsEnabled = !value); // revert
        _showSnack("Couldn't update notifications. Please try again.",
            isError: true);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: const Text('Log out?'),
        content:
            const Text('You will need to sign in again to use DamuLink.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.critical,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child:
                const Text('Log out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear FCM token BEFORE sign-out so the leftover doesn't keep
    // receiving pushes for this account on this device. Must run while
    // we still have auth permission to write /users/{uid}.
    await NotificationService().removeToken();
    await _auth.signOut();
    _store.erase();
    Get.offAllNamed('/login');
  }

  void _showAbout() {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: AppColors.primarySoft,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.bloodtype,
                    color: AppColors.primary, size: 34),
              ),
              const SizedBox(height: AppSpace.md),
              Text('DamuLink', style: AppText.title),
              const SizedBox(height: 2),
              Text('Version $_appVersion', style: AppText.caption),
              const SizedBox(height: AppSpace.md),
              Text(
                'DamuLink connects people who urgently need blood with '
                'compatible, willing donors nearby. Post a request or '
                'offer to help — quickly and safely.',
                style: AppText.body,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpace.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Get.back(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Close',
                      style: TextStyle(color: Colors.white, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
            Expanded(
              child: Text(message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        backgroundColor: isError ? AppColors.critical : AppColors.success,
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
    return Container(
      color: AppColors.background,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.lg, AppSpace.lg, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Settings', style: AppText.title),
                  const SizedBox(height: 4),
                  Text('Manage your alerts and account.',
                      style: AppText.caption),
                  const SizedBox(height: AppSpace.lg),

                  _sectionLabel('NOTIFICATIONS'),
                  _card(
                    child: _toggleRow(
                      icon: Icons.notifications_outlined,
                      title: 'Push Notifications',
                      subtitle: 'Alerts for nearby requests you can help with',
                      value: _notificationsEnabled,
                      onChanged: _toggleNotifications,
                    ),
                  ),
                  const SizedBox(height: AppSpace.lg),

                  _sectionLabel('ABOUT'),
                  _card(
                    child: Column(
                      children: [
                        _navRow(
                          icon: Icons.info_outline,
                          title: 'About DamuLink',
                          onTap: _showAbout,
                        ),
                        _divider(),
                        _navRow(
                          icon: Icons.description_outlined,
                          title: 'Terms of Service',
                          onTap: LegalContent.showTerms,
                        ),
                        _divider(),
                        _navRow(
                          icon: Icons.shield_outlined,
                          title: 'Privacy Policy',
                          onTap: LegalContent.showPrivacy,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _logout,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.critical,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 20),
                      label: Text('Log Out', style: AppText.button),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: AppSpace.sm),
        child: Text(
          text,
          style: AppText.caption.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.md, vertical: AppSpace.xs),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadow.card,
        ),
        child: child,
      );

  Widget _divider() =>
      const Divider(height: 1, color: AppColors.border, indent: 38);

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 22),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.caption),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _navRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: AppSpace.md),
            Expanded(child: Text(title, style: AppText.body)),
            const Icon(Icons.chevron_right,
                size: 20, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}