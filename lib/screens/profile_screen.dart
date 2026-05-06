import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';   // ✅ OneSignal (replaces FCM)
import 'auth_screen.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);

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
    _refreshOneSignalToken(); // ✅ Ensure OneSignal user is linked when profile loads
  }

  // ✅ Link OneSignal user (replaces FCM token saving)
  Future<void> _refreshOneSignalToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // This links the current device to the logged-in user in OneSignal
      OneSignal.login(user.uid);
      print("✅ OneSignal user linked for user: ${user.uid}");
    } catch (e) {
      print("❌ Error linking OneSignal user: $e");
    }
  }

  Future<void> _loadUserData() async {
    setState(() {
      _isLoading = true;
    });
    
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
          
          // Update UserSession with loaded data
          UserSession.userName = data['name'] ?? '';
          UserSession.profileImageUrl = data['profileImageUrl'];
        }
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter your name'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    setState(() {
      _isSaving = true;
    });
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({
        'name': _nameController.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      // Update UserSession
      UserSession.userName = _nameController.text.trim();
      
      // Save to SharedPreferences for persistence
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userName', _nameController.text.trim());
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully!'),
            backgroundColor: kobicha,
          ),
        );
      }
    } catch (e) {
      print('Error updating profile: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          _isSaving = true;
        });
        
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
            .update({
          'profileImageUrl': downloadUrl,
        });
        
        setState(() {
          _profileImageUrl = downloadUrl;
          _isSaving = false;
        });
        
        // Update UserSession
        UserSession.profileImageUrl = downloadUrl;
        
        // Save to SharedPreferences for persistence
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('profileImageUrl', downloadUrl);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile picture updated!'),
              backgroundColor: kobicha,
            ),
          );
        }
      }
    } catch (e) {
      print('Error picking image: $e');
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeProfileImage() async {
    setState(() {
      _isSaving = true;
    });
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userId)
          .update({
        'profileImageUrl': FieldValue.delete(),
      });
      
      setState(() {
        _profileImageUrl = null;
        _isSaving = false;
      });
      
      // Update UserSession
      UserSession.profileImageUrl = null;
      
      // Save to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('profileImageUrl', '');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile picture removed'),
            backgroundColor: kobicha,
          ),
        );
      }
    } catch (e) {
      print('Error removing image: $e');
      setState(() {
        _isSaving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: chamoisee),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [smokyBlack, blackBean, kobicha],
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
                            gradient: LinearGradient(
                              colors: [kobicha, chamoisee],
                            ),
                            border: Border.all(color: chamoisee, width: 2),
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
                            icon: Icon(Icons.photo_camera, size: 16, color: chamoisee),
                            label: Text('Upload', style: TextStyle(color: chamoisee)),
                          ),
                          if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty)
                            TextButton.icon(
                              onPressed: _removeProfileImage,
                              icon: Icon(Icons.delete, size: 16, color: Colors.red),
                              label: const Text('Remove', style: TextStyle(color: Colors.red)),
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
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Full Name',
                    labelStyle: TextStyle(color: chamoisee),
                    prefixIcon: Icon(Icons.person_outline, color: chamoisee),
                    filled: true,
                    fillColor: licorice.withOpacity(0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: kobicha, width: 1.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: chamoisee, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Email Field
                TextField(
                  controller: _emailController,
                  style: const TextStyle(color: Colors.white54),
                  readOnly: true,
                  enabled: false,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    labelStyle: TextStyle(color: chamoisee.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.email_outlined, color: chamoisee.withOpacity(0.5)),
                    filled: true,
                    fillColor: licorice.withOpacity(0.6),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: kobicha, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // User Role Display
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: licorice.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kobicha, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.badge, color: chamoisee),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Role', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            Text(
                              (UserSession.userRole ?? 'member') == 'admin' ? 'Administrator' : 'Worship Leader',
                              style: TextStyle(color: chamoisee, fontSize: 16, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: (UserSession.userRole ?? 'member') == 'admin'
                              ? Colors.green.withOpacity(0.2)
                              : kobicha.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          (UserSession.userRole ?? 'member') == 'admin' ? 'Admin' : 'Member',
                          style: TextStyle(
                            color: (UserSession.userRole ?? 'member') == 'admin' ? Colors.green : chamoisee,
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
                            color: licorice.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kobicha, width: 1.5),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: chamoisee),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Member Since', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    Text(
                                      DateFormat('MMMM d, yyyy').format(date),
                                      style: TextStyle(color: chamoisee, fontSize: 16, fontWeight: FontWeight.w500),
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
                    backgroundColor: kobicha,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
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
      color: kobicha,
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 40,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}