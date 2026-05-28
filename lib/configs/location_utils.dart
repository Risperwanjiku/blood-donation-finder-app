/// Utilities for parsing free-text and Places API location strings
/// into a normalized city/area key for filtering.
class LocationUtils {
  /// Extracts the city/area from a location string.
  ///
  /// Handles common patterns:
  ///   "Muthaiga, Nairobi"        → "Nairobi"
  ///   "Nairobi, Kenya"            → "Nairobi"  (strips trailing "Kenya")
  ///   "Westlands, Nairobi, Kenya" → "Nairobi"
  ///   "Kerugoya, Kenya"           → "Kerugoya"
  ///   "Mombasa"                   → "Mombasa"
  ///   ""                          → null
  ///
  /// Returns title-cased output for consistent matching across users
  /// and requests (e.g. "nairobi" and "NAIROBI" both become "Nairobi").
  static String? extractCity(String location) {
    final trimmed = location.trim();
    if (trimmed.isEmpty) return null;

    final tokens = trimmed
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    // Strip trailing "Kenya" — Google Places often appends the country.
    final filtered = tokens
        .where((t) => t.toLowerCase() != 'kenya')
        .toList();
    if (filtered.isEmpty) return null;

    // City is typically the last remaining token after Kenya is stripped:
    //   "Neighborhood, City" → "City"
    //   "Street, Area, City" → "City"
    return _titleCase(filtered.last);
  }

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}