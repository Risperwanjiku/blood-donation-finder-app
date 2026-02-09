import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:test_app/services/notification_service.dart';

class RequestForm extends StatefulWidget {
  final VoidCallback? onRequestCreated;

  const RequestForm({super.key, this.onRequestCreated});

  @override
  State<RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends State<RequestForm> {
  final _formKey = GlobalKey<FormState>();
  String? _selectedBloodType;
  final List<String> _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  String _urgencyLevel = 'Urgent';
  final List<String> _urgencyLevels = ['Critical', 'Urgent', 'Normal'];
  bool isLoading = false;

  TextEditingController patientNameController = TextEditingController();
  TextEditingController locationController = TextEditingController();
  TextEditingController contactController = TextEditingController();
  TextEditingController unitsController = TextEditingController();

  // Firebase instances
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Notification service
  final NotificationService _notificationService = NotificationService();

  @override
  void dispose() {
    patientNameController.dispose();
    locationController.dispose();
    contactController.dispose();
    unitsController.dispose();
    super.dispose();
  }

  Future<void> submitRequest() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    User? user = _auth.currentUser;
    if (user == null) {
      Get.snackbar("Error", "Please login first");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // Get user data for the request
      DocumentSnapshot userDoc =
      await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      // Create blood request in Firestore and capture the document reference
      DocumentReference requestRef = await _firestore.collection('blood_requests').add({
        'requester_id': user.uid,
        'requester_name': userData['name'] ?? '',
        'requester_phone': userData['phone'] ?? '',
        'patient_name': patientNameController.text.trim(),
        'blood_type': _selectedBloodType,
        'hospital': locationController.text.trim(),
        'location': locationController.text.trim(),
        'contact': contactController.text.trim(),
        'urgency': _urgencyLevel.toLowerCase(),
        'units': int.parse(unitsController.text),
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      // Send notifications to compatible donors with the request ID
      await _notificationService.notifyCompatibleDonors(
        requestId: requestRef.id,
        bloodType: _selectedBloodType!,
        hospital: locationController.text.trim(),
        patientName: patientNameController.text.trim(),
        requesterId: user.uid,
      );

      setState(() {
        isLoading = false;
      });

      Get.snackbar(
        "Success",
        "Blood request submitted! Donors have been notified.",
        snackPosition: SnackPosition.TOP,
      );

      // Clear form
      patientNameController.clear();
      locationController.clear();
      contactController.clear();
      unitsController.clear();
      setState(() {
        _selectedBloodType = null;
        _urgencyLevel = 'Urgent';
      });

      // Notify parent to refresh list
      if (widget.onRequestCreated != null) {
        widget.onRequestCreated!();
      }

    } catch (e) {
      setState(() {
        isLoading = false;
      });
      Get.snackbar("Error", "Failed to submit: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Request Blood Donation",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            TextFormField(
              controller: patientNameController,
              decoration: InputDecoration(
                labelText: "Patient Name",
                prefixIcon: Icon(Icons.person, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter patient name";
                }
                if (value.length < 3) {
                  return "Name must be at least 3 characters";
                }
                return null;
              },
            ),
            SizedBox(height: 15),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "Blood Type Needed",
                prefixIcon: Icon(Icons.bloodtype, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              value: _selectedBloodType,
              items: _bloodTypes.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedBloodType = value;
                });
              },
              validator: (value) {
                if (value == null) {
                  return "Please select blood type";
                }
                return null;
              },
            ),
            SizedBox(height: 15),
            TextFormField(
              controller: locationController,
              decoration: InputDecoration(
                labelText: "Hospital Location",
                prefixIcon: Icon(Icons.local_hospital, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter hospital location";
                }
                if (value.length < 3) {
                  return "Location must be at least 3 characters";
                }
                return null;
              },
            ),
            SizedBox(height: 15),
            TextFormField(
              controller: contactController,
              decoration: InputDecoration(
                labelText: "Contact Number",
                prefixIcon: Icon(Icons.phone, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter contact number";
                }
                if (!RegExp(r'^(07|01)\d{8}$').hasMatch(value)) {
                  return "Enter a valid Kenyan phone number";
                }
                return null;
              },
            ),
            SizedBox(height: 15),
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: "Urgency Level",
                prefixIcon: Icon(Icons.priority_high, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              value: _urgencyLevel,
              items: _urgencyLevels.map((level) {
                return DropdownMenuItem(
                  value: level,
                  child: Text(level),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _urgencyLevel = value!;
                });
              },
            ),
            SizedBox(height: 15),
            TextFormField(
              controller: unitsController,
              decoration: InputDecoration(
                labelText: "Units Needed",
                prefixIcon: Icon(Icons.opacity, color: primaryColor),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return "Please enter units needed";
                }
                int? units = int.tryParse(value);
                if (units == null || units <= 0) {
                  return "Please enter a valid number";
                }
                if (units > 10) {
                  return "Maximum 10 units per request";
                }
                return null;
              },
            ),
            SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isLoading ? null : submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isLoading ? Colors.grey : primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: isLoading
                    ? CircularProgressIndicator(color: Colors.white)
                    : Text("Submit Request",
                    style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}