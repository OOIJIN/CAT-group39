import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cat304/LocationService/location_service.dart';
import 'package:cat304/pages/map_page.dart';
import 'package:cat304/pages/emergency_page.dart';
import 'package:cat304/pages/user_profile.dart';
import 'package:cat304/noti.dart';
import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cat304/pages/user_profile.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat304/screens/signin_screen.dart';

class HomeNavigation extends StatefulWidget {
  const HomeNavigation({super.key});

  static HomeNavigationState? of(BuildContext context) {
    return context.findAncestorStateOfType<HomeNavigationState>();
  }

  @override
  State<HomeNavigation> createState() => HomeNavigationState();
}

class HomeNavigationState extends State<HomeNavigation> with WidgetsBindingObserver {
  int _selectedIndex = 1;
  bool _hasPermission = false;
  bool _isCheckingPermission = true;
  String username = "";
  bool isEmergencyEnabled = false;
  StreamSubscription<QuerySnapshot>? _notificationSubscription;
  LatLng? userLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _getCurrentUser();
    _setupNotificationListener();
    _restoreEmergencyState();
    _getUserLocation();
    _checkUserStatus();
  }

  Future<void> _getUserLocation() async {
    LocationService locationService = LocationService();
    try {
      Position position = await locationService.getCurrentLocation();
      final user = FirebaseAuth.instance.currentUser;
      
      setState(() {
        userLocation = LatLng(position.latitude, position.longitude);
      });

      // Update user's location in Firestore
      if (user != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .update({
          'lastLatitude': position.latitude,
          'lastLongitude': position.longitude,
          'lastLocationUpdate': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print('Error getting location: $e');
    }
  }

  Future<void> _restoreEmergencyState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedState = prefs.getBool('emergency_enabled') ?? false;
    setState(() {
      isEmergencyEnabled = savedState;
    });
  }

  void _setupNotificationListener() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _notificationSubscription?.cancel();
      _notificationSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection('notifications')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {  // Only process new notifications
            final data = change.doc.data() as Map<String, dynamic>;
            final timestamp = data['timestamp'] as Timestamp;
            
            // Only process notifications that are less than 30 seconds old
            if (timestamp.toDate().isAfter(
              DateTime.now().subtract(Duration(seconds: 30))
            )) {
              if (data['type'] == 'emergency_start' && data['status'] == 0) {
                // Show red alert notification for status 0
                FirebaseFirestore.instance
                    .collection('emergency_alerts')
                    .doc(data['alertId'])
                    .get()
                    .then((alertDoc) {
                      if (alertDoc.exists && alertDoc.data()?['status'] == 'active') {
                        change.doc.reference.update({'read': true});
                        Future.microtask(() {
                          if (mounted) {
                            NotificationService.showInAppNotification(
                              context,
                              data['sender'],
                              () => navigateToMap(),
                              isEmergencyEnd: false,
                            );
                          }
                        });
                      }
                    });
              } else if (data['type'] == 'emergency_end' && !data['read']) {
                // For emergency end notifications, verify the alert
                FirebaseFirestore.instance
                    .collection('emergency_alerts')
                    .doc(data['alertId'])
                    .get()
                    .then((alertDoc) async {
                      if (alertDoc.exists && alertDoc.data()?['status'] == 'resolved') {
                        // Mark notification as read
                        await change.doc.reference.update({
                          'read': true,
                          'status': 2,
                        });

                        // Dismiss any existing red alert notifications
                        Navigator.of(context).popUntil((route) => route.isFirst);
                        
                        // Show green alert notification
                        Future.microtask(() {
                          if (mounted) {
                            NotificationService.showInAppNotification(
                              context,
                              data['sender'],
                              () {},
                              isEmergencyEnd: true,
                            );
                          }
                        });
                      }
                    });
              }
            }
          }
        }
      });
    }
  }

  void _checkUserStatus() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (!snapshot.exists) {
          // User has been deleted
          _signOut();
        } else {
          final userData = snapshot.data();
          if (userData?['status'] == 'suspended') {
            // Force logout for suspended users
            _signOut();
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _notificationSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only check permission if we don't already have it
      if (!_hasPermission) {
        _checkPermission();
      }
    }
  }

  Future<void> _checkPermission() async {
    if (!mounted) return;
    
    setState(() => _isCheckingPermission = true);
    
    final hasPermission = await NotificationService.checkPermission();
    
    if (mounted) {
      setState(() {
        _hasPermission = hasPermission;
        _isCheckingPermission = false;
      });
    }
  }

  Future<void> _getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userData = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      
      if (userData.exists && mounted) {
        setState(() {
          username = userData.data()?['name'] ?? "";
        });
      }
    }
  }

  List<Widget> _getPages() {
    final user = FirebaseAuth.instance.currentUser;
    return [
      MapPage(
        userLocation: userLocation ?? const LatLng(5.3546, 100.3015),
        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      ),
      EmergencyPage(
        username: username,
        isEnabled: isEmergencyEnabled,
        onStateChanged: toggleEmergency,
      ),
      UserProfileScreen(userId: user?.uid ?? ''),
    ];
  }

  void navigateToMap() {
    if (mounted) {
      setState(() {
        _selectedIndex = 0;
      });
    }
  }

  void toggleEmergency(bool value) async {
    setState(() {
      isEmergencyEnabled = value;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emergency_enabled', value);
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SignInScreen(hasNotificationPermission: true)),
        (route) => false
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCheckingPermission) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_hasPermission) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: PopScope(
          canPop: false, // Prevent back button
          child: Center(
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Notification Permission Required',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'This app requires notifications to be enabled to function properly. Please enable notifications in settings.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () {
                          SystemNavigator.pop();
                        },
                        child: const Text('Exit App'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          await AppSettings.openAppSettings(
                            type: AppSettingsType.notification,
                          );
                        },
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final pages = _getPages();
    return Scaffold(
      backgroundColor: Colors.black,
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.emergency),
            label: 'Emergency',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
        selectedItemColor: Colors.red,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.black,
      ),
    );
  }
}