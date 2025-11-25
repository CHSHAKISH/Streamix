import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class TicketService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // --- NOTIFICATION SENDER ---
  Future<void> _sendNotificationV1({
    required String targetUserId,
    required String title,
    required String body,
    required String type,
  }) async {
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(targetUserId).get();
      if (!userDoc.exists) return;

      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;
      String? fcmToken = userData['fcmToken'];

      if (fcmToken == null) return;

      final String accessToken = await _getAccessToken();
      final String projectId = await _getProjectId();

      await http.post(
        Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': {
            'token': fcmToken,
            'notification': {
              'title': title,
              'body': body,
            },
            'data': {
              'type': type,
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'high_importance_channel', // MUST MATCH RECEIVER
                'default_sound': true,
                'default_vibrate_timings': true,
                'visibility': 'public',
              }
            }
          }
        }),
      );
    } catch (e) {
      print("❌ Notification Error: $e");
    }
  }

  // ... (Keep Auth Helpers: _getAccessToken, _getProjectId same as before) ...
  Future<String> _getAccessToken() async {
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);
    final authClient = await clientViaServiceAccount(accountCredentials, ['https://www.googleapis.com/auth/firebase.messaging']);
    final accessToken = authClient.credentials.accessToken.data;
    authClient.close();
    return accessToken;
  }

  Future<String> _getProjectId() async {
    final jsonString = await rootBundle.loadString('assets/service_account.json');
    return jsonDecode(jsonString)['project_id'];
  }

  // ... (Keep Create/Update logic, just ensure they call _sendNotificationV1) ...
  Future<String> createScheduledRequest({required String peerUserId, required String serviceType, required Timestamp startTime, required Timestamp endTime}) async {
    try {
      DocumentSnapshot myDoc = await _firestore.collection('users').doc(_currentUserId).get();
      String myName = (myDoc.data() as Map)['name'] ?? 'User';

      await _firestore.collection('requests').add({
        'requesterId': _currentUserId, 'requesterName': myName, 'peerUserId': peerUserId,
        'serviceType': serviceType, 'startTime': startTime, 'endTime': endTime,
        'status': 'pending', 'createdAt': Timestamp.now(),
      });

      await _sendNotificationV1(targetUserId: peerUserId, title: "New Request", body: "$myName requested $serviceType", type: 'request');
      return "Success";
    } catch (e) { return e.toString(); }
  }

  Future<void> updateRequestStatus(String requestId, bool accepted) async {
    DocumentSnapshot doc = await _firestore.collection('requests').doc(requestId).get();
    String requesterId = doc['requesterId'];
    String status = accepted ? 'accepted' : 'denied';
    await _firestore.collection('requests').doc(requestId).update({'status': status});

    await _sendNotificationV1(targetUserId: requesterId, title: accepted ? "Accepted" : "Denied", body: "Your request was $status.", type: 'status');
  }

  Future<void> notifySessionStarted(String requestId) async {
    DocumentSnapshot doc = await _firestore.collection('requests').doc(requestId).get();
    String requesterId = doc['requesterId'];
    await _sendNotificationV1(targetUserId: requesterId, title: "Session Started", body: "Service is active now.", type: 'start');
  }

  // ... (Keep CRUD methods) ...
  Future<void> updateRequestMedia(String requestId, String mediaUrl) async { await _firestore.collection('requests').doc(requestId).update({'mediaUrl': mediaUrl}); }
  Future<void> completeRequest(String requestId) async { await _firestore.collection('requests').doc(requestId).update({'status': 'completed'}); }
  Future<void> completeRequestWithMedia(String requestId, String mediaUrl) async { await _firestore.collection('requests').doc(requestId).update({'status': 'completed', 'mediaUrl': mediaUrl}); }
  Future<void> deleteRequest(String requestId) async { await _firestore.collection('requests').doc(requestId).delete(); }
  Stream<QuerySnapshot> getChatHistoryStream(String peerUserId) { return _firestore.collection('requests').where(Filter.or(Filter.and(Filter('requesterId', isEqualTo: _currentUserId), Filter('peerUserId', isEqualTo: peerUserId)), Filter.and(Filter('requesterId', isEqualTo: peerUserId), Filter('peerUserId', isEqualTo: _currentUserId)))).orderBy('startTime', descending: true).snapshots(); }
  Stream<QuerySnapshot> getIncomingRequestsStream() { return _firestore.collection('requests').where('peerUserId', isEqualTo: _currentUserId).where('status', isEqualTo: 'pending').orderBy('startTime', descending: false).snapshots(); }
}