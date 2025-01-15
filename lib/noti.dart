import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:app_settings/app_settings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cat304/main.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cat304/push_notification.dart';
import 'package:cat304/screens/signin_screen.dart';
import 'package:geolocator/geolocator.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static final ValueNotifier<bool> _isLoggingOut = ValueNotifier<bool>(false);

  static Future<void> initializeNotification() async {
    // Create the notification channel for Android
    final AndroidNotificationChannel channel = AndroidNotificationChannel(
      'emergency_channel',
      'Emergency Alerts',
      description: 'Notifications for emergency alerts',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
      enableLights: true,
    );

    // Create the Android-specific notification details
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        print('Notification clicked: ${details.payload}');
      },
    );

    // Get FCM token
    final fcmToken = await FirebaseMessaging.instance.getToken();
    print('FCM Token: $fcmToken'); // Debug print
    
    if (fcmToken != null) {
      await _saveFcmToken(fcmToken);
    }

    // Listen for token refresh
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      print('FCM Token Refreshed: $newToken'); // Debug print
      _saveFcmToken(newToken);
    });
  }

  static Future<void> _saveFcmToken(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      print('Saving FCM token for user ${user.uid}: $token'); // Debug print
      
      // Use set with merge option instead of update
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));  // This will create the document if it doesn't exist
    }
  }

  static Future<bool> checkPermission() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation == null) return false;
      
      try {
        final bool? granted = await androidImplementation.areNotificationsEnabled();
        return granted ?? false;
      } catch (e) {
        print('Error checking notification permission: $e');
        return false;
      }
    }
    
    if (Platform.isIOS) {
      // For iOS, we need to check notification settings
      final settings = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return settings ?? false;
    }
    return false;
  }

  
  static Future<void> revokeNotificationPermission() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Delete the notification channel
      await androidImplementation?.deleteNotificationChannel('emergency_channel');
      
      // Open settings to manually disable notifications
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    }
    
    // For iOS, we can't programmatically revoke permissions
    // User needs to do it manually through settings
  }

  static Future<void> showEmergencyNotification({
    required String username,
    required bool isBackground,
    required bool isEndNotification,
  }) async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      // Get sender's location
      final senderDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final senderData = senderDoc.data();
      final senderLat = senderData?['lastLatitude'];
      final senderLng = senderData?['lastLongitude'];

      if (senderLat == null || senderLng == null) return;

      // Store emergency alert in Firestore
      final alertRef = await FirebaseFirestore.instance
          .collection('emergency_alerts')
          .add({
        'sender': username,
        'senderId': currentUser.uid,
        'timestamp': FieldValue.serverTimestamp(),
        'status': isEndNotification ? 'resolved' : 'active',
        'latitude': senderLat,
        'longitude': senderLng,
      });

      // Get all users within their set notification distance
      final users = await FirebaseFirestore.instance
          .collection('users')
          .where('status', isEqualTo: 'approved')
          .get();

      final batch = FirebaseFirestore.instance.batch();
      
      for (var userDoc in users.docs) {
        if (userDoc.id == currentUser.uid) continue;
        
        final userData = userDoc.data();
        final userLat = userData['lastLatitude'];
        final userLng = userData['lastLongitude'];
        final fcmToken = userData['fcmToken'];
        final notificationDistance = userData['notificationDistance'] ?? 1000.0;

        if (userLat == null || userLng == null || fcmToken == null) continue;

        // Calculate distance between sender and receiver
        final distance = await Geolocator.distanceBetween(
          senderLat,
          senderLng,
          userLat,
          userLng,
        );

        // Only send notification if user is within their set notification distance
        if (distance <= notificationDistance) {
          // Create Firestore notification
          final notificationRef = FirebaseFirestore.instance
              .collection('users')
              .doc(userDoc.id)
              .collection('notifications')
              .doc();

          batch.set(notificationRef, {
            'type': isEndNotification ? 'emergency_end' : 'emergency_start',
            'sender': username,
            'senderId': currentUser.uid,
            'timestamp': FieldValue.serverTimestamp(),
            'read': false,
            'status': 0,
            'alertId': alertRef.id,
            'distance': distance,
          });

          // Send FCM notification
          await PushNotification.sendEmergencyNotification(
            username: username,
            currentUser: currentUser,
            isEndNotification: isEndNotification,
            alertId: alertRef.id,
            token: fcmToken,
            distance: distance,
          );
        }
      }

      await batch.commit();
    } catch (e) {
      print('Error in showEmergencyNotification: $e');
    }
  }

  static void showInAppNotification(
    BuildContext context, 
    String username, 
    VoidCallback onDirectPress, 
    {bool isEmergencyEnd = false}
  ) {
    // Dismiss any existing dialogs first
    Navigator.of(navigatorKey.currentState!.context).popUntil((route) => route.isFirst);

    showDialog(
      context: navigatorKey.currentState!.context,
      barrierDismissible: true,
      builder: (BuildContext dialogContext) {
        if (isEmergencyEnd) {
          // Auto-dismiss after 3 seconds for end notification
          Future.delayed(Duration(seconds: 3), () {
            if (dialogContext.mounted) {
              Navigator.of(dialogContext).pop();
            }
          });
        }

        return WillPopScope(
          onWillPop: () async => true,
          child: AlertDialog(
            backgroundColor: isEmergencyEnd ? Colors.green : const Color(0xFFE3242B),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            title: Row(
              children: [
                Icon(
                  isEmergencyEnd ? Icons.check_circle : Icons.warning_rounded,
                  color: Colors.white,
                  size: 24
                ),
                const SizedBox(width: 8),
                Text(
                  isEmergencyEnd ? 'Emergency Resolved' : 'Emergency Alert!',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Text(
              isEmergencyEnd 
                ? '$username is now safe'
                : '$username needs immediate assistance',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            actions: [
              if (!isEmergencyEnd)
                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    onDirectPress();
                  },
                  child: const Text('View Location', style: TextStyle(color: Colors.white)),
                ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(
                  isEmergencyEnd ? 'OK' : 'Dismiss',
                  style: TextStyle(color: Colors.white)
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Future<void> showLocalNotification({
    required String title,
    required String body,
    required String payload,
    bool showBubble = false,
  }) async {
    final isBackground = !WidgetsBinding.instance.lifecycleState!.index.isEven;
    
    if (isBackground) {
      final androidDetails = AndroidNotificationDetails(
        'emergency_channel',
        'Emergency Alerts',
        channelDescription: 'Notifications for emergency alerts',
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        visibility: NotificationVisibility.public,
        channelShowBadge: true,
        icon: '@mipmap/ic_launcher',
        timeoutAfter: 5000,  // System notification will disappear after 5 seconds
        styleInformation: showBubble ? BigTextStyleInformation(
          body,
          htmlFormatBigText: true,
          contentTitle: title,
          htmlFormatContentTitle: true,
          summaryText: 'Emergency Alert',
          htmlFormatSummaryText: true,
        ) : null,
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'emergency_category',
        interruptionLevel: InterruptionLevel.timeSensitive,
      );

      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _notifications.show(
        DateTime.now().millisecondsSinceEpoch.hashCode,
        title,
        body,
        details,
        payload: payload,
      );
    }

    // Show permanent in-app notification if in foreground
    if (!isBackground && navigatorKey.currentState != null && navigatorKey.currentState!.mounted) {
      if (navigatorKey.currentState != null && navigatorKey.currentState!.mounted) {
        showInAppNotification(
          navigatorKey.currentState!.context,
          title,
          () {},
          isEmergencyEnd: payload.contains('emergency_end'),
        );
      }
    }
  }

  static Future<void> handleLogout(BuildContext context) async {
    if (_isLoggingOut.value) return; // Prevent multiple logout attempts
    _isLoggingOut.value = true;

    try {
      // Clear all dialogs first
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).popUntil((route) => route.isFirst);
      }

      // Wait for any pending operations to complete
      await Future.delayed(Duration(milliseconds: 500));

      // Clear notifications and subscriptions
      await _clearNotifications();

      // Update login status
      await _updateLoginStatus();

      // Finally navigate to login screen
      if (navigatorKey.currentContext != null) {
        Navigator.of(navigatorKey.currentContext!).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => FutureBuilder<bool>(
              future: NotificationService.checkPermission(),
              builder: (context, snapshot) {
                return SignInScreen(
                  hasNotificationPermission: snapshot.data ?? false,
                );
              },
            ),
          ),
          (route) => false,
        );
      }
    } catch (e) {
      print('Error during logout: $e');
    } finally {
      _isLoggingOut.value = false;
    }
  }

  static Future<void> _clearNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'fcmToken': null,
        'loginStatus': 0,
        'lastLogoutTime': FieldValue.serverTimestamp(),
      });
    }
  }

  static Future<void> _updateLoginStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'loginStatus': 0,
      });
    }
  }
}