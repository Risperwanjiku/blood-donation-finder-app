import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:test_app/configs/colors.dart';
import 'package:test_app/view/screen/blood_requests/blood_requests.dart';
import 'package:test_app/view/screen/find_donors/find_donors.dart';
import 'package:test_app/view/widgets/record_donation_dialog.dart';
import 'package:get_storage/get_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timeago/timeago.dart' as timeago;

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  var store = GetStorage();

  String userName = "User";
  String bloodType = "O+";
  bool isAvailable = true;

  int livesSaved = 0;
  int totalDonations = 0;
  int daysUntilNextDonation = 0;

  List<Map<String, dynamic>> bloodRequests = [];
  Map<String, int> responseCountMap = {};

  bool isLoading = true;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Blood type compatibility - who can DONATE to whom
  static const Map<String, List<String>> canDonateTo = {
    "O-": ["O-", "O+", "A-", "A+", "B-", "B+", "AB-", "AB+"],
    "O+": ["O+", "A+", "B+", "AB+"],
    "A-": ["A-", "A+", "AB-", "AB+"],
    "A+": ["A+", "AB+"],
    "B-": ["B-", "B+", "AB-", "AB+"],
    "B+": ["B+", "AB+"],
    "AB-": ["AB-", "AB+"],
    "AB+": ["AB+"],
  };

  @override
  void initState() {
    super.initState();
    loadAllData();
  }

  Future<void> loadAllData() async {
    setState(() {
      isLoading = true;
    });

    await loadUserData();
    await loadBloodRequests();
    await loadDonationStats();

    setState(() {
      isLoading = false;
    });
  }

  Future<void> loadUserData() async {
    setState(() {
      userName = store.read("user_name") ?? "User";
      bloodType = store.read("blood_type") ?? "O+";
      isAvailable = store.read("is_available") ?? true;
    });

    User? user = _auth.currentUser;
    if (user != null) {
      DocumentSnapshot userDoc =
      await _firestore.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          userName = userData['name'] ?? "User";
          bloodType = userData['blood_type'] ?? "O+";
          isAvailable = userData['is_available'] ?? true;
          livesSaved = userData['lives_saved'] ?? 0;
          totalDonations = userData['total_donations'] ?? 0;
        });
      }
    }
  }

  void updateAvailability(bool value) async {
    User? user = _auth.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).update({
        'is_available': value,
      });
      store.write("is_available", value);
    }
  }

  Future<void> loadBloodRequests() async {
    try {
      User? user = _auth.currentUser;

      QuerySnapshot allSnapshot = await _firestore
          .collection('blood_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('created_at', descending: true)
          .get();

      List<Map<String, dynamic>> requests = allSnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();

      // Filter to show only requests the user can donate to (based on blood type)
      // Also exclude user's own requests
      List<String> canDonateToTypes = canDonateTo[bloodType] ?? [];
      requests = requests.where((request) {
        bool canHelp = canDonateToTypes.contains(request['blood_type']);
        bool isOwnRequest = request['requester_id'] == user?.uid;
        return canHelp && !isOwnRequest;
      }).toList();

      // Load response counts for each request
      for (var request in requests) {
        QuerySnapshot responses = await _firestore
            .collection('responses')
            .where('request_id', isEqualTo: request['id'])
            .get();
        responseCountMap[request['id']] = responses.docs.length;
      }

      setState(() {
        bloodRequests = requests;
      });
    } catch (e) {
      print("ERROR loading blood requests: $e");
    }
  }

  Future<void> loadDonationStats() async {
    User? user = _auth.currentUser;
    if (user != null) {
      try {
        DocumentSnapshot userDoc =
        await _firestore.collection('users').doc(user.uid).get();

        if (userDoc.exists) {
          Map<String, dynamic> userData =
          userDoc.data() as Map<String, dynamic>;

          // Calculate days until next donation
          int daysRemaining = 0;
          if (userData['last_donation_date'] != null) {
            Timestamp lastDonation = userData['last_donation_date'];
            DateTime lastDate = lastDonation.toDate();
            DateTime nextDonationDate = lastDate.add(Duration(days: 56));
            int difference = nextDonationDate.difference(DateTime.now()).inDays;
            daysRemaining = difference > 0 ? difference : 0;
          }

          setState(() {
            livesSaved = userData['lives_saved'] ?? 0;
            totalDonations = userData['total_donations'] ?? 0;
            daysUntilNextDonation = daysRemaining;
          });
        }
      } catch (e) {
        print("Error loading donation stats: $e");
      }
    }
  }

  void navigateToRequestDetails(String requestId) {
    Get.toNamed('/request-details', arguments: requestId);
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: loadAllData,
      color: primaryColor,
      child: Container(
        color: Colors.grey[100],
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: primaryColor))
            : SingleChildScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting Section
                Text(
                  "Hi $userName,",
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                SizedBox(height: 10),
                Text(
                  "Blood type $bloodType.",
                  style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                ),
                SizedBox(height: 30),

                // Availability Toggle
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isAvailable ? successColor : Colors.grey,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAvailable
                                ? "Available to Donate"
                                : "Not Available",
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isAvailable
                                    ? successColor
                                    : Colors.grey[700]),
                          ),
                          SizedBox(height: 5),
                          Text(
                            isAvailable
                                ? "You will get notifications for requests"
                                : "You won't get notifications",
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      Switch(
                        value: isAvailable,
                        onChanged: (value) {
                          setState(() {
                            isAvailable = value;
                          });
                          updateAvailability(value);
                        },
                        activeColor: successColor,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 30),

                // Quick Actions
                Text(
                  "What would you like to do?",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87),
                ),
                SizedBox(height: 15),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => BloodRequests()),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: primaryColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.bloodtype,
                                  size: 35, color: primaryColor),
                              SizedBox(height: 10),
                              Text(
                                "Request Blood",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: primaryColor),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 15),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => FindDonors()),
                          );
                        },
                        child: Container(
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: accentColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.search,
                                  size: 35, color: accentColor),
                              SizedBox(height: 10),
                              Text(
                                "Find Donors",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: accentColor),
                              )
                            ],
                          ),
                        ),
                      ),
                    )
                  ],
                ),
                SizedBox(height: 30),

                // Donation Stats
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text("My Donation Stats",
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    TextButton.icon(
                      onPressed: () =>
                          showRecordDonation(context, loadDonationStats),
                      icon: Icon(Icons.add, color: primaryColor, size: 18),
                      label:
                      Text("Add", style: TextStyle(color: primaryColor)),
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                "$livesSaved",
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              Text(
                                "Lives Saved",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                          Container(
                            width: 1,
                            height: 35,
                            color: Colors.white54,
                          ),
                          Column(
                            children: [
                              Text(
                                "$totalDonations",
                                style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              Text(
                                "Total Donations",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      Text(
                        daysUntilNextDonation > 0
                            ? "You can donate again in $daysUntilNextDonation days"
                            : "You are eligible to donate",
                        style:
                        TextStyle(fontSize: 12, color: Colors.white70),
                      )
                    ],
                  ),
                ),
                SizedBox(height: 30),

                // Blood Requests Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "People Who Need Blood",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                    ),
                    if (bloodRequests.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          Get.toNamed('/notifications');
                        },
                        child: Text(
                          "View All",
                          style: TextStyle(color: primaryColor),
                        ),
                      ),
                  ],
                ),
                SizedBox(height: 15),

                bloodRequests.isEmpty
                    ? Container(
                  padding: EdgeInsets.all(30),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 50, color: Colors.grey[400]),
                        SizedBox(height: 12),
                        Text(
                          "No blood requests matching your type",
                          style: TextStyle(color: Colors.grey[600]),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 4),
                        Text(
                          "You can donate to: ${canDonateTo[bloodType]?.join(', ') ?? 'Unknown'}",
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
                    : ListView.builder(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    itemCount: bloodRequests.length > 5
                        ? 5
                        : bloodRequests.length,
                    itemBuilder: (context, index) {
                      var request = bloodRequests[index];
                      int responseCount =
                          responseCountMap[request['id']] ?? 0;
                      Timestamp? createdAt = request['created_at'];

                      return GestureDetector(
                        onTap: () =>
                            navigateToRequestDetails(request['id']),
                        child: Container(
                          margin: EdgeInsets.only(bottom: 10),
                          padding: EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: request['urgency'] == 'critical'
                                  ? Colors.red
                                  : request['urgency'] == 'urgent'
                                  ? Colors.orange
                                  : Colors.green,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment.start,
                            children: [
                              // Top Row - Urgency Badge & Time
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: request['urgency'] ==
                                          'critical'
                                          ? Colors.red
                                          : request['urgency'] ==
                                          'urgent'
                                          ? Colors.orange
                                          : Colors.green,
                                      borderRadius:
                                      BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      request['urgency']
                                          ?.toUpperCase() ??
                                          'NORMAL',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    createdAt != null
                                        ? timeago.format(
                                        createdAt.toDate())
                                        : '',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey),
                                  ),
                                ],
                              ),
                              SizedBox(height: 10),

                              // Blood Type Needed
                              Text(
                                "${request['blood_type']} Blood Needed",
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: 8),

                              // Hospital
                              Row(
                                children: [
                                  Icon(Icons.local_hospital,
                                      size: 14, color: Colors.grey),
                                  SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      "${request['hospital'] ?? request['location']}",
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey[600]),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 5),

                              // Units & Responses Row
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.opacity,
                                          size: 14,
                                          color: Colors.grey),
                                      SizedBox(width: 5),
                                      Text(
                                        "${request['units'] ?? 1} units needed",
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  if (responseCount > 0)
                                    Container(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green
                                            .withOpacity(0.1),
                                        borderRadius:
                                        BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.people,
                                              size: 12,
                                              color: Colors.green),
                                          SizedBox(width: 4),
                                          Text(
                                            "$responseCount donor${responseCount > 1 ? 's' : ''} responding",
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.green,
                                                fontWeight:
                                                FontWeight.w500),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),

                              SizedBox(height: 10),

                              // Tap to respond hint
                              Row(
                                mainAxisAlignment:
                                MainAxisAlignment.end,
                                children: [
                                  Text(
                                    "Tap to respond",
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: primaryColor,
                                        fontWeight: FontWeight.w500),
                                  ),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios,
                                      size: 10, color: primaryColor),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}