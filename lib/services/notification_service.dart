import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:streamix/main.dart'; // Needed for navigatorKey
import 'package:streamix/screens/requests/requests_list_screen.dart';
import 'dart:convert';

// Top-level function for background message handling
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('📲 Background message received: ${message.messageId}');
  print('📲 Title: ${message.notification?.title}');
  print('📲 Body: ${message.notification?.body}');
  print('📲 Data: ${message.data}');
}

class NotificationService {
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Local Notifications Plugin
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Define notification channels
  final AndroidNotificationChannel _androidChannel =
      const AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

  final AndroidNotificationChannel _requestChannel =
      const AndroidNotificationChannel(
        'request_channel',
        'Service Requests',
        description: 'Notifications for incoming service requests with actions',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

  Future<void> initNotifications() async {
    // 1. Request Permissions
    await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: true,
      criticalAlert: true,
    );

    // 2. Create Channels on Android
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(_androidChannel);
    await androidPlugin?.createNotificationChannel(_requestChannel);

    // 3. Initialize Local Plugin with action handling
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationAction(response);
      },
    );

    // Set background message handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 4. Save Token
    String? token = await _firebaseMessaging.getToken();
    if (token != null) _saveTokenToFirestore(token);
    _firebaseMessaging.onTokenRefresh.listen(_saveTokenToFirestore);

    // 5. Foreground Listener (Show banner when app is open)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📲 Foreground message received: ${message.messageId}');
      _showNotificationFromMessage(message);
    });
  }

  Future<void> _showNotificationFromMessage(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;
    Map<String, dynamic> data = message.data;

    if (notification != null) {
      final String? type = data['type'];
      final String? requestId = data['requestId'];
      final String? serviceType = data['serviceType'];

      // Check if this is a request notification that needs actions
      if (type == 'request' && requestId != null) {
        await _showInteractiveRequestNotification(
          requestId: requestId,
          title: notification.title ?? 'New Request',
          body: notification.body ?? '',
          serviceType: serviceType ?? 'service',
        );
      } else {
        // Regular notification
        await _localNotifications.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _androidChannel.id,
              _androidChannel.name,
              channelDescription: _androidChannel.description,
              icon: '@mipmap/ic_launcher',
              importance: Importance.max,
              priority: Priority.high,
              playSound: true,
            ),
          ),
          payload: jsonEncode(data),
        );
      }
    }
  }

  Future<void> _showInteractiveRequestNotification({
    required String requestId,
    required String title,
    required String body,
    required String serviceType,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'request_channel',
          'Service Requests',
          channelDescription:
              'Notifications for incoming service requests with actions',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              'accept',
              'Accept',
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
              showsUserInterface: true,
            ),
            AndroidNotificationAction(
              'reject',
              'Reject',
              icon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
              showsUserInterface: false,
              cancelNotification: true,
            ),
          ],
        );

    await _localNotifications.show(
      requestId.hashCode,
      title,
      body,
      const NotificationDetails(android: androidDetails),
      payload: jsonEncode({
        'requestId': requestId,
        'type': 'request',
        'serviceType': serviceType,
      }),
    );
  }

  Future<void> _handleNotificationAction(NotificationResponse response) async {
    print('📲 Notification action: ${response.actionId}');
    print('📲 Payload: ${response.payload}');

    if (response.payload == null) {
      _handleNavigation();
      return;
    }

    try {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String? requestId = data['requestId'];
      final String? actionId = response.actionId;

      if (requestId != null && actionId != null) {
        if (actionId == 'accept') {
          await _handleAcceptRequest(requestId);
        } else if (actionId == 'reject') {
          await _handleRejectRequest(requestId);
        }
      } else {
        _handleNavigation();
      }
    } catch (e) {
      print('❌ Error handling notification action: $e');
      _handleNavigation();
    }
  }

  Future<void> _handleAcceptRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
            'status': 'accepted',
            'acceptedAt': FieldValue.serverTimestamp(),
          });
      print('✅ Request accepted: $requestId');
      _handleNavigation();
    } catch (e) {
      print('❌ Error accepting request: $e');
    }
  }

  Future<void> _handleRejectRequest(String requestId) async {
    try {
      await FirebaseFirestore.instance
          .collection('requests')
          .doc(requestId)
          .update({
            'status': 'denied',
            'deniedAt': FieldValue.serverTimestamp(),
          });
      print('✅ Request rejected: $requestId');
    } catch (e) {
      print('❌ Error rejecting request: $e');
    }
  }

  // Background Taps
  Future<void> setupInteractedMessage(
    GlobalKey<NavigatorState> navigatorKey,
  ) async {
    RemoteMessage? initialMessage = await _firebaseMessaging
        .getInitialMessage();
    if (initialMessage != null) _handleNavigation();

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNavigation();
    });
  }

  void _handleNavigation() {
    if (navigatorKey.currentState != null) {
      navigatorKey.currentState!.push(
        MaterialPageRoute(builder: (_) => const RequestsListScreen()),
      );
    }
  }

  // Show in-app notification banner
  void showInAppNotification(
    BuildContext context,
    String title,
    String message, {
    Color? backgroundColor,
  }) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: backgroundColor ?? Colors.blue.shade900,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(
                  backgroundColor == Colors.red.shade900
                      ? Icons.cancel
                      : Icons.notifications_active,
                  color: Colors.white,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      overlayEntry.remove();
    });
  }

  Future<void> _saveTokenToFirestore(String token) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await _firestore.collection('users').doc(user.uid).set({
        'fcmToken': token,
        'lastTokenUpdate': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }
}
