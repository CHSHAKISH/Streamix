import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart' as auth;

class TicketService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';

  // --- 1. SEND COMMAND (User A) ---
  // "I want a photo. I am setting the flag to REQUEST_CAPTURE"
  Future<void> sendCameraTrigger(String requestId) async {
    print("🚀 [TicketService] Setting command to REQUEST_CAPTURE");
    await _firestore.collection('requests').doc(requestId).update({
      'remoteCommand': 'REQUEST_CAPTURE',
      'commandTimestamp': FieldValue.serverTimestamp(),
    });
  }

  // --- 2. MARK COMPLETE (User B) ---
  // "I finished the job. I am setting flag to COMPLETED"
  Future<void> completeCameraTask(String requestId, String mediaUrl) async {
    try {
      print("✅ [TicketService] Task Finished. Updating URL: $mediaUrl");
      print("✅ [TicketService] RequestId: $requestId");

      await _firestore.collection('requests').doc(requestId).update({
        'remoteCommand': 'COMPLETED',
        'mediaUrl': mediaUrl,
        'lastUpdated': FieldValue.serverTimestamp(),
      });

      print("✅ [TicketService] Firestore update completed successfully");

      // Verify the update
      final doc = await _firestore.collection('requests').doc(requestId).get();
      if (doc.exists) {
        final data = doc.data();
        print(
          "✅ [TicketService] Verification - mediaUrl in Firestore: ${data?['mediaUrl']}",
        );
      }
    } catch (e) {
      print("❌ [TicketService] Error updating Firestore: $e");
      rethrow;
    }
  }

  // --- 3. RESET (Optional cleanup) ---
  Future<void> resetCommand(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'remoteCommand': 'IDLE',
    });
  }

  // --- EXISTING CORE METHODS ---
  // (Keep Notification logic & other CRUD methods exactly as they were)
  Future<void> _sendNotificationV1({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
    String? requestId,
    String? serviceType,
  }) async {
    try {
      // Get target user's FCM token
      DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(targetUserId)
          .get();
      if (!userDoc.exists) {
        print('⚠️ Target user not found');
        return;
      }

      String? fcmToken = (userDoc.data() as Map<String, dynamic>?)?['fcmToken'];
      if (fcmToken == null || fcmToken.isEmpty) {
        print('⚠️ FCM token not found for user');
        return;
      }

      // Get service account credentials
      final String serviceAccountJson = await rootBundle.loadString(
        'assets/service_account.json',
      );
      final Map<String, dynamic> serviceAccountData = jsonDecode(
        serviceAccountJson,
      );

      // Create service account credentials
      final accountCredentials = auth.ServiceAccountCredentials.fromJson(
        serviceAccountData,
      );
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      // Get access token
      final authClient = await auth.clientViaServiceAccount(
        accountCredentials,
        scopes,
      );
      final accessToken = authClient.credentials.accessToken.data;

      // Extract project ID from service account
      final projectId = serviceAccountData['project_id'];

      // Prepare notification payload
      final Map<String, dynamic> notificationData = {
        'type': type,
        if (requestId != null) 'requestId': requestId,
        if (serviceType != null) 'serviceType': serviceType,
      };

      final Map<String, dynamic> message = {
        'message': {
          'token': fcmToken,
          'notification': {'title': title, 'body': body},
          'data': notificationData,
          'android': {
            'priority': 'high',
            'notification': {
              'sound': 'default',
              'channelId': type == 'request'
                  ? 'request_channel'
                  : 'high_importance_channel',
              'priority': 'high',
              'defaultSound': true,
              'defaultVibrateTimings': true,
            },
          },
        },
      };

      // Send notification
      final response = await http.post(
        Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(message),
      );

      authClient.close();

      if (response.statusCode == 200) {
        print('✅ Notification sent successfully');
      } else {
        print('❌ Failed to send notification: ${response.statusCode}');
        print('❌ Response: ${response.body}');
      }
    } catch (e) {
      print('❌ Error sending notification: $e');
    }
  }

  Future<String> createScheduledRequest({
    required String peerUserId,
    required String serviceType,
    required Timestamp startTime,
    required Timestamp endTime,
  }) async {
    try {
      DocumentSnapshot myDoc = await _firestore
          .collection('users')
          .doc(_currentUserId)
          .get();
      String myName = (myDoc.data() as Map)['name'] ?? 'User';

      // Create request and get document reference
      DocumentReference docRef = await _firestore.collection('requests').add({
        'requesterId': _currentUserId,
        'requesterName': myName,
        'peerUserId': peerUserId,
        'serviceType': serviceType,
        'startTime': startTime,
        'endTime': endTime,
        'status': 'pending',
        'createdAt': Timestamp.now(),
        'remoteCommand': 'IDLE',
        'mediaUrl': null,
      });

      // Send notification with request ID for interactive actions
      await _sendNotificationV1(
        targetUserId: peerUserId,
        title: "New Request",
        body: "$myName requested $serviceType",
        type: 'request',
        requestId: docRef.id,
        serviceType: serviceType,
      );

      return "Success";
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> updateRequestStatus(String requestId, bool accepted) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': accepted ? 'accepted' : 'denied',
      accepted ? 'acceptedAt' : 'deniedAt': FieldValue.serverTimestamp(),
    });

    // Notify the requester (User A)
    try {
      DocumentSnapshot requestDoc = await _firestore
          .collection('requests')
          .doc(requestId)
          .get();
      if (requestDoc.exists) {
        final data = requestDoc.data() as Map<String, dynamic>;
        String requesterId = data['requesterId'];
        String serviceType = data['serviceType'];
        DocumentSnapshot myDoc = await _firestore
            .collection('users')
            .doc(_currentUserId)
            .get();
        String myName = (myDoc.data() as Map)['name'] ?? 'User';

        await _sendNotificationV1(
          targetUserId: requesterId,
          title: accepted ? "Request Accepted ✅" : "Request Denied ❌",
          body:
              "$myName ${accepted ? 'accepted' : 'denied'} your $serviceType request",
          type: accepted ? 'accepted' : 'denied',
          requestId: requestId,
          serviceType: serviceType,
        );
      }
    } catch (e) {
      print('Error sending notification: $e');
    }
  }

  Future<void> notifySessionStarted(String requestId) async {
    /* ... */
  }
  Future<void> completeRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'completed',
    });
  }

  Future<void> completeRequestWithMedia(
    String requestId,
    String mediaUrl,
  ) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'completed',
      'mediaUrl': mediaUrl,
    });
  }

  Future<void> deleteRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).delete();
  }

  Stream<QuerySnapshot> getChatHistoryStream(String peerUserId) {
    return _firestore
        .collection('requests')
        .where(
          Filter.or(
            Filter.and(
              Filter('requesterId', isEqualTo: _currentUserId),
              Filter('peerUserId', isEqualTo: peerUserId),
            ),
            Filter.and(
              Filter('requesterId', isEqualTo: peerUserId),
              Filter('peerUserId', isEqualTo: _currentUserId),
            ),
          ),
        )
        .orderBy('startTime', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot> getIncomingRequestsStream() {
    return _firestore
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('startTime', descending: false)
        .snapshots();
  }
}
