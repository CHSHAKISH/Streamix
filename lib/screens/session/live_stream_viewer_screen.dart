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
      // Initialize video renderer
      await _remoteRenderer.initialize();
      
      // Configure audio output
      await _remoteRenderer.audioOutput('speaker');
      
      // Create WebRTC service as viewer (not initiator)
      _webrtcService = WebRTCService(
        requestId: widget.requestId,
        isInitiator: false, // User A is the viewer
        onRemoteStream: (stream) {
          print('📺 Remote stream received, setting up renderer');
          setState(() {
            _remoteRenderer.srcObject = stream;
            _isConnecting = false;
            _connectionStatus = 'Connected';
          });
          
          // Ensure audio tracks are enabled
          final audioTracks = stream.getAudioTracks();
          for (var track in audioTracks) {
            track.enabled = true;
            print('🔊 Audio track enabled: ${track.id}');
          }
        },
        onConnectionStateChange: (state) {
          setState(() {
            _connectionStatus = state;
          });
        },
      );

      await _webrtcService!.initialize();
      
      print('✅ Stream viewer initialized, waiting for broadcaster...');
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

  Future<void> _cleanup() async {
    await _webrtcService?.dispose();
    await _remoteRenderer.dispose();
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
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

          return Stack(
            fit: StackFit.expand,
            children: [
              // Live Stream View
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
                    ],
                  ),
                )
              else if (_remoteRenderer.srcObject != null)
                // Display actual video stream
                RTCVideoView(_remoteRenderer, mirror: isFront)
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
          );
        },
      ),
    );
  }
}
