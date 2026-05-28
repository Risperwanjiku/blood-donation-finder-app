/// Centralized donation eligibility rules for DamuLink.
///
/// Based on Kenya National Blood Transfusion Service (KNBTS) practice
/// for whole blood donations:
/// - Male donors:   minimum 3 calendar months between donations
/// - Female donors: minimum 4 calendar months
/// - Unknown / prefer not to say: defaults to 4 months (most conservative)
///
/// Sources: KUTRRH, Damu Sasa, KNBTS guidance.
class DonationRules {
  /// Whole blood donation cooldown in calendar months, by gender.
  /// Null or unrecognized values default to 4 (conservative).
  static int cooldownMonths(String? gender) {
    switch ((gender ?? '').toLowerCase()) {
      case 'male':
        return 3;
      case 'female':
        return 4;
      default:
        return 4;
    }
  }

  /// Calculate the next eligible donation date by adding calendar months
  /// to a last-donation date, with day-of-month clamping for short months.
  ///
  /// Example: 3 months after Jan 31 → April 30 (April has 30 days),
  /// not May 1 (which is what Dart's default constructor would give you).
  static DateTime nextEligibleDate(DateTime lastDonation, String? gender) {
    final months = cooldownMonths(gender);
    return _addMonths(_normalize(lastDonation), months);
  }

  /// Number of days remaining until the donor is eligible again.
  /// Returns 0 if already eligible.
  static int daysUntilEligible(DateTime lastDonation, String? gender) {
    final nextDate = nextEligibleDate(lastDonation, gender);
    final today = _normalize(DateTime.now());
    final diff = nextDate.difference(today).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Whether the donor can record a donation on `proposedDate`.
  /// Returns null if OK, or an error message if blocked by cooldown.
  /// Logging an older donation than the last is always OK (no cooldown applies).
  static String? canDonateOn({
    required DateTime proposedDate,
    required DateTime? lastDonation,
    required String? gender,
  }) {
    if (lastDonation == null) return null;
    final p = _normalize(proposedDate);
    final l = _normalize(lastDonation);
    if (!p.isAfter(l)) return null; // logging an old donation, no rule
    final months = cooldownMonths(gender);
    final earliestNext = _addMonths(l, months);
    if (p.isBefore(earliestNext)) {
      return 'Must be at least $months months after your last donation';
    }
    return null;
  }

  // ----- private helpers -----

  static DateTime _normalize(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  /// Add calendar months with day-of-month clamping.
  /// Jan 31 + 1 month → Feb 28 (not March 3).
  static DateTime _addMonths(DateTime date, int months) {
    final totalMonths = date.month + months;
    final yearOffset = (totalMonths - 1) ~/ 12;
    final newMonth = ((totalMonths - 1) % 12) + 1;
    final newYear = date.year + yearOffset;
    final lastDayOfNewMonth = DateTime(newYear, newMonth + 1, 0).day;
    final newDay = date.day > lastDayOfNewMonth ? lastDayOfNewMonth : date.day;
    return DateTime(newYear, newMonth, newDay);
  }
}