import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/requests/requests_list_screen.dart';

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> initNotifications() async {
    try {
      // 1. Request Permission
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ [Notification] Permission granted');

        // 2. Get Token
        String? token = await _firebaseMessaging.getToken();
        if (token != null) {
          print('✅ [Notification] Token generated: $token');
          await _saveTokenToFirestore(token);
        } else {
          print('❌ [Notification] Failed to generate FCM token');
        }

        // 3. Listen for Refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          print('🔄 [Notification] Token refreshed: $newToken');
          _saveTokenToFirestore(newToken);
        });

        // 4. Foreground Listener
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          print('🔔 Foreground Message: ${message.notification?.title}');
        });
      } else {
        print('❌ [Notification] User declined permission');
      }
    } catch (e) {
      print('❌ [Notification] Error in initNotifications: $e');
    }
  }

  // Handle Taps
  Future<void> setupInteractedMessage(GlobalKey<NavigatorState> navigatorKey) async {
    try {
      RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        _handleMessage(initialMessage, navigatorKey);
      }

      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        _handleMessage(message, navigatorKey);
      });
    } catch (e) {
      print('❌ [Notification] Error in setupInteractedMessage: $e');
    }
  }

  void _handleMessage(RemoteMessage message, GlobalKey<NavigatorState> navigatorKey) {
    if (message.data['click_action'] == 'FLUTTER_NOTIFICATION_CLICK') {
      print("🚀 [Notification] Navigating to Requests List");
      navigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const RequestsListScreen()),
      );
    }
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      print("⚠️ [Notification] User not logged in, cannot save token yet.");
      return;
    }

    try {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print("✅ [Notification] Token saved for user ${user.uid}");
    } catch (e) {
      print("❌ [Notification] Error saving token to Firestore: $e");
    }
  }
}