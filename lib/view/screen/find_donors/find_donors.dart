import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:test_app/view/screen/find_donors/donor_card.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class FindDonors extends StatefulWidget {
  const FindDonors({super.key});

  @override
  State<FindDonors> createState() => _FindDonorsState();
}

class _FindDonorsState extends State<FindDonors> {
  String selectedBloodType = "All";
  bool showOnlyAvailable = true;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<String> bloodTypes = [
    "All", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-",
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Find Donors"),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Filter Section
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Filter By Blood Type",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 40,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: bloodTypes.length,
                    itemBuilder: (context, index) {
                      final bloodType = bloodTypes[index];
                      final isSelected = selectedBloodType == bloodType;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(bloodType),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              selectedBloodType = bloodType;
                            });
                          },
                          selectedColor: primaryColor,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                // Availability Toggle
                Row(
                  children: [
                    const Text(
                      "Show only available donors",
                      style: TextStyle(fontSize: 14),
                    ),
                    const Spacer(),
                    Switch(
                      value: showOnlyAvailable,
                      onChanged: (value) {
                        setState(() {
                          showOnlyAvailable = value;
                        });
                      },
                      activeColor: primaryColor,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Donors List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _buildQuery(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text("Error: ${snapshot.error}"),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          "No donors found",
                          style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedBloodType != "All"
                              ? "Try selecting a different blood type"
                              : "No registered donors yet",
                          style: TextStyle(color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  );
                }

                var donors = snapshot.data!.docs;

                return Column(
                  children: [
                    // Count Header
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            "${donors.length} donor${donors.length != 1 ? 's' : ''} found",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Donors List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: donors.length,
                        itemBuilder: (context, index) {
                          var donor = donors[index].data() as Map<String, dynamic>;
                          return DonorCard(
                            name: donor['name'] ?? 'Unknown',
                            bloodType: donor['blood_type'] ?? '',
                            location: donor['location'] ?? 'Not specified',
                            distance: '',
                            phone: donor['phone'] ?? '',
                            isAvailable: donor['is_available'] ?? false,
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Stream<QuerySnapshot> _buildQuery() {
    Query query = _firestore.collection('users');

    // Filter by blood type
    if (selectedBloodType != "All") {
      query = query.where('blood_type', isEqualTo: selectedBloodType);
    }

    // Filter by availability
    if (showOnlyAvailable) {
      query = query.where('is_available', isEqualTo: true);
    }

    return query.snapshots();
  }
}