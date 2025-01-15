import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ActivityLogScreen extends StatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  State<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  late Stream<QuerySnapshot> _logsStream;

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  void _initializeStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _logsStream = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('emergency_logs')
          .orderBy('timestamp', descending: true)
          .snapshots();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Activity Log', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: user == null
          ? Center(child: Text('Not logged in', style: TextStyle(color: Colors.white)))
          : StreamBuilder<QuerySnapshot>(
              stream: _logsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      'No emergency records found',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final timestamp = data['timestamp'];
                    
                    if (timestamp == null) {
                      return SizedBox.shrink();
                    }

                    return Card(
                      color: Colors.grey[900],
                      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: ListTile(
                        leading: Icon(
                          Icons.emergency,
                          color: Colors.red,
                          size: 28,
                        ),
                        title: Text(
                          data['action'] ?? 'Emergency Alert',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        subtitle: Text(
                          _formatDateTime((timestamp as Timestamp).toDate()),
                          style: TextStyle(color: Colors.grey[400], fontSize: 16),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}