import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:camera/camera.dart';
import '../services/webrtc_service.dart';

/// Background streaming service that runs independently of UI
/// User B can be anywhere in the app - stream runs in background
class BackgroundStreamService {
  static final BackgroundStreamService _instance = BackgroundStreamService._internal();
  factory BackgroundStreamService() => _instance;
  BackgroundStreamService._internal();

  // Active streams mapped by requestId
  final Map<String, _ActiveStream> _activeStreams = {};

  /// Start a background stream for a request
  /// User B doesn't need to navigate anywhere - stream runs in background
  Future<void> startStream({
    required String requestId,
    required String serviceType,
    required DateTime scheduledStartTime,
    required DateTime scheduledEndTime,
  }) async {
    print('🎬 BackgroundStreamService: Starting stream for $requestId');
    
    // Check if already running
    if (_activeStreams.containsKey(requestId)) {
      print('⚠️ Stream already running for $requestId');
      return;
    }

    // Create and start the stream
    final stream = _ActiveStream(
      requestId: requestId,
      serviceType: serviceType,
      scheduledStartTime: scheduledStartTime,
      scheduledEndTime: scheduledEndTime,
    );

    _activeStreams[requestId] = stream;
    await stream.start();
  }

  /// Stop a specific stream
  Future<void> stopStream(String requestId) async {
    final stream = _activeStreams[requestId];
    if (stream != null) {
      print('🛑 Stopping stream for $requestId');
      await stream.stop();
      _activeStreams.remove(requestId);
    }
  }

  /// Stop all active streams
  Future<void> stopAllStreams() async {
    print('🛑 Stopping all active streams');
    for (var stream in _activeStreams.values) {
      await stream.stop();
    }
    _activeStreams.clear();
  }

  /// Check if a stream is active
  bool isStreamActive(String requestId) {
    return _activeStreams.containsKey(requestId);
  }

  /// Get all active request IDs
  List<String> getActiveStreamIds() {
    return _activeStreams.keys.toList();
  }
}

/// Internal class representing an active background stream
class _ActiveStream {
  final String requestId;
  final String serviceType;
  final DateTime scheduledStartTime;
  final DateTime scheduledEndTime;

  WebRTCService? _webrtcService;
  MediaStream? _localStream;
  Timer? _scheduleTimer;
  Timer? _endTimer;
  StreamSubscription? _viewerSubscription;
  StreamSubscription? _stopSubscription;
  bool _isStreamInitialized = false;
  Timestamp? _lastViewerTimestamp;

  _ActiveStream({
    required this.requestId,
    required this.serviceType,
    required this.scheduledStartTime,
    required this.scheduledEndTime,
  });

  Future<void> start() async {
    print('▶️ Starting background stream for $requestId');
    
    // Listen for stop commands
    _listenForStopCommand();
    
    // Listen for viewer connections
    _listenForViewerReady();
    
    // Check schedule and auto-start
    await _checkScheduleAndAutoStart();
  }

  Future<void> _checkScheduleAndAutoStart() async {
    final now = DateTime.now();
    final isStream = serviceType.contains('stream');

    // Check if expired
    if (now.isAfter(scheduledEndTime)) {
      print('⏰ Session expired for $requestId');
      await stop();
      return;
    }

    // If before start time, schedule auto-start
    if (now.isBefore(scheduledStartTime)) {
      final waitDuration = scheduledStartTime.difference(now);
      print('⏰ Scheduling stream to start in ${waitDuration.inMinutes}:${(waitDuration.inSeconds % 60).toString().padLeft(2, '0')}');

      _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final timeLeft = scheduledStartTime.difference(DateTime.now());
        if (timeLeft.isNegative) {
          timer.cancel();
          if (isStream) {
            print('⏰ Scheduled start time reached, auto-starting stream...');
            _initializeStreaming();
          }
        }
      });
    }
    // If within time window, start immediately
    else if (!now.isAfter(scheduledEndTime)) {
      if (isStream) {
        print('✅ Within scheduled time window, starting stream immediately...');
        await _initializeStreaming();
        
        // Schedule auto-stop at end time
        final timeUntilEnd = scheduledEndTime.difference(now);
        _endTimer = Timer(timeUntilEnd, () {
          print('⏰ Scheduled end time reached, stopping stream...');
          stop();
        });
      }
    }
  }

  Future<void> _initializeStreaming() async {
    try {
      print('📹 Initializing background streaming for $serviceType...');

      // Get camera based on service type
      String? cameraId;
      String facingMode;
      try {
        final cameras = await availableCameras();
        print('📷 Available cameras: ${cameras.length}');

        if (serviceType == 'front_stream') {
          final frontCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.front,
          );
          cameraId = frontCamera.name;
          facingMode = 'user';
          print('📷 Using FRONT camera');
        } else {
          final backCamera = cameras.firstWhere(
            (camera) => camera.lensDirection == CameraLensDirection.back,
          );
          cameraId = backCamera.name;
          facingMode = 'environment';
          print('📷 Using BACK camera');
        }
      } catch (e) {
        print('⚠️ Could not get specific camera, using default: $e');
        facingMode = serviceType == 'front_stream' ? 'user' : 'environment';
      }

      // Create WebRTC service as broadcaster
      _webrtcService = WebRTCService(
        requestId: requestId,
        isInitiator: true,
        onRemoteStream: null,
        onConnectionStateChange: (state) {
          print('🔗 Background stream connection state: $state');
        },
      );

      await _webrtcService!.initialize(cameraId: cameraId, facingMode: facingMode);
      print('✅ WebRTC service initialized');

      if (_webrtcService!.localStream != null) {
        _localStream = _webrtcService!.localStream;
        _isStreamInitialized = true;
        print('✅ Background stream initialized successfully');
        print('📊 Stream tracks: audio=${_localStream!.getAudioTracks().length}, video=${_localStream!.getVideoTracks().length}');

        // Create initial offer
        await _webrtcService!.createOffer();
        
        // Signal that broadcaster is ready
        await FirebaseFirestore.instance
            .collection('webrtc_signaling')
            .doc(requestId)
            .set({
          'broadcasterReady': true,
          'broadcasterReadyTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        
        print('✅ Background stream broadcasting and ready for viewers');
      } else {
        print('❌ Failed to create local stream');
      }
    } catch (e) {
      print('❌ Error initializing background stream: $e');
      
      // Update Firestore with error
      try {
        await FirebaseFirestore.instance
            .collection('webrtc_signaling')
            .doc(requestId)
            .set({
          'broadcasterError': e.toString(),
          'broadcasterErrorTime': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } catch (firestoreError) {
        print('❌ Failed to update Firestore with error: $firestoreError');
      }
    }
  }

  void _listenForViewerReady() {
    _viewerSubscription = FirebaseFirestore.instance
        .collection('webrtc_signaling')
        .doc(requestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();

        // Detect viewer disconnect
        if (data != null && data['viewerDisconnected'] == true && data['viewerReady'] == false) {
          print('👋 Viewer disconnected, ready for reconnection');
          _lastViewerTimestamp = null;
          return;
        }

        // Viewer ready to connect
        if (data != null && data['viewerReady'] == true) {
          final timestamp = data['viewerTimestamp'] as Timestamp?;
          final viewerRetry = data['viewerRetry'] as int? ?? 0;
          print('📡 Viewer ready signal received at ${timestamp?.toDate()}, retry: $viewerRetry');

          if (_webrtcService != null && _isStreamInitialized) {
            // Always create fresh offer for viewer connection/reconnection
            // Check if this is truly a new connection attempt based on timestamp
            bool isNewConnection = _lastViewerTimestamp == null ||
                timestamp == null ||
                (timestamp.millisecondsSinceEpoch != _lastViewerTimestamp!.millisecondsSinceEpoch);

            if (isNewConnection) {
              print('📤 Creating fresh offer for viewer (connection/reconnection)...');
              print('   Last timestamp: ${_lastViewerTimestamp?.toDate()}');
              print('   New timestamp: ${timestamp?.toDate()}');
              _lastViewerTimestamp = timestamp;
              _webrtcService!.createOffer();
            } else {
              print('⏭️ Skipping duplicate viewerReady signal (same timestamp)');
            }
          } else {
            print('⚠️ Background stream not ready yet, waiting...');
            Future.delayed(const Duration(milliseconds: 1000), () {
              if (_webrtcService != null && _isStreamInitialized) {
                print('✅ Background stream now ready, creating offer...');
                _webrtcService!.createOffer();
              }
            });
          }
        }
      }
    });
  }

  void _listenForStopCommand() {
    _stopSubscription = FirebaseFirestore.instance
        .collection('requests')
        .doc(requestId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data();
        if (data != null) {
          final command = data['remoteCommand'];
          final status = data['status'];
          // ONLY stop if explicitly stopped by requester or provider
          // Do NOT stop on viewer disconnect - viewer can reconnect
          if (status == 'stopped_by_provider') {
            print('🛑 User B stopped sharing, stopping background stream...');
            stop();
          } else if (command == 'STOP' || status == 'stopped_by_requester') {
            print('🛑 User A stopped viewing (explicit stop), stopping background stream...');
            stop();
          }
        }
      }
    });
  }

  Future<void> stop() async {
    print('🛑 Stopping background stream for $requestId');

    _scheduleTimer?.cancel();
    _endTimer?.cancel();
    await _viewerSubscription?.cancel();
    await _stopSubscription?.cancel();

    await _webrtcService?.dispose(cleanupSignaling: true);
    _webrtcService = null;
    _localStream = null;
    _isStreamInitialized = false;

    print('✅ Background stream stopped and cleaned up');
  }
}
