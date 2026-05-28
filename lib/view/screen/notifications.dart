import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:damulink/configs/colors.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:get/get.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Notifications"),
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
        ),
        body: Center(child: Text("Please login to view notifications")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text("Notifications"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => _markAllAsRead(user.uid),
            child: Text("Mark all read", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('notifications')
            .where('recipient_id', isEqualTo: user.uid)
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text("Error loading notifications"));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 80, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "No notifications yet",
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "You'll be notified when someone needs blood",
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

              bool isRead = data['read'] ?? false;
              String title = data['title'] ?? 'Blood Donation Alert';
              String body = data['body'] ?? '';
              Timestamp? timestamp = data['created_at'];
              String timeAgo = timestamp != null
                  ? timeago.format(timestamp.toDate())
                  : 'Just now';

              return Card(
                margin: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isRead ? Colors.white : Colors.red.shade50,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isRead ? Colors.grey : primaryColor,
                    child: Icon(
                      Icons.bloodtype,
                      color: Colors.white,
                    ),
                  ),
                  title: Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 4),
                      Text(body),
                      SizedBox(height: 4),
                      Text(
                        timeAgo,
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    // Mark as read
                    _markAsRead(doc.id);

                    // Navigate to request details if request_id exists
                    String? requestId = data['request_id'];
                    if (requestId != null) {
                      Get.toNamed('/request-details', arguments: requestId);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAsRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'read': true,
    });
  }

  Future<void> _markAllAsRead(String userId) async {
    QuerySnapshot notifications = await _firestore
        .collection('notifications')
        .where('recipient_id', isEqualTo: userId)
        .where('read', isEqualTo: false)
        .get();

    for (var doc in notifications.docs) {
      await doc.reference.update({'read': true});
    }
  }
}