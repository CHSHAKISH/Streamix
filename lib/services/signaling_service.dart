import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class SignalingService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<void> createOffer(
    String requestId,
    RTCSessionDescription offer,
  ) async {
    await _db
        .collection('requests')
        .doc(requestId)
        .collection('signaling')
        .doc('room')
        .set({'offer': offer.toMap(), 'type': 'offer'});
  }

  Future<void> createAnswer(
    String requestId,
    RTCSessionDescription answer,
  ) async {
    await _db
        .collection('requests')
        .doc(requestId)
        .collection('signaling')
        .doc('room')
        .update({'answer': answer.toMap(), 'type': 'answer'});
  }

  Future<void> addCandidate(
    String requestId,
    RTCIceCandidate candidate,
    bool isCaller,
  ) async {
    final collection = isCaller ? 'callerCandidates' : 'calleeCandidates';
    await _db
        .collection('requests')
        .doc(requestId)
        .collection('signaling')
        .doc('room')
        .collection(collection)
        .add(candidate.toMap());
  }

  // --- FIX: ADDED THIS METHOD ---
  Stream<DocumentSnapshot> getRoomStream(String requestId) {
    return _db
        .collection('requests')
        .doc(requestId)
        .collection('signaling')
        .doc('room')
        .snapshots();
  }

  Stream<QuerySnapshot> getCandidateStream(String requestId, bool isCaller) {
    final collection = isCaller ? 'calleeCandidates' : 'callerCandidates';
    return _db
        .collection('requests')
        .doc(requestId)
        .collection('signaling')
        .doc('room')
        .collection(collection)
        .snapshots();
  }
}
