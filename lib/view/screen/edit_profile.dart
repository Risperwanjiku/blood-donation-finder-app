import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:test_app/configs/colors.dart';
import 'package:get_storage/get_storage.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

class EditProfile extends StatefulWidget {
  const EditProfile({super.key});

  @override
  State<EditProfile> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfile> {
  final store = GetStorage();
  final _formKey = GlobalKey<FormState>();

  late TextEditingController nameController;
  late TextEditingController phoneController;
  late TextEditingController locationController;
  late TextEditingController emailController;

  String selectedBloodType = "A+";
  final List<String> bloodTypes = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-'
  ];

  bool isLoading = false;
  bool isLoadingData = true;

  Uint8List? _selectedImageBytes;
  File? _selectedImageFile;
  String? _currentImageUrl;

  final ImagePicker _picker = ImagePicker();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController();
    phoneController = TextEditingController();
    locationController = TextEditingController();
    emailController = TextEditingController();
    loadUserData();
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    locationController.dispose();
    emailController.dispose();
    super.dispose();
  }

  Future<void> loadUserData() async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          Map<String, dynamic> userData = userDoc.data() as Map<String,
              dynamic>;
          setState(() {
            nameController.text = userData['name'] ?? '';
            phoneController.text = userData['phone'] ?? '';
            locationController.text = userData['location'] ?? '';
            emailController.text = userData['email'] ?? user.email ?? '';
            selectedBloodType = userData['blood_type'] ?? 'A+';
            _currentImageUrl = userData['profile_image'];
            isLoadingData = false;
          });
        } else {
          setState(() {
            emailController.text = user.email ?? '';
            isLoadingData = false;
          });
        }
      } catch (e) {
        print("Error loading user data: $e");
        setState(() {
          isLoadingData = false;
        });
      }
    } else {
      setState(() {
        isLoadingData = false;
      });
    }
  }

  void showImageOptions() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(height: 20),
              Text(
                "Change Profile Photo",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              ListTile(
                leading: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.photo_library, color: primaryColor),
                ),
                title: Text("Choose from Gallery"),
                onTap: () {
                  Navigator.pop(context);
                  pickImage();
                },
              ),
              if (_selectedImageBytes != null ||
                  _selectedImageFile != null ||
                  _currentImageUrl != null)
                ListTile(
                  leading: Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.delete, color: Colors.red),
                  ),
                  title: Text(
                      "Remove Photo", style: TextStyle(color: Colors.red)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() {
                      _selectedImageBytes = null;
                      _selectedImageFile = null;
                      _currentImageUrl = null;
                    });
                  },
                ),
              SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  void pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image != null) {
      if (kIsWeb) {
        Uint8List imageBytes = await image.readAsBytes();
        setState(() {
          _selectedImageBytes = imageBytes;
        });
      } else {
        setState(() {
          _selectedImageFile = File(image.path);
        });
      }
    }
  }

  Future<String?> uploadProfileImage(String userId) async {
    try {
      Reference ref = _storage.ref().child('profile_images').child(
          '$userId.jpg');

      UploadTask uploadTask;

      if (kIsWeb && _selectedImageBytes != null) {
        uploadTask = ref.putData(
          _selectedImageBytes!,
          SettableMetadata(contentType: 'image/jpeg'),
        );
      } else if (_selectedImageFile != null) {
        uploadTask = ref.putFile(_selectedImageFile!);
      } else {
        return null;
      }

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      return downloadUrl;
    } catch (e) {
      print("Error uploading image: $e");
      return null;
    }
  }

  Future<void> saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    User? user = _auth.currentUser;
    if (user == null) {
      Get.snackbar("Error", "Please login first");
      return;
    }

    setState(() => isLoading = true);

    try {
      String? imageUrl = _currentImageUrl;

      if (_selectedImageBytes != null || _selectedImageFile != null) {
        String? uploadedUrl = await uploadProfileImage(user.uid);
        if (uploadedUrl != null) {
          imageUrl = uploadedUrl;
        }
      }

      await _firestore.collection('users').doc(user.uid).update({
        'name': nameController.text.trim(),
        'phone': phoneController.text.trim(),
        'location': locationController.text.trim(),
        'blood_type': selectedBloodType,
        'profile_image': imageUrl,
        'updated_at': FieldValue.serverTimestamp(),
      });

      store.write("user_name", nameController.text.trim());
      store.write("user_phone", phoneController.text.trim());
      store.write("user_location", locationController.text.trim());
      store.write("blood_type", selectedBloodType);
      if (imageUrl != null) {
        store.write("profile_image", imageUrl);
      }

      setState(() {
        _currentImageUrl = imageUrl;
        _selectedImageBytes = null;
        _selectedImageFile = null;
        isLoading = false;
      });

      Get.snackbar(
        "Success",
        "Profile updated successfully",
        snackPosition: SnackPosition.TOP,
      );
    } catch (e) {
      setState(() => isLoading = false);
      Get.snackbar(
        "Error",
        "Failed to update profile: $e",
        snackPosition: SnackPosition.TOP,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoadingData) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: primaryColor),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Profile Image
              Center(
                child: GestureDetector(
                  onTap: showImageOptions,
                  child: Stack(
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.grey[200],
                          border: Border.all(color: primaryColor, width: 3),
                          image: _selectedImageBytes != null
                              ? DecorationImage(
                            image: MemoryImage(_selectedImageBytes!),
                            fit: BoxFit.cover,
                          )
                              : _selectedImageFile != null
                              ? DecorationImage(
                            image: FileImage(_selectedImageFile!),
                            fit: BoxFit.cover,
                          )
                              : _currentImageUrl != null
                              ? DecorationImage(
                            image: NetworkImage(_currentImageUrl!),
                            fit: BoxFit.cover,
                          )
                              : null,
                        ),
                        child: (_selectedImageBytes == null &&
                            _selectedImageFile == null &&
                            _currentImageUrl == null)
                            ? Icon(Icons.person, size: 60, color: Colors
                            .grey[400])
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Icon(Icons.camera_alt, size: 20,
                              color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 10),
              Center(
                child: Text(
                  "Tap to change photo",
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ),
              SizedBox(height: 20),

              // Donation History Button
              Container(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Get.toNamed('/donation-history'),
                  icon: Icon(Icons.volunteer_activism, color: primaryColor),
                  label: Text("View Donation History"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(color: primaryColor),
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 25),

              // Email (Read Only)
              Text("Email",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              TextFormField(
                controller: emailController,
                enabled: false,
                decoration: InputDecoration(
                  hintText: "Your email",
                  prefixIcon: Icon(Icons.email_outlined, color: Colors.grey),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
              ),
              SizedBox(height: 20),

              // Full Name
              Text("Full Name",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(
                  hintText: "Enter your name",
                  prefixIcon: Icon(Icons.person_outline, color: primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your name";
                  }
                  if (value.length < 3) {
                    return "Name must be at least 3 characters";
                  }
                  if (RegExp(r'\d').hasMatch(value)) {
                    return "Name should not contain numbers";
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Phone Number
              Text("Phone Number",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  hintText: "Enter your phone number",
                  prefixIcon: Icon(Icons.phone_outlined, color: primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your phone number";
                  }
                  if (!RegExp(r'^(07|01)\d{8}$').hasMatch(value)) {
                    return "Enter a valid Kenyan phone number (07... or 01...)";
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Location
              Text("Location",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              TextFormField(
                controller: locationController,
                decoration: InputDecoration(
                  hintText: "Enter your location",
                  prefixIcon: Icon(
                      Icons.location_on_outlined, color: primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Please enter your location";
                  }
                  if (value.length < 3) {
                    return "Location must be at least 3 characters";
                  }
                  return null;
                },
              ),
              SizedBox(height: 20),

              // Blood Type
              Text("Blood Type",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
              SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: bloodTypes.contains(selectedBloodType)
                    ? selectedBloodType
                    : bloodTypes[0],
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.bloodtype, color: primaryColor),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: bloodTypes.map((type) {
                  return DropdownMenuItem(value: type, child: Text(type));
                }).toList(),
                onChanged: (value) {
                  setState(() => selectedBloodType = value!);
                },
              ),
              SizedBox(height: 40),

              // Save Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: isLoading ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isLoading
                      ? CircularProgressIndicator(color: Colors.white)
                      : Text("Save Changes",
                      style: TextStyle(fontSize: 18, color: Colors.white)),
                ),
              ),
              SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
