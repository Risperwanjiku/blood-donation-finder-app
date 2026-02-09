import 'package:flutter/material.dart';
import 'package:test_app/configs/colors.dart';
import 'package:url_launcher/url_launcher.dart';

class DonorCard extends StatelessWidget {
  final String name;
  final String bloodType;
  final String location;
  final String distance;
  final String phone;
  final bool isAvailable;

  const DonorCard({
    super.key,
    required this.name,
    required this.bloodType,
    required this.location,
    required this.distance,
    required this.phone,
    this.isAvailable = true,
  });

  void _callDonor() async {
    final Uri phoneUri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(phoneUri)) {
      await launchUrl(phoneUri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Blood Type Badge
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  bloodType,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Donor Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      // Availability Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isAvailable
                              ? Colors.green.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isAvailable ? Icons.check_circle : Icons.cancel,
                              size: 12,
                              color: isAvailable ? Colors.green : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isAvailable ? "Available" : "Unavailable",
                              style: TextStyle(
                                fontSize: 11,
                                color: isAvailable ? Colors.green : Colors.grey,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          location.isNotEmpty ? location : "Location not specified",
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Call Button
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: IconButton(
                onPressed: phone.isNotEmpty ? _callDonor : null,
                icon: Icon(
                  Icons.phone,
                  color: phone.isNotEmpty ? Colors.green : Colors.grey,
                  size: 22,
                ),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}