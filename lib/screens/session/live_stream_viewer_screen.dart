import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';

class LiveStreamViewerScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_stream' or 'back_stream'

  const LiveStreamViewerScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
  });

  @override
  State<LiveStreamViewerScreen> createState() => _LiveStreamViewerScreenState();
}

class _LiveStreamViewerScreenState extends State<LiveStreamViewerScreen> {
  bool _isMuted = false;
  bool _isConnecting = true;
  String _connectionStatus = 'Connecting...';
  WebRTCService? _webrtcService;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();

  @override
  void initState() {
    super.initState();
    _initializeStream();
  }

  Future<void> _initializeStream() async {
    try {
      print('🔄 Viewer initializing connection...');
      
      // Signal to broadcaster that viewer is ready to connect
      await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(widget.requestId)
          .set({
        'viewerReady': true,
        'viewerTimestamp': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      print('📡 Signaled broadcaster that viewer is ready');
      
      // Check if broadcaster reported any errors
      final signalingDoc = await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(widget.requestId)
          .get();
      
      if (signalingDoc.exists) {
        final data = signalingDoc.data();
        if (data != null && data['broadcasterError'] != null) {
          print('⚠️ Broadcaster reported error: ${data['broadcasterError']}');
          setState(() {
            _isConnecting = false;
            _connectionStatus = 'Broadcaster Error: ${data['broadcasterError']}';
          });
          return;
        }
      }
      
      // Initialize video renderer
      await _remoteRenderer.initialize();
      
      // Configure audio output to speaker (ensure audio plays out loud on mobile)
      try {
        await Helper.setSpeakerphoneOn(true);
        print('🔊 Speakerphone enabled');
      } catch (e) {
        print('⚠️ Unable to set speakerphone: $e');
      }
      
      // Create WebRTC service as viewer (not initiator)
      _webrtcService = WebRTCService(
        requestId: widget.requestId,
        isInitiator: false, // User A is the viewer
        onRemoteStream: (stream) {
          print('📺 Remote stream received, setting up renderer');
          final audioTracks = stream.getAudioTracks();
          final videoTracks = stream.getVideoTracks();
          print('📊 Remote stream tracks - audio: ${audioTracks.length}, video: ${videoTracks.length}');
          
          // Enable all audio tracks
          for (var a in audioTracks) {
            print('🔊 Audio track found: id=${a.id}, enabled=${a.enabled}');
            try {
              a.enabled = true;
              print('🔊 Audio track ${a.id} enabled');
            } catch (e) {
              print('⚠️ Failed to enable audio track ${a.id}: $e');
            }
          }
          
          for (var v in videoTracks) {
            print('🎞️ Video track found: id=${v.id}, kind=${v.kind}');
          }

          setState(() {
            _remoteRenderer.srcObject = stream;
            _isConnecting = false;
            _connectionStatus = 'Connected';
          });

          if (videoTracks.isEmpty) {
            print('⚠️ Remote stream has no video tracks - viewer will see a black/white screen');
          }
          
          if (audioTracks.isEmpty) {
            print('⚠️ Remote stream has no audio tracks - viewer will not hear audio');
          }
        },
        onConnectionStateChange: (state) {
          setState(() {
            _connectionStatus = state;
          });
        },
      );

      await _webrtcService!.initialize();
      
      print('✅ Stream viewer initialized, waiting for broadcaster offer...');
      
        // If no remote stream arrives within a short timeout, re-signal readiness
        // to request a fresh offer from the broadcaster. Retry a few times.
        (() async {
          final signalingRef = FirebaseFirestore.instance.collection('webrtc_signaling').doc(widget.requestId);
          int attempts = 0;
          while (attempts < 3 && mounted) {
            await Future.delayed(const Duration(seconds: 6));
            attempts++;
            if (!mounted) break;
            // If remote stream not set yet, try re-sending viewerReady to prompt broadcaster
            if (_remoteRenderer.srcObject == null) {
              print('🔁 No remote stream yet after ${6 * attempts}s — re-sending viewerReady (attempt $attempts)');
              try {
                await signalingRef.set({
                  'viewerReady': true,
                  'viewerTimestamp': FieldValue.serverTimestamp(),
                  'viewerRetry': attempts,
                }, SetOptions(merge: true));
              } catch (e) {
                print('⚠️ Failed to re-signal viewerReady: $e');
              }
            } else {
              // Remote stream arrived — stop retries
              print('✅ Remote stream arrived before retry #$attempts');
              break;
            }
          }
          if (_remoteRenderer.srcObject == null && mounted) {
            setState(() {
              _isConnecting = false;
              _connectionStatus = 'No remote stream received';
            });
          }
        })();
    } catch (e) {
      print('❌ Error initializing stream: $e');
      setState(() {
        _isConnecting = false;
        _connectionStatus = 'Connection Failed';
      });
    }
  }

  void _toggleMute() async {
    setState(() {
      _isMuted = !_isMuted;
    });
    
    // This mutes the audio that User A hears from User B
    if (_webrtcService != null && _remoteRenderer.srcObject != null) {
      final audioTracks = _remoteRenderer.srcObject!.getAudioTracks();
      for (var track in audioTracks) {
        track.enabled = !_isMuted;
        print('🔊 Audio track ${track.id} ${_isMuted ? "muted" : "unmuted"}');
      }
    }
  }

  Future<void> _stopStream() async {
    // Set status to stopped by requester
    await FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.requestId)
        .update({
      'status': 'stopped_by_requester',
      'remoteCommand': 'STOP',
    });
    
    await _cleanup();
    
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    // Clean up viewer connection completely when closing
    print('👋 Viewer closing, cleaning up connection...');
    _cleanupConnection();
    super.dispose();
  }

  Future<void> _cleanupConnection() async {
    // Close WebRTC but DON'T clean signaling (broadcaster keeps it)
    await _webrtcService?.dispose(cleanupSignaling: false);
    await _remoteRenderer.dispose();
  }

  Future<void> _cleanup() async {
    print('🧹 Cleaning up viewer completely (stop stream)...');
    await _webrtcService?.dispose(cleanupSignaling: true); // Clean everything on explicit stop
    await _remoteRenderer.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isFront = widget.serviceType == 'front_stream';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${isFront ? 'Front' : 'Back'} Camera Stream'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          // Mute/Unmute Button
          IconButton(
            icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
            onPressed: _toggleMute,
            tooltip: _isMuted ? 'Unmute' : 'Mute',
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }

          var data = snapshot.data!.data() as Map<String, dynamic>?;
          String? status = data?['status'];

          // If User B stopped sharing
          if (status == 'stopped_by_provider') {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.videocam_off, size: 80, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text(
                    'User B stopped sharing',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            );
          }

          return Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Live Stream View - FILL ENTIRE SCREEN
                if (_isConnecting)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Text(
                          _connectionStatus,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Connecting to User B\'s camera...',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                else if (_remoteRenderer.srcObject != null)
                  // Display actual video stream - FULLSCREEN
                  Positioned.fill(
                    child: RTCVideoView(
                      _remoteRenderer,
                      mirror: isFront,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover, // Fill screen
                    ),
                  )
                else
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isFront ? Icons.camera_front : Icons.camera_rear,
                          size: 100,
                          color: Colors.white70,
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Waiting for stream...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Status: $_connectionStatus',
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),

                // Mute Indicator
                if (_isMuted)
                  Positioned(
                    top: 20,
                    left: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.mic_off, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Muted',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Stop Stream Button
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.stop_circle),
                      label: const Text('STOP VIEWING'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                      ),
                      onPressed: _stopStream,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
