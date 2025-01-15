import 'package:cat304/screens/signin_screen.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat304/screens/activity_log_screen.dart';
//import 'package:cat304/screens/settings_screen.dart';
import 'package:cat304/screens/reset_password.dart';
import 'package:cat304/screens/edit_profile.dart';
import 'package:cat304/screens/delete_account.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'package:cat304/noti.dart';

class UserProfileScreen extends StatefulWidget {
  final String? userId;
  const UserProfileScreen({super.key, this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  String? _profileImageUrl;
  final ImagePicker _picker = ImagePicker();

  Future<void> _uploadImage() async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 50
      );
      
      if (image == null) return;

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
      );

      // Convert image to base64
      final bytes = await File(image.path).readAsBytes();
      final base64Image = base64Encode(bytes);

      // Store in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
            'profileImage': base64Image,
          });

      // Update state
      setState(() {
        _profileImageUrl = base64Image;
      });

      // Hide loading indicator
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile picture updated successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

    } catch (e) {
      // Hide loading indicator
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      
      print('Error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update profile picture. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _signOut() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Update login status before signing out
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'loginStatus': 0,
          'lastLogoutTime': FieldValue.serverTimestamp(),
        });
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      await FirebaseAuth.instance.signOut();
      
      if (!mounted) return;
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (context) => FutureBuilder<bool>(
            future: NotificationService.checkPermission(),
            builder: (context, snapshot) {
              return SignInScreen(
                hasNotificationPermission: snapshot.data ?? false,
              );
            },
          ),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: $e')),
      );
    }
  }

  Future<void> _showDistanceSettingDialog(BuildContext context) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Get current distance setting
    final userData = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    
    double currentDistance = userData.data()?['notificationDistance']?.toDouble() ?? 1000.0;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        double selectedDistance = currentDistance;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(
                'Set Notification Distance',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'You will receive notifications for incidents within this distance',
                    style: TextStyle(color: Colors.grey[400]),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 20),
                  Slider(
                    value: selectedDistance.clamp(500, 5000),
                    min: 500,
                    max: 5000,
                    divisions: 45,
                    label: '${(selectedDistance / 1000).toStringAsFixed(1)} km',
                    onChanged: (value) {
                      setState(() {
                        selectedDistance = value.roundToDouble();
                      });
                    },
                  ),
                  Text(
                    '${(selectedDistance / 1000).toStringAsFixed(1)} kilometers',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () async {
                    // Save the selected distance
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .update({
                      'notificationDistance': selectedDistance,
                    });
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Notification distance updated'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  child: Text('Save', style: TextStyle(color: Colors.blue)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = widget.userId ?? FirebaseAuth.instance.currentUser?.uid ?? '';
    
    if (currentUserId.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text('No user logged in', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.logout, color: Colors.red[300], size: 28),
            onPressed: _signOut,
          ),
          SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(child: Text('User not found', style: TextStyle(color: Colors.white)));
          }

          final userData = snapshot.data!.data() as Map<String, dynamic>;
          final userName = userData['name'] ?? 'User';
          final userEmail = userData['email'] ?? 'No email';
          _profileImageUrl = userData['profileImage'];

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SizedBox(height: 40),
                        GestureDetector(
                          onTap: _uploadImage,
                          child: Stack(
                            children: [
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: Colors.grey[800],
                                backgroundImage: _profileImageUrl != null
                                    ? MemoryImage(base64Decode(_profileImageUrl!))
                                    : null,
                                child: _profileImageUrl == null
                                    ? Icon(Icons.person, size: 50, color: Colors.white)
                                    : null,
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[900],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 16),
                        Text(
                          userName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          userEmail,
                          style: TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 30),
                        _buildSettingItem(
                          context,
                          'Change password',
                          Icons.lock_outline,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ResetPassword()),
                          ),
                        ),
                        _buildSettingItem(
                          context,
                          'Edit profile',
                          Icons.person_2,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => EditProfileScreen()),
                          ),
                        ),
                        _buildSettingItem(
                          context,
                          'Activity Log',
                          Icons.history,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => ActivityLogScreen()),
                          ),
                        ),
                        _buildSettingItem(
                          context,
                          'Notification Distance',
                          Icons.notifications_active,
                          () => _showDistanceSettingDialog(context),
                        ),
                        SizedBox(height: 20),
                        _buildSettingItem(
                          context,
                          'Delete account',
                          Icons.security,
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => DeleteAccountScreen()),
                          ),
                        ),
                        
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSettingItem(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey),
      title: Text(
        title,
        style: TextStyle(color: Colors.white),
      ),
      trailing: Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
    );
   }
}