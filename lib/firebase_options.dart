// lib/firebase_options.dart

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions have not been configured for web - '
        'you can reconfigure this by running the FlutterFire CLI again.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  // ✅ Android 配置 (從你的 google-services.json)
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBp-MpE8pVipS1XPNexYVLNqoqltEHpc0Q',
    appId: '1:677409674412:android:4f17ddbd8d53d576c97b09',
    messagingSenderId: '677409674412',
    projectId: 'iot-project-8749e',
    storageBucket: 'iot-project-8749e.firebasestorage.app',
  );

  // ✅ iOS 配置 (如果你有 iOS 版本才需要)
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBp-MpE8pVipS1XPNexYVLNqoqltEHpc0Q',
    appId: '1:677409674412:ios:XXXXX',  // 需要從 Firebase Console 獲取 iOS App ID
    messagingSenderId: '677409674412',
    projectId: 'iot-project-8749e',
    storageBucket: 'iot-project-8749e.firebasestorage.app',
    iosBundleId: 'com.example.iotProject',
  );
}