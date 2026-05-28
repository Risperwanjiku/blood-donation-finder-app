import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:damulink/configs/theme.dart';
import 'package:damulink/view/screen/blood_requests/my_requests_list.dart';
import 'package:damulink/view/screen/donor/donor_browse.dart';

class BloodRequests extends StatefulWidget {
  const BloodRequests({super.key});

  @override
  State<BloodRequests> createState() => _BloodRequestsState();
}

class _BloodRequestsState extends State<BloodRequests> {
  int _selectedView = 0;

  Future<void> _openRequestForm() async {
    HapticFeedback.lightImpact();
    await Get.toNamed('/request-form');
  }

  void _switchView(int index) {
    if (_selectedView == index) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedView = index);
  }

  @override
  Widget build(BuildContext context) {
    final isMyRequests = _selectedView == 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          isMyRequests ? 'My Blood Requests' : 'Donate Blood',
          style: AppText.heading.copyWith(color: AppColors.textPrimary),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMyRequests
                      ? "Manage requests you've posted"
                      : "Pending requests near you",
                  style: AppText.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpace.sm),
                _buildToggle(),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _selectedView,
        children: const [
          MyRequestsList(),
          DonorBrowseScreen(),
        ],
      ),
      // FAB only on My Requests — donors don't post from Browse
      floatingActionButton: isMyRequests
          ? FloatingActionButton.extended(
              onPressed: _openRequestForm,
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 4,
              icon: const Icon(Icons.add),
              label: const Text(
                'New Request',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            )
          : null,
    );
  }

  Widget _buildToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _ToggleTab(
              label: 'My Requests',
              icon: Icons.assignment_outlined,
              isSelected: _selectedView == 0,
              onTap: () => _switchView(0),
            ),
          ),
          Expanded(
            child: _ToggleTab(
              label: 'Donate Blood',
              icon: Icons.volunteer_activism_outlined,
              isSelected: _selectedView == 1,
              onTap: () => _switchView(1),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}