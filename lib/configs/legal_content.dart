import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:damulink/configs/theme.dart';

/// Single source of truth for DamuLink's legal text and the dialog that
/// presents it. Used by BOTH signup and settings so the Terms / Privacy
/// text (and version) can never drift between the two screens.
class LegalContent {
  LegalContent._();

  // Bump this when the terms or privacy policy materially change.
  static const String termsVersion = '1.1';

  static const String termsOfService =
      "DamuLink Terms of Service (v$termsVersion).\n\n"
      "This app is currently in development. Final terms will be "
      "published before production launch.\n\n"
      "By using DamuLink, you agree to use the service in good faith "
      "to help connect people in need of blood with willing donors. "
      "DamuLink is a connection facilitator, not a medical service.\n\n"
      "We do not guarantee any donor response or successful matching. "
      "Always coordinate with a qualified medical professional for "
      "all blood transfusion needs.\n\n"
      "Continued use implies acceptance of these terms.";

  static const String privacyPolicy =
      "DamuLink Privacy Policy (v$termsVersion).\n\n"
      "We collect the following information when you sign up:\n"
      " • Full name\n"
      " • Email address\n"
      " • Phone number\n"
      " • Location\n"
      " • Blood type\n"
      " • Gender (used only to calculate your safe donation interval)\n\n"
      "How we use your data:\n"
      " • To match you with compatible blood requests\n"
      " • To notify you when someone needs blood you can donate\n"
      " • To allow other users to contact you ONLY after you "
      "explicitly offer to help\n"
      " • To recommend safe intervals between your donations, based "
      "on Kenyan medical practice (men every 3 months, women every "
      "4 months)\n\n"
      "Your data is stored securely on Firebase (Google Cloud). "
      "We do not sell or share your data with third parties.\n\n"
      "Under Kenya's Data Protection Act 2019, you have the right "
      "to access, correct, or delete your personal data at any time.\n\n"
      "Contact: privacy@damulink.test (placeholder).";

  static void showTerms() =>
      _showLegalPage(title: 'Terms of Service', body: termsOfService);

  static void showPrivacy() =>
      _showLegalPage(title: 'Privacy Policy', body: privacyPolicy);

  static void _showLegalPage({required String title, required String body}) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Container(
          padding: const EdgeInsets.all(AppSpace.lg),
          constraints: const BoxConstraints(maxHeight: 500),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: AppText.title)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Get.back(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.sm),
              const Divider(),
              const SizedBox(height: AppSpace.sm),
              Flexible(
                child: SingleChildScrollView(
                  child: Text(body, style: AppText.body),
                ),
              ),
              const SizedBox(height: AppSpace.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Get.back(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text(
                    "Close",
                    style: TextStyle(color: Colors.white, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}