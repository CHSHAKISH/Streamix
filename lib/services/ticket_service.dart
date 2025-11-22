import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart'; // For rootBundle
import 'package:googleapis_auth/auth_io.dart'; // For V1 Auth
import 'package:http/http.dart' as http;

class TicketService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // --- NOTIFICATION SENDER (V1 DIRECT) ---
  Future<void> _sendNotificationV1({
    required String peerUserId,
    required String title,
    required String body,
    required String requestId,
  }) async {
    try {
      // 1. Get Peer's Token
      DocumentSnapshot peerDoc = await _firestore.collection('users').doc(peerUserId).get();
      if (!peerDoc.exists) return;

      Map<String, dynamic> peerData = peerDoc.data() as Map<String, dynamic>;
      String? fcmToken = peerData['fcmToken'];

      if (fcmToken == null) {
        print("⚠️ [Notification] Peer has no FCM token.");
        return;
      }

      // 2. Get Access Token from Service Account
      final String accessToken = await _getAccessToken();
      final String projectId = await _getProjectId();

      // 3. Send Request to FCM V1 Endpoint
      final response = await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode(
          <String, dynamic>{
            'message': {
              'token': fcmToken,
              'notification': {
                'title': title,
                'body': body,
              },
              'data': {
                'requestId': requestId,
                'click_action': 'FLUTTER_NOTIFICATION_CLICK',
                'status': 'done'
              },
              'android': {
                'priority': 'high',
                'notification': {
                  'channel_id': 'high_importance_channel',
                  'default_sound': true,
                  'default_vibrate_timings': true,
                }
              }
            }
          },
        ),
      );

      if (response.statusCode == 200) {
        print("✅ [Notification] Sent successfully (V1)!");
      } else {
        print("❌ [Notification] Failed: ${response.body}");
      }

    } catch (e) {
      print("❌ [Notification] Error: $e");
    }
  }

  // Helper: Load Service Account and Mint Token
  Future<String> _getAccessToken() async {
    // Load the file from assets
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);

    // Define scopes required for FCM
    final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

    // Authenticate
    final authClient = await clientViaServiceAccount(accountCredentials, scopes);
    final accessToken = authClient.credentials.accessToken.data;
    authClient.close(); // Close the client to free resources

    return accessToken;
  }

  // Helper: Get Project ID from JSON
  Future<String> _getProjectId() async {
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    final map = jsonDecode(jsonString);
    return map['project_id'];
  }

  /// Creates a new scheduled request AND Sends Notification
  Future<String> createScheduledRequest({
    required String peerUserId,
    required String serviceType,
    required Timestamp startTime,
    required Timestamp endTime,
  }) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(_currentUserId).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String myName = userData['name'] ?? userData['email'];

      // 1. Create Request in Firestore
      DocumentReference ref = await _firestore.collection('requests').add({
        'requesterId': _currentUserId,
        'requesterName': myName,
        'peerUserId': peerUserId,
        'serviceType': serviceType,
        'startTime': startTime,
        'endTime': endTime,
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });

      // 2. Send Notification
      await _sendNotificationV1(
        peerUserId: peerUserId,
        title: "New Request",
        body: "$myName requested $serviceType",
        requestId: ref.id,
      );

      return "Success";
    } catch (e) {
      return e.toString();
    }
  }

  // ... Standard Firestore Methods ...
  Future<void> updateRequestMedia(String requestId, String mediaUrl) async {
    await _firestore.collection('requests').doc(requestId).update({'mediaUrl': mediaUrl});
  }

  Future<void> completeRequestWithMedia(String requestId, String mediaUrl) async {
    await _firestore.collection('requests').doc(requestId).update({'status': 'completed', 'mediaUrl': mediaUrl});
  }

  Stream<QuerySnapshot> getChatHistoryStream(String peerUserId) {
    return _firestore.collection('requests').where(Filter.or(
      Filter.and(Filter('requesterId', isEqualTo: _currentUserId), Filter('peerUserId', isEqualTo: peerUserId)),
      Filter.and(Filter('requesterId', isEqualTo: peerUserId), Filter('peerUserId', isEqualTo: _currentUserId)),
    )).orderBy('startTime', descending: true).snapshots();
  }

  Stream<QuerySnapshot> getIncomingRequestsStream() {
    return _firestore.collection('requests').where('peerUserId', isEqualTo: _currentUserId).where('status', isEqualTo: 'pending').orderBy('startTime', descending: false).snapshots();
  }

  Future<void> updateRequestStatus(String requestId, bool accepted) async {
    await _firestore.collection('requests').doc(requestId).update({'status': accepted ? 'accepted' : 'denied'});
  }

  Future<void> completeRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({'status': 'completed'});
  }

  Future<void> deleteRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).delete();
  }
}