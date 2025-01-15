import 'package:firebase_auth/firebase_auth.dart';
import 'package:cat304/reusable_widgets/reusable_widget.dart';
import 'package:cat304/screens/home_navigation.dart';
import 'package:cat304/screens/reset_password.dart';
import 'package:cat304/screens/signup_screen.dart';
import 'package:cat304/screens/admin_page.dart';
//import 'package:cat304/utils/color_utils.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class SignInScreen extends StatefulWidget {
  final bool hasNotificationPermission;
  final bool clearFields;

  const SignInScreen({
    Key? key,
    required this.hasNotificationPermission,
    this.clearFields = false,
  }) : super(key: key);

  @override
  _SignInScreenState createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  TextEditingController _passwordTextController = TextEditingController();
  TextEditingController _myKadController = TextEditingController();
  TextEditingController _emailController = TextEditingController();
  bool isAdminLogin = false;

  @override
  void initState() {
    super.initState();
    if (widget.clearFields) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _myKadController.clear();
        _passwordTextController.clear();
      });
    }
    checkLoginStatus();
  }

  Future<void> checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    
    if (widget.clearFields) {
      await prefs.clear();
      _myKadController.clear();
      _passwordTextController.clear();
      return;
    }

    final savedMyKad = prefs.getString('myKad');
    final savedPassword = prefs.getString('password');
    
    if (savedMyKad != null && savedPassword != null) {
      // Check user status in Firestore before auto-login
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('myKadNumber', isEqualTo: savedMyKad)
          .get();

      if (userQuery.docs.isNotEmpty) {
        final userData = userQuery.docs.first.data();
        
        // Only proceed with auto-login if user is approved
        if (userData['status'] == 'approved') {
          _myKadController.text = savedMyKad;
          _passwordTextController.text = savedPassword;
          await handleUserLogin();
        } else {
          // Clear saved credentials if not approved
          await prefs.clear();
          _myKadController.clear();
          _passwordTextController.clear();
        }
      } else {
        // Clear saved credentials if user not found
        await prefs.clear();
      }
    }
  }

  void _clearFields() {
    _passwordTextController.clear();
    _myKadController.clear();
    _emailController.clear();
  }

  Future<void> handleUserLogin() async {
    try {
      if (_myKadController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Please enter your MyKad number')),
        );
        return;
      }

      // First check if current user is logged in and log them out
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .update({
          'loginStatus': 0,
          'lastLogoutTime': FieldValue.serverTimestamp(),
        });
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        await FirebaseAuth.instance.signOut();
      }

      // Continue with regular user check
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('myKadNumber', isEqualTo: _myKadController.text)
          .get();
          
      if (userDoc.docs.isEmpty) {
        throw FirebaseAuthException(
          code: 'user-not-found',
          message: 'No user found with this MyKad number',
        );
      }

      final userData = userDoc.docs.first.data();
      final userStatus = userData['status'] as String?;
      final loginStatus = userData['loginStatus'] as int?;

      // Check if user is suspended
      if (userStatus == 'suspended') {
        throw Exception('Your account is suspended');
      }
      
      // Check if user is approved
      if (userStatus != 'approved') {
        throw Exception('Your account is pending approval');
      }

      // Check if user is already logged in
      if (loginStatus == 1) {
        throw Exception('Account already logged in on another device');
      }

      // If approved and not logged in, proceed with login
      String email = userData['email'];
      UserCredential userCredential = await FirebaseAuth.instance
          .signInWithEmailAndPassword(
        email: email,
        password: _passwordTextController.text,
      );
      
      // Update login status after successful sign in
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .update({
        'loginStatus': 1,
        'lastLoginTime': FieldValue.serverTimestamp(),
      });
      
      // Save new credentials after successful login
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('myKad', _myKadController.text);
      await prefs.setString('password', _passwordTextController.text);

      if (!mounted) return;
      
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => HomeNavigation()),
        (route) => false,
      );
    } catch (error) {
      print("Error ${error.toString()}");
      if (!mounted) return;
      
      // Clear text fields for specific cases
      if (error is FirebaseAuthException && error.code == 'account-deleted') {
        // Remove the record from deleted_accounts after showing the message
        await FirebaseFirestore.instance
            .collection('deleted_accounts')
            .doc(_myKadController.text)
            .delete();
            
        // Clear text fields
        _myKadController.clear();
        _passwordTextController.clear();
      } else if (error.toString().contains('account is suspended') || 
                error.toString().contains('account is pending approval')) {
        // Clear text fields for suspended or pending accounts
        _myKadController.clear();
        _passwordTextController.clear();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    }
  }

  Future<void> logout() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Clear the FCM token
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'fcmToken': '',
          'lastTokenUpdate': FieldValue.serverTimestamp(),
        });
      }
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('myKad');
      await prefs.remove('password');
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      print("Error during logout: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        color: Colors.black,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, MediaQuery.of(context).size.height * 0.15, 20, 0),
            child: Column(
              children: <Widget>[
                Image.asset(
                  "images/logo.png",
                  height: 120,
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          isAdminLogin = false;
                          _clearFields();
                        });
                      },
                      icon: Icon(
                        Icons.person,
                        color: !isAdminLogin ? Colors.white : Colors.grey,
                      ),
                      label: Text(
                        "User",
                        style: TextStyle(
                          color: !isAdminLogin ? Colors.white : Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Text(" | ", style: TextStyle(color: Colors.grey)),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          isAdminLogin = true;
                          _clearFields();
                        });
                      },
                      icon: Icon(
                        Icons.admin_panel_settings,
                        color: isAdminLogin ? Colors.white : Colors.grey,
                      ),
                      label: Text(
                        "Admin",
                        style: TextStyle(
                          color: isAdminLogin ? Colors.white : Colors.grey,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                reusableTextField(
                  isAdminLogin ? "Admin ID" : "MyKad Number",
                  isAdminLogin ? Icons.admin_panel_settings : Icons.person_outline,
                  false,
                  isAdminLogin ? _emailController : _myKadController,
                  isModern: true,
                  inputType: isAdminLogin ? TextInputType.text : TextInputType.number,
                ),
                const SizedBox(height: 20),
                reusableTextField(
                  "Password",
                  Icons.lock_outline,
                  true,
                  _passwordTextController,
                  isModern: true,
                ),
                const SizedBox(height: 30),
                Container(
                  width: MediaQuery.of(context).size.width,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: TextButton(
                    onPressed: () async {
                      try {
                        if (isAdminLogin) {
                          if (_emailController.text == "admin" && 
                              _passwordTextController.text == "123456") {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => AdminPage()),
                            );
                          } else {
                            throw Exception('Invalid admin credentials');
                          }
                        } else {
                          await handleUserLogin();
                        }
                      } catch (error) {
                        print("Error ${error.toString()}");
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isAdminLogin ? 
                            'Invalid admin credentials' : 
                            error.toString())),
                        );
                      }
                    },
                    child: Text(
                      "Login",
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ),
                if (!isAdminLogin) ...[  // Only show these widgets for user login
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: () {
                      Navigator.push(context,
                          MaterialPageRoute(builder: (context) => ResetPassword()));
                    },
                    child: Text(
                      "Forgot Password?",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("Don't have an account? ",
                          style: TextStyle(color: Colors.grey)),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (context) => SignUpScreen()));
                        },
                        child: Text(
                          "Sign Up",
                          style: TextStyle(color: Colors.white),
                        ),
                      )
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}