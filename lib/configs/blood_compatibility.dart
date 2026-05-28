/// Blood type compatibility rules.
///
/// Medical rule: a donor's RED CELLS must match the recipient's plasma.
/// O- is the universal donor (can give to anyone).
/// AB+ is the universal recipient (can receive from anyone).
///
/// Source: WHO blood donation guidelines.
class BloodCompatibility {
  /// Map from donor blood type -> list of recipient types they can give to.
  static const Map<String, List<String>> _donorToRecipients = {
    'O-': ['O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+'], // Universal donor
    'O+': ['O+', 'A+', 'B+', 'AB+'],
    'A-': ['A-', 'A+', 'AB-', 'AB+'],
    'A+': ['A+', 'AB+'],
    'B-': ['B-', 'B+', 'AB-', 'AB+'],
    'B+': ['B+', 'AB+'],
    'AB-': ['AB-', 'AB+'],
    'AB+': ['AB+'],
  };

  /// All valid blood types in the order most commonly listed.
  static const List<String> allTypes = [
    'O-', 'O+', 'A-', 'A+', 'B-', 'B+', 'AB-', 'AB+',
  ];

  /// Can a donor with [donorType] give blood to a recipient who needs [recipientType]?
  ///
  /// Returns false for unknown blood types (defensive).
  static bool canDonate({
    required String donorType,
    required String recipientType,
  }) {
    final donor = donorType.trim().toUpperCase();
    final recipient = recipientType.trim().toUpperCase();
    final recipients = _donorToRecipients[donor];
    if (recipients == null) return false;
    return recipients.contains(recipient);
  }

  /// What blood types can [donorType] donate to?
  /// Useful for filtering the donor browse list ("show requests I can help with").
  static List<String> compatibleRecipientsFor(String donorType) {
    final donor = donorType.trim().toUpperCase();
    return _donorToRecipients[donor] ?? const [];
  }

  /// What blood types can a recipient with [recipientType] receive from?
  /// Inverse of compatibleRecipientsFor.
  static List<String> compatibleDonorsFor(String recipientType) {
    final recipient = recipientType.trim().toUpperCase();
    return _donorToRecipients.entries
        .where((entry) => entry.value.contains(recipient))
        .map((entry) => entry.key)
        .toList();
  }

  /// Human-readable compatibility note for the donor.
  /// Used on the Request Details screen.
  static String compatibilityMessage({
    required String donorType,
    required String recipientType,
  }) {
    if (canDonate(donorType: donorType, recipientType: recipientType)) {
      if (donorType == 'O-') {
        return "You're a universal donor — you can help anyone";
      }
      return 'Your blood type is compatible';
    }
    return 'Your blood type is not compatible with this request';
  }
}