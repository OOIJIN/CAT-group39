import 'package:firebase_core/firebase_core.dart';
import 'package:cat304/screens/signin_screen.dart';
import 'package:cat304/screens/home_navigation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
// ignore: unused_import
import 'firebase_options.dart';
import 'package:cat304/noti.dart';
import 'package:flutter/services.dart';
import 'package:app_settings/app_settings.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cat304/LocationService/location_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';


// Add this at the top level, outside any class
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  
  final notification = message.notification;
  final data = message.data;
  
  if (notification != null) {
    final currentUser = FirebaseAuth.instance.currentUser;
    final senderId = data['senderId'];
    
    // Only show notification if the current user is not the sender
    if (currentUser?.uid != senderId) {
      await NotificationService.showLocalNotification(
        title: notification.title ?? '',
        body: notification.body ?? '',
        payload: '${data['type']}:${data['alertId']}',
        showBubble: true
      );
    }
  }
}

List<CameraDescription>? cameras;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error initializing camera: $e');
  }
  await Firebase.initializeApp();
  
  // Register the background handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  
  // Handle foreground messages
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("Got a message whilst in the foreground!");
    
    final notification = message.notification;
    final data = message.data;
    
    if (notification != null) {
      // Check if current user is the sender
      final currentUser = FirebaseAuth.instance.currentUser;
      final senderId = data['senderId'];
      
      // Only show notification if the current user is not the sender
      if (currentUser?.uid != senderId) {
        NotificationService.showLocalNotification(
          title: notification.title ?? '',
          body: notification.body ?? '',
          payload: '${data['type']}:${data['alertId']}',
          showBubble: true
        );
      }
    }
  });
  
  // Request notification permissions
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );
  
  // Initialize local notifications
  await NotificationService.initializeNotification();
  
  runApp(const MyApp());
}

// Create a global key for the navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  void _getUserLocation() async {
    LocationService locationService = LocationService();
    try {
      Position position = await locationService.getCurrentLocation();
      print('Current location: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      print('Error: $e');
    }
  }

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only rebuild if permission status might have changed
      NotificationService.checkPermission().then((hasPermission) {
        if (!hasPermission && mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,  // Use the global navigator key
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: Builder(  // Wrap with Builder to get correct context
        builder: (context) => FutureBuilder<bool>(
          future: NotificationService.checkPermission(),
          builder: (context, permissionSnapshot) {
            if (permissionSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(),
                ),
              );
            }

            final hasPermission = permissionSnapshot.data ?? false;
            if (!hasPermission) {
              return NotificationPermissionScreen();
            }

            return StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                
                if (snapshot.hasData && snapshot.data != null) {
                  return const HomeNavigation();
                }
                
                return const SignInScreen(
                  hasNotificationPermission: true,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// Create a separate widget for the notification permission screen
class NotificationPermissionScreen extends StatelessWidget {
  const NotificationPermissionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PopScope(
        canPop: false,
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
}
