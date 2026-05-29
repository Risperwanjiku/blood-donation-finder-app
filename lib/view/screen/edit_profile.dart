import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:damulink/configs/theme.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key});

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final GetStorage _store = GetStorage();

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final emailController = TextEditingController();

  String? _selectedLocation;
  String? _selectedBloodType;
  String? _photoUrl;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;
  bool _hasChanges = false;

  // Original values, used to detect whether anything actually changed.
  String _origName = '';
  String _origPhone = '';
  String? _origLocation;
  String? _origBloodType;

  String? _nameError;
  String? _phoneError;
  String? _locationError;
  String? _bloodTypeError;

  static const List<String> _bloodTypes = [
    'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-',
  ];

  // Major Kenyan towns/counties. The donor city filter matches on this
  // value via LocationUtils.extractCity, so a clean single-city selection
  // keeps the filter accurate.
  static const List<String> _locations = [
    'Nairobi', 'Mombasa', 'Kisumu', 'Nakuru', 'Eldoret', 'Thika',
    'Nyeri', 'Machakos', 'Kakamega', 'Kisii', 'Meru', 'Kericho',
    'Naivasha', 'Kitale', 'Garissa', 'Malindi', 'Embu', 'Kitui',
    'Bungoma', 'Kerugoya', "Murang'a", 'Kiambu', 'Narok', 'Voi',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = _auth.currentUser;
    if (user == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    String email = user.email ?? (_store.read('user_email') ?? '');

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      final data = doc.data() ?? {};
      _origName = (data['name'] ?? _store.read('user_name') ?? '').toString();
      _origPhone =
          (data['phone'] ?? _store.read('user_phone') ?? '').toString();
      _origLocation =
          _normalizeToKnownLocation((data['location'] as String?)?.trim());
      _origBloodType = data['blood_type'] as String?;
      _photoUrl = data['photo_url'] as String?;
      if ((data['email'] ?? '').toString().isNotEmpty) {
        email = data['email'].toString();
      }
    } catch (_) {
      _origName = (_store.read('user_name') ?? '').toString();
      _origPhone = (_store.read('user_phone') ?? '').toString();
      _origBloodType = _store.read('blood_type') as String?;
    }

    nameController.text = _origName;
    phoneController.text = _origPhone;
    emailController.text = email;
    _selectedLocation = _origLocation;
    _selectedBloodType = _origBloodType;

    nameController.addListener(_recomputeChanges);
    phoneController.addListener(_recomputeChanges);

    if (mounted) setState(() => _isLoading = false);
  }

  String? _normalizeToKnownLocation(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final loc in _locations) {
      if (raw.toLowerCase().contains(loc.toLowerCase())) return loc;
    }
    return null;
  }

  void _recomputeChanges() {
    final changed = nameController.text.trim() != _origName.trim() ||
        phoneController.text.trim() != _origPhone.trim() ||
        _selectedLocation != _origLocation ||
        _selectedBloodType != _origBloodType;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  bool _isValidKenyanPhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    final local = RegExp(r'^(07|01)\d{8}$');
    final intl = RegExp(r'^\+254[71]\d{8}$');
    return local.hasMatch(cleaned) || intl.hasMatch(cleaned);
  }

  String _normalizePhone(String phone) {
    final cleaned = phone.replaceAll(' ', '').replaceAll('-', '');
    if (cleaned.startsWith('+254')) return '0${cleaned.substring(4)}';
    return cleaned;
  }

  bool _validate() {
    setState(() {
      _nameError = null;
      _phoneError = null;
      _locationError = null;
      _bloodTypeError = null;
    });

    bool ok = true;

    final name = nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Please enter your name');
      ok = false;
    } else if (name.length < 2) {
      setState(() => _nameError = 'Name must be at least 2 characters');
      ok = false;
    }

    final phone = phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _phoneError = 'Please enter your phone number');
      ok = false;
    } else if (!_isValidKenyanPhone(phone)) {
      setState(() => _phoneError = 'Use 0712345678 or +254712345678 format');
      ok = false;
    }

    if (_selectedLocation == null) {
      setState(() => _locationError = 'Please select your location');
      ok = false;
    }

    if (_selectedBloodType == null) {
      setState(() => _bloodTypeError = 'Please select your blood type');
      ok = false;
    }

    return ok;
  }

  Future<void> _save() async {
    if (!_validate()) return;

    final user = _auth.currentUser;
    if (user == null) {
      _showSnack('You must be signed in', isError: true);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _isSaving = true);

    final name = nameController.text.trim();
    final phone = _normalizePhone(phoneController.text.trim());
    final location = _selectedLocation!;
    final bloodType = _selectedBloodType!;

    try {
      final batch = _firestore.batch();

      // /users holds the full profile.
      batch.update(_firestore.collection('users').doc(user.uid), {
        'name': name,
        'phone': phone,
        'location': location,
        'blood_type': bloodType,
      });

      // /public_profiles mirrors the donor-visible fields the fan-out
      // queries on (blood_type and city). They must stay in sync with
      // /users. merge:true protects is_available, first_name, profile_pic
      // and other public fields managed elsewhere.
      batch.set(
        _firestore.collection('public_profiles').doc(user.uid),
        {
          'blood_type': bloodType,
          'city': location,
        },
        SetOptions(merge: true),
      );

      await batch.commit();

      _store.write('user_name', name);
      _store.write('user_phone', phone);
      _store.write('blood_type', bloodType);

      _origName = name;
      _origPhone = phone;
      _origLocation = location;
      _origBloodType = bloodType;

      if (mounted) {
        setState(() {
          _isSaving = false;
          _hasChanges = false;
        });
        _showSnack('Profile saved successfully', isError: false);
      }
    } on FirebaseException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack(
          e.code == 'permission-denied'
              ? 'Permission denied. Please sign in again.'
              : "Couldn't save changes. Please try again.",
          isError: true,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isSaving = false);
        _showSnack('Something went wrong. Please try again.', isError: true);
      }
    }
  }

  // ─── PHOTO ─────────────────────────────────────────────

  Future<void> _onPhotoTap() async {
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: AppSpace.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: Text('Take a photo', style: AppText.body),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: Text('Choose from gallery', style: AppText.body),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: AppColors.critical),
                title: Text('Remove photo',
                    style:
                        AppText.body.copyWith(color: AppColors.critical)),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: AppSpace.sm),
          ],
        ),
      ),
    );

    if (action == null) return;
    if (action == 'remove') {
      await _removePhoto();
    } else {
      await _uploadPhoto(
          action == 'camera' ? ImageSource.camera : ImageSource.gallery);
    }
  }

  Future<void> _uploadPhoto(ImageSource source) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final XFile? picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);

    try {
      final ref = FirebaseStorage.instance
          .ref()
          .child('avatars')
          .child('${user.uid}.jpg');

      await ref.putFile(File(picked.path));
      final url = await ref.getDownloadURL();

      // Photo is saved immediately (separate from the Save Changes button).
      await _firestore
          .collection('users')
          .doc(user.uid)
          .update({'photo_url': url});

      if (mounted) {
        setState(() {
          _photoUrl = url;
          _isUploadingPhoto = false;
        });
        _showSnack('Profile photo updated', isError: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        _showSnack("Couldn't upload photo. Please try again.",
            isError: true);
      }
    }
  }

  Future<void> _removePhoto() async {
    final user = _auth.currentUser;
    if (user == null) return;

    setState(() => _isUploadingPhoto = true);

    try {
      // Best-effort delete from Storage; ignore if the object is missing.
      try {
        await FirebaseStorage.instance
            .ref()
            .child('avatars')
            .child('${user.uid}.jpg')
            .delete();
      } catch (_) {}

      await _firestore
          .collection('users')
          .doc(user.uid)
          .update({'photo_url': FieldValue.delete()});

      if (mounted) {
        setState(() {
          _photoUrl = null;
          _isUploadingPhoto = false;
        });
        _showSnack('Profile photo removed', isError: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isUploadingPhoto = false);
        _showSnack("Couldn't remove photo. Please try again.",
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

    await _auth.signOut();
    _store.erase();
    // TODO: change '/login' to match your actual login route name.
    Get.offAllNamed('/login');
  }

  // Improved, polished feedback — matches the floating snackbar style your
  // HomeScreen uses (icon + rounded + floating), via ScaffoldMessenger
  // (reliable inside the home shell's Scaffold).
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

  String _initials() {
    final parts = nameController.text
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.lg, AppSpace.lg, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('My Profile', style: AppText.title),
                  const SizedBox(height: 4),
                  Text(
                    'Manage your personal information and blood type. These '
                    'details match you with requests and let people you '
                    'offer to help contact you.',
                    style: AppText.caption,
                  ),
                  const SizedBox(height: AppSpace.lg),

                  Center(child: _buildAvatar()),
                  const SizedBox(height: AppSpace.lg),

                  _buildField(
                    label: 'Full Name',
                    error: _nameError,
                    child: TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _decoration(
                        hint: 'Enter your full name',
                        icon: Icons.person_outline,
                        hasError: _nameError != null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),

                  _buildField(
                    label: 'Email Address',
                    helper: 'Contact support to change your email.',
                    child: TextField(
                      controller: emailController,
                      enabled: false,
                      decoration: _decoration(
                        hint: 'No email on file',
                        icon: Icons.mail_outline,
                        hasError: false,
                      ).copyWith(
                        fillColor: AppColors.disabled.withOpacity(0.3),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),

                  _buildField(
                    label: 'Phone Number',
                    error: _phoneError,
                    child: TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration(
                        hint: '0712345678',
                        icon: Icons.phone_outlined,
                        hasError: _phoneError != null,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),

                  _buildField(
                    label: 'Primary Location',
                    error: _locationError,
                    child: DropdownButtonFormField<String>(
                      value: _selectedLocation,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppColors.textSecondary),
                      decoration: _decoration(
                        hint: 'Select your town/city',
                        icon: Icons.location_on_outlined,
                        hasError: _locationError != null,
                      ),
                      items: _locations
                          .map((l) => DropdownMenuItem(
                                value: l,
                                child: Text(l, style: AppText.body),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedLocation = v;
                          _locationError = null;
                        });
                        _recomputeChanges();
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpace.md),

                  _buildField(
                    label: 'Blood Type',
                    helper:
                        'Used to match you with compatible requests — make '
                        'sure this is accurate.',
                    error: _bloodTypeError,
                    child: DropdownButtonFormField<String>(
                      value: _selectedBloodType,
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down,
                          color: AppColors.textSecondary),
                      decoration: _decoration(
                        hint: 'Select your blood type',
                        icon: Icons.bloodtype_outlined,
                        hasError: _bloodTypeError != null,
                      ),
                      items: _bloodTypes
                          .map((b) => DropdownMenuItem(
                                value: b,
                                child: Text(b, style: AppText.body),
                              ))
                          .toList(),
                      onChanged: (v) {
                        setState(() {
                          _selectedBloodType = v;
                          _bloodTypeError = null;
                        });
                        _recomputeChanges();
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  SizedBox(
                    height: 54,
                    child: ElevatedButton(
                      onPressed:
                          (!_hasChanges || _isSaving) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.disabled,
                        disabledForegroundColor: AppColors.textTertiary,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Text('Save Changes', style: AppText.button),
                    ),
                  ),
                  const SizedBox(height: AppSpace.sm),

                  Center(
                    child: TextButton(
                      onPressed: _logout,
                      child: Text(
                        'Log Out',
                        style: AppText.label
                            .copyWith(color: AppColors.critical),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAvatar() {
    final hasPhoto = _photoUrl != null && _photoUrl!.isNotEmpty;
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primarySoft,
              image: (hasPhoto && !_isUploadingPhoto)
                  ? DecorationImage(
                      image: NetworkImage(_photoUrl!), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: _isUploadingPhoto
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  )
                : (hasPhoto
                    ? null
                    : Text(
                        _initials(),
                        style: AppText.title
                            .copyWith(color: AppColors.primary),
                      )),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: GestureDetector(
              onTap: _isUploadingPhoto ? null : _onPhotoTap,
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
                child:
                    const Icon(Icons.edit, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required Widget child,
    String? helper,
    String? error,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.label),
        const SizedBox(height: AppSpace.xs),
        child,
        if (error != null) ...[
          const SizedBox(height: AppSpace.xs),
          Row(
            children: [
              const Icon(Icons.error_outline,
                  size: 14, color: AppColors.critical),
              const SizedBox(width: AppSpace.xs),
              Expanded(
                child: Text(
                  error,
                  style: AppText.caption.copyWith(
                    color: AppColors.critical,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ] else if (helper != null) ...[
          const SizedBox(height: AppSpace.xs),
          Text(
            helper,
            style: AppText.caption.copyWith(
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _decoration({
    required String hint,
    required IconData icon,
    required bool hasError,
  }) {
    final border = hasError ? AppColors.critical : AppColors.border;
    final focus = hasError ? AppColors.critical : AppColors.primary;
    return InputDecoration(
      hintText: hint,
      hintStyle: AppText.body.copyWith(color: AppColors.textTertiary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md, vertical: AppSpace.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        borderSide: BorderSide(color: focus, width: 1.5),
      ),
    );
  }
}