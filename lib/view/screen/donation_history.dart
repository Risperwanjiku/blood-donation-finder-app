import 'package:flutter/material.dart';
import 'package:damulink/configs/colors.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class DonationHistory extends StatefulWidget {
  const DonationHistory({super.key});

  @override
  State<DonationHistory> createState() => _DonationHistoryState();
}

class _DonationHistoryState extends State<DonationHistory> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Widget build(BuildContext context) {
    User? user = _auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: Text("Donation History"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.grey[100],
      body: user == null
          ? Center(child: Text("Please login first"))
          : StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('donations')
            .where('user_id', isEqualTo: user.uid)
            .orderBy('donation_date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator(color: primaryColor));
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 60, color: Colors.grey),
                  SizedBox(height: 16),
                  Text("Error loading donations"),
                ],
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Empty Stats Card
                  _buildStatsCard(0, 0),
                  SizedBox(height: 30),
                  // Empty State
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volunteer_activism,
                              size: 80, color: Colors.grey[300]),
                          SizedBox(height: 16),
                          Text(
                            "No donations yet",
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[600]),
                          ),
                          SizedBox(height: 8),
                          Text(
                            "Your donation history will appear here",
                            style: TextStyle(color: Colors.grey),
                          ),
                          SizedBox(height: 24),
                          Text(
                            "Record your first donation from the Dashboard",
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          var donations = snapshot.data!.docs;

          // Calculate totals
          int totalUnits = 0;
          for (var doc in donations) {
            var data = doc.data() as Map<String, dynamic>;
            totalUnits += (data['units'] as int?) ?? 1;
          }

          return SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats Card
                _buildStatsCard(donations.length, totalUnits),
                SizedBox(height: 24),

                // Section Title
                Text(
                  "Your Donations",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                SizedBox(height: 12),

                // Donations List
                ListView.builder(
                  shrinkWrap: true,
                  physics: NeverScrollableScrollPhysics(),
                  itemCount: donations.length,
                  itemBuilder: (context, index) {
                    var doc = donations[index];
                    var data = doc.data() as Map<String, dynamic>;

                    String location = data['location'] ?? 'Unknown';
                    int units = data['units'] ?? 1;
                    Timestamp? donationDate = data['donation_date'];

                    String formattedDate = donationDate != null
                        ? DateFormat('MMM dd, yyyy')
                        .format(donationDate.toDate())
                        : 'Unknown date';

                    return Card(
                      margin: EdgeInsets.only(bottom: 12),
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListTile(
                        contentPadding: EdgeInsets.all(16),
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.volunteer_activism,
                            color: primaryColor,
                            size: 28,
                          ),
                        ),
                        title: Text(
                          location,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(height: 6),
                            Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    size: 14, color: Colors.grey),
                                SizedBox(width: 6),
                                Text(
                                  formattedDate,
                                  style:
                                  TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            "$units unit${units > 1 ? 's' : ''}",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatsCard(int totalDonations, int totalUnits) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            "$totalDonations",
            "Total Donations",
            Icons.favorite,
          ),
          Container(width: 1, height: 50, color: Colors.white38),
          _buildStatItem(
            "$totalUnits",
            "Units Donated",
            Icons.opacity,
          ),
          Container(width: 1, height: 50, color: Colors.white38),
          _buildStatItem(
            "$totalUnits",
            "Lives Saved",
            Icons.people,
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 24),
        SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}