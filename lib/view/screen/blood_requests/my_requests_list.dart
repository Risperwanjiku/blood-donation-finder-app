import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class MyRequestsList extends StatefulWidget {
  final List<Map<String, dynamic>> requests;
  final VoidCallback onStatusChanged;

  const MyRequestsList({
    super.key,
    required this.requests,
    required this.onStatusChanged,
  });

  @override
  State<MyRequestsList> createState() => _MyRequestsListState();
}

class _MyRequestsListState extends State<MyRequestsList> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  void showStatusDialog(Map<String, dynamic> request) {
    if (request['status']?.toLowerCase() == 'fulfilled') {
      Get.snackbar("Info", "This request is already fulfilled");
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text("Update Status"),
          content: Text(
              "Mark as fulfilled only after you have found a donor for this request."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                updateStatus(request['id']);
              },
              child: Text("Mark Fulfilled", style: TextStyle(color: primaryColor)),
            ),
          ],
        );
      },
    );
  }

  void updateStatus(String requestId) async {
    try {
      await _firestore.collection('blood_requests').doc(requestId).update({
        'status': 'fulfilled',
        'fulfilled_at': FieldValue.serverTimestamp(),
      });

      Get.snackbar("Success", "Request marked as fulfilled");
      widget.onStatusChanged();
    } catch (e) {
      Get.snackbar("Error", "Failed to update: $e");
    }
  }

  void showDeleteDialog(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.delete_outline, color: Colors.red),
              SizedBox(width: 10),
              Text("Delete Request"),
            ],
          ),
          content: Text(
              "Are you sure you want to delete this blood request? This action cannot be undone."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text("Cancel", style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                deleteRequest(request['id']);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text("Delete", style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void deleteRequest(String requestId) async {
    try {
      // Delete all responses for this request first
      QuerySnapshot responses = await _firestore
          .collection('responses')
          .where('request_id', isEqualTo: requestId)
          .get();

      for (var doc in responses.docs) {
        await doc.reference.delete();
      }

      // Delete all notifications for this request
      QuerySnapshot notifications = await _firestore
          .collection('notifications')
          .where('request_id', isEqualTo: requestId)
          .get();

      for (var doc in notifications.docs) {
        await doc.reference.delete();
      }

      // Delete the request itself
      await _firestore.collection('blood_requests').doc(requestId).delete();

      Get.snackbar("Success", "Request deleted successfully");
      widget.onStatusChanged();
    } catch (e) {
      Get.snackbar("Error", "Failed to delete: $e");
    }
  }

  void viewResponses(Map<String, dynamic> request) {
    Get.toNamed('/responses', arguments: {
      'requestId': request['id'],
      'patientName': request['patient_name'] ?? 'Patient',
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 60, color: Colors.grey),
            SizedBox(height: 10),
            Text("No requests yet",
                style: TextStyle(color: Colors.grey, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: widget.requests.length,
      itemBuilder: (context, index) {
        final request = widget.requests[index];
        bool isFulfilled = request['status']?.toLowerCase() == 'fulfilled';

        return Card(
          margin: const EdgeInsets.only(bottom: 15),
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: primaryColor,
                      child: Text(
                        request['blood_type'] ?? '',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request['hospital'] ?? request['location'] ?? '',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            "Patient: ${request['patient_name'] ?? ''}",
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                    // Delete Button
                    IconButton(
                      onPressed: () => showDeleteDialog(request),
                      icon: Icon(Icons.delete_outline, color: Colors.red),
                      tooltip: "Delete request",
                    ),
                  ],
                ),

                SizedBox(height: 12),

                // Status and Details Row
                Row(
                  children: [
                    _buildDetailChip(Icons.priority_high, request['urgency'] ?? ''),
                    SizedBox(width: 8),
                    _buildDetailChip(Icons.opacity, "${request['units'] ?? ''} units"),
                    Spacer(),
                    Chip(
                      label: Text(
                        request['status']?.toUpperCase() ?? '',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                      backgroundColor: isFulfilled ? successColor : warningColor,
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),

                SizedBox(height: 16),

                // Action Buttons Row
                Row(
                  children: [
                    // View Responses Button
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => viewResponses(request),
                        icon: Icon(Icons.people, size: 18),
                        label: Text("View Responses"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryColor,
                          side: BorderSide(color: primaryColor),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                    // Mark Fulfilled Button
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isFulfilled ? null : () => showStatusDialog(request),
                        icon: Icon(
                          isFulfilled ? Icons.check : Icons.done_all,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: Text(
                          isFulfilled ? "Fulfilled" : "Mark Done",
                          style: TextStyle(color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isFulfilled ? Colors.grey : primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }
}