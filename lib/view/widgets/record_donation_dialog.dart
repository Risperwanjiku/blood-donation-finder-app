import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:test_app/configs/colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void showRecordDonation(BuildContext context, Function onSuccess) {
  TextEditingController locationController = TextEditingController();
  TextEditingController unitsController = TextEditingController(text: "1");
  DateTime selectedDate = DateTime.now();
  bool isLoading = false;

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> saveDonation() async {
            // Validation
            if (locationController.text.trim().isEmpty) {
              Get.snackbar("Error", "Please enter the hospital/location");
              return;
            }

            int units = int.tryParse(unitsController.text) ?? 1;
            if (units <= 0 || units > 5) {
              Get.snackbar("Error", "Units must be between 1 and 5");
              return;
            }

            // Check if date is in the future
            if (selectedDate.isAfter(DateTime.now())) {
              Get.snackbar("Error", "Donation date cannot be in the future");
              return;
            }

            User? user = auth.currentUser;
            if (user == null) {
              Get.snackbar("Error", "Please login first");
              return;
            }

            setModalState(() {
              isLoading = true;
            });

            try {
              // Get current user data
              DocumentSnapshot userDoc =
              await firestore.collection('users').doc(user.uid).get();
              Map<String, dynamic> userData =
              userDoc.data() as Map<String, dynamic>;

              int currentDonations = userData['total_donations'] ?? 0;
              int currentLivesSaved = userData['lives_saved'] ?? 0;

              // Add donation record to donations collection
              await firestore.collection('donations').add({
                'user_id': user.uid,
                'user_name': userData['name'] ?? '',
                'location': locationController.text.trim(),
                'units': units,
                'donation_date': Timestamp.fromDate(selectedDate),
                'created_at': FieldValue.serverTimestamp(),
              });

              // Update user's donation stats
              await firestore.collection('users').doc(user.uid).update({
                'total_donations': currentDonations + 1,
                'lives_saved': currentLivesSaved + units,
                'last_donation_date': Timestamp.fromDate(selectedDate),
              });

              setModalState(() {
                isLoading = false;
              });

              Navigator.pop(context);
              Get.snackbar(
                "Success",
                "Donation recorded! Thank you for saving lives.",
                snackPosition: SnackPosition.TOP,
              );
              onSuccess();
            } catch (e) {
              setModalState(() {
                isLoading = false;
              });
              Get.snackbar("Error", "Failed to record donation: $e");
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              left: 20,
              right: 20,
              top: 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  Text(
                    "Record Donation",
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 5),
                  Text(
                    "Add your blood donation to track your contributions",
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                  ),
                  SizedBox(height: 25),

                  // Date Picker
                  Text(
                    "Donation Date",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  InkWell(
                    onTap: () async {
                      DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: primaryColor,
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setModalState(() {
                          selectedDate = picked;
                        });
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.calendar_today, color: primaryColor, size: 22),
                          SizedBox(width: 12),
                          Text(
                            "${selectedDate.day}/${selectedDate.month}/${selectedDate.year}",
                            style: TextStyle(fontSize: 16),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_drop_down, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),

                  // Location
                  Text(
                    "Hospital / Blood Bank",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: locationController,
                    decoration: InputDecoration(
                      hintText: "e.g., Nairobi Hospital",
                      prefixIcon: Icon(Icons.local_hospital, color: primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),

                  // Units
                  Text(
                    "Units Donated",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  SizedBox(height: 8),
                  TextField(
                    controller: unitsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: "Usually 1 unit per donation",
                      prefixIcon: Icon(Icons.opacity, color: primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "1 unit = approximately 450ml of blood",
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  ),
                  SizedBox(height: 25),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : saveDonation,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: isLoading
                          ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Text(
                        "Save Donation",
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}