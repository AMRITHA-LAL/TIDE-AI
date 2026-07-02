import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    return const FirebaseOptions(
      apiKey: "AIzaSyD83XuzPBVB4pA6JysRo4rDsRqpLL_NfLw",
      authDomain: "tideai04.firebaseapp.com",
      projectId: "tideai04",
      storageBucket: "tideai04.firebasestorage.app",
      messagingSenderId: "346659118486",
      appId: "1:346659118486:web:e4613b4ceb3d55e7ec11b7",
    );
  }
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD83XuzPBVB4pA6JysRo4rDsRqpLL_NfLw',
    authDomain: 'tideai04.firebaseapp.com',
    projectId: 'tideai04',
    storageBucket: 'tideai04.firebasestorage.app',
    messagingSenderId: '346659118486',
    appId: '1:346659118486:web:e4613b4ceb3d55e7ec11b7'
  );

}
