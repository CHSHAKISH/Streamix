import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class TicketService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  /// --- NEW FUNCTION: Update Media WITHOUT completing the session ---
  /// This keeps the status as 'accepted' so the session remains open.
  Future<void> updateRequestMedia(String requestId, String mediaUrl) async {
    await _firestore.collection('requests').doc(requestId).update({
      'mediaUrl': mediaUrl,
    });
  }

  /// Marks a request as 'completed' and saves the Supabase media URL.
  Future<void> completeRequestWithMedia(String requestId, String mediaUrl) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'completed',
      'mediaUrl': mediaUrl,
    });
  }

  /// Creates a new scheduled request
  Future<String> createScheduledRequest({
    required String peerUserId,
    required String serviceType,
    required Timestamp startTime,
    required Timestamp endTime,
  }) async {
    try {
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
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });
      return "Success";
    } catch (e) {
      return e.toString();
    }
  }

  /// Gets the chat/request history between the current user and a peer
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

  /// Gets all incoming requests for the current user that are 'pending'
  Stream<QuerySnapshot> getIncomingRequestsStream() {
    return _firestore
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .orderBy('startTime', descending: false)
        .snapshots();
  }

  /// Accept or Deny an incoming request
  Future<void> updateRequestStatus(String requestId, bool accepted) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': accepted ? 'accepted' : 'denied',
    });
  }

  /// Marks an accepted request as 'completed'
  Future<void> completeRequest(String requestId) async {
    await _firestore.collection('requests').doc(requestId).update({
      'status': 'completed',
    });
  }
}