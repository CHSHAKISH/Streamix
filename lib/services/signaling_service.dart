import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get a reference to the 'requests' collection for signaling
  CollectionReference _getRequestsCollection() {
    return _firestore.collection('requests');
  }

  /// Creates an offer for a WebRTC call and saves it to the request document.
  Future<void> createOffer(String requestId, RTCSessionDescription offer) async {
    print("🔥 [Signaling] Creating Offer for Request ID: $requestId");
    try {
      final sessionDoc = _getRequestsCollection().doc(requestId);

      // Print the full path for debugging
      print("🔥 [Signaling] Writing to path: requests/$requestId/signaling/session");

      // We'll store signaling data in a subcollection
      await sessionDoc.collection('signaling').doc('session').set({
        'offer': offer.toMap(),
        'timestamp': FieldValue.serverTimestamp(), // Add timestamp to verify write
      });
      print("✅ [Signaling] Offer written successfully!");
    } catch (e) {
      print("❌ [Signaling] FAILED to write offer: $e");
      throw e; // Rethrow so UI knows it failed
    }
  }

  /// Creates an answer to an offer and saves it.
  Future<void> createAnswer(String requestId, RTCSessionDescription answer) async {
    print("🔥 [Signaling] Creating Answer for Request ID: $requestId");
    try {
      final sessionDoc = _getRequestsCollection().doc(requestId);
      await sessionDoc.collection('signaling').doc('session').update({
        'answer': answer.toMap(),
      });
      print("✅ [Signaling] Answer written successfully!");
    } catch (e) {
      print("❌ [Signaling] FAILED to write answer: $e");
    }
  }

  /// Listens to the session document for an answer or offer.
  Stream<DocumentSnapshot> getSessionStream(String requestId) {
    print("🔥 [Signaling] Listening to stream: requests/$requestId/signaling/session");
    return _getRequestsCollection().doc(requestId).collection('signaling').doc('session').snapshots();
  }

  /// Adds an ICE candidate to the appropriate subcollection.
  Future<void> addCandidate(String requestId, RTCIceCandidate candidate, bool isRequester) async {
    final collectionName = isRequester ? 'requesterCandidates' : 'peerCandidates';
    try {
      await _getRequestsCollection().doc(requestId)
          .collection(collectionName)
          .add(candidate.toMap());
      // print("✅ [Signaling] Candidate added to $collectionName"); // Commented out to reduce noise
    } catch (e) {
      print("❌ [Signaling] Failed to add candidate: $e");
    }
  }

  /// Listens for new ICE candidates from the other peer.
  Stream<QuerySnapshot> getCandidateStream(String requestId, bool isRequester) {
    final collectionName = isRequester ? 'peerCandidates' : 'requesterCandidates';
    return _getRequestsCollection().doc(requestId)
        .collection(collectionName)
        .snapshots();
  }
}