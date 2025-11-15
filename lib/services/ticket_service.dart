import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TicketService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  /// --- UPDATED ---
  /// Creates a new scheduled request
  Future<String> createScheduledRequest({
    required String peerUserId,
    required String serviceType,
    required Timestamp startTime,
    required Timestamp endTime,
  }) async {
    try {
      // Get current user's data to store their name/email
      DocumentSnapshot userDoc =
      await _firestore.collection('users').doc(_currentUserId).get();
      Map<String, dynamic> userData = userDoc.data() as Map<String, dynamic>;

      await _firestore.collection('requests').add({
        'requesterId': _currentUserId,
        'requesterName': userData['name'] ?? userData['email'],
        'peerUserId': peerUserId,
        'serviceType': serviceType,
        'startTime': startTime,
        'endTime': endTime,
        'status': 'pending', // pending -> accepted -> denied
        'createdAt': Timestamp.now(),
      });
      return "Success";
    } catch (e) {
      return e.toString();
    }
  }

  /// --- NEW ---
  /// Gets the chat/request history between the current user and a peer
  Stream<QuerySnapshot> getChatHistoryStream(String peerUserId) {
    // This query is complex: it gets all documents where
    // (I am the requester AND you are the peer)
    // OR
    // (You are the requester AND I am the peer)
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

  /// --- NEW ---
  /// Gets all incoming requests for the current user that are 'pending'
  Stream<QuerySnapshot> getIncomingRequestsStream() {
    return _firestore
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('startTime', descending: false)
        .snapshots();
  }

  /// --- NEW ---
  /// Accept or Deny an incoming request
  Future<void> updateRequestStatus(String requestId, bool accepted) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': accepted ? 'accepted' : 'denied',
    });
  }
}