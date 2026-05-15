import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import 'dashboard_screen.dart';
import 'admin_screen.dart';
import 'music_director_screen.dart';
import 'musician_dashboard_screen.dart';

// =========================================================================
// Color Palette
// =========================================================================
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightError = Color(0xFFEF5350);

// =========================================================================
// User Session Management
// =========================================================================
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

// =========================================================================
// Auth Screen
// =========================================================================
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  bool isLogin = true;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool _isLoading = false;
  bool _isOffline = false;
  bool _isCheckingSession = true;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _checkConnectivity();
    _initializeOneSignal();
    _checkAutoLogin();
  }

  // -------------------------------------------------------------------------
  // Connectivity & Offline
  // -------------------------------------------------------------------------
  Future<void> _checkConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    setState(() => _isOffline = result == ConnectivityResult.none);
    Connectivity().onConnectivityChanged.listen((result) {
      setState(() => _isOffline = result == ConnectivityResult.none);
      if (!_isOffline && mounted) _syncOneSignalIfNeeded();
    });
  }

  Future<void> _syncOneSignalIfNeeded() async {
    // Skip on web
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final userRole = prefs.getString('userRole');
    if (userId != null && userRole != null) {
      await _syncOneSignalData(userId, userRole);
    }
  }

  // -------------------------------------------------------------------------
  // OneSignal (only on mobile)
  // -------------------------------------------------------------------------
  void _initializeOneSignal() {
    if (kIsWeb) {
      print("⚠️ OneSignal not supported on web – skipping init");
      return;
    }
    const String oneSignalAppId = "6eed93c0-d444-4990-9c6d-cc151a557578";
    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(oneSignalAppId);
    OneSignal.Notifications.requestPermission(true);
    print("✅ OneSignal initialized (mobile)");
  }

  Future<void> _syncOneSignalData(String userId, String role) async {
    if (kIsWeb || _isOffline) {
      print("⚠️ _syncOneSignalData skipped (web or offline)");
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
      } else {
        print("⚠️ OneSignal ID not available yet");
      }
      await OneSignal.User.addTags({"role": role});
      print("✅ Role tag added: $role");
    } catch (e) {
      print("❌ Sync error: $e");
    }
  }

  // -------------------------------------------------------------------------
  // Auto‑Login (skip login screen if session exists)
  // -------------------------------------------------------------------------
  Future<void> _checkAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId');
    final userRole = prefs.getString('userRole');
    final userName = prefs.getString('userName');
    final userEmail = prefs.getString('userEmail');

    if (userId != null && userRole != null) {
      UserSession.userId = userId;
      UserSession.userRole = userRole;
      UserSession.userName = userName;
      UserSession.userEmail = userEmail;
      UserSession.isLoggedIn = true;

      if (!_isOffline && !kIsWeb) {
        await _syncOneSignalData(userId, userRole);
      } else if (mounted && _isOffline) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Offline mode – using cached session'),
            backgroundColor: highlightSuccess,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      if (mounted) {
        _navigateToDashboard(userRole);
        return;
      }
    }

    if (mounted) {
      setState(() => _isCheckingSession = false);
    }
  }

  void _navigateToDashboard(String role) {
    Widget destination;
    if (role == 'admin') {
      destination = const AdminScreen();
    } else if (role == 'music_director') {
      destination = const MusicDirectorDashboard();
    } else if (role == 'musician') {
      destination = const MusicianDashboardScreen();
    } else {
      destination = const DashboardScreen();
    }
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => destination));
  }

  // -------------------------------------------------------------------------
  // UI Builders
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    if (_isCheckingSession) {
      return Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/head.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isLargeScreen = maxWidth > 600;
        final cardWidth = isLargeScreen ? 500.0 : maxWidth - 48.0;

        return Container(
          decoration: const BoxDecoration(
            image: DecorationImage(
              image: AssetImage('assets/head.jpg'),
              fit: BoxFit.cover,
            ),
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(horizontal: isLargeScreen ? 24.0 : 16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_isOffline)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: highlightSuccess.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: highlightSuccess),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.wifi_off, color: highlightSuccess, size: 16),
                              const SizedBox(width: 8),
                              Text('Offline – using cached data', style: TextStyle(color: highlightSuccess, fontSize: 12)),
                            ],
                          ),
                        ),
                      _buildLogo(isLargeScreen),
                      const SizedBox(height: 40),
                      SizedBox(width: cardWidth, child: _buildFormCard()),
                      const SizedBox(height: 20),
                      _buildToggleText(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogo(bool isLargeScreen) {
    final logoSize = isLargeScreen ? 130.0 : 110.0;
    final fontSize = isLargeScreen ? 36.0 : 28.0;
    return Column(
      children: [
        Container(
          width: logoSize,
          height: logoSize,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [mediumGrey, lightGrey]),
          ),
          child: ClipOval(
            child: Transform.scale(
              scale: 1.1,
              child: Image.asset(
                'assets/SHACHAH.png',
                width: logoSize * 0.9,
                height: logoSize * 0.9,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [mediumGrey, lightGrey]),
                  ),
                  child: const Center(child: Icon(Icons.music_note, color: primaryWhite, size: 50)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'SHACHAH',
          style: GoogleFonts.playfairDisplay(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: primaryWhite,
            letterSpacing: 1.5,
            shadows: const [Shadow(blurRadius: 12, color: Colors.white24, offset: Offset(0, 4))],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isLogin ? 'Sign in to continue' : 'Create your account',
          style: TextStyle(color: lightGrey, fontSize: isLargeScreen ? 15 : 14),
        ),
      ],
    );
  }

  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: almostBlack.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: mediumGrey.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: primaryBlack.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isLogin) ...[
              _buildTextField(
                controller: nameController,
                label: 'Full Name',
                icon: Icons.person_outline,
                validator: (value) => value == null || value.isEmpty ? 'Please enter your name' : null,
              ),
              const SizedBox(height: 16),
            ],
            _buildTextField(
              controller: emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter your email';
                if (!value.contains('@') || !value.contains('.')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _buildTextField(
              controller: passwordController,
              label: 'Password',
              icon: Icons.lock_outline,
              obscureText: obscurePassword,
              suffixIcon: IconButton(
                icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility, color: lightGrey, size: 20),
                onPressed: () => setState(() => obscurePassword = !obscurePassword),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) return 'Please enter your password';
                if (!isLogin && value.length < 6) return 'Password must be at least 6 characters';
                return null;
              },
            ),
            const SizedBox(height: 16),
            if (!isLogin) ...[
              _buildTextField(
                controller: confirmPasswordController,
                label: 'Confirm Password',
                icon: Icons.lock_outline,
                obscureText: obscureConfirmPassword,
                suffixIcon: IconButton(
                  icon: Icon(obscureConfirmPassword ? Icons.visibility_off : Icons.visibility, color: lightGrey, size: 20),
                  onPressed: () => setState(() => obscureConfirmPassword = !obscureConfirmPassword),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) return 'Please confirm your password';
                  if (value != passwordController.text) return 'Passwords do not match';
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            if (isLogin)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _showForgotPasswordDialog,
                  child: Text('Forgot Password?', style: TextStyle(color: lightGrey, fontSize: 12)),
                ),
              ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _formKey.currentState!.validate() ? _handleAuth() : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: mediumGrey,
                foregroundColor: primaryWhite,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 5,
              ),
              child: _isLoading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: primaryWhite, strokeWidth: 2))
                  : Text(isLogin ? 'SIGN IN' : 'SIGN UP', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(color: primaryWhite),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: lightGrey),
        prefixIcon: Icon(icon, color: mediumGrey, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: primaryBlack.withOpacity(0.5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: mediumGrey.withOpacity(0.5))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: lightGrey, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: highlightError, width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: highlightError, width: 1.5)),
        errorStyle: const TextStyle(color: highlightError, fontSize: 10),
      ),
      validator: validator,
    );
  }

  Widget _buildToggleText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(isLogin ? "Don't have an account? " : "Already have an account? ", style: TextStyle(color: lightGrey, fontSize: 13)),
        GestureDetector(
          onTap: () => setState(() {
            isLogin = !isLogin;
            emailController.clear();
            passwordController.clear();
            confirmPasswordController.clear();
            nameController.clear();
          }),
          child: Text(isLogin ? 'Sign Up' : 'Sign In', style: TextStyle(color: lightGrey, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Authentication Logic
  // -------------------------------------------------------------------------
  void _handleAuth() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    setState(() => _isLoading = true);
    print("=== Starting Auth ===");

    try {
      if (isLogin) {
        // LOGIN
        UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
        print("✅ Signed in: ${userCredential.user?.uid}");

        DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
        String userName = email.split('@').first;
        String role = 'member';

        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          userName = data['name'] ?? email.split('@').first;
          if (data['isAdmin'] == true) {
            role = 'admin';
          } else if (data['isMusicDirector'] == true) role = 'music_director';
          else if (data['isMusician'] == true) role = 'musician';
          else role = 'member';
        } else {
          await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
            'id': userCredential.user!.uid,
            'name': userName,
            'email': email,
            'isAdmin': false,
            'isMusicDirector': false,
            'isMusician': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        UserSession.userId = userCredential.user!.uid;
        UserSession.userEmail = email;
        UserSession.userName = userName;
        UserSession.userRole = role;
        UserSession.isLoggedIn = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', userCredential.user!.uid);
        await prefs.setString('userRole', role);
        await prefs.setString('userName', userName);
        await prefs.setString('userEmail', email);
        print("✅ Session saved to SharedPreferences - role: $role");

        await _syncOneSignalData(userCredential.user!.uid, role);
        if (mounted) _navigateToDashboard(role);
      } else {
        // SIGN UP
        print("Signing up...");
        UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
        print("✅ Signed up: ${userCredential.user?.uid}");

        await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
          'id': userCredential.user!.uid,
          'name': nameController.text.trim(),
          'email': email,
          'isAdmin': false,
          'isMusicDirector': false,
          'isMusician': false,
          'createdAt': FieldValue.serverTimestamp(),
        });

        UserSession.userId = userCredential.user!.uid;
        UserSession.userName = nameController.text.trim();
        UserSession.userEmail = email;
        UserSession.userRole = 'member';
        UserSession.isLoggedIn = true;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', userCredential.user!.uid);
        await prefs.setString('userRole', 'member');
        await prefs.setString('userName', nameController.text.trim());
        await prefs.setString('userEmail', email);
        print("✅ Session saved to SharedPreferences");

        await _syncOneSignalData(userCredential.user!.uid, 'member');
        if (mounted) _navigateToDashboard('member');
      }
    } on FirebaseAuthException catch (e) {
      print("❌ Firebase Error: ${e.code}");
      String message = '';
      switch (e.code) {
        case 'user-not-found': message = 'No user found with this email'; break;
        case 'wrong-password': message = 'Wrong password provided'; break;
        case 'email-already-in-use': message = 'Email already exists'; break;
        case 'weak-password': message = 'Password is too weak (minimum 6 characters)'; break;
        case 'invalid-email': message = 'Invalid email address'; break;
        default: message = e.message ?? 'Authentication failed';
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), backgroundColor: highlightError));
    } catch (e) {
      print("❌ General Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: highlightError));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showForgotPasswordDialog() {
    TextEditingController resetEmailController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_reset, color: lightGrey, size: 48),
              const SizedBox(height: 12),
              const Text('Reset Password', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Enter your email to receive reset link', style: TextStyle(color: lightGrey, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextField(
                controller: resetEmailController,
                style: const TextStyle(color: primaryWhite),
                decoration: InputDecoration(
                  hintText: 'Email Address',
                  hintStyle: TextStyle(color: lightGrey),
                  prefixIcon: Icon(Icons.email_outlined, color: mediumGrey),
                  filled: true,
                  fillColor: primaryBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(foregroundColor: lightGrey, side: BorderSide(color: mediumGrey)),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        final email = resetEmailController.text.trim();
                        if (email.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your email'), backgroundColor: highlightError));
                          return;
                        }
                        try {
                          await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reset link sent to your email'), backgroundColor: highlightSuccess));
                            Navigator.pop(context);
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error sending reset email'), backgroundColor: highlightError));
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: mediumGrey),
                      child: const Text('Send'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}