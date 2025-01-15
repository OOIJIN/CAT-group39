import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
// ignore: unused_import
import 'package:flutter/foundation.dart'show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
    static FirebaseOptions get currentPlatform {
    // Replace these values with your Firebase configuration
    return const FirebaseOptions(
      apiKey: 'AIzaSyDXRbmCW3z8eEhIWGdYbj3hZoGstGBCDr0',
      appId: '1:732961352241:android:5f2f9339322296d7194310',
      messagingSenderId: '732961352241',
      projectId: 'cat304-85852',
      storageBucket: 'cat304-85852.appspot.com',
      androidClientId: '732961352241-xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com',
    );
  }
}