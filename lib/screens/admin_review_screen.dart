import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cat304/screens/admin_page.dart';
import 'package:cat304/push_notification.dart';
import 'package:intl/intl.dart';

class AdminReviewScreen extends StatefulWidget {
  const AdminReviewScreen({Key? key}) : super(key: key);

  @override
  State<AdminReviewScreen> createState() => _AdminReviewScreenState();
}

class _AdminReviewScreenState extends State<AdminReviewScreen> with SingleTickerProviderStateMixin {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late ScaffoldMessengerState _scaffoldMessenger;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  Future<void> _deleteUser(String userId, String userEmail, String password) async {
    try {
      // Sign in as the user to delete
      final credentials = await _auth.signInWithEmailAndPassword(
        email: userEmail,
        password: password,
      );

      // Delete from Authentication
      await credentials.user?.delete();

      // Delete from Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .delete();

      print('User deleted successfully');
    } catch (e) {
      print('Error deleting user: $e');
      throw e;
    }
  }

  Future<void> _updateStatus(String userId, String status) async {
    try {
      // Get user data
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      final userData = userDoc.data();
      
      if (userData == null) {
        throw 'User data not found';
      }

      if (status == 'rejected') {
        await _deleteUser(userId, userData['email'], userData['password']);
        return;
      }

      // Use a batch write for atomic operations
      final batch = FirebaseFirestore.instance.batch();
      final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

      // 1. Update user status
      batch.update(userRef, {
        'status': status,
        'updatedAt': FieldValue.serverTimestamp(),
        'approvedBy': FirebaseAuth.instance.currentUser?.email,
      });

      // 2. Add to activity logs
      final logRef = FirebaseFirestore.instance.collection('activity_logs').doc();
      batch.set(logRef, {
        'type': 'user_approval',
        'userId': userId,
        'userEmail': userData['email'],
        'approvedBy': FirebaseAuth.instance.currentUser?.email,
        'timestamp': FieldValue.serverTimestamp(),
      });

      // 3. Add notification for user
      final notificationRef = userRef.collection('notifications').doc();
      batch.set(notificationRef, {
        'type': 'account_approved',
        'title': 'Account Approved',
        'message': 'Your registration has been approved. You can now log in to the app.',
        'timestamp': FieldValue.serverTimestamp(),
        'read': false,
        'status': 0
      });

      // Commit all operations
      await batch.commit();

      // 4. Send FCM notification if token exists
      if (userData['fcmToken'] != null) {
        try {
          await PushNotification.sendNotification(
            token: userData['fcmToken'],
            title: 'Account Approved',
            body: 'Your registration has been approved. You can now log in.',
            data: {
              'type': 'account_approved',
              'userId': userId,
            },
          );
        } catch (e) {
          print('FCM notification failed but continuing: $e');
        }
      }

      // Show success message
      if (!mounted) return;
      _scaffoldMessenger.hideCurrentSnackBar();
      _scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('User approved successfully'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );

    } catch (e) {
      print('Error in _updateStatus: $e');
      if (!mounted) return;
      _scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error updating user status. Please try again later.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showConfirmDialog(String userId, String action) {
    // Hide any existing SnackBar first
    _scaffoldMessenger.hideCurrentSnackBar();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          action == 'approve' ? 'Confirm Approval' : 'Confirm Rejection',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          action == 'approve' 
              ? 'Are you sure you want to approve this user?'
              : 'This will permanently delete the user data. Continue?',
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Hide any existing SnackBar before showing loading
              _scaffoldMessenger.hideCurrentSnackBar();
              // Show loading snackbar
              _scaffoldMessenger.showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      SizedBox(width: 16),
                      Text(action == 'approve' ? 'Approving user...' : 'Rejecting user...'),
                    ],
                  ),
                  duration: Duration(seconds: 2), // Reduced from days to seconds
                  backgroundColor: Colors.grey[800],
                ),
              );
              
              await _updateStatus(userId, action == 'approve' ? 'approved' : 'rejected');
              
              if (!mounted) return;
              _scaffoldMessenger.hideCurrentSnackBar();
            },
            child: Text(
              action == 'approve' ? 'Approve' : 'Delete',
              style: TextStyle(
                color: action == 'approve' ? Colors.green : Colors.red
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuspiciousReportsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[900],
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  title: Text('Suspicious Reports', style: TextStyle(color: Colors.white)),
                  leading: IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                Flexible(
                  child: Container(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('markers')
                          .where('status', isEqualTo: 'suspicious')
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
                        }

                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return Center(
                            child: Text(
                              'No suspicious reports found',
                              style: TextStyle(color: Colors.grey[400]),
                            ),
                          );
                        }

                        return ListView.builder(
                          padding: EdgeInsets.all(16),
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) {
                            final doc = snapshot.data!.docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final timestamp = data['timestamp'] as Timestamp;

                            return Card(
                              color: Colors.grey[850],
                              margin: EdgeInsets.only(bottom: 12),
                              child: ExpansionTile(
                                leading: Icon(
                                  Icons.warning_amber_rounded,
                                  color: Colors.orange,
                                  size: 32,
                                ),
                                title: Text(
                                  'Type: ${data['type']?.toString().toUpperCase() ?? 'Unknown'}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Text(
                                  DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate()),
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        _buildDetailRow('Address', data['address'] ?? 'N/A'),
                                        _buildDetailRow('Latitude', data['latitude']?.toString() ?? 'N/A'),
                                        _buildDetailRow('Longitude', data['longitude']?.toString() ?? 'N/A'),
                                        SizedBox(height: 16),
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.green,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                              ),
                                              onPressed: () => _handleReport(doc.id, true),
                                              child: Text('Verify'),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(20),
                                                ),
                                              ),
                                              onPressed: () => _handleReport(doc.id, false),
                                              child: Text('Remove'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: TextStyle(
                color: Colors.grey[400],
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleReport(String docId, bool isVerified) async {
    try {
      if (isVerified) {
        // Get the marker document
        final markerDoc = await FirebaseFirestore.instance
            .collection('markers')
            .doc(docId)
            .get();
        
        if (!markerDoc.exists) {
          throw 'Marker document not found';
        }

        // Update the status to verified
        await FirebaseFirestore.instance
            .collection('markers')
            .doc(docId)
            .update({
          'status': 'verified',
          'verifiedAt': FieldValue.serverTimestamp(),
          'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
        });
        
        // Add to activity logs
        await FirebaseFirestore.instance
            .collection('activity_logs')
            .add({
          'type': 'report_verification',
          'markerId': docId,
          'verifiedBy': FirebaseAuth.instance.currentUser?.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'action': 'Report verified',
        });
        
        _scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Report verified successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Delete the marker if not verified
        await FirebaseFirestore.instance
            .collection('markers')
            .doc(docId)
            .delete();
            
        _scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Text('Report removed successfully'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('Error processing report: $e');
      _scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Error processing report'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPendingAccountsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: TextStyle(color: Colors.red),
            ),
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No pending accounts',
              style: TextStyle(color: Colors.grey[400]),
            ),
          );
        }

        return Container(
          color: Colors.black,
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;
              final base64Image = data['myKadImage'] as String?;

              return Card(
                color: Color(0xFF1E1E1E), // Darker card background
                margin: EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (base64Image != null)
                      GestureDetector(
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (context) => Dialog(
                              child: Image.memory(
                                base64Decode(base64Image),
                                fit: BoxFit.contain,
                              ),
                            ),
                          );
                        },
                        child: Container(
                          width: double.infinity,
                          height: 200,
                          decoration: BoxDecoration(
                            image: DecorationImage(
                              image: MemoryImage(base64Decode(base64Image)),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MyKad: ${data['myKadNumber'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Name: ${data['name'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Phone: ${data['phone'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Email: ${data['email'] ?? 'N/A'}',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: () => _showConfirmDialog(doc.id, 'approve'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text('Accept'),
                              ),
                              ElevatedButton(
                                onPressed: () => _showConfirmDialog(doc.id, 'reject'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 12,
                                  ),
                                ),
                                child: Text('Reject'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Admin Review',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w500,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Text(
                'Pending Accounts',
                style: TextStyle(color: Colors.white),
              ),
            ),
            Tab(
              child: Text(
                'Suspicious Reports',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPendingAccountsView(),
          _buildSuspiciousReportsView(),
        ],
      ),
    );
  }

  Widget _buildSuspiciousReportsView() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('markers')
          .where('status', isEqualTo: 'suspicious')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Text(
              'No suspicious reports found',
              style: TextStyle(color: Colors.grey[400]),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            final timestamp = data['timestamp'] as Timestamp;
            final reportedAt = data['reportedAt'] as Timestamp?;

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('users')
                  .doc(data['reportedBy'])
                  .get(),
              builder: (context, userSnapshot) {
                String reportedBy = 'Unknown User';
                if (userSnapshot.hasData && userSnapshot.data!.exists) {
                  final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                  reportedBy = userData['name'] ?? userData['email'] ?? 'Unknown User';
                }

                return Card(
                  color: Colors.grey[850],
                  margin: EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 32,
                    ),
                    title: Text(
                      'Type: ${data['type']?.toString().toUpperCase() ?? 'Unknown'}',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Created: ${DateFormat('dd/MM/yyyy HH:mm').format(timestamp.toDate())}',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        if (reportedAt != null)
                          Text(
                            'Reported: ${DateFormat('dd/MM/yyyy HH:mm').format(reportedAt.toDate())}',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        Text(
                          'Reported by: $reportedBy',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    children: [
                      Padding(
                        padding: EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildDetailRow('Address', data['address'] ?? 'N/A'),
                            _buildDetailRow('Latitude', data['latitude']?.toString() ?? 'N/A'),
                            _buildDetailRow('Longitude', data['longitude']?.toString() ?? 'N/A'),
                            SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed: () => _handleReport(doc.id, true),
                                  child: Text('Verify'),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  onPressed: () => _handleReport(doc.id, false),
                                  child: Text('Remove'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> sendIncidentReportNotification(String userId, String incidentDetails) async {
    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      final userData = userDoc.data();

      if (userData != null && userData['fcmToken'] != null) {
        await PushNotification.sendNotification(
          token: userData['fcmToken'],
          title: 'Incident Reported',
          body: 'An incident has been reported: $incidentDetails',
          data: {
            'type': 'incident_report',
            'userId': userId,
          },
        );
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }
}