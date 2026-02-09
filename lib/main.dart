import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:test_app/configs/routes.dart';
import 'package:test_app/view/screen/login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:test_app/services/notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
      getPages: routes,
    ),
  );
}