import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'auth_screen.dart';

// Professional Black/White/Smoke Palette
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);

// Functional highlights
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightWarning = Color(0xFFFFA726);
const Color highlightError = Color(0xFFEF5350);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  
  String? _profileImageUrl;
  bool _isLoading = true;
  bool _isSaving = false;
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _refreshOneSignalToken();
  }

  Future<void> _refreshOneSignalToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      OneSignal.login(user.uid);
      print("✅ OneSignal user linked for user: ${user.uid}");
    } catch (e) {
      print("❌ Error linking OneSignal user: $e");
    }
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _userId = user.uid;
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .get();
        if (userDoc.exists) {
          final data = userDoc.data() as Map<String, dynamic>;
          _nameController.text = data['name'] ?? '';
          _emailController.text = data['email'] ?? '';
          _profileImageUrl = data['profileImageUrl'];
          UserSession.userName = data['name'] ?? '';
          UserSession.profileImageUrl = data['profileImageUrl'];
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name'), backgroundColor: highlightError),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({
        'name': _nameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      UserSession.userName = _nameController.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _nameController.text.trim());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!'), backgroundColor: highlightSuccess),
        );
      }
    } catch (e) {
      print('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() => _isSaving = true);
        final file = result.files.first;
        final fileName = '$_userId.jpg';
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_images')
            .child(fileName);
        if (file.bytes != null) {
          await storageRef.putData(file.bytes!);
        } else if (file.path != null) {
          final File imageFile = File(file.path!);
          await storageRef.putFile(imageFile);
        }
        final downloadUrl = await storageRef.getDownloadURL();
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userId)
            .update({'profileImageUrl': downloadUrl});
        setState(() {
          _profileImageUrl = downloadUrl;
          _isSaving = false;
        });
        UserSession.profileImageUrl = downloadUrl;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profileImageUrl', downloadUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile picture updated!'), backgroundColor: highlightSuccess),
          );
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
        );
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() => _isSaving = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({'profileImageUrl': FieldValue.delete()});
      setState(() {
        _profileImageUrl = null;
        _isSaving = false;
      });
      UserSession.profileImageUrl = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImageUrl', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile picture removed'), backgroundColor: highlightSuccess),
        );
      }
    } catch (e) {
      print('Error removing image: $e');
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryBlack, almostBlack, darkSmoke],
          ),
        ),
        child: const Center(child: CircularProgressIndicator(color: lightGrey)),
      );
    }

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryBlack, almostBlack, darkSmoke],
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                // Profile Picture Section
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _pickImage,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [mediumGrey, lightGrey],
                            ),
                            border: Border.all(color: lightGrey, width: 2),
                          ),
                          child: ClipOval(
                            child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                                ? Image.network(
                                    _profileImageUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return _buildDefaultAvatar();
                                    },
                                  )
                                : _buildDefaultAvatar(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _pickImage,
                            icon: Icon(Icons.photo_camera, size: 16, color: lightGrey),
                            label: Text('Upload', style: TextStyle(color: lightGrey)),
                          ),
                          if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                            TextButton.icon(
                              onPressed: _removeProfileImage,
                              icon: Icon(Icons.delete, size: 16, color: highlightError),
                              label: Text('Remove', style: TextStyle(color: highlightError)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Name Field
                TextField(
                  controller: _nameController,
                  style: const TextStyle(color: primaryWhite),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: lightGrey),
                    prefixIcon: Icon(Icons.person_outline, color: lightGrey),
                    filled: true,
                    fillColor: almostBlack.withOpacity(0.8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: mediumGrey, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: lightGrey, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                // Email Field (read-only)
                TextField(
                  controller: _emailController,
                  style: TextStyle(color: primaryWhite.withOpacity(0.7)),
                  readOnly: true,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: lightGrey.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.email_outlined, color: lightGrey.withOpacity(0.5)),
                    filled: true,
                    fillColor: almostBlack.withOpacity(0.8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: mediumGrey, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                const SizedBox(height: 16),
                // User Role Display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: almostBlack.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: mediumGrey, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.badge, color: lightGrey),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Role', style: TextStyle(color: mediumGrey, fontSize: 12)),
                            Text(
                              (UserSession.userRole ?? 'member') == 'admin' ? 'Administrator' : 'Worship Leader',
                              style: TextStyle(color: lightGrey, fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (UserSession.userRole ?? 'member') == 'admin'
                              ? highlightSuccess.withOpacity(0.2)
                              : darkSmoke,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (UserSession.userRole ?? 'member') == 'admin' ? 'Admin' : 'Member',
                          style: TextStyle(
                            color: (UserSession.userRole ?? 'member') == 'admin' ? highlightSuccess : lightGrey,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Member Since
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('users')
                      .doc(_userId)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData && snapshot.data!.exists) {
                      final data = snapshot.data!.data() as Map<String, dynamic>;
                      final createdAt = data['createdAt'];
                      if (createdAt != null) {
                        final date = (createdAt as Timestamp).toDate();
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: almostBlack.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: mediumGrey, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: lightGrey),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Member Since', style: TextStyle(color: mediumGrey, fontSize: 12)),
                                    Text(
                                      DateFormat('MMMM d, yyyy').format(date),
                                      style: TextStyle(color: lightGrey, fontSize: 16, fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
                ),
                const SizedBox(height: 32),
                // Save Button
                ElevatedButton(
                  onPressed: _isSaving ? null : _updateProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: mediumGrey,
                    foregroundColor: primaryWhite,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: primaryWhite,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'SAVE CHANGES',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDefaultAvatar() {
    final initial = _nameController.text.isNotEmpty
        ? _nameController.text[0].toUpperCase()
        : 'U';
    return Container(
      color: mediumGrey,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: primaryWhite,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}