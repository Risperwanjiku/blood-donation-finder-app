import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:damulink/configs/routes.dart';
import 'package:damulink/view/screen/login.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ─── Firestore offline persistence ─────────────────────────
  // Caches data locally so the app works on slow / no network.
  // Reads come from local cache first, writes are queued and
  // synced when connection returns. Free performance + UX win.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );
  // ──────────────────────────────────────────────────────────

  runApp(
    GetMaterialApp(
      debugShowCheckedModeBanner: false,
      home: LoginScreen(),
      getPages: routes,
    ),
  );
}