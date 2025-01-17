import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth.dart' as auth;
import 'package:googleapis_auth/auth_io.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart' show rootBundle;


class PushNotification {
  static Future<String> getAccessToken() async {
    try {
      final serviceAccountJson = await rootBundle.loadString('assets/service-account.json');
      print('Service account loaded: ${serviceAccountJson.substring(0, 100)}...');
      final credentials = ServiceAccountCredentials.fromJson(
        json.decode(serviceAccountJson)
      );

      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      final client = await clientViaServiceAccount(credentials, scopes);
      return client.credentials.accessToken.data;
    } catch (e) {
      print('Error getting access token: $e');
      rethrow;
    }
  }

  static sendEmergencyUserNotification(String token, String title, String body, {
    required String username,
    required User currentUser,
    required bool isEndNotification
  }) async {
    {
      final String serverAccessTokenKey = await getAccessToken();
      String endpointFirebaseCloudMessaging = "https://fcm.googleapis.com/v1/projects/cat304-85852/messages:send";

      final Map<String, dynamic> message = {
        "message": {
          "token": token,
          "notification": {
            "title": "Calling for help!!!!",
            "body": "$username is in danger",
          },
          "data": {
           'sender': username,
          'senderId': currentUser.uid,
          'timestamp': FieldValue.serverTimestamp(),
          'status': isEndNotification ? 'resolved' : 'active',
          },
        },
      };

      final http.Response response = await http.post(
        Uri.parse(endpointFirebaseCloudMessaging),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $serverAccessTokenKey',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('FCM message sent successfully');
      } else {
        print('Failed to send FCM message: ${response.statusCode}');
      }
    }
}

    static Future<void> sendNotificationToAllUsers({
  required String title,
  required String body,
  required String senderId,
}) async {
  try {
    final String serverAccessTokenKey = await getAccessToken();
    String endpointFirebaseCloudMessaging = "https://fcm.googleapis.com/v1/projects/cat304-85852/messages:send";

    // Get all users with FCM tokens
    final users = await FirebaseFirestore.instance
        .collection('users')
        .where('status', isEqualTo: 'approved')
        .get();

    for (var user in users.docs) {
      if (user.id == senderId) continue; // Skip the sender

      final userData = user.data();
      final fcmToken = userData['fcmToken'];

      if (fcmToken == null) continue;

      final Map<String, dynamic> message = {
        "message": {
          "token": fcmToken,
          "notification": {
            "title": title,
            "body": body,
          },
          "android": {
            "notification": {
              "click_action": "FLUTTER_NOTIFICATION_CLICK"
            }
          }
        }
      };

      final http.Response response = await http.post(
        Uri.parse(endpointFirebaseCloudMessaging),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $serverAccessTokenKey',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('FCM message sent successfully to ${user.id}');
      } else {
        print('Failed to send FCM message to ${user.id}: ${response.statusCode}');
      }
    }
  } catch (e) {
    print('Error sending notification to all users: $e');
    rethrow;
  }
}

    static Future<void> sendEmergencyNotification({
    required String username,
    required User currentUser,
    required bool isEndNotification,
    required String alertId,
    required String token,
    required double distance,
  }) async {
    try {
      final String serverAccessTokenKey = await getAccessToken();
      String endpointFirebaseCloudMessaging = "https://fcm.googleapis.com/v1/projects/cat304-85852/messages:send";

      final Map<String, dynamic> message = {
        "message": {
          "token": token,
          "notification": {
            "title": isEndNotification ? "Emergency Update" : "Emergency Alert!",
            "body": isEndNotification 
                ? "$username is now safe"
                : "$username needs immediate assistance! (${distance.toStringAsFixed(0)}m away)",
          },
          "data": {
            "type": isEndNotification ? "emergency_end" : "emergency_start",
            "sender": username,
            "senderId": currentUser.uid,
            "alertId": alertId,
            "distance": distance.toString(),
            "click_action": "FLUTTER_NOTIFICATION_CLICK"
          },
        }
      };

      final http.Response response = await http.post(
        Uri.parse(endpointFirebaseCloudMessaging),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $serverAccessTokenKey',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('FCM message sent successfully');
      } else {
        print('Failed to send FCM message: ${response.statusCode}');
      }
    } catch (e) {
      print('Error sending emergency notification: $e');
      rethrow;
    }
  }

  static Future<void> sendNotification({
    required String token,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final String serverAccessTokenKey = await getAccessToken();
      String endpointFirebaseCloudMessaging = "https://fcm.googleapis.com/v1/projects/cat304-85852/messages:send";

      final Map<String, dynamic> message = {
        "message": {
          "token": token,
          "notification": {
            "title": title,
            "body": body,
          },
          "data": data,
          "android": {
            "notification": {
              "click_action": "FLUTTER_NOTIFICATION_CLICK"
            }
          }
        }
      };

      final http.Response response = await http.post(
        Uri.parse(endpointFirebaseCloudMessaging),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $serverAccessTokenKey',
        },
        body: jsonEncode(message),
      );

      if (response.statusCode == 200) {
        print('FCM message sent successfully');
      } else {
        print('Failed to send FCM message: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('Error sending notification: $e');
      rethrow;
    }
  }
}
