import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cat304/screens/signin_screen.dart';
import 'package:cat304/noti.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  _DeleteAccountScreenState createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _isLoading = false;
  final TextEditingController _passwordController = TextEditingController();

  Future<void> _deleteAccount() async {
    if (_passwordController.text.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter your current password')),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get user data from Firestore
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        final userData = userDoc.data();
        final userEmail = userData?['email'];

        // Reauthenticate user before deletion
        final credential = EmailAuthProvider.credential(
          email: userEmail ?? user.email!,
          password: _passwordController.text,
        );
        await user.reauthenticateWithCredential(credential);

        // Clear FCM token and update status
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
              'fcmToken': null,
              'loginStatus': 0,
              'lastLogoutTime': FieldValue.serverTimestamp(),
            });

        // Delete from Authentication
        await FirebaseAuth.instance.currentUser?.delete();

        // Delete from Firestore collections
        await _deleteUserData(user.uid, userEmail);

        if (!mounted) return;
        
        // Clear saved credentials
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        // Show deletion message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Your account has been deleted'),
            duration: Duration(seconds: 2),
          ),
        );

        // Wait for message to show
        await Future.delayed(Duration(seconds: 2));

        // Navigate
        if (!mounted) return;
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (context) => SignInScreen(
              hasNotificationPermission: false,
              clearFields: true,
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete account: Incorrect password')),
      );
    }
  }

  Future<void> _deleteUserData(String uid, String? userEmail) async {
    // Delete user document
    await FirebaseFirestore.instance.collection('users').doc(uid).delete();
    
    // Delete user's notifications
    await FirebaseFirestore.instance
        .collection('notifications')
        .where('userEmail', isEqualTo: userEmail)
        .get()
        .then((snapshot) {
      for (var doc in snapshot.docs) {
        doc.reference.delete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Delete Account', 
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current password *',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                hintText: 'Enter your current password',
                hintStyle: TextStyle(
                  color: Colors.grey,
                  fontSize: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Enter your current password to confirm cancellation of your account.',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isLoading ? null : _deleteAccount,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                padding: EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.white),
                ),
              ),
              child: _isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'Delete account',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}