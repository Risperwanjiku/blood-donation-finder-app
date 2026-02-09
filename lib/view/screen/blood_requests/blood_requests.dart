import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:test_app/view/screen/blood_requests/request_form.dart';
import 'package:test_app/view/screen/blood_requests/my_requests_list.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class BloodRequests extends StatefulWidget {
  const BloodRequests({super.key});

  @override
  State<BloodRequests> createState() => _BloodRequestsState();
}

class _BloodRequestsState extends State<BloodRequests> {
  int _selectedIndex = 0;
  List<Map<String, dynamic>> myRequests = [];
  bool isLoading = false;

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    loadMyRequests();
  }

  void loadMyRequests() async {
    User? user = _auth.currentUser;
    if (user == null) return;

    setState(() {
      isLoading = true;
    });

    try {
      QuerySnapshot allSnapshot =
      await _firestore.collection('blood_requests').get();

      List<Map<String, dynamic>> requests = allSnapshot.docs
          .map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      })
          .where((data) => data['requester_id'] == user.uid)
          .toList();

      setState(() {
        myRequests = requests;
        isLoading = false;
      });
    } catch (e) {
      print("Error loading requests: $e");
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _selectedIndex == 0
          ? RequestForm(onRequestCreated: loadMyRequests)
          : isLoading
          ? Center(child: CircularProgressIndicator())
          : MyRequestsList(requests: myRequests, onStatusChanged: loadMyRequests),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
          if (index == 1) {
            loadMyRequests();
          }
        },
        selectedItemColor: primaryColor,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.add_circle_outline), label: "Request Blood"),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: "My Requests"),
        ],
      ),
    );
  }
}