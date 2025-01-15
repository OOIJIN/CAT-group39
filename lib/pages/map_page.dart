import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cat304/push_notification.dart';

enum TimeFilter {
  last24Hours,
  last7Days,
  lastMonth,
  last3Months,
  all
}

class MapPage extends StatefulWidget {
  final LatLng userLocation;
  final String userId;
  final bool showTitle;

  const MapPage({
    super.key,
    required this.userLocation,
    required this.userId,
    this.showTitle = true,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  Set<Marker> _markers = {};
  late GoogleMapController _mapController;
  final Set<Polyline> _polylines = {};
  Marker? _selectedMarker;
  bool _filterMarkers = false;
  BitmapDescriptor? _sosIcon;
  String _selectedIncidentType = 'robbery';
  LatLng? _selectedLocation;
  bool _isSelectingLocation = false;
  bool _showHeatmap = false;
  final List<Circle> _heatmapCircles = [];
  Map<String, BitmapDescriptor?> _incidentIcons = {
    'robbery': null,
    'assault': null,
    'murder': null,
    'vandalism': null,
    'stalker': null,
  };
  TimeFilter _selectedTimeFilter = TimeFilter.all;
  bool _hideSuspiciousReports = false;
  StreamSubscription? _markerSubscription;
  double _userNotificationDistance = 1000.0; // Default value
  StreamSubscription? _distanceSubscription;
  StreamSubscription? _sosMarkerSubscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchMarkersFromFirestore();
  }

  @override
void initState() {
  super.initState();
  _fetchUserNotificationDistance();
  _setupDistanceListener();
  _loadCustomMarker().then((_) {
    if (!mounted) return;
    _fetchMarkersFromFirestore();
    _listenToMarkerUpdates();
    _listenToNewSosMarkers();
    _loadHeatmapData();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _moveCameraToSosMarker();
    });
  });
}

  @override
  void dispose() {
    _markerSubscription?.cancel();
    _distanceSubscription?.cancel();
    _sosMarkerSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializeMarkers() async {
    await _loadCustomMarker();
    await _fetchMarkersFromFirestore();
  }

  Future<void> _loadCustomMarker() async {
    final ByteData data = await rootBundle.load('images/sos_icon.png');
    final ui.Codec codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(),
      targetWidth: 150,
      targetHeight: 150,
    );
    final ui.FrameInfo fi = await codec.getNextFrame();
    final ByteData? byteData = await fi.image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List resizedImageData = byteData!.buffer.asUint8List();

    _sosIcon = BitmapDescriptor.fromBytes(resizedImageData);
  }

  Future<void> _fetchMarkersFromFirestore() async {
    try {
      await _loadIncidentIcons();
      
      final querySnapshot = await FirebaseFirestore.instance
          .collection('markers')
          .where('status', whereIn: ['verified', 'active', 'pending'])
          .get();
      
      print('Fetched ${querySnapshot.docs.length} markers from Firestore');
      
      final allMarkers = querySnapshot.docs.map((doc) {
        final data = doc.data();
        final docId = doc.id;
        final incidentType = data['type'] as String;
        final position = LatLng(data['latitude'], data['longitude']);
        final status = data['status'] as String;

        // Skip suspicious reports if hide option is enabled
        if (_hideSuspiciousReports && status == 'suspicious') {
          return null;
        }

        BitmapDescriptor markerIcon;
        if (incidentType == 'sos_signal') {
          markerIcon = _sosIcon ?? BitmapDescriptor.defaultMarker;
          print('Adding SOS marker at ${position.latitude}, ${position.longitude}');
        } else {
          markerIcon = _incidentIcons[incidentType] ?? BitmapDescriptor.defaultMarker;
          print('Adding ${incidentType} marker at ${position.latitude}, ${position.longitude}');
        }

        return Marker(
          markerId: MarkerId(docId),
          position: position,
          icon: markerIcon,
          onTap: () => _showMarkerInfo(docId, data),
        );
      })
      .where((marker) => marker != null)
      .cast<Marker>()
      .toSet();

      setState(() {
        _markers = _filterMarkers
            ? Set<Marker>.from(allMarkers.where((marker) =>
                _calculateDistance(widget.userLocation, marker.position) <= _userNotificationDistance))
            : allMarkers;
      });
    } catch (e) {
      print('Error fetching markers from Firestore: $e');
    }
  }

  Future<BitmapDescriptor?> _loadSpecificIcon(String type) async {
    try {
      final ByteData data = await rootBundle.load('images/${type}_icon.png');
      final ui.Codec codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(),
        targetWidth: 100,
        targetHeight: 100,
      );
      final ui.FrameInfo fi = await codec.getNextFrame();
      final ByteData? byteData = await fi.image.toByteData(
        format: ui.ImageByteFormat.png
      );
      
      if (byteData != null) {
        final Uint8List resizedImageData = byteData.buffer.asUint8List();
        return BitmapDescriptor.fromBytes(resizedImageData);
      }
    } catch (e) {
      print('Warning: Could not load icon for $type: $e');
    }
    return null;
  }

  void _showMarkerInfo(String docId, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final incidentType = data['type'] as String;
        final address = data['address'] as String? ?? 'Unknown location';
        final timestamp = data['timestamp'] as Timestamp?;
        final latitude = data['latitude'] as double;
        final longitude = data['longitude'] as double;

        return AlertDialog(
          backgroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Center(
            child: Column(
              children: [
                if (incidentType != 'sos_signal')
                  Image.asset(
                    'images/${incidentType}_icon.png',
                    width: 50,
                    height: 50,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(Icons.warning, color: Colors.white, size: 50);
                    },
                  ),
                SizedBox(height: 10),
                Text(
                  incidentType.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Address:',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 4),
                    Text(
                      address,
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    if (timestamp != null) ...[
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.access_time, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Reported on:',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        timestamp.toDate().toString(),
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          actions: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (incidentType != 'sos_signal') 
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              backgroundColor: Colors.black,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                              title: Text(
                                'Confirm Report',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              content: Text(
                                'Are you sure you want to report this incident as suspicious?',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              actionsAlignment: MainAxisAlignment.center,
                              actionsPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                              actions: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          _reportSuspiciousIncident(docId);
                                          Navigator.of(context).pop();
                                          Navigator.of(context).pop();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: Text(
                                          'Yes',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          Navigator.of(context).pop();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.grey[800],
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        child: Text(
                                          'No',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            );
                          },
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[800],
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Report Suspicious Incident',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 12),
                if (incidentType == 'sos_signal')
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _showOpenMapsConfirmation(LatLng(latitude, longitude));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Navigate to Location',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[800],
                      padding: EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'Close',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Future<void> _reportSuspiciousIncident(String docId) async {
    try {
      await FirebaseFirestore.instance
          .collection('markers')
          .doc(docId)
          .update({
        'status': 'suspicious',
        'reportedBy': FirebaseAuth.instance.currentUser?.uid,
        'reportedAt': FieldValue.serverTimestamp(),
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Incident reported as suspicious'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      print('Error reporting suspicious incident: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reporting incident'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _locateSosMarker() async {
    const int maxRetries = 3;
    const Duration retryDelay = Duration(seconds: 2);

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('markers')
            .where('userId', isEqualTo: widget.userId)
            .where('type', isEqualTo: 'sos_signal')
            .get();

        if (querySnapshot.docs.isNotEmpty) {
          final markerData = querySnapshot.docs.first.data();
          final LatLng markerPosition = LatLng(markerData['latitude'], markerData['longitude']);

          _mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: markerPosition,
                zoom: 15,
              ),
            ),
          );
          return; // Exit the function if successful
        }
      } catch (e) {
        print('Error locating SOS marker (attempt ${attempt + 1}): $e');
      }

      // Wait before retrying
      if (attempt < maxRetries - 1) {
        await Future.delayed(retryDelay);
      }
    }

    print('Failed to locate SOS marker after $maxRetries attempts.');
  }

  LatLng _calculateNewPosition(LatLng start, double distanceInMeters, double bearing) {
    const double earthRadius = 6371000; // meters
    final double bearingRad = bearing * (pi / 180);
    final double lat1 = start.latitude * (pi / 180);
    final double lon1 = start.longitude * (pi / 180);

    final double lat2 = asin(sin(lat1) * cos(distanceInMeters / earthRadius) +
        cos(lat1) * sin(distanceInMeters / earthRadius) * cos(bearingRad));

    final double lon2 = lon1 + atan2(
        sin(bearingRad) * sin(distanceInMeters / earthRadius) * cos(lat1),
        cos(distanceInMeters / earthRadius) - sin(lat1) * sin(lat2));

    return LatLng(lat2 * (180 / pi), lon2 * (180 / pi));
  }

  void _goToUserLocation() {
    _mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: widget.userLocation,
          zoom: 15,
        ),
      ),
    );
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371000; // meters
    final double dLat = (end.latitude - start.latitude) * (3.141592653589793 / 180);
    final double dLng = (end.longitude - start.longitude) * (3.141592653589793 / 180);
    final double a =
        (sin(dLat / 2) * sin(dLat / 2)) +
        cos(start.latitude * (3.141592653589793 / 180)) *
            cos(end.latitude * (3.141592653589793 / 180)) *
            (sin(dLng / 2) * sin(dLng / 2));
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  Future<Map<String, dynamic>> getDirections(
    String origin, String destination, String apiKey) async {
  final url =
      'https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$destination&key=$apiKey';
  final response = await http.get(Uri.parse(url));

  if (response.statusCode == 200) {
    return json.decode(response.body);
  } else {
    throw Exception('Failed to load directions');
  }
}

  void _onMarkerTapped(MarkerId markerId) {
    final selectedMarker = _markers.firstWhere((marker) => marker.markerId == markerId);
    setState(() {
      _selectedMarker = selectedMarker;
    });

    // Fetch the marker data from Firestore to get the address
    FirebaseFirestore.instance
        .collection('markers')
        .doc(markerId.value)
        .get()
        .then((doc) {
      if (doc.exists) {
        final data = doc.data();
        final markerType = data?['type'] ?? 'Unknown';
        final address = data?['address'] ?? 'Unknown';
        final latitude = data?['latitude'] as double? ?? 0.0;
        final longitude = data?['longitude'] as double? ?? 0.0;

        showDialog(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: Colors.black,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sosIcon != null)
                    Center(
                      child: Image.asset(
                        'images/sos_icon.png', // Ensure this path is correct
                        width: 50,
                        height: 50,
                      ),
                    ),
                  SizedBox(height: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start, // Align text to the left
                    children: [
                      if (markerType == 'sos_signal')
                        Center(
                          child: Text(
                            'SOS Signal',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white),
                          ),
                        )
                      else
                        Text(
                          'Type: $markerType',
                          textAlign: TextAlign.left,
                          style: TextStyle(color: Colors.white),
                        ),
                      Text(
                        'Address: $address',
                        textAlign: TextAlign.left,
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    setState(() {
                      _polylines.clear();
                    });
                  },
                  child: Text('Cancel', style: TextStyle(color: Colors.white)),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    if (latitude != null && longitude != null) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (context) => MapPage(
                            userLocation: LatLng(latitude, longitude),
                            userId: widget.userId,
                            showTitle: widget.showTitle,
                          ),
                        ),
                      );
                    }
                  },
                  child: Text('Go to Location', style: TextStyle(color: Colors.white)),
                ),
              ],
            );
          },
        );
      }
    }).catchError((e) {
      print('Error fetching marker details: $e');
    });
  }

  void _showOpenMapsConfirmation(LatLng position) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Open Google Maps'),
          content: Text('Do you want to open this location in Google Maps?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _openGoogleMaps(position);
              },
              child: Text('Open'),
            ),
          ],
        );
      },
    );
  }

  void _openGoogleMaps(LatLng position) async {
    final Uri googleMapsUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=${position.latitude},${position.longitude}');
    final Uri chromeUrl = Uri.parse('googlechrome://navigate?url=${googleMapsUrl.toString()}');

    if (await canLaunchUrl(chromeUrl)) {
      await launchUrl(chromeUrl);
    } else if (await canLaunchUrl(googleMapsUrl)) {
      await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
    } else {
      print('Could not launch $googleMapsUrl');
    }
  }

  void _showHelpOnTheWayDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.green,
          content: Text(
            'Help is on the way!',
            style: TextStyle(color: Colors.white, fontSize: 18),
            textAlign: TextAlign.center,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchDirections(LatLng destination) async {
    try {
      final origin = '${widget.userLocation.latitude},${widget.userLocation.longitude}';
      final destinationStr = '${destination.latitude},${destination.longitude}';
      final apiKey = 'AIzaSyAbtr_xCWBQ9JsJEmH-n62g_Q8cpAkOnGY'; // Replace with your actual API key

      final directions = await getDirections(origin, destinationStr, apiKey);

      // Process the directions data here
      final polylinePoints = directions['routes'][0]['overview_polyline']['points'];
      final decodedPolyline = _decodePolyline(polylinePoints);

      setState(() {
        _polylines.add(Polyline(
          polylineId: PolylineId('route'),
          points: decodedPolyline,
          color: Colors.red,
          width: 5,
        ));
      });
    } catch (e) {
      print('Error fetching directions: $e');
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> polyline = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      polyline.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return polyline;
  }

  void _listenToMarkerUpdates() {
    _markerSubscription = FirebaseFirestore.instance
        .collection('markers')
        .where('status', whereIn: ['verified', 'active', 'pending'])
        .snapshots()
        .listen((querySnapshot) {
      if (!mounted) return;
      
      print('Received marker update with ${querySnapshot.docs.length} markers');
      
      final allMarkers = querySnapshot.docs
          .map((doc) {
            final data = doc.data();
            final docId = doc.id;
            final incidentType = data['type'] as String;
            final position = LatLng(data['latitude'], data['longitude']);
            final status = data['status'] as String;

            // Skip suspicious reports if hide option is enabled
            if (_hideSuspiciousReports && status == 'suspicious') {
              return null;
            }

            BitmapDescriptor markerIcon;
            if (incidentType == 'sos_signal') {
              markerIcon = _sosIcon ?? BitmapDescriptor.defaultMarker;
              print('Adding SOS marker at ${position.latitude}, ${position.longitude}');
            } else {
              markerIcon = _incidentIcons[incidentType] ?? BitmapDescriptor.defaultMarker;
              print('Adding ${incidentType} marker at ${position.latitude}, ${position.longitude}');
            }

            return Marker(
              markerId: MarkerId(docId),
              position: position,
              icon: markerIcon,
              onTap: () => _showMarkerInfo(docId, data),
            );
          })
          .where((marker) => marker != null)
          .cast<Marker>()
          .toSet();

      setState(() {
        if (_filterMarkers) {
          _markers = Set<Marker>.from(
            allMarkers.where((marker) =>
                _calculateDistance(widget.userLocation, marker.position) <= _userNotificationDistance)
          );
        } else {
          _markers = allMarkers;
        }
      });
    });
  }

  Future<void> _loadIncidentIcons() async {
    for (String type in _incidentIcons.keys) {
      try {
        if (_incidentIcons[type] != null) continue; // Skip if already loaded

        final ByteData data = await rootBundle.load('images/${type}_icon.png');
        final ui.Codec codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: 100,
          targetHeight: 100,
        );
        final ui.FrameInfo fi = await codec.getNextFrame();
        final ByteData? byteData = await fi.image.toByteData(
          format: ui.ImageByteFormat.png
        );
        
        if (byteData != null) {
          final Uint8List resizedImageData = byteData.buffer.asUint8List();
          final icon = BitmapDescriptor.fromBytes(resizedImageData);
          setState(() {
            _incidentIcons[type] = icon;
          });
          print('Successfully loaded icon for $type');
        }
      } catch (e) {
        print('Warning: Could not load icon for $type: $e');
      }
    }
  }

  Future<void> _loadHeatmapData() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance.collection('markers').get();
      
      final List<Circle> circles = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final lat = data['latitude'] as double;
        final lng = data['longitude'] as double;
        
        circles.add(
          Circle(
            circleId: CircleId('heat_${doc.id}'),
            center: LatLng(lat, lng),
            radius: 1000.0,
            fillColor: Colors.yellow.withOpacity(0.3),
            strokeWidth: 0,
          ),
        );
      }
      
      setState(() {
        _heatmapCircles.clear();
        _heatmapCircles.addAll(circles);
      });
    } catch (e) {
      print('Error loading heatmap data: $e');
    }
  }

  Color _getHeatmapColor(LatLng position) {
    int nearbyCount = _heatmapCircles.where((circle) {
      final distance = _calculateDistance(position, circle.center);
      return distance <= 1000;
    }).length;

    if (nearbyCount <= 2) {
      return Colors.yellow.withOpacity(0.3);
    } else if (nearbyCount <= 5) {
      return Colors.orange[300]!.withOpacity(0.4);
    } else if (nearbyCount <= 8) {
      return Colors.orange[700]!.withOpacity(0.5);
    } else {
      return Colors.red.withOpacity(0.6);
    }
  }

  void _showReportDialog() {
    setState(() {
      _isSelectingLocation = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Tap on the map to select incident location'),
        duration: Duration(seconds: 3),
        backgroundColor: Colors.black87,
        action: SnackBarAction(
          label: 'Cancel',
          textColor: Colors.white,
          onPressed: () {
            setState(() {
              _isSelectingLocation = false;
              _selectedLocation = null;
            });
          },
        ),
      ),
    );
  }

  void _onMapTapped(LatLng location) {
    if (_isSelectingLocation) {
      setState(() {
        _selectedLocation = location;
        _isSelectingLocation = false;
      });
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: Colors.black,
                title: Text('Report Incident', style: TextStyle(color: Colors.white)),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Selected Location:', style: TextStyle(color: Colors.white)),
                      Text(
                        'Lat: ${location.latitude.toStringAsFixed(6)}\nLng: ${location.longitude.toStringAsFixed(6)}',
                        style: TextStyle(color: Colors.grey),
                      ),
                      SizedBox(height: 16),
                      Text('Incident Type:', style: TextStyle(color: Colors.white)),
                      SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        dropdownColor: Colors.grey[900],
                        value: _selectedIncidentType,
                        style: TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Colors.grey[800],
                        ),
                        items: [
                          'robbery',
                          'assault',
                          'murder',
                          'vandalism',
                          'stalker',
                        ].map((String value) {
                          return DropdownMenuItem<String>(
                            value: value,
                            child: Text(
                              value.toUpperCase(),
                              style: TextStyle(color: Colors.white)
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setDialogState(() {
                            _selectedIncidentType = newValue!;
                          });
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      setState(() {
                        _selectedLocation = null;
                        _isSelectingLocation = false;
                      });
                    },
                    child: Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                  TextButton(
                    onPressed: () {
                      _submitReport();
                      Navigator.of(context).pop();
                    },
                    child: Text('Submit', style: TextStyle(color: Colors.red)),
                  ),
                ],
              );
            },
          );
        },
      );
    }
  }

  Future<void> _submitReport() async {
    if (_selectedLocation == null) return;
    
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final placemarks = await placemarkFromCoordinates(
          _selectedLocation!.latitude,
          _selectedLocation!.longitude
        );
        
        String address = "Unknown location";
        if (placemarks.isNotEmpty) {
          final place = placemarks[0];
          address = "${place.street}, ${place.locality}, ${place.country}";
        }

        // Add the marker to Firestore
        final markerRef = await FirebaseFirestore.instance.collection('markers').add({
          'type': _selectedIncidentType,
          'latitude': _selectedLocation!.latitude,
          'longitude': _selectedLocation!.longitude,
          'address': address,
          'timestamp': FieldValue.serverTimestamp(),
          'userId': user.uid,
          'status': 'active',
        });

        // Get all users
        final usersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('status', isEqualTo: 'approved')
            .get();

        for (var userDoc in usersSnapshot.docs) {
          if (userDoc.id == user.uid) continue; // Skip the sender

          final userData = userDoc.data();
          final userLat = userData['lastLatitude'];
          final userLng = userData['lastLongitude'];
          final fcmToken = userData['fcmToken'];
          final notificationDistance = userData['notificationDistance'] ?? 1000.0;

          if (userLat == null || userLng == null || fcmToken == null) continue;

          // Calculate distance between user and incident
          final distance = await Geolocator.distanceBetween(
            userLat,
            userLng,
            _selectedLocation!.latitude,
            _selectedLocation!.longitude,
          );

          // If user is within their set notification distance, send notification
          if (distance <= notificationDistance) {
            await PushNotification.sendNotification(
              token: fcmToken,
              title: 'Nearby Incident Alert',
              body: 'A ${_selectedIncidentType.toUpperCase()} incident was reported near your location (${distance.toStringAsFixed(0)}m away)',
              data: {
                'type': 'incident_report',
                'markerId': markerRef.id,
                'incidentType': _selectedIncidentType,
                'latitude': _selectedLocation!.latitude.toString(),
                'longitude': _selectedLocation!.longitude.toString(),
                'distance': distance.toString(),
              },
            );
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Incident reported successfully'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        await _fetchMarkersFromFirestore();
        await _loadHeatmapData();

        setState(() {
          _selectedLocation = null;
        });
      }
    } catch (e) {
      print('Error submitting report: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reporting incident'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _debugPrintIconStatus() {
    print('SOS Icon: ${_sosIcon != null ? 'Loaded' : 'Not loaded'}');
    _incidentIcons.forEach((type, icon) {
      print('$type icon: ${icon != null ? 'Loaded' : 'Not loaded'}');
    });
  }

  String _getFilterLabel(TimeFilter filter) {
    switch (filter) {
      case TimeFilter.last24Hours:
        return 'Last 24 Hours';
      case TimeFilter.last7Days:
        return 'Last 7 Days';
      case TimeFilter.lastMonth:
        return 'Last Month';
      case TimeFilter.last3Months:
        return 'Last 3 Months';
      case TimeFilter.all:
        return 'All Time';
    }
  }

  Future<void> _fetchUserNotificationDistance() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final userData = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        
        setState(() {
          _userNotificationDistance = userData.data()?['notificationDistance']?.toDouble() ?? 1000.0;
        });
      }
    } catch (e) {
      print('Error fetching notification distance: $e');
    }
  }

  void _setupDistanceListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _distanceSubscription?.cancel();
      _distanceSubscription = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) {
        if (!mounted) return;
        if (snapshot.exists) {
          final newDistance = snapshot.data()?['notificationDistance']?.toDouble() ?? 1000.0;
          if (newDistance != _userNotificationDistance) {
            setState(() {
              _userNotificationDistance = newDistance;
            });
          }
        }
      });
    }
  }

  Future<LatLng?> _fetchNewestSosMarker() async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('markers')
          .where('type', isEqualTo: 'sos_signal')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final data = querySnapshot.docs.first.data();
        final latitude = data['latitude'] as double;
        final longitude = data['longitude'] as double;
        return LatLng(latitude, longitude);
      }
    } catch (e) {
      print('Error fetching newest SOS marker: $e');
    }
    return null;
  }

  void _moveCameraToSosMarker() async {
    final sosLocation = await _fetchNewestSosMarker();
    if (sosLocation != null) {
      _mapController.animateCamera(
        CameraUpdate.newLatLng(sosLocation),
      );
    }
  }

  void _moveCameraToPosition(LatLng position) {
    if (_mapController != null) {
      print('Moving camera to position: ${position.latitude}, ${position.longitude}');
      _mapController.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: position,
            zoom: 15,
          ),
        ),
      );
    } else {
      print('MapController is not initialized');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
    print('MapController initialized');
    // Optionally, move the camera to the user's location or any initial position
    _moveCameraToPosition(widget.userLocation);
  }

  void _listenToNewSosMarkers() {
    _sosMarkerSubscription = FirebaseFirestore.instance
        .collection('markers')
        .where('type', isEqualTo: 'sos_signal')
        .snapshots()
        .listen((querySnapshot) {
      if (!mounted) return;

      for (var change in querySnapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          final latitude = data?['latitude'] as double;
          final longitude = data?['longitude'] as double;
          final newSosLocation = LatLng(latitude, longitude);

          // Move camera to the new SOS marker
          _moveCameraToPosition(newSosLocation);
          break; // Move to the first new SOS marker found
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showTitle
          ? AppBar(
              backgroundColor: Colors.black,
              title: Text(
                'Map Page',
                style: TextStyle(color: Colors.white),
              ),
              actions: [
                PopupMenuButton<void>(
                  icon: Icon(Icons.filter_list, color: Colors.white),
                  color: Colors.black,
                  itemBuilder: (BuildContext context) => [
                    PopupMenuItem(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Time Filter',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          ...TimeFilter.values.map((filter) => 
                            RadioListTile<TimeFilter>(
                              title: Text(
                                _getFilterLabel(filter),
                                style: TextStyle(color: Colors.white),
                              ),
                              value: filter,
                              groupValue: _selectedTimeFilter,
                              onChanged: (TimeFilter? value) {
                                if (value != null) {
                                  setState(() {
                                    _selectedTimeFilter = value;
                                  });
                                  _fetchMarkersFromFirestore();
                                  Navigator.pop(context);
                                }
                              },
                              activeColor: Colors.white,
                            ),
                          ).toList(),
                          Divider(color: Colors.white30),
                          CheckboxListTile(
                            title: Text(
                              'Hide Suspicious Reports',
                              style: TextStyle(color: Colors.white),
                            ),
                            value: _hideSuspiciousReports,
                            onChanged: (bool? value) {
                              if (value != null) {
                                setState(() {
                                  _hideSuspiciousReports = value;
                                });
                                _fetchMarkersFromFirestore();
                                Navigator.pop(context);
                              }
                            },
                            activeColor: Colors.orange,
                            checkColor: Colors.black,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: Icon(
                    _showHeatmap ? Icons.map : Icons.heat_pump_outlined,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _showHeatmap = !_showHeatmap;
                    });
                  },
                  tooltip: 'Toggle Heatmap',
                ),
                Row(
                  children: [
                    Text(
                      'Distance Filter',
                      style: TextStyle(color: Colors.white),
                    ),
                    Switch(
                      value: _filterMarkers,
                      onChanged: (value) {
                        setState(() {
                          _filterMarkers = value;
                          _fetchMarkersFromFirestore();
                        });
                      },
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: GoogleMap(
        onMapCreated: _onMapCreated,
        initialCameraPosition: CameraPosition(
          target: widget.userLocation,
          zoom: 15,
        ),
        markers: _showHeatmap ? {} : _markers,
        zoomControlsEnabled: false,
        circles: {
          ..._showHeatmap ? _heatmapCircles.map((circle) {
            return Circle(
              circleId: circle.circleId,
              center: circle.center,
              radius: circle.radius,
              fillColor: _getHeatmapColor(circle.center),
              strokeWidth: 0,
            );
          }).toSet() : {},
          Circle(
            circleId: CircleId('userLocationCircle'),
            center: widget.userLocation,
            radius: 5, // Radius in meters for the blue dot
            fillColor: Colors.blue.withOpacity(1),
            strokeColor: Colors.blue,
            strokeWidth: 1,
          ),
          Circle(
            circleId: CircleId('userLocationOuterCircle'),
            center: widget.userLocation,
            radius: _userNotificationDistance, // Replace hardcoded 1000 with variable
            fillColor: Colors.blue.withOpacity(0.15),
            strokeColor: Colors.blue.withOpacity(0.3),
            strokeWidth: 1,
          ),
          Circle(
            circleId: CircleId('userLocationWhiteCircle'),
            center: widget.userLocation,
            radius: 15, // Slightly larger than the blue dot for the white border
            fillColor: Colors.white.withOpacity(0.8),
            strokeColor: Colors.white,
            strokeWidth: 1,
          ),
        },
        polylines: _polylines,
        onTap: _onMapTapped,
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton(
            heroTag: 'reportButton',
            onPressed: () {
              _showReportDialog();
            },
            backgroundColor: Colors.red,
            child: Icon(Icons.report_problem),
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'zoomInButton',
            onPressed: () {
              _mapController.animateCamera(CameraUpdate.zoomIn());
            },
            mini: true,
            child: Icon(Icons.zoom_in),
          ),
          SizedBox(height: 8),
          FloatingActionButton(
            heroTag: 'zoomOutButton',
            onPressed: () {
              _mapController.animateCamera(CameraUpdate.zoomOut());
            },
            mini: true,
            child: Icon(Icons.zoom_out),
          ),
          SizedBox(height: 16),
          FloatingActionButton(
            heroTag: 'locationButton',
            onPressed: _goToUserLocation,
            child: Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}