import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/admin_screen.dart';
import 'screens/music_director_screen.dart';
import 'screens/musician_dashboard_screen.dart';

const Color smokyBlack = Color(0xFF110703);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);

class UserSession {
  static String? userId;
  static String? userName;
  static String? userEmail;
  static String? userRole;
  static String? profileImageUrl;
  static bool isLoggedIn = false;
  static void clearSession() {
    userId = null;
    userName = null;
    userEmail = null;
    userRole = null;
    profileImageUrl = null;
    isLoggedIn = false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  } catch (e) {}
  
  const String onesignalAppId = "6eed93c0-d444-4990-9c6d-cc151a557578";
  OneSignal.initialize(onesignalAppId);
  OneSignal.Notifications.addClickListener((event) {});
  
  runApp(const WorshipTeamApp());
}

class WorshipTeamApp extends StatelessWidget {
  const WorshipTeamApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Harp & Honor',
      theme: ThemeData.dark().copyWith(
        primaryColor: kobicha,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: ColorScheme.fromSeed(seedColor: kobicha, brightness: Brightness.dark),
      ),
      home: const CheckAuthScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class CheckAuthScreen extends StatefulWidget {
  const CheckAuthScreen({super.key});
  @override
  State<CheckAuthScreen> createState() => _CheckAuthScreenState();
}

class _CheckAuthScreenState extends State<CheckAuthScreen> {
  bool _isLoading = true;
  String? _targetScreen;

  @override
  void initState() {
    super.initState();
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUserId = prefs.getString('userId');
    final savedUserRole = prefs.getString('userRole');
    final savedUserName = prefs.getString('userName');
    final savedUserEmail = prefs.getString('userEmail');
    
    if (savedUserId != null && savedUserRole != null && savedUserRole.isNotEmpty) {
      UserSession.userId = savedUserId;
      UserSession.userRole = savedUserRole;
      UserSession.userName = savedUserName ?? 'User';
      UserSession.userEmail = savedUserEmail ?? '';
      UserSession.isLoggedIn = true;
      _targetScreen = savedUserRole;
    } else {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
          if (doc.exists) {
            final data = doc.data() as Map<String, dynamic>;
            String role = 'member';
            if (data['isAdmin'] == true) role = 'admin';
            else if (data['isMusicDirector'] == true) role = 'music_director';
            else if (data['isMusician'] == true) role = 'musician';
            
            await prefs.setString('userId', user.uid);
            await prefs.setString('userRole', role);
            await prefs.setString('userName', data['name'] ?? user.email?.split('@').first ?? 'User');
            await prefs.setString('userEmail', user.email ?? '');
            
            UserSession.userId = user.uid;
            UserSession.userRole = role;
            UserSession.userName = data['name'] ?? user.email?.split('@').first ?? 'User';
            UserSession.userEmail = user.email ?? '';
            UserSession.isLoggedIn = true;
            _targetScreen = role;
          }
        } catch (e) {}
      }
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_targetScreen == 'admin') return const AdminScreen();
    if (_targetScreen == 'music_director') return const MusicDirectorDashboard();
    if (_targetScreen == 'musician') return const MusicianDashboardScreen();
    if (_targetScreen == 'member' || UserSession.isLoggedIn) return const DashboardScreen();
    return const AuthScreen();
  }
}