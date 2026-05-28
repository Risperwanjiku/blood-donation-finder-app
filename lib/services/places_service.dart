import 'package:cloud_functions/cloud_functions.dart';

/// A single autocomplete suggestion from Google Places.
class PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });

  // Accept a plain Map (not Map<String, dynamic>).
  // Cloud Functions / platform channels return nested maps as
  // _Map<Object?, Object?>, so we read keys defensively as Map?.
  factory PlaceSuggestion.fromJson(Map json) {
    final pred = (json['placePrediction'] as Map?) ?? {};
    final structured = (pred['structuredFormat'] as Map?) ?? {};
    final main = (structured['mainText'] as Map?) ?? {};
    final secondary = (structured['secondaryText'] as Map?) ?? {};

    return PlaceSuggestion(
      placeId: (pred['placeId'] as String?) ?? '',
      mainText: (main['text'] as String?) ?? '',
      secondaryText: (secondary['text'] as String?) ?? '',
    );
  }
}

/// Wrapper around our Cloud Function proxy for Places API autocomplete.
class PlacesService {
  static final _functions =
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Returns up to 5 hospital suggestions in Kenya matching [input].
  /// Returns empty list on any failure.
  static Future<List<PlaceSuggestion>> autocompleteHospitals(
    String input,
  ) async {
    final trimmed = input.trim();
    if (trimmed.length < 2) return [];

    try {
      final callable = _functions.httpsCallable(
        'placesAutocomplete',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 10),
        ),
      );

      // Call without a generic type — let result.data come back as dynamic.
      // Platform channels deserialize as Map<Object?, Object?>, not
      // Map<String, dynamic>, so direct typed casts fail.
      final result = await callable.call({
        'input': trimmed,
      });

      final data = result.data;
      if (data is! Map) return [];

      final suggestions = (data['suggestions'] as List?) ?? [];

      return suggestions
          .whereType<Map>()
          .map((s) => PlaceSuggestion.fromJson(s))
          .where((s) => s.placeId.isNotEmpty && s.mainText.isNotEmpty)
          .toList();
    } on FirebaseFunctionsException catch (e) {
      // ignore: avoid_print
      print('[PlacesService] Cloud Function error: ${e.code} — ${e.message}');
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('[PlacesService] Unexpected error: $e');
      return [];
    }
  }
}