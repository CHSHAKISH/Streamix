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
    final sessionDoc = _getRequestsCollection().doc(requestId);

    // We'll store signaling data in a subcollection
    await sessionDoc.collection('signaling').doc('session').set({
      'offer': offer.toMap(),
    });
  }

  /// Creates an answer to an offer and saves it.
  Future<void> createAnswer(String requestId, RTCSessionDescription answer) async {
    final sessionDoc = _getRequestsCollection().doc(requestId);

    await sessionDoc.collection('signaling').doc('session').update({
      'answer': answer.toMap(),
    });
  }

  /// Listens to the session document for an answer or offer.
  Stream<DocumentSnapshot> getSessionStream(String requestId) {
    return _getRequestsCollection().doc(requestId).collection('signaling').doc('session').snapshots();
  }

  /// Adds an ICE candidate to the appropriate subcollection.
  Future<void> addCandidate(String requestId, RTCIceCandidate candidate, bool isRequester) async {
    final collectionName = isRequester ? 'requesterCandidates' : 'peerCandidates';
    await _getRequestsCollection().doc(requestId)
        .collection(collectionName)
        .add(candidate.toMap());
  }

  /// Listens for new ICE candidates from the other peer.
  Stream<QuerySnapshot> getCandidateStream(String requestId, bool isRequester) {
    final collectionName = isRequester ? 'peerCandidates' : 'requesterCandidates';
    return _getRequestsCollection().doc(requestId)
        .collection(collectionName)
        .snapshots();
  }
}