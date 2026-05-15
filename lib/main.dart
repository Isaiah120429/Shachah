import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'screens/splash_screen.dart';

// ✅ Global navigator key for handling notification taps from anywhere
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Preload Google Fonts
  await GoogleFonts.pendingFonts([
    GoogleFonts.playfairDisplay(),
    GoogleFonts.montserrat(),
  ]);

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: const FirebaseOptions(
        apiKey: "AIzaSyD__w5lh9b7zg7wUX2-hd4meRTGdBpzeqQ",
        authDomain: "worship-team-app-ac0eb.firebaseapp.com",
        projectId: "worship-team-app-ac0eb",
        storageBucket: "worship-team-app-ac0eb.firebasestorage.app",
        messagingSenderId: "616124787110",
        appId: "1:616124787110:web:67676882cda13aaf3d0767",
      ),
    );
    print("✅ Firebase initialized");
  } catch (e) {
    print("❌ Firebase init error: $e");
  }

  // ✅ Initialize OneSignal ONLY for mobile (Android/iOS)
  // Web does not support OneSignal plugin
  if (!kIsWeb) {
    try {
      OneSignal.initialize("6eed93c0-d444-4990-9c6d-cc151a557578");
      
      // Request notification permission (Android 13+ / iOS)
      await OneSignal.Notifications.requestPermission(true);
      
      // ✅ Handle notification tap (opens app)
      OneSignal.Notifications.addClickListener((event) {
        final data = event.notification.additionalData;
        if (data != null) {
          final type = data['type'];      // 'announcement', 'lineup', 'song', etc.
          final id = data['id'];
          print("🔔 Notification tapped: type=$type, id=$id");
          
          // You can navigate based on the type – example:
          // if (type == 'announcement') {
          //   navigatorKey.currentState?.pushNamed('/announcements');
          // } else if (type == 'lineup') {
          //   navigatorKey.currentState?.pushNamed('/schedule', arguments: id);
          // } else if (type == 'song') {
          //   navigatorKey.currentState?.pushNamed('/song_detail', arguments: id);
          // }
        }
      });
      
      print("✅ OneSignal initialized for mobile");
    } catch (e) {
      print("⚠️ OneSignal init error (expected on web): $e");
    }
  } else {
    print("⚠️ OneSignal skipped: Running on Web");
  }

  runApp(const WorshipTeamApp());
}

class WorshipTeamApp extends StatelessWidget {
  const WorshipTeamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Shachah',
      navigatorKey: navigatorKey, // ✅ for notification navigation
      theme: ThemeData.dark().copyWith(
        primaryColor: const Color(0xFF6E3C19),
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6E3C19),
          brightness: Brightness.dark,
        ),
      ),
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// =========================================================================
// ✅ Helper function to sync OneSignal player ID and role to Firestore
// Call this immediately after the user logs in (e.g., in AuthScreen)
// =========================================================================
Future<void> syncOneSignalUser(String userId, String role) async {
  // Skip on web
  if (kIsWeb) {
    print("⚠️ syncOneSignalUser skipped: Running on Web");
    return;
  }
  
  try {
    await Future.delayed(const Duration(seconds: 2));
    final onesignalId = await OneSignal.User.getOnesignalId();
    if (onesignalId != null && onesignalId.isNotEmpty) {
      await FirebaseFirestore.instance.collection('users').doc(userId).set({
        'onesignalId': onesignalId,
        'role': role,
      }, SetOptions(merge: true));
      print("✅ OneSignal ID stored: $onesignalId");
    }
    await OneSignal.User.addTags({"role": role});
    print("✅ Role tag added: $role");
  } catch (e) {
    print("❌ Sync error: $e");
  }
}