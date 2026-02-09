import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:test_app/configs/colors.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:get/get.dart';

class RequestDetails extends StatefulWidget {
  final String requestId;

  const RequestDetails({super.key, required this.requestId});

  @override
  State<RequestDetails> createState() => _RequestDetailsState();
}

class _RequestDetailsState extends State<RequestDetails> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool isResponding = false;
  bool hasResponded = false;

  @override
  void initState() {
    super.initState();
    _checkIfAlreadyResponded();
  }

  // Check if current user has already responded to this request
  Future<void> _checkIfAlreadyResponded() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    QuerySnapshot response = await _firestore
        .collection('responses')
        .where('request_id', isEqualTo: widget.requestId)
        .where('donor_id', isEqualTo: user.uid)
        .get();

    if (response.docs.isNotEmpty) {
      setState(() {
        hasResponded = true;
      });
    }
  }

  // Handle the "I Want to Help" button tap
  Future<void> _respondToRequest(Map<String, dynamic> requestData) async {
    User? user = _auth.currentUser;
    if (user == null) {
      Get.snackbar("Error", "Please login first");
      return;
    }

    // Show confirmation dialog
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Confirm Response"),
        content: Text(
          "You are about to offer to donate blood for this request. The requester will be notified with your contact information.\n\nDo you want to proceed?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
            ),
            child: Text("Yes, I Want to Help", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      isResponding = true;
    });

    try {
      // Get current user's data
      DocumentSnapshot userDoc =
      await _firestore.collection('users').doc(user.uid).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      String donorName = userData['name'] ?? 'A donor';
      String donorPhone = userData['phone'] ?? '';
      String donorBloodType = userData['blood_type'] ?? '';

      // Get requester's ID from the request
      String requesterId = requestData['requester_id'] ?? '';

      if (requesterId.isEmpty) {
        Get.snackbar("Error", "Could not find requester information");
        setState(() {
          isResponding = false;
        });
        return;
      }

      // Save the response to Firestore
      await _firestore.collection('responses').add({
        'request_id': widget.requestId,
        'donor_id': user.uid,
        'donor_name': donorName,
        'donor_phone': donorPhone,
        'donor_blood_type': donorBloodType,
        'requester_id': requesterId,
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
      });

      // Send notification to the requester
      await _sendNotificationToRequester(
        requesterId: requesterId,
        donorName: donorName,
        donorBloodType: donorBloodType,
        patientName: requestData['patient_name'] ?? '',
      );

      setState(() {
        isResponding = false;
        hasResponded = true;
      });

      Get.snackbar(
        "Thank You!",
        "The requester has been notified. They will contact you soon.",
        snackPosition: SnackPosition.TOP,
        duration: Duration(seconds: 4),
      );
    } catch (e) {
      setState(() {
        isResponding = false;
      });
      Get.snackbar("Error", "Failed to send response: $e");
    }
  }

  // Send notification to the requester
  Future<void> _sendNotificationToRequester({
    required String requesterId,
    required String donorName,
    required String donorBloodType,
    required String patientName,
  }) async {
    // Get requester's FCM token
    DocumentSnapshot requesterDoc =
    await _firestore.collection('users').doc(requesterId).get();
    Map<String, dynamic> requesterData =
    requesterDoc.data() as Map<String, dynamic>;

    String? token = requesterData['fcm_token'];

    // Create notification in Firestore
    await _firestore.collection('notifications').add({
      'token': token ?? '',
      'recipient_id': requesterId,
      'request_id': widget.requestId,
      'title': 'Good News! A Donor Wants to Help',
      'body': '$donorName ($donorBloodType) wants to donate blood for $patientName.',
      'type': 'donor_response',
      'created_at': FieldValue.serverTimestamp(),
      'read': false,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Request Details"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _firestore.collection('blood_requests').doc(widget.requestId).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error loading request details"));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Request not found",
                      style: TextStyle(fontSize: 18, color: Colors.grey)),
                ],
              ),
            );
          }

          Map<String, dynamic> data =
          snapshot.data!.data() as Map<String, dynamic>;

          String bloodType = data['blood_type'] ?? 'Unknown';
          String patientName = data['patient_name'] ?? 'Unknown';
          String hospital = data['hospital'] ?? 'Unknown';
          String contact = data['contact'] ?? '';
          String urgency = data['urgency'] ?? 'normal';
          int units = data['units'] ?? 1;
          String status = data['status'] ?? 'pending';
          String requesterName = data['requester_name'] ?? 'Unknown';
          String requesterId = data['requester_id'] ?? '';
          Timestamp? createdAt = data['created_at'];

          // Check if current user is the requester (don't show respond button)
          bool isOwnRequest = _auth.currentUser?.uid == requesterId;

          Color urgencyColor = urgency == 'critical'
              ? Colors.red
              : urgency == 'urgent'
              ? Colors.orange
              : Colors.green;

          return SingleChildScrollView(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Blood Type Card
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      Text(
                        bloodType,
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        "Blood Type Needed",
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      SizedBox(height: 16),
                      Container(
                        padding:
                        EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: urgencyColor,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          urgency.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 24),

                // Details Section
                Text(
                  "Request Details",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),

                _buildDetailRow(Icons.person, "Patient Name", patientName),
                _buildDetailRow(Icons.local_hospital, "Hospital", hospital),
                _buildDetailRow(Icons.opacity, "Units Needed", "$units units"),
                _buildDetailRow(Icons.person_outline, "Requested By", requesterName),
                _buildDetailRow(
                  Icons.access_time,
                  "Posted",
                  createdAt != null
                      ? timeago.format(createdAt.toDate())
                      : 'Unknown',
                ),
                _buildDetailRow(
                  Icons.info_outline,
                  "Status",
                  status.toUpperCase(),
                  valueColor: status == 'pending' ? Colors.orange : Colors.green,
                ),

                SizedBox(height: 32),

                // Contact Button
                if (contact.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: () => _makePhoneCall(contact),
                      icon: Icon(Icons.phone, color: Colors.white),
                      label: Text(
                        "Call $contact",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                SizedBox(height: 16),

                // Respond Button - only show if not own request
                if (!isOwnRequest)
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: isResponding || hasResponded
                          ? null
                          : () => _respondToRequest(data),
                      icon: isResponding
                          ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                          : Icon(
                        hasResponded ? Icons.check : Icons.favorite,
                        color: Colors.white,
                      ),
                      label: Text(
                        hasResponded
                            ? "Response Sent"
                            : isResponding
                            ? "Sending..."
                            : "I Want to Help",
                        style: TextStyle(fontSize: 16, color: Colors.white),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                        hasResponded ? Colors.grey : primaryColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),

                // Show message if it's own request
                if (isOwnRequest)
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "This is your blood request",
                            style: TextStyle(color: Colors.blue.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: primaryColor, size: 24),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: Colors.grey, fontSize: 12)),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    }
  }
}