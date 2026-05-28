import 'package:get/get.dart';
import 'package:damulink/view/screen/homescreen.dart';
import 'package:damulink/view/screen/login.dart';
import 'package:damulink/view/screen/signup.dart';
import 'package:damulink/view/screen/notifications.dart';
import 'package:damulink/view/screen/blood_requests/request_form.dart';
import 'package:damulink/view/screen/blood_requests/responses_list.dart';
import 'package:damulink/view/screen/donation_history.dart';

// Donor-side screens
import 'package:damulink/view/screen/donor/donor_browse.dart';
import 'package:damulink/view/screen/donor/request_details.dart';

var routes = [
  GetPage(name: '/signup', page: () => SignupScreen()),
  GetPage(name: '/login', page: () => LoginScreen()),
  GetPage(name: '/homeScreen', page: () => HomeScreen()),
  GetPage(name: '/notifications', page: () => NotificationsScreen()),
  GetPage(name: '/request-form', page: () => const RequestFormScreen()),

  // Donor's view of a request (with privacy reveal)
  GetPage(
    name: '/requestDetails',
    page: () => const RequestDetailsScreen(),
  ),

  // Donor browse list
  GetPage(
    name: '/donor-browse',
    page: () => const DonorBrowseScreen(),
  ),

  GetPage(
    name: '/responses',
    page: () {
      Map<String, dynamic> args = Get.arguments as Map<String, dynamic>;
      return ResponsesList(
        requestId: args['requestId'],
        patientName: args['patientName'],
      );
    },
  ),
  GetPage(name: '/donation-history', page: () => DonationHistory()),
];