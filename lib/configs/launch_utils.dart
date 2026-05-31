import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches external apps — dialer, WhatsApp, Google Maps.
/// Returns true on success, false if the app couldn't be opened, so the
/// caller owns the UI feedback (snackbars stay in the widget layer).
class LaunchUtils {
  LaunchUtils._();

  static Future<bool> callPhone(String phone) async {
    HapticFeedback.lightImpact();
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return true;
    }
    return false;
  }

  static Future<bool> openWhatsApp(String phone) async {
    HapticFeedback.lightImpact();
    // wa.me needs international format: no '+', no leading 0.
    // Stored numbers are Kenyan local (e.g. 0785236442).
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = '254${digits.substring(1)}';
    } else if (!digits.startsWith('254') && digits.length == 9) {
      digits = '254$digits';
    }
    final uri = Uri.parse('https://wa.me/$digits');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  static Future<bool> openDirections(
    String hospital,
    String area,
    String placeId,
  ) async {
    HapticFeedback.lightImpact();
    final dest = Uri.encodeComponent(
      area.isNotEmpty ? '$hospital, $area' : hospital,
    );
    var url = 'https://www.google.com/maps/dir/?api=1&destination=$dest';
    if (placeId.isNotEmpty) {
      url += '&destination_place_id=$placeId';
    }
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }
}