import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WebRTCService {
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription? _offerSubscription;
  StreamSubscription? _answerSubscription;
  StreamSubscription? _candidateSubscription;

  final String requestId;
  final bool isInitiator; // true for User B (broadcaster), false for User A (viewer)
  final Function(MediaStream stream)? onRemoteStream;
  final Function(String state)? onConnectionStateChange;

  WebRTCService({
    required this.requestId,
    required this.isInitiator,
    this.onRemoteStream,
    this.onConnectionStateChange,
  });

  Future<void> initialize({String? cameraId, String? facingMode}) async {
    try {
      print('🌐 WebRTC initializing... isInitiator: $isInitiator');
      
      // Create peer connection with multiple STUN servers for better connectivity
      _peerConnection = await createPeerConnection({
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
          {'urls': 'stun:stun2.l.google.com:19302'},
          {'urls': 'stun:stun3.l.google.com:19302'},
          {'urls': 'stun:stun4.l.google.com:19302'},
        ],
        'sdpSemantics': 'unified-plan',
        'iceTransportPolicy': 'all',
      });

      // Monitor connection state
      _peerConnection!.onConnectionState = (state) {
        print('🔗 Connection state: $state');
        onConnectionStateChange?.call(state.toString());
        
        // Handle connection failure
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          print('❌ Connection failed! Attempting recovery...');
          // Don't dispose yet - let ICE candidates continue trying
        }
      };
      
      // Monitor ICE connection state separately
      _peerConnection!.onIceConnectionState = (state) {
        print('🧊 ICE connection state: $state');
        if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          print('❌ ICE connection failed!');
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateConnected) {
          print('✅ ICE connection established!');
        }
      };

      // Handle remote stream
      _peerConnection!.onTrack = (RTCTrackEvent event) {
        print('📺 Remote track received: ${event.track.kind}');
        print('📊 Track ID: ${event.track.id}, enabled: ${event.track.enabled}');
        
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
          
          // Log all tracks in the stream
          final audioTracks = _remoteStream!.getAudioTracks();
          final videoTracks = _remoteStream!.getVideoTracks();
          print('📊 Remote stream tracks - audio: ${audioTracks.length}, video: ${videoTracks.length}');
          
          // CRITICAL: Enable all audio tracks
          for (var track in audioTracks) {
            track.enabled = true;
            print('🔊 Audio track ${track.id} enabled for playback');
          }
          
          // Enable all video tracks
          for (var track in videoTracks) {
            track.enabled = true;
            print('🎥 Video track ${track.id} enabled');
          }
          
          onRemoteStream?.call(_remoteStream!);
        }
      };

      // Handle ICE candidates
      _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
        print('🧊 ICE candidate: ${candidate.candidate}');
        _sendIceCandidate(candidate);
      };

      // If broadcaster (User B), create local stream
      if (isInitiator) {
        await _createLocalStream(cameraId: cameraId, facingMode: facingMode);
      }

      // Listen for signaling
      _setupSignalingListeners();

      print('✅ WebRTC initialized successfully');
    } catch (e) {
      print('❌ Error initializing WebRTC: $e');
      rethrow;
    }
  }

  Future<void> _createLocalStream({String? cameraId, String? facingMode}) async {
    try {
      print('📹 Creating local stream with camera: $cameraId, facing: $facingMode');
      
      final Map<String, dynamic> mediaConstraints = {
        'audio': true, // Enable audio - must be true for audio to work!
        'video': {
          'facingMode': facingMode ?? 'user',
          'width': {'ideal': 1280},
          'height': {'ideal': 720},
        },
      };
      
      // Log the constraints for debugging
      print('📹 Video constraints: ${mediaConstraints['video']}');

      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      
      // Verify tracks and enable audio
      if (_localStream != null) {
        final videoTracks = _localStream!.getVideoTracks();
        final audioTracks = _localStream!.getAudioTracks();
        
        if (videoTracks.isNotEmpty) {
          print('✅ Video track selected: ${videoTracks[0].label}');
          print('✅ Video track settings: ${videoTracks[0].getSettings()}');
        }
        
        if (audioTracks.isNotEmpty) {
          // Explicitly enable audio
          for (var track in audioTracks) {
            track.enabled = true;
            print('✅ Audio track enabled: ${track.label}, enabled: ${track.enabled}');
          }
        } else {
          print('⚠️ No audio tracks in local stream!');
        }
      }
      
      // Add tracks to peer connection
      _localStream!.getTracks().forEach((track) {
        print('➕ Adding track: ${track.kind}');
        _peerConnection!.addTrack(track, _localStream!);
      });

      print('✅ Local stream created with ${_localStream!.getTracks().length} tracks');
    } catch (e) {
      print('❌ Error creating local stream: $e');
      rethrow;
    }
  }

  void _setupSignalingListeners() {
    final signalingDoc = FirebaseFirestore.instance
        .collection('webrtc_signaling')
        .doc(requestId);

    if (isInitiator) {
      print('👂 Broadcaster listening for answers...');
      // User B listens for answer from User A
      _answerSubscription = signalingDoc.snapshots().listen((snapshot) async {
        print('📬 Broadcaster received snapshot - exists: ${snapshot.exists}');
        if (snapshot.exists) {
          final data = snapshot.data();
          print('📬 Broadcaster data: ${data?.keys}');
          if (data != null && data['answer'] != null) {
            // Only process answer if we're in the right state
            print('🔍 Broadcaster state: ${_peerConnection?.signalingState}');
            if (_peerConnection?.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
              print('📩 Received answer, processing...');
              await _handleAnswer(data['answer']);
            } else {
              print('⏭️ Skipping answer - wrong state: ${_peerConnection?.signalingState}');
            }
          }
        }
      });
    } else {
      print('👂 Viewer listening for offers...');
      // User A listens for offer from User B
      _offerSubscription = signalingDoc.snapshots().listen((snapshot) async {
        print('📬 Viewer received snapshot - exists: ${snapshot.exists}');
        if (snapshot.exists) {
          final data = snapshot.data();
          print('📬 Viewer data: ${data?.keys}');
          if (data != null && data['offer'] != null) {
            final currentState = _peerConnection?.signalingState;
            print('🔍 Viewer state: $currentState');
            
            // Only process offer if in stable state or null (new connection)
            // Use _remoteStream to check if we already have a connection
            if ((currentState == RTCSignalingState.RTCSignalingStateStable || currentState == null) && 
                _remoteStream == null) {
              print('📩 Received NEW offer, processing...');
              await _handleOffer(data['offer']);
            } else {
              print('⏭️ Skipping offer - state: $currentState, hasRemoteStream: ${_remoteStream != null}');
            }
          } else {
            print('⚠️ Viewer: No offer in snapshot yet');
          }
        }
      });
    }

    // Both listen for ICE candidates
    _candidateSubscription = signalingDoc
        .collection('candidates')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final senderId = data['senderId'];
            // Only process candidates from the other peer
            if ((isInitiator && senderId == 'viewer') ||
                (!isInitiator && senderId == 'broadcaster')) {
              print('📩 Received ICE candidate from $senderId');
              _handleIceCandidate(data);
            }
          }
        }
      }
    });
  }

  Future<void> createOffer() async {
    try {
      print('📤 Creating offer...');
      
      // Verify local stream has tracks
      if (_localStream != null) {
        final audioTracks = _localStream!.getAudioTracks();
        final videoTracks = _localStream!.getVideoTracks();
        print('📊 Local stream tracks - audio: ${audioTracks.length}, video: ${videoTracks.length}');
        
        // Ensure audio tracks are enabled
        for (var track in audioTracks) {
          track.enabled = true;
          print('🔊 Audio track ${track.id} enabled: ${track.enabled}');
        }
      }
      
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await _peerConnection!.setLocalDescription(offer);
      
      // Wait a bit for ICE gathering to collect candidates
      print('🧊 Waiting for ICE gathering...');
      await Future.delayed(const Duration(milliseconds: 500));

      await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(requestId)
          .set({
        'offer': {
          'type': offer.type,
          'sdp': offer.sdp,
        },
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Offer created and sent');
    } catch (e) {
      print('❌ Error creating offer: $e');
      rethrow;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> offerData) async {
    try {
      print('📥 Handling offer...');
      
      final offer = RTCSessionDescription(
        offerData['sdp'],
        offerData['type'],
      );

      await _peerConnection!.setRemoteDescription(offer);

      // Create answer
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);

      await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(requestId)
          .set({
        'answer': {
          'type': answer.type,
          'sdp': answer.sdp,
        },
        'timestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print('✅ Answer created and sent');
    } catch (e) {
      print('❌ Error handling offer: $e');
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> answerData) async {
    try {
      print('📥 Handling answer...');
      final answer = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );

      await _peerConnection!.setRemoteDescription(answer);
      print('✅ Answer handled');
    } catch (e) {
      print('❌ Error handling answer: $e');
    }
  }

  Future<void> _sendIceCandidate(RTCIceCandidate candidate) async {
    try {
      await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(requestId)
          .collection('candidates')
          .add({
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
        'senderId': isInitiator ? 'broadcaster' : 'viewer',
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('❌ Error sending ICE candidate: $e');
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> candidateData) async {
    try {
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      await _peerConnection!.addCandidate(candidate);
      print('✅ ICE candidate added');
    } catch (e) {
      print('❌ Error handling ICE candidate: $e');
    }
  }

  Future<void> toggleAudio(bool enabled) async {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = enabled;
      }
      print('🔇 Audio ${enabled ? "enabled" : "muted"}');
    }
  }

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  Future<void> dispose({bool cleanupSignaling = true}) async {
    print('🧹 Disposing WebRTC service... cleanupSignaling=$cleanupSignaling');
    
    await _offerSubscription?.cancel();
    await _answerSubscription?.cancel();
    await _candidateSubscription?.cancel();

    _localStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _localStream?.dispose();

    _remoteStream?.getTracks().forEach((track) {
      track.stop();
    });
    await _remoteStream?.dispose();

    await _peerConnection?.close();
    await _peerConnection?.dispose();

    // Clean up Firestore signaling data only if requested (broadcaster should clean, viewer shouldn't)
    if (cleanupSignaling) {
      try {
        final signalingDoc = FirebaseFirestore.instance
            .collection('webrtc_signaling')
            .doc(requestId);
        
        final candidatesSnapshot = await signalingDoc.collection('candidates').get();
        for (var doc in candidatesSnapshot.docs) {
          await doc.reference.delete();
        }
        
        await signalingDoc.delete();
        print('🗑️ Signaling data cleaned up');
      } catch (e) {
        print('⚠️ Error cleaning signaling data: $e');
      }
    } else {
      print('⏭️ Skipping signaling cleanup (viewer disconnect)');
    }

    print('✅ WebRTC service disposed');
  }
}
