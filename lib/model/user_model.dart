class UserModel {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String bloodType;
  final String location;
  final String profileImage;
  final bool isAvailable;
  final int totalDonations;
  final int livesSaved;
  final DateTime createdAt;
  final String? fcmToken; // For push notifications

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.bloodType,
    required this.location,
    this.profileImage = '',
    this.isAvailable = true,
    this.totalDonations = 0,
    this.livesSaved = 0,
    required this.createdAt,
    this.fcmToken,
  });

  // Create UserModel from Firestore document
  factory UserModel.fromMap(Map<String, dynamic> map, String documentId) {
    return UserModel(
      uid: documentId,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      bloodType: map['blood_type'] ?? '',
      location: map['location'] ?? '',
      profileImage: map['profile_image'] ?? '',
      isAvailable: map['is_available'] ?? true,
      totalDonations: map['total_donations'] ?? 0,
      livesSaved: map['lives_saved'] ?? 0,
      createdAt: map['created_at']?.toDate() ?? DateTime.now(),
      fcmToken: map['fcm_token'],
    );
  }

  // Convert UserModel to Map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'phone': phone,
      'blood_type': bloodType,
      'location': location,
      'profile_image': profileImage,
      'is_available': isAvailable,
      'total_donations': totalDonations,
      'lives_saved': livesSaved,
      'created_at': createdAt,
      'fcm_token': fcmToken,
    };
  }
}