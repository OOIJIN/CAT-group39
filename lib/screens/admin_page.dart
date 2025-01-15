import 'package:flutter/material.dart';
import 'package:cat304/screens/admin_review_screen.dart';
import 'package:cat304/screens/signin_screen.dart';
import 'package:cat304/screens/user_management_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
//import 'package:intl/intl.dart';
// import 'dart:convert';

class AdminPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Admin Dashboard',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
        actions: [
          IconButton(
            padding: EdgeInsets.only(right: 16),
            icon: Icon(
              Icons.logout,
              color: Colors.red,
              size: 24,
            ),
            onPressed: () async {
              try {
                await FirebaseAuth.instance.signOut();
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SignInScreen(
                      hasNotificationPermission: true,
                    ),
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error signing out')),
                );
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            SizedBox(height: 20),
            _buildDashboardCard(
              context,
              'Pending Accounts',
              'Review and manage new user registrations',
              Icons.person_outline,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => AdminReviewScreen()),
              ),
            ),
            SizedBox(height: 16),
            _buildDashboardCard(
              context,
              'User Management',
              'Manage existing user accounts',
              Icons.manage_accounts,
              () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => UserManagementScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, String title, 
      String subtitle, IconData icon, VoidCallback onTap) {
    return Card(
      color: Colors.grey[900],
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: Colors.blue,
                ),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey[600],
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}