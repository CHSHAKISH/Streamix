import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../services/webrtc_service.dart';
import 'package:camera/camera.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_camera', 'back_camera', 'front_video', 'back_video', 'audio', 'front_stream', or 'back_stream'
  final DateTime scheduledStartTime;
  final DateTime scheduledEndTime;

  const ActiveSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  // State Variables
  String _statusMessage = "Checking Schedule...";
  
  // WebRTC for streaming
  WebRTCService? _webrtcService;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isStreamInitialized = false;

  // Timers
  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    _checkScheduleAndAutoStart();
    
    // For stream services, always listen for viewer and stop commands
    if (widget.serviceType.contains('stream')) {
      _listenForStopCommand();
      _listenForViewerReady();
    }
  }
  
  Timestamp? _lastViewerTimestamp;
  
  void _listenForViewerReady() {
    // Listen for viewer ready signal to create fresh offer
    FirebaseFirestore.instance
        .collection('webrtc_signaling')
        .doc(widget.requestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        
        // Detect viewer disconnect to prepare for reconnection
        if (data != null && data['viewerDisconnected'] == true && data['viewerReady'] == false) {
          print('👋 Viewer disconnected, ready for reconnection');
          _lastViewerTimestamp = null; // Reset timestamp for next connection
          return; // Wait for viewer to reconnect
        }
        
        if (data != null && data['viewerReady'] == true) {
          final timestamp = data['viewerTimestamp'] as Timestamp?;
          final viewerRetry = data['viewerRetry'] as int? ?? 0;
          print('📡 Viewer ready signal received at ${timestamp?.toDate()}, retry: $viewerRetry');
          
          // Create fresh offer for the viewer (initial or reconnection)
          if (_webrtcService != null && _isStreamInitialized && _localRenderer.srcObject != null) {
            // Check if this is a new viewer connection based on timestamp
            bool isNewConnection = _lastViewerTimestamp == null || 
                                   timestamp == null || 
                                   timestamp.seconds != _lastViewerTimestamp!.seconds;
            
            if (isNewConnection) {
              print('📤 Creating fresh offer for viewer (new connection or retry: $viewerRetry)...');
              print('📊 Local stream status: hasVideo=${_localRenderer.srcObject != null}, tracks=${_webrtcService!.localStream?.getTracks().length}');
              _lastViewerTimestamp = timestamp;
              _webrtcService!.createOffer();
            } else {
              print('⏭️ Skipping duplicate viewerReady signal (same timestamp)');
            }
          } else {
            print('⚠️ Cannot create offer - service not ready');
            print('   - WebRTC service: ${_webrtcService != null}');
            print('   - Stream initialized: $_isStreamInitialized');
            print('   - Local renderer has stream: ${_localRenderer.srcObject != null}');
            
            // If stream not ready, wait a bit and retry
            if (_webrtcService != null && !_isStreamInitialized) {
              print('🔄 Stream initializing, will create offer when ready...');
              Future.delayed(const Duration(milliseconds: 1000), () {
                if (_webrtcService != null && _isStreamInitialized && _localRenderer.srcObject != null) {
                  print('✅ Stream now ready, creating offer for waiting viewer...');
                  _webrtcService!.createOffer();
                }
              });
            }
          }
        }
      }
    });
  }
  
  void _listenForStopCommand() {
    // Listen for STOP command from User A
    FirebaseFirestore.instance
        .collection('requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          final command = data['remoteCommand'];
          final status = data['status'];
          if (command == 'STOP' || status == 'stopped_by_requester') {
            print('🛑 Received STOP command, closing stream...');
            _handleStop();
          }
        }
      }
    });
  }
  
  Future<void> _handleStop() async {
    print('🛑 Handling stop command from User A...');
    await _cleanupStreaming();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🛑 Stream stopped by User A'),
          backgroundColor: Colors.red,
        ),
      );
      await Future.delayed(const Duration(seconds: 1));
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }
  
  Future<void> _initializeStreamingImmediately() async {
    print('🚀 Auto-initializing stream for ${widget.serviceType}...');
    
    setState(() {
      _statusMessage = "🔄 Initializing camera and stream...";
    });
    
    await _initializeStreaming();
  }

  Future<void> _initializeStreaming() async {
    try {
      print('📹 Initializing streaming for ${widget.serviceType}...');
      
      // Initialize video renderer
      await _localRenderer.initialize();
      print('✅ Local renderer initialized');
      
      // Get camera ID and facing mode based on service type
      String? cameraId;
      String facingMode;
      try {
        final cameras = await availableCameras();
        print('📷 Available cameras: ${cameras.length}');
        for (var cam in cameras) {
          print('   - ${cam.name}: ${cam.lensDirection}');
        }
        
        if (widget.serviceType == 'front_stream') {
          final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
          );
          cameraId = frontCamera.name;
          facingMode = 'user'; // Front camera
          print('📷 Using FRONT camera for front_stream');
        } else {
          final backCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
          );
          cameraId = backCamera.name;
          facingMode = 'environment'; // Back camera
          print('📷 Using BACK camera for back_stream');
        }
        print('📷 Selected camera: $cameraId, facing: $facingMode');
      } catch (e) {
        print('⚠️ Could not get specific camera, using default: $e');
        facingMode = widget.serviceType == 'front_stream' ? 'user' : 'environment';
      }
      
      // Create WebRTC service as broadcaster (initiator)
      _webrtcService = WebRTCService(
        requestId: widget.requestId,
        isInitiator: true, // User B is the broadcaster
        onRemoteStream: null, // Broadcaster doesn't receive stream
        onConnectionStateChange: (state) {
          print('🔗 Broadcaster connection state: $state');
        },
      );

      await _webrtcService!.initialize(cameraId: cameraId, facingMode: facingMode);
      print('✅ WebRTC service initialized');
      
      // Set local stream to renderer
      if (_webrtcService!.localStream != null) {
        print('✅ Local stream available, setting to renderer');
        setState(() {
          _localRenderer.srcObject = _webrtcService!.localStream;
          _isStreamInitialized = true;
          _statusMessage = "🎥 Stream Ready - Waiting for User A to connect";
        });
        print('✅ Local stream set to renderer');
        print('📊 Local stream tracks: audio=${_webrtcService!.localStream!.getAudioTracks().length}, video=${_webrtcService!.localStream!.getVideoTracks().length}');
      } else {
        print('⚠️ Local stream is null!');
        setState(() {
          _statusMessage = "Failed to create local stream";
        });
        return;
      }
      
      // Create initial offer for User A to connect
      await _webrtcService!.createOffer();
      
      print('✅ Streaming initialized and initial offer sent');
      setState(() {
        _statusMessage = "📡 Broadcasting - User A can now view the stream";
      });
      
      // Signal that broadcaster is ready
      await FirebaseFirestore.instance
          .collection('webrtc_signaling')
          .doc(widget.requestId)
          .set({
        'broadcasterReady': true,
        'broadcasterReadyTime': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      print('✅ Signaled that broadcaster is ready');
    } catch (e) {
      print('❌ Error initializing streaming: $e');
      print('Stack trace: ${StackTrace.current}');
      
      // Update Firestore with error so viewer can see it
      try {
        await FirebaseFirestore.instance.collection('webrtc_signaling').doc(widget.requestId).set({
          'broadcasterError': e.toString(),
          'broadcasterErrorTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (firestoreError) {
        print('❌ Failed to update Firestore with error: $firestoreError');
      }
      
      setState(() {
        _statusMessage = "Stream initialization failed: $e";
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Stream error: Check camera permissions'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _cleanupStreaming() async {
    print('🧹 Broadcaster cleaning up with signaling data removal...');
    await _webrtcService?.dispose(cleanupSignaling: true); // Broadcaster should clean signaling
    await _localRenderer.dispose();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    if (widget.serviceType.contains('stream')) {
      _cleanupStreaming();
    }
    super.dispose();
  }

  // --- 1. SCHEDULE LOGIC WITH AUTO-START FOR STREAMS ---
  void _checkScheduleAndAutoStart() {
    final now = DateTime.now();
    final isStream = widget.serviceType.contains('stream');

    // A. Too Early -> Wait and auto-start at scheduled time
    if (now.isBefore(widget.scheduledStartTime)) {
      final waitDuration = widget.scheduledStartTime.difference(now);
      setState(() {
        _statusMessage = isStream 
            ? "Stream will auto-start in ${waitDuration.inMinutes}:${(waitDuration.inSeconds % 60).toString().padLeft(2, '0')}"
            : "Auto-start in ${waitDuration.inMinutes}:${(waitDuration.inSeconds % 60).toString().padLeft(2, '0')}";
      });

      // Update countdown every second until start time
      _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final timeLeft = widget.scheduledStartTime.difference(DateTime.now());
        if (timeLeft.isNegative) {
          timer.cancel();
          // Auto-start streaming when time is reached
          if (isStream) {
            print('⏰ Scheduled start time reached, auto-starting stream...');
            _initializeStreamingImmediately();
          } else {
            setState(() {
              _statusMessage = "Camera Ready for Remote Capture";
            });
          }
        } else {
          if (mounted) {
            setState(() {
              _statusMessage = isStream
                  ? "Stream will auto-start in ${timeLeft.inHours}:${(timeLeft.inMinutes % 60).toString().padLeft(2, '0')}:${(timeLeft.inSeconds % 60).toString().padLeft(2, '0')}"
                  : "Auto-start in ${timeLeft.inHours}:${(timeLeft.inMinutes % 60).toString().padLeft(2, '0')}:${(timeLeft.inSeconds % 60).toString().padLeft(2, '0')}";
            });
          }
        }
      });
    }
    // B. Too Late -> Expire
    else if (now.isAfter(widget.scheduledEndTime)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Session Expired")));
        Navigator.pop(context);
      }
    }
    // C. On Time -> Auto-start streaming or show standby
    else {
      if (isStream) {
        // Stream service: auto-start immediately
        print('✅ Within scheduled time window, auto-starting stream...');
        _initializeStreamingImmediately();
        
        // Schedule auto-stop at end time
        final timeUntilEnd = widget.scheduledEndTime.difference(now);
        Timer(timeUntilEnd, () {
          if (mounted) {
            print('⏰ Scheduled end time reached, auto-stopping stream...');
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('⏰ Session time ended, stream stopped'),
                backgroundColor: Colors.orange,
              ),
            );
            Navigator.pop(context);
          }
        });
      } else {
        // Other services: show standby
        bool isVideo = widget.serviceType.contains('video');
        bool isAudio = widget.serviceType == 'audio';
        setState(() {
          _statusMessage = isVideo 
              ? "Video Ready for Remote Recording" 
              : isAudio
                  ? "Audio Ready for Remote Recording"
                  : "Camera Ready for Remote Capture";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('${widget.serviceType.toUpperCase()} Session'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          String? mediaUrl;
          String remoteCommand = 'IDLE';
          
          if (snapshot.hasData) {
            var data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data != null) {
              mediaUrl = data['mediaUrl'];
              remoteCommand = data['remoteCommand'] ?? 'IDLE';
            }
          }

          bool mediaExists = mediaUrl != null && mediaUrl.isNotEmpty;
          bool isProcessing = remoteCommand == 'REQUEST_CAPTURE';
          bool isVideo = widget.serviceType.contains('video');
          bool isAudio = widget.serviceType == 'audio';
          bool isStream = widget.serviceType.contains('stream');
          
          String processingText = isVideo 
              ? "User A viewing file\nRecording 10s video automatically..." 
              : isAudio
                  ? "User A viewing file\nRecording 10s audio automatically..."
                  : "User A viewing file\nTaking photo automatically...";
          
          String successText = isVideo ? "Video Sent!" : isAudio ? "Audio Sent!" : "Photo Sent!";
          
          // For stream services, show different message
          if (isStream) {
            if (_isStreamInitialized) {
              processingText = "User A is viewing your live stream...";
              successText = "Stream Active";
            } else {
              processingText = "Waiting for User A to start viewing...";
              successText = "Stream Ready";
            }
          }
          
          String detailText = isVideo
              ? "Video sent successfully!\n\nVideo still active.\nUser A can view again anytime.\n\nTap STOP SHARING to end."
              : isAudio
                  ? "Audio sent successfully!\n\nAudio still active.\nUser A can request again anytime.\n\nTap STOP SHARING to end."
                  : isStream
                      ? "Live stream active.\nUser A is viewing your camera.\n\nTap STOP SHARING to end stream."
                      : "Photo sent successfully!\n\nCamera still active.\nUser A can view again anytime.\n\nTap STOP SHARING to end.";

          return Stack(
            fit: StackFit.expand,
            children: [
              // BLACK BACKGROUND OR STREAM PREVIEW
              if (isStream && _localRenderer.srcObject != null)
                // Show local camera preview for streaming
                RTCVideoView(
                  _localRenderer,
                  mirror: widget.serviceType == 'front_stream',
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Container(color: Colors.black),

              // CENTER: MESSAGES & STATUS
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Processing Indicator
                      if (isProcessing) ...[
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            processingText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                      // Success State
                      else if (mediaExists) ...[
                        const Icon(Icons.check_circle, color: Colors.green, size: 60),
                        const SizedBox(height: 10),
                        Text(successText, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            detailText,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ),
                      ]
                      // Standby State
                      else ...[
                        Icon(
                          isVideo ? Icons.videocam : isAudio ? Icons.mic : Icons.camera_alt, 
                          color: Colors.white70, 
                          size: 60
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${isVideo ? '🎥' : isAudio ? '🎤' : '📷'} ${isVideo ? 'Video' : isAudio ? 'Audio' : 'Camera'} Ready\n\n$_statusMessage\n\nKeep this app open.\nWhen User A clicks VIEW FILE,\n${isVideo ? 'video will be recorded' : isAudio ? 'audio will be recorded' : 'photo will be taken'} automatically.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                      
                      const SizedBox(height: 40),
                      
                      // Stop Sharing Button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.stop_circle),
                        label: const Text("STOP SHARING"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        onPressed: () async {
                          // Mark request as completed and notify User A
                          await FirebaseFirestore.instance
                              .collection('requests')
                              .doc(widget.requestId)
                              .update({
                            'status': 'stopped_by_provider',
                            'remoteCommand': 'STOPPED',
                            'lastUpdated': FieldValue.serverTimestamp(),
                          });
                          
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('✅ Stopped sharing camera'),
                                backgroundColor: Colors.green,
                              ),
                            );
                            Navigator.pop(context);
                          }
                        },
                      ),
                      
                      const SizedBox(height: 10),
                      
                      // Close Button
                      TextButton(
                        child: const Text("Close & Exit", style: TextStyle(color: Colors.grey, fontSize: 16)),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
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