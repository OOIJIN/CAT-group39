import 'package:flutter/material.dart';
import 'package:cat304/noti.dart';
import 'package:cat304/screens/home_navigation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../LocationService/location_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart';

class EmergencyPage extends StatefulWidget {
  final String username;
  final bool isEnabled;
  final Function(bool) onStateChanged;

  const EmergencyPage({
    super.key, 
    required this.username,
    required this.isEnabled,
    required this.onStateChanged,
  });

  @override
  State<EmergencyPage> createState() => _EmergencyPageState();
}

class _EmergencyPageState extends State<EmergencyPage> with WidgetsBindingObserver {
  HomeNavigationState? _homeNav;
  bool _isSwitchOn = false;
  String? _markerDocumentId;
  StreamSubscription? _emergencySubscription;
  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  StreamSubscription<SpeechResultListener>? _speechSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _homeNav = HomeNavigation.of(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadMarkerDocumentId();
    _initSpeech();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Restart speech recognition when app comes to foreground
      if (!_speechToText.isListening && mounted) {
        _initSpeech();
      }
    } else if (state == AppLifecycleState.paused) {
      // Stop speech recognition when app goes to background
      _speechToText.stop();
    }
  }

  Future<void> _loadMarkerDocumentId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _markerDocumentId = prefs.getString('markerDocumentId');
    });
  }

  Future<void> _showEmergencyStartNotification() async {
    try {
      final isBackground = !WidgetsBinding.instance.lifecycleState!.index.isEven;
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Create emergency alert document first
        final alertRef = await FirebaseFirestore.instance
            .collection('emergency_alerts')
            .add({
          'senderId': user.uid,
          'status': 'active',
          'timestamp': FieldValue.serverTimestamp(),
          'sender': widget.username,
        });
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('emergency_logs')
            .add({
          'action': 'Emergency Alert Started',
          'timestamp': FieldValue.serverTimestamp(),
          'alertId': alertRef.id,
        });

        // Get user location and add marker to Firestore
        LocationService locationService = LocationService();
        Position position = await locationService.getCurrentLocation();
        LatLng userLocation = LatLng(position.latitude, position.longitude);
        await _addMarkerToFirestore(userLocation);
       // Send notifications to other users
        await NotificationService.showEmergencyNotification(
          username: widget.username,
          isBackground: isBackground,
          isEndNotification: false,
        );
      }
    } catch (e) {
      print('Error in _showEmergencyStartNotification: $e');
    }
  }

  Future<void> _showEmergencyEndNotification() async {
    try {
      final isBackground = !WidgetsBinding.instance.lifecycleState!.index.isEven;
      final user = FirebaseAuth.instance.currentUser;
      
      if (user != null) {
        // Get all notifications with status 0
        await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('emergency_logs')
            .add({
          'action': 'Emergency Alert Ended',
          'timestamp': FieldValue.serverTimestamp(),
        });

        // Send notifications to other users
        await NotificationService.showEmergencyNotification(
          username: widget.username,
          isBackground: isBackground,
          isEndNotification: true,
        );

        // Remove marker from map if exists
        if (_markerDocumentId != null) {
          try {
            final alertDoc = await FirebaseFirestore.instance
                .collection('emergency_alerts')
                .doc(_markerDocumentId)
                .get();
                
            if (alertDoc.exists) {
              await alertDoc.reference.update({'status': 'resolved'});
            }
          } catch (e) {
            print('Error updating alert status: $e');
          }
        }

        await _removeMarkerFromFirestore();
      }
    } catch (e) {
      print('Error in _showEmergencyEndNotification: $e');
    }
  }

  void _toggleMarker() {
    if (!mounted) return;
    setState(() {
      _isSwitchOn = !_isSwitchOn;
    });
  }

  Future<void> _addMarkerToFirestore(LatLng location) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        // Get the address from the latitude and longitude
        List<Placemark> placemarks = await placemarkFromCoordinates(
          location.latitude,
          location.longitude,
        );
        String address = placemarks.isNotEmpty ? placemarks.first.street ?? 'Unknown' : 'Unknown';

        DocumentReference docRef = await FirebaseFirestore.instance
            .collection('markers')
            .add({
          'type': 'sos_signal',
          'latitude': location.latitude,
          'longitude': location.longitude,
          'address': address,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'active',
          'userId': user.uid,
        });
        _markerDocumentId = docRef.id;
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('markerDocumentId', _markerDocumentId!);
      }
    } catch (e) {
      print('Error adding marker to Firestore: $e');
    }
  }

  Future<void> _removeMarkerFromFirestore() async {
    try {
      if (_markerDocumentId != null) {
        await FirebaseFirestore.instance
            .collection('markers')
            .doc(_markerDocumentId)
            .delete();
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.remove('markerDocumentId');
        _markerDocumentId = null;
      }
    } catch (e) {
      print('Error removing marker from Firestore: $e');
    }
  }

  void _initSpeech() async {
    try {
      _speechEnabled = await _speechToText.initialize(
        onError: (errorNotification) => print('Speech recognition error: $errorNotification'),
        onStatus: (status) {
          print('Speech recognition status: $status');
          // Restart listening when it stops
          if (status == 'done' && mounted) {
            Future.delayed(Duration(milliseconds: 500), () {
              if (mounted && !_speechToText.isListening) {
                _startListening();
              }
            });
          }
        },
      );
      
      if (_speechEnabled) {
        _startListening(); // Start listening immediately after initialization
      }
      setState(() {});
    } catch (e) {
      print('Error initializing speech: $e');
      _speechEnabled = false;
      setState(() {});
    }
  }

  void _startListening() {
    if (!_speechEnabled || _speechToText.isListening) return;

    try {
      _speechToText.listen(
        onResult: (result) {
          String text = result.recognizedWords.toLowerCase();
          print('Recognized words: $text'); // Debug print
          
          if ((text.contains('help') || text.contains('sos') || text.contains('emergency') ||
              text.contains('danger') ||
              text.contains('how long') || // Malay word for help
              text.contains('bahaya') || // Malay word for danger || // Chinese characters for help
              text.contains('saya')) && !widget.isEnabled) {
            print('Emergency keyword detected!'); // Debug print
            widget.onStateChanged(true);
            _showEmergencyStartNotification();
          }
        },
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
        cancelOnError: false,
        listenMode: ListenMode.confirmation,
      );
    } catch (e) {
      print('Error starting speech recognition: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speechToText.stop();
    _speechSubscription?.cancel();
    _emergencySubscription?.cancel();
    if (_isSwitchOn) {
      NotificationService.handleLogout(context).then((_) {
        if (mounted) {
          widget.onStateChanged(false);
        }
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Emergency Quick Dial',
              style: TextStyle(
                color: Colors.white,
                fontSize: 35,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 100),
            if (!widget.isEnabled)
              Transform.scale(
                scale: 2.0,
                child: Switch(
                  value: widget.isEnabled,
                  onChanged: (bool value) {
                    widget.onStateChanged(value);
                    if (value) {
                      Future.microtask(() => _showEmergencyStartNotification());
                    }
                  },
                  activeColor: Colors.red,
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.grey[800],
                  thumbIcon: WidgetStateProperty.resolveWith<Icon?>(
                    (Set<WidgetState> states) {
                      return const Icon(
                        Icons.phone,
                        color: Colors.black,
                        size: 16,
                      );
                    },
                  ),
                ),
              )
            else
              ElevatedButton(
                onPressed: () {
                  if (!mounted) return;
                  _showEmergencyEndNotification();
                  widget.onStateChanged(false);
                  _removeMarkerFromFirestore();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  padding: const EdgeInsets.all(20),
                  shape: const CircleBorder(),
                ),
                child: const Icon(
                  Icons.phone,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}