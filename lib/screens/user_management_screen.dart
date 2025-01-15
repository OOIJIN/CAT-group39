import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
//import 'dart:typed_data';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  _UserManagementScreenState createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  late BuildContext _contextRef;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _contextRef = context;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showSuspendConfirmation(BuildContext context, String userId) {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(_contextRef);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Suspend User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to suspend this user? This will delete all their activity logs.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: Text('Suspend', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              try {
                if (!mounted) return;
                
                // Show loading indicator
                showDialog(
                  context: dialogContext,
                  barrierDismissible: false,
                  builder: (context) => Center(child: CircularProgressIndicator()),
                );
                
                // Get user data first
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get();
                
                final userData = userDoc.data();
                if (userData == null) {
                  Navigator.pop(dialogContext); // Remove loading
                  Navigator.pop(dialogContext); // Remove dialog
                  return;
                }
                
                // Update user status to suspended
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({
                  'status': 'suspended',
                  'loginStatus': 0,
                  'lastLogoutTime': FieldValue.serverTimestamp(),
                });

                // Queue suspension email instead of sending directly
                await _sendSuspensionEmail(userData['email']);

                // Delete emergency logs in batches
                final logs = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('emergency_logs')
                    .get();

                final batch = FirebaseFirestore.instance.batch();
                for (var doc in logs.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit();

                if (!mounted) return;
                Navigator.pop(dialogContext); // Remove loading
                Navigator.pop(dialogContext); // Remove dialog
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('User suspended successfully')),
                );
              } catch (e) {
                print('Suspension error: $e');
                if (!mounted) return;
                Navigator.pop(dialogContext); // Remove loading
                Navigator.pop(dialogContext); // Remove dialog
                scaffoldMessenger.showSnackBar(
                  SnackBar(
                    content: Text('Error suspending user. Please try again later.'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  void _showUnsuspendConfirmation(BuildContext context, String userId) {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(_contextRef);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Unsuspend User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to unsuspend this user?',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          TextButton(
            child: Text('Unsuspend', style: TextStyle(color: Colors.green)),
            onPressed: () async {
              try {
                if (!mounted) return;
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .update({'status': 'approved'});

                if (!mounted) return;
                Navigator.pop(dialogContext);
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('User unsuspended successfully')),
                );
              } catch (e) {
                if (!mounted) return;
                Navigator.pop(dialogContext);
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Error unsuspending user: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String userId, String userEmail, String password) async {
    try {
      // Get user data first
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      
      final userData = userDoc.data();
      if (userData == null) return;

      final myKadNumber = userData['myKadNumber'];
      
      // Add to deleted_accounts collection
      await FirebaseFirestore.instance
          .collection('deleted_accounts')
          .doc(myKadNumber)
          .set({
            'deletedAt': FieldValue.serverTimestamp(),
          });

      // Rest of your existing deletion logic...
      final fcmToken = userData['fcmToken'];

      // Delete from Firestore first
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .delete();

      // Delete all user's emergency logs
      final logs = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('emergency_logs')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      for (var doc in logs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Delete from Authentication
      try {
        final credentials = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: userEmail,
          password: password,
        );
        await credentials.user?.delete();
      } catch (e) {
        print('Error deleting from Authentication: $e');
      }

      // If user had FCM token, remove it
      if (fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('fcm_tokens')
            .doc(userId)
            .delete();
      }

    } catch (e) {
      print('Error deleting user: $e');
      rethrow;
    }
  }

  void _showDeleteConfirmation(BuildContext context, String userId) {
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final navigatorState = Navigator.of(context);
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text('Delete User', style: TextStyle(color: Colors.white)),
        content: Text(
          'Are you sure you want to delete this user? This action cannot be undone.',
          style: TextStyle(color: Colors.grey[400]),
        ),
        actions: [
          TextButton(
            child: Text('Cancel', style: TextStyle(color: Colors.grey)),
            onPressed: () => navigatorState.pop(),
          ),
          TextButton(
            child: Text('Delete', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              try {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .get();
                final userData = userDoc.data();
                
                if (userData != null) {
                  await _deleteUser(userId, userData['email'], userData['password']);
                }

                // Delete user's activity logs
                final logs = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('emergency_logs')
                    .get();

                final batch = FirebaseFirestore.instance.batch();
                for (var doc in logs.docs) {
                  batch.delete(doc.reference);
                }
                await batch.commit();

                if (!mounted) return;
                navigatorState.pop();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('User deleted successfully')),
                );
              } catch (e) {
                if (!mounted) return;
                navigatorState.pop();
                scaffoldMessenger.showSnackBar(
                  SnackBar(content: Text('Error deleting user: $e')),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search by MyKad or Email',
          hintStyle: TextStyle(color: Colors.grey[400]),
          prefixIcon: Icon(Icons.search, color: Colors.grey[400]),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: Colors.grey[400]),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Future<void> _sendSuspensionEmail(String userEmail) async {
    try {
      print('Attempting to send suspension email to: $userEmail');
      
      // Create custom email template
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: userEmail,
        actionCodeSettings: ActionCodeSettings(
          url: 'https://cat304.page.link/suspended',
          handleCodeInApp: true,
          iOSBundleId: 'com.example.cat304',
          androidPackageName: 'com.example.cat304',
          androidInstallApp: true,
          androidMinimumVersion: '12'
        )
      );
      
      print('Email sent successfully');
      
      // Add notification to user's collection
      final userQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: userEmail)
          .limit(1)  // Optimize query
          .get();
      
      if (userQuery.docs.isNotEmpty) {
        final userId = userQuery.docs.first.id;
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notifications')
            .add({
              'type': 'account_suspended',
              'title': 'Account Suspended',
              'message': 'Your account has been suspended. Please check your email for more information.',
              'timestamp': FieldValue.serverTimestamp(),
              'read': false,
              'status': 0
            });
      }
    } catch (e) {
      print('Detailed error sending suspension email:');
      print('Error type: ${e.runtimeType}');
      print('Error message: $e');
      
      // Check for specific error types
      if (e is FirebaseAuthException) {
        if (e.code == 'too-many-requests') {
          throw 'Too many attempts. Please try again later.';
        }
      }
      throw 'Failed to send suspension notification';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('User Management', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('status', whereIn: ['approved', 'suspended'])
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No approved users found',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  );
                }

                // Filter users based on search query
                final filteredDocs = snapshot.data!.docs.where((doc) {
                  final userData = doc.data() as Map<String, dynamic>;
                  final myKad = (userData['myKadNumber'] ?? '').toString().toLowerCase();
                  final email = (userData['email'] ?? '').toString().toLowerCase();
                  
                  return _searchQuery.isEmpty || 
                         myKad.contains(_searchQuery) || 
                         email.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return Center(
                    child: Text(
                      'No matching users found',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: filteredDocs.length,
                  itemBuilder: (context, index) {
                    final userData = filteredDocs[index].data() as Map<String, dynamic>;
                    final userId = filteredDocs[index].id;

                    return Card(
                      color: Colors.grey[900],
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ExpansionTile(
                        leading: CircleAvatar(
                          radius: 25,
                          backgroundColor: Colors.grey[800],
                          backgroundImage: userData['profileImage'] != null
                              ? MemoryImage(base64Decode(userData['profileImage']))
                              : null,
                          child: userData['profileImage'] == null
                              ? Icon(Icons.person, color: Colors.blue)
                              : null,
                        ),
                        title: Text(
                          userData['name'] ?? 'N/A',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          userData['myKadNumber'] ?? 'N/A',
                          style: TextStyle(color: Colors.grey[400]),
                        ),
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildDetailRow('Name', userData['name'] ?? 'N/A'),
                                _buildDetailRow('MyKad', userData['myKadNumber'] ?? 'N/A'),
                                _buildDetailRow('Email', userData['email'] ?? 'N/A'),
                                _buildDetailRow('Phone', userData['phone'] ?? 'N/A'),
                                Divider(color: Colors.grey[800], height: 32),
                                Text(
                                  'Activity Log',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                StreamBuilder<QuerySnapshot>(
                                  stream: FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(userId)
                                      .collection('emergency_logs')
                                      .orderBy('timestamp', descending: true)
                                      .snapshots(),
                                  builder: (context, logSnapshot) {
                                    if (!logSnapshot.hasData || logSnapshot.data!.docs.isEmpty) {
                                      return Padding(
                                        padding: const EdgeInsets.all(8.0),
                                        child: Text(
                                          'No emergency records',
                                          style: TextStyle(color: Colors.grey[400]),
                                        ),
                                      );
                                    }

                                    // Get all logs
                                    final logs = logSnapshot.data!.docs;
                                    
                                    return Column(
                                      children: logs.map((log) {
                                        final logData = log.data() as Map<String, dynamic>;
                                        final timestamp = logData['timestamp'];
                                        
                                        if (timestamp == null) {
                                          return SizedBox.shrink();
                                        }

                                        return ListTile(
                                          leading: Icon(
                                            Icons.warning_amber_rounded,
                                            color: Colors.red[400],
                                            size: 24,
                                          ),
                                          title: Text(
                                            logData['action'] ?? 'Emergency Alert',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          ),
                                          subtitle: Text(
                                            _formatDateTime((timestamp as Timestamp).toDate()),
                                            style: TextStyle(
                                              color: Colors.grey[400],
                                              fontSize: 14,
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    );
                                  },
                                ),
                                SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: userData['status'] == 'suspended' 
                                            ? Color(0xFF4CAF50) // Material Green
                                            : Color(0xFFE57373), // Light Red
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          elevation: 3,
                                        ),
                                        onPressed: () => userData['status'] == 'suspended' 
                                          ? _showUnsuspendConfirmation(context, userId)
                                          : _showSuspendConfirmation(context, userId),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              userData['status'] == 'suspended' 
                                                ? Icons.lock_open 
                                                : Icons.lock_person,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              userData['status'] == 'suspended' ? 'Unsuspend' : 'Suspend',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Color(0xFFD32F2F), // Material Dark Red
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          elevation: 3,
                                        ),
                                        onPressed: () => _showDeleteConfirmation(context, userId),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.delete_forever,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Delete',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
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
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey[400]),
        ),
        Text(
          value,
          style: TextStyle(color: Colors.white),
        ),
      ],
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[400]),
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
}