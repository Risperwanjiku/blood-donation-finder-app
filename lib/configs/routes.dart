import 'package:get/get.dart';
import 'package:test_app/view/screen/homescreen.dart';
import 'package:test_app/view/screen/login.dart';
import 'package:test_app/view/screen/signup.dart';
import 'package:test_app/view/screen/notifications.dart';
import 'package:test_app/view/screen/blood_requests/request_details.dart';
import 'package:test_app/view/screen/blood_requests/responses_list.dart';
import 'package:test_app/view/screen/donation_history.dart';

var routes = [
   GetPage(name: '/signup', page: () => SignupScreen()),
   GetPage(name: '/login', page: () => LoginScreen()),
   GetPage(name: '/homeScreen', page: () => HomeScreen()),
   GetPage(name: '/notifications', page: () => NotificationsScreen()),
   GetPage(
      name: '/request-details',
      page: () => RequestDetails(requestId: Get.arguments as String),
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