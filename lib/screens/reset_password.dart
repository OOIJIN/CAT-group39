import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cat304/reusable_widgets/reusable_widget.dart';
import 'package:flutter/material.dart';

class ResetPassword extends StatefulWidget {
  const ResetPassword({super.key});

  @override
  _ResetPasswordState createState() => _ResetPasswordState();
}

class _ResetPasswordState extends State<ResetPassword> {
  final TextEditingController _myKadController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  Future<void> resetPassword() async {
    if (_myKadController.text.isEmpty || _emailController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    try {
      // First verify if MyKad and email match in Firestore
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .where('myKadNumber', isEqualTo: _myKadController.text)
          .where('email', isEqualTo: _emailController.text)
          .get();

      if (userDoc.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No matching account found')),
        );
        return;
      }

      // Send reset email to the verified email
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailController.text
      );

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Password reset email sent')),
      );
      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Reset Password",
          style: TextStyle(color: Colors.white),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SizedBox(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.of(context).size.height * 0.15,
              20,
              0
            ),
            child: Column(
              children: <Widget>[
                Image.asset(
                  "images/logo.png",
                  height: 120,
                ),
                const SizedBox(height: 30),
                reusableTextField(
                  "MyKad Number",
                  Icons.person_2_outlined,
                  false,
                  _myKadController,
                  isModern: true,
                  inputType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                reusableTextField(
                  "Email",
                  Icons.email_outlined,
                  false,
                  _emailController,
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
                    onPressed: resetPassword,
                    child: Text(
                      "Send",
                      style: TextStyle(color: Colors.white, fontSize: 18),
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
}