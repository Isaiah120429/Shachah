import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

// Import screens (same folder)
import 'dashboard_screen.dart';
import 'admin_screen.dart';
import 'music_director_screen.dart';
import 'musician_dashboard_screen.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);
const Color highlightError = Color(0xFFC62828);

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
  
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController nameController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  
  @override
  void initState() {
    super.initState();
  }
  
  Future<void> _linkUserWithOneSignal(String userId) async {
    try {
      await OneSignal.login(userId);
      print("✅ OneSignal user linked: $userId");
    } catch (e) {
      print("❌ OneSignal error: $e");
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
    
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => destination),
    );
  }
  
  // ==================== BUILD UI ====================
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/notes.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildLogo(),
                  const SizedBox(height: 40),
                  _buildFormCard(),
                  const SizedBox(height: 20),
                  _buildToggleText(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildLogo() {
    return Column(
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFF6E3C19), Color(0xFFA7795E)],
            ),
          ),
          child: ClipOval(
            child: Transform.scale(
              scale: 1.1,
              child: Image.asset(
                'assets/stones.png',
                width: 100,
                height: 100,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF6E3C19), Color(0xFFA7795E)],
                      ),
                    ),
                    child: const Center(
                      child: Icon(Icons.music_note, color: Colors.white, size: 50),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'BHWT',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Color.fromARGB(255, 207, 199, 199),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isLogin ? 'Sign in to continue' : 'Create your account',
          style: const TextStyle(
            color: Color.fromARGB(255, 211, 165, 136),
            fontSize: 14,
          ),
        ),
      ],
    );
  }
  
  Widget _buildFormCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: licorice.withOpacity(0.70),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kobicha.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: smokyBlack.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
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
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter your name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            
            _buildTextField(
              controller: emailController,
              label: 'Email Address',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Enter a valid email';
                }
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
                icon: Icon(
                  obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: chamoisee,
                  size: 20,
                ),
                onPressed: () {
                  setState(() {
                    obscurePassword = !obscurePassword;
                  });
                },
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                if (!isLogin && value.length < 6) {
                  return 'Password must be at least 6 characters';
                }
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
                  icon: Icon(
                    obscureConfirmPassword ? Icons.visibility_off : Icons.visibility,
                    color: chamoisee,
                    size: 20,
                  ),
                  onPressed: () {
                    setState(() {
                      obscureConfirmPassword = !obscureConfirmPassword;
                    });
                  },
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please confirm your password';
                  }
                  if (value != passwordController.text) {
                    return 'Passwords do not match';
                  }
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
                  child: Text(
                    'Forgot Password?',
                    style: TextStyle(color: chamoisee, fontSize: 12),
                  ),
                ),
              ),
            
            const SizedBox(height: 18),
            
            ElevatedButton(
              onPressed: _isLoading ? null : () {
                if (_formKey.currentState!.validate()) {
                  _handleAuth();
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kobicha,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 5,
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      isLogin ? 'SIGN IN' : 'SIGN UP',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
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
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: chamoisee),
        prefixIcon: Icon(icon, color: kobicha, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: smokyBlack.withOpacity(0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: chamoisee.withOpacity(0.5)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: chamoisee, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1.5),
        ),
        errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 10),
      ),
      validator: validator,
    );
  }
  
  Widget _buildToggleText() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isLogin ? "Don't have an account? " : "Already have an account? ",
          style: TextStyle(color: const Color.fromARGB(255, 212, 152, 116), fontSize: 13),
        ),
        GestureDetector(
          onTap: () {
            setState(() {
              isLogin = !isLogin;
              emailController.clear();
              passwordController.clear();
              confirmPasswordController.clear();
              nameController.clear();
            });
          },
          child: Text(
            isLogin ? 'Sign Up' : 'Sign In',
            style: TextStyle(
              color: const Color.fromARGB(255, 206, 162, 130),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
  
  // ==================== AUTHENTICATION ====================
  void _handleAuth() async {
    String email = emailController.text.trim();
    String password = passwordController.text.trim();
    
    setState(() => _isLoading = true);
    print("=== Starting Auth ===");
    
    try {
      if (isLogin) {
        // LOGIN
        UserCredential userCredential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: email, password: password);
        print("✅ Signed in: ${userCredential.user?.uid}");
        
        // Get user role from Firestore
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .get();
        
        String userName = email.split('@').first;
        String role = 'member';
        
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          userName = data['name'] ?? email.split('@').first;
          if (data['isAdmin'] == true) {
            role = 'admin';
          } else if (data['isMusicDirector'] == true) {
            role = 'music_director';
          } else if (data['isMusician'] == true) {
            role = 'musician';
          } else {
            role = 'member';
          }
        } else {
          // Create user document
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .set({
            'id': userCredential.user!.uid,
            'name': userName,
            'email': email,
            'isAdmin': false,
            'isMusicDirector': false,
            'isMusician': false,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
        
        // Save to UserSession
        UserSession.userId = userCredential.user!.uid;
        UserSession.userEmail = email;
        UserSession.userName = userName;
        UserSession.userRole = role;
        UserSession.isLoggedIn = true;
        
        // ✅ SAVE SESSION TO SHAREDPREFERENCES
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', userCredential.user!.uid);
        await prefs.setString('userRole', role);
        await prefs.setString('userName', userName);
        await prefs.setString('userEmail', email);
        print("✅ Session saved to SharedPreferences - role: $role");
        
        await _linkUserWithOneSignal(userCredential.user!.uid);
        
        // ✅ Navigate to correct dashboard
        if (mounted) {
          _navigateToDashboard(role);
        }
      } else {
        // SIGN UP
        print("Signing up...");
        UserCredential userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        print("✅ Signed up: ${userCredential.user?.uid}");
        
        // Save user to Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCredential.user!.uid)
            .set({
          'id': userCredential.user!.uid,
          'name': nameController.text.trim(),
          'email': email,
          'isAdmin': false,
          'isMusicDirector': false,
          'isMusician': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        // Save session
        UserSession.userId = userCredential.user!.uid;
        UserSession.userName = nameController.text.trim();
        UserSession.userEmail = email;
        UserSession.userRole = 'member';
        UserSession.isLoggedIn = true;
        
        // ✅ SAVE SESSION TO SHAREDPREFERENCES
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userId', userCredential.user!.uid);
        await prefs.setString('userRole', 'member');
        await prefs.setString('userName', nameController.text.trim());
        await prefs.setString('userEmail', email);
        print("✅ Session saved to SharedPreferences");
        
        await _linkUserWithOneSignal(userCredential.user!.uid);
        
        // ✅ Navigate to dashboard (member)
        if (mounted) {
          _navigateToDashboard('member');
        }
      }
    } on FirebaseAuthException catch (e) {
      print("❌ Firebase Error: ${e.code}");
      String message = '';
      if (e.code == 'user-not-found') {
        message = 'No user found with this email';
      } else if (e.code == 'wrong-password') {
        message = 'Wrong password provided';
      } else if (e.code == 'email-already-in-use') {
        message = 'Email already exists';
      } else if (e.code == 'weak-password') {
        message = 'Password is too weak (minimum 6 characters)';
      } else if (e.code == 'invalid-email') {
        message = 'Invalid email address';
      } else {
        message = e.message ?? 'Authentication failed';
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: highlightError),
        );
      }
    } catch (e) {
      print("❌ General Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: highlightError),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
  
  void _showForgotPasswordDialog() {
    TextEditingController resetEmailController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: licorice,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_reset, color: kobicha, size: 48),
                const SizedBox(height: 12),
                const Text('Reset Password', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Enter your email to receive reset link', style: TextStyle(color: chamoisee, fontSize: 12), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextField(
                  controller: resetEmailController,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Email Address',
                    hintStyle: TextStyle(color: chamoisee),
                    prefixIcon: Icon(Icons.email_outlined, color: kobicha),
                    filled: true,
                    fillColor: smokyBlack.withOpacity(0.5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(foregroundColor: chamoisee, side: BorderSide(color: kobicha)),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          final email = resetEmailController.text.trim();
                          if (email.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter your email'), backgroundColor: highlightError),
                            );
                            return;
                          }
                          try {
                            await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: const Text('Reset link sent to your email'), backgroundColor: kobicha),
                              );
                              Navigator.pop(context);
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Error sending reset email'), backgroundColor: highlightError),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: kobicha),
                        child: const Text('Send'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}