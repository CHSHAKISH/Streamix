import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart' show getApplicationDocumentsDirectory;

class GlobalCameraHandler extends StatefulWidget {
  final Widget child;
  const GlobalCameraHandler({super.key, required this.child});

  @override
  State<GlobalCameraHandler> createState() => _GlobalCameraHandlerState();
}

class _GlobalCameraHandlerState extends State<GlobalCameraHandler> with WidgetsBindingObserver {
  final String _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();
  final TicketService _ticketService = TicketService();

  CameraController? _cameraController;
  FlutterSoundRecorder? _audioRecorder;
  StreamSubscription? _requestSubscription;

  String? _activeRequestId;
  String? _activeServiceType; // Store the camera type (front_camera/back_camera/front_video/back_video)
  Timestamp? _lastProcessedTriggerTime;
  bool _isProcessing = false;
  bool _isRecording = false;
  bool _isDisposing = false;
  Timer? _recordingTimer;
  Timer? _pollingTimer; // Backup polling mechanism

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_currentUserId.isNotEmpty) {
      _initAudioRecorder();
      _ensureRuntimePermissions(); // Request camera/mic early on startup to avoid missing-permission issues in release APKs
      _listenForActiveRequests();
      _startBackupPolling(); // Start backup polling every 3 seconds
    }
  }

  /// Request camera and microphone permissions at startup so release APKs
  /// prompt the user and we can detect permanently denied state early.
  Future<void> _ensureRuntimePermissions() async {
    try {
      print('🔐 [GlobalCamera] Ensuring runtime permissions for camera/microphone');

      final cameraStatus = await Permission.camera.status;
      if (!cameraStatus.isGranted) {
        final result = await Permission.camera.request();
        print('🔐 [GlobalCamera] Camera permission result: $result');
        if (result.isPermanentlyDenied) {
          // Guide user to settings
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Camera permission permanently denied. Please enable it in app settings.'),
              backgroundColor: Colors.orange,
            ));
          }
        }
      }

      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        final mres = await Permission.microphone.request();
        print('🔐 [GlobalCamera] Microphone permission result: $mres');
        if (mres.isPermanentlyDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Microphone permission permanently denied. Please enable it in app settings.'),
              backgroundColor: Colors.orange,
            ));
          }
        }
      }
    } catch (e) {
      print('❌ [GlobalCamera] Error while requesting runtime permissions: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestSubscription?.cancel();
    _recordingTimer?.cancel();
    _pollingTimer?.cancel();
    _cameraController?.dispose();
    _audioRecorder?.closeRecorder();
    super.dispose();
  }

  Future<void> _initAudioRecorder() async {
    try {
      _audioRecorder = FlutterSoundRecorder();
      await _audioRecorder!.openRecorder();
      print("🎤 [GlobalAudio] Audio recorder initialized");
    } catch (e) {
      print("❌ [GlobalAudio] Failed to initialize audio recorder: $e");
    }
  }

  // Re-initialize if user switches apps and comes back
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("🔄 [GlobalCamera] App lifecycle state changed to: $state");
    
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      // App going to background - dispose camera to free resources
      print("💤 [GlobalCamera] App going to background, disposing camera");
      if (_cameraController != null) {
        _cameraController?.dispose();
        _cameraController = null;
      }
    } else if (state == AppLifecycleState.resumed) {
      // App came back to foreground - check for active requests
      print("👁️ [GlobalCamera] App resumed, checking for active requests");
      if (_activeRequestId != null && _activeServiceType != null) {
        // Re-awaken camera with the correct camera type
        print("🔄 [GlobalCamera] Reinitializing camera for active request: $_activeRequestId, service: $_activeServiceType");
        _initializeHiddenCamera(_activeRequestId!, _activeServiceType!);
      } else {
        // No stored active request, manually check Firestore for pending requests
        print("🔍 [GlobalCamera] Checking Firestore for pending requests after resume");
        _checkForPendingRequests();
      }
    }
  }

  // Check Firestore manually for active requests (used after app resume)
  Future<void> _checkForPendingRequests() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('requests')
          .where('peerUserId', isEqualTo: _currentUserId)
          .where('status', isEqualTo: 'accepted')
          .get();

      print("📊 [GlobalCamera] Found ${snapshot.docs.length} accepted requests");

      final now = DateTime.now();
      for (var doc in snapshot.docs) {
        var data = doc.data();
        String service = data['serviceType'] ?? '';
        
        // Skip streams
        if (service.contains('stream')) continue;
        
        // Only check camera/video/audio services
        if (!service.contains('camera') && !service.contains('video') && service != 'audio') continue;

        DateTime startTime = (data['startTime'] as Timestamp).toDate();
        DateTime endTime = (data['endTime'] as Timestamp).toDate();
        String command = data['remoteCommand'] ?? 'IDLE';
        
        bool inTimeWindow = now.isAfter(startTime) && now.isBefore(endTime);
        bool hasActiveCommand = command == 'REQUEST_CAPTURE';
        
        if (inTimeWindow || hasActiveCommand) {
          print("✅ [GlobalCamera] Found active request: ${doc.id}, service: $service, command: $command");
          _activeRequestId = doc.id;
          _activeServiceType = service;
          
          // Initialize camera for this request
          if (service.contains('camera') || service.contains('video')) {
            await _initializeHiddenCamera(doc.id, service);
          }
          break; // Handle one at a time
        }
      }
    } catch (e) {
      print("❌ [GlobalCamera] Error checking pending requests: $e");
    }
  }

  void _listenForActiveRequests() {
    print("👀 [GlobalCamera] Service Started for User ID: $_currentUserId");
    print("👀 [GlobalCamera] Listening for requests where peerUserId == $_currentUserId");
    
    // First, let's see ALL accepted requests for this user (no time filter)
    FirebaseFirestore.instance
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'accepted')
        .get()
        .then((snapshot) {
      print("🔍 [GlobalCamera] DEBUG: Found ${snapshot.docs.length} total accepted requests for this user:");
      for (var doc in snapshot.docs) {
        var data = doc.data();
        print("   📄 ${doc.id}: ${data['serviceType']}, command: ${data['remoteCommand']}, status: ${data['status']}");
      }
    });
    
    _requestSubscription = FirebaseFirestore.instance
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {

      print("📬 [GlobalCamera] Received snapshot with ${snapshot.docs.length} documents");
      
      final now = DateTime.now();

      var activeDocs = snapshot.docs.where((doc) {
        var data = doc.data();
        String service = data['serviceType'] ?? '';
        
        print("📄 [GlobalCamera] Checking doc ${doc.id}: serviceType=$service");
        
        // Skip stream services (handled by WebRTC in ActiveSessionScreen)
        if (service.contains('stream')) {
          print("   ⏭️ Stream service, handled by WebRTC, skipping GlobalCamera");
          return false;
        }
        
        // Handle camera, video, and audio services
        if (!service.contains('camera') && !service.contains('video') && service != 'audio') {
          print("   ❌ Not a camera/video/audio service, skipping");
          return false;
        }

        // Check if session is within time window OR if command is active
        DateTime startTime = (data['startTime'] as Timestamp).toDate();
        DateTime endTime = (data['endTime'] as Timestamp).toDate();
        String command = data['remoteCommand'] ?? 'IDLE';
        
        bool inTimeWindow = now.isAfter(startTime) && now.isBefore(endTime);
        bool hasActiveCommand = command == 'REQUEST_CAPTURE';
        
        print("   🔍 startTime: $startTime, endTime: $endTime, now: $now");
        print("   🔍 inTimeWindow=$inTimeWindow, command=$command, hasActiveCommand=$hasActiveCommand");
        
        // Allow if either in time window OR has active capture command
        return inTimeWindow || hasActiveCommand;
      }).toList();
      
      print("📊 [GlobalCamera] Found ${activeDocs.length} active camera/video requests");

      if (activeDocs.isNotEmpty) {
        var doc = activeDocs.first;
        var data = doc.data();
        String serviceType = data['serviceType'];

        // 1. Wake Camera (for camera/video/stream services)
        if (serviceType.contains('camera') || serviceType.contains('video') || serviceType.contains('stream')) {
          if (_activeRequestId != doc.id || _cameraController == null) {
            _activeServiceType = serviceType; // Store the camera type
            _initializeHiddenCamera(doc.id, serviceType);
          }
        }

        // 2. Check Trigger - Use timestamp to detect new commands
        String command = data['remoteCommand'] ?? 'IDLE';
        Timestamp? commandTimestamp = data['commandTimestamp'] as Timestamp?;
        
        print("🔍 [GlobalCamera] Command: $command, Processing: $_isProcessing, LastTime: $_lastProcessedTriggerTime, NewTime: $commandTimestamp");
        
        // Execute capture/recording on REQUEST_CAPTURE
        if (command == 'REQUEST_CAPTURE' && !_isProcessing) {
          // Check if this is a NEW command (different timestamp)
          if (_lastProcessedTriggerTime == null || 
              commandTimestamp == null ||
              commandTimestamp.millisecondsSinceEpoch != _lastProcessedTriggerTime!.millisecondsSinceEpoch) {
            print("⚡ [GlobalCamera] NEW COMMAND RECEIVED for serviceType: $serviceType");
            _lastProcessedTriggerTime = commandTimestamp;
            
            // Route to photo, video, or audio based on service type
            if (serviceType.contains('video')) {
              print("🎥 [GlobalCamera] Routing to VIDEO recording: $serviceType");
              _recordVideoAndUpload(doc.id, serviceType);
            } else if (serviceType == 'audio') {
              print("🎤 [GlobalCamera] Routing to AUDIO recording");
              _recordAudioAndUpload(doc.id);
            } else {
              print("📸 [GlobalCamera] Routing to PHOTO capture: $serviceType");
              _takePictureAndUpload(doc.id, serviceType);
            }
          } else {
            print("⏭️ [GlobalCamera] Already processed this command");
          }
        }

      } else {
        // Don't dispose immediately - keep camera ready for quick successive requests
        // _disposeCamera(); // Commented out to prevent disposal race conditions
      }
    });
  }

  // Backup polling mechanism - checks Firestore every 3 seconds for pending commands
  void _startBackupPolling() {
    print("🔄 [GlobalCamera] Starting backup polling mechanism");
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_isProcessing || _currentUserId.isEmpty) return;
      
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('requests')
            .where('peerUserId', isEqualTo: _currentUserId)
            .where('status', isEqualTo: 'accepted')
            .where('remoteCommand', isEqualTo: 'REQUEST_CAPTURE')
            .get();
        
        if (snapshot.docs.isNotEmpty) {
          print("🔄 [GlobalCamera] Polling found ${snapshot.docs.length} pending commands");
          for (var doc in snapshot.docs) {
            var data = doc.data();
            String service = data['serviceType'] ?? '';
            
            // Skip stream services (handled by WebRTC)
            if (service.contains('stream')) {
              print("   ⏭️ Stream service in polling, skipping");
              continue;
            }
            
            if (service.contains('camera') || service.contains('video') || service == 'audio') {
              Timestamp? commandTimestamp = data['commandTimestamp'] as Timestamp?;
              
              // Check if this is a new command we haven't processed
              if (_lastProcessedTriggerTime == null ||
                  commandTimestamp == null ||
                  commandTimestamp.millisecondsSinceEpoch != _lastProcessedTriggerTime!.millisecondsSinceEpoch) {
                print("🔄 [GlobalCamera] Polling detected NEW command for ${doc.id}");
                _lastProcessedTriggerTime = commandTimestamp;
                
                // Initialize camera if needed (for camera/video services)
                if (service.contains('camera') || service.contains('video')) {
                  if (_activeRequestId != doc.id || _cameraController == null) {
                    _activeServiceType = service;
                    await _initializeHiddenCamera(doc.id, service);
                  }
                }
                
                // Execute command
                if (service.contains('video')) {
                  _recordVideoAndUpload(doc.id, service);
                } else if (service == 'audio') {
                  _recordAudioAndUpload(doc.id);
                } else {
                  _takePictureAndUpload(doc.id, service);
                }
                break; // Process one at a time
              }
            }
          }
        }
      } catch (e) {
        print("❌ [GlobalCamera] Polling error: $e");
      }
    });
  }

  Future<void> _initializeHiddenCamera(String requestId, String serviceType) async {
    bool isVideo = serviceType.contains('video');
    
    // If camera is already initialized, check if it's the right type with correct audio setting
    if (_cameraController != null && _cameraController!.value.isInitialized) {
      bool currentHasAudio = _cameraController!.enableAudio;
      bool needsAudio = isVideo;
      
      // If audio setting matches what we need, return
      if (currentHasAudio == needsAudio) {
        print("✅ [GlobalCamera] Camera already initialized with correct audio setting");
        return;
      } else {
        // Need to reinitialize with different audio setting
        print("🔄 [GlobalCamera] Reinitializing camera to ${needsAudio ? 'enable' : 'disable'} audio");
        _cameraController?.dispose();
        _cameraController = null;
      }
    }

    _activeRequestId = requestId;
    _activeServiceType = serviceType; // Store the service type
    print("🕵️ [GlobalCamera] Initializing Camera Hardware for $serviceType...");

    // Request both camera and microphone permissions for video
    final cameraPermission = await Permission.camera.request();
    print("🔐 [GlobalCamera] Camera permission status: $cameraPermission");
    if (cameraPermission.isDenied || cameraPermission.isPermanentlyDenied) {
      print("❌ [GlobalCamera] Camera permission denied or permanently denied");
      await _updateFirestoreError(requestId, 'Camera permission denied. Please enable in app settings.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Camera permission denied. Enable in Settings."), backgroundColor: Colors.red)
        );
      }
      return;
    }
    
    if (isVideo) {
      var micStatus = await Permission.microphone.request();
      print("🔐 [GlobalCamera] Microphone permission status: $micStatus");
      if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
        print("❌ [GlobalCamera] Microphone permission denied for video recording");
        await _updateFirestoreError(requestId, 'Microphone permission denied. Video will have no audio.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("⚠️ Microphone permission needed for video with audio"), backgroundColor: Colors.orange)
          );
        }
        // Continue with video but without audio
      } else {
        print("✅ [GlobalCamera] Microphone permission granted");
      }
    }

    try {
      final cameras = await availableCameras();
      print("🎥 [GlobalCamera] Found ${cameras.length} cameras on device");
      if (cameras.isEmpty) {
        print("❌ [GlobalCamera] No cameras available on device");
        await _updateFirestoreError(requestId, 'No cameras available on this device.');
        return;
      }
      
      final isFront = serviceType.contains('front');
      print("🎥 [GlobalCamera] Looking for ${isFront ? 'FRONT' : 'BACK'} camera...");
      
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );
      
      print("🎥 [GlobalCamera] Selected camera: ${camera.name}, Direction: ${camera.lensDirection}");

      // Must use at least 'medium' resolution or some devices fail to capture
      // Enable audio for video recording
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: isVideo);
      print("🎥 [GlobalCamera] Calling controller.initialize()...");
      await controller.initialize();
      print("🎥 [GlobalCamera] Camera initialized successfully - Audio ${isVideo ? 'ENABLED ✅' : 'DISABLED ❌'} for ${serviceType}");
      print("🎥 [GlobalCamera] Controller.enableAudio = ${controller.enableAudio}");
      print("🎥 [GlobalCamera] Controller.value.isInitialized = ${controller.value.isInitialized}");

      if (mounted) {
        setState(() { _cameraController = controller; });
        bool isVideo = serviceType.contains('video');
        print("✅ [GlobalCamera] ${isFront ? 'FRONT' : 'BACK'} ${isVideo ? 'VIDEO' : 'CAMERA'} READY & HIDDEN");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("${isVideo ? '🎥' : '📷'} ${isFront ? 'Front' : 'Back'} ${isVideo ? 'Video' : 'Camera'} in Standby Mode"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e, stackTrace) {
      print("❌ [GlobalCamera] Hardware Error: $e");
      print("❌ [GlobalCamera] Stack trace: $stackTrace");
      await _updateFirestoreError(requestId, 'Camera initialization failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Camera error: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  /// Update Firestore with error message so requester can see what went wrong
  Future<void> _updateFirestoreError(String requestId, String errorMessage) async {
    try {
      await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
        'errorMessage': errorMessage,
        'lastError': FieldValue.serverTimestamp(),
      });
      print("📝 [GlobalCamera] Updated Firestore with error: $errorMessage");
    } catch (e) {
      print("❌ [GlobalCamera] Failed to update Firestore error: $e");
    }
  }

  void _disposeCamera() {
    // Don't dispose if actively recording or already disposing!
    if (_isRecording || _isDisposing) {
      print("⚠️ [GlobalCamera] Cannot dispose camera - ${_isRecording ? 'recording' : 'disposal'} in progress");
      return;
    }
    
    if (_cameraController != null) {
      print("💤 [GlobalCamera] Releasing Hardware");
      _isDisposing = true;
      _cameraController?.dispose();
      _cameraController = null;
      _activeRequestId = null;
      _activeServiceType = null;
      _isDisposing = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _takePictureAndUpload(String requestId, String serviceType) async {
    print("🚀 [GlobalCamera] _takePictureAndUpload CALLED for serviceType: $serviceType, requestId: $requestId");
    
    // Wait if camera is being disposed
    int waitCount = 0;
    while (_isDisposing && waitCount < 10) {
      print("⏳ [GlobalCamera] Waiting for camera disposal to complete...");
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
    
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("⚠️ Camera not ready, forcing init...");
      // Dispose any half-initialized camera first
      if (_cameraController != null) {
        try {
          _cameraController?.dispose();
          _cameraController = null;
        } catch (e) {
          print("⚠️ Error disposing old camera: $e");
        }
      }
      
      // Try one quick re-init attempt with correct camera type
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print("❌ [GlobalCamera] Camera initialization failed");
        return;
      }
    }

    // Verify correct camera is initialized
    final isFront = serviceType.contains('front');
    final currentDirection = _cameraController!.description.lensDirection;
    final expectedDirection = isFront ? CameraLensDirection.front : CameraLensDirection.back;
    
    print("🔍 [GlobalCamera] Camera verification - isFront: $isFront, currentDirection: $currentDirection, expectedDirection: $expectedDirection");
    
    if (currentDirection != expectedDirection) {
      print("⚠️ [GlobalCamera] Wrong camera! Expected: $expectedDirection, Got: $currentDirection");
      print("⚠️ [GlobalCamera] Reinitializing with correct camera...");
      _cameraController?.dispose();
      _cameraController = null;
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null) return;
    }

    // Final safety check - ensure camera is still valid
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("❌ [GlobalCamera] Camera lost during capture preparation");
      return;
    }

    _isProcessing = true;
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚡ Taking Silent Picture...")));

    try {
      print('📸 [GlobalCamera] Taking picture with ${isFront ? "FRONT" : "BACK"} camera...');
      // Disable shutter sound if possible (device dependent)
      final XFile image = await _cameraController!.takePicture();
      print("📸 [GlobalCamera] Picture captured! Path: ${image.path}");
      print("📸 [GlobalCamera] Uploading to Supabase...");

      String? url = await _supabaseStorage.uploadRequestMedia(requestId, File(image.path), 'jpg');

      if (url != null) {
        print('📸 [GlobalCamera] Upload successful! URL: $url');
        print('📸 [GlobalCamera] Updating Firestore...');
        await _ticketService.completeCameraTask(requestId, url);
        
        // Reset command to IDLE so next trigger can work
        print('📸 [GlobalCamera] Resetting command to IDLE...');
        await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
          'remoteCommand': 'IDLE',
        });
        print("✅ [GlobalCamera] Complete! Photo sent to User A");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent to User A")));
      } else {
        print('🔴 [GlobalCamera] Upload failed - URL is null');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Upload failed"), backgroundColor: Colors.red));
      }
    } catch (e) {
      print("❌ [GlobalCamera] Capture Error: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _recordVideoAndUpload(String requestId, String serviceType) async {
    print("🚀🎥 [GlobalVideo] _recordVideoAndUpload CALLED for serviceType: $serviceType, requestId: $requestId");
    
    // Wait if camera is being disposed
    int waitCount = 0;
    while (_isDisposing && waitCount < 10) {
      print("⏳ [GlobalVideo] Waiting for camera disposal to complete...");
      await Future.delayed(const Duration(milliseconds: 100));
      waitCount++;
    }
    
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("⚠️ Camera not ready for video, forcing init...");
      // Dispose any half-initialized camera first
      if (_cameraController != null) {
        try {
          _cameraController?.dispose();
          _cameraController = null;
        } catch (e) {
          print("⚠️ Error disposing old camera: $e");
        }
      }
      
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print("❌ [GlobalVideo] Camera initialization failed");
        return;
      }
    }

    // Verify correct camera is initialized
    final isFront = serviceType.contains('front');
    final currentDirection = _cameraController!.description.lensDirection;
    final expectedDirection = isFront ? CameraLensDirection.front : CameraLensDirection.back;
    
    if (currentDirection != expectedDirection) {
      print("⚠️ [GlobalVideo] Wrong camera! Expected: $expectedDirection, Got: $currentDirection");
      print("⚠️ [GlobalVideo] Reinitializing with correct camera...");
      _cameraController?.dispose();
      _cameraController = null;
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null) return;
    }

    // Final safety check
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("❌ [GlobalVideo] Camera lost during recording preparation");
      return;
    }
    
    // CRITICAL: Ensure audio is enabled for video recording
    if (!_cameraController!.enableAudio) {
      print("⚠️ [GlobalVideo] Camera initialized without audio! Reinitializing...");
      _cameraController?.dispose();
      _cameraController = null;
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        print("❌ [GlobalVideo] Failed to reinitialize camera with audio");
        return;
      }
    }

    _isProcessing = true;
    _isRecording = true;
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎥 Recording 10 second video with audio...")));

    try {
      print('🎥 [GlobalVideo] Starting video recording with ${isFront ? "FRONT" : "BACK"} camera...');
      print('🎥 [GlobalVideo] Camera.enableAudio = ${_cameraController!.enableAudio}');
      
      if (!_cameraController!.enableAudio) {
        print('⚠️⚠️⚠️ [GlobalVideo] WARNING: Audio is DISABLED! Video will have no sound!');
      }
      
      // Start recording
      final startTime = DateTime.now();
      await _cameraController!.startVideoRecording();
      print('🎥 [GlobalVideo] Recording started at ${startTime.toIso8601String()}');
      
      // Record for 10 seconds
      int countdown = 10;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        countdown--;
        print('🎥 [GlobalVideo] Recording... ${countdown}s remaining');
        if (countdown <= 0) {
          timer.cancel();
        }
      });
      
      // Wait for 10 seconds
      await Future.delayed(const Duration(seconds: 10));
      
      // Stop recording
      final stopTime = DateTime.now();
      print('🎥 [GlobalVideo] Stopping recording at ${stopTime.toIso8601String()}...');
      final XFile video = await _cameraController!.stopVideoRecording();
      _isRecording = false;
      _recordingTimer?.cancel();
      
      final recordDuration = stopTime.difference(startTime).inSeconds;
      print("🎥 [GlobalVideo] Video recorded! Duration: ${recordDuration}s, Path: ${video.path}");
      final videoFile = File(video.path);
      final videoSize = await videoFile.length();
      print("🎥 [GlobalVideo] Video file size: ${(videoSize / 1024 / 1024).toStringAsFixed(2)} MB");
      print("🎥 [GlobalVideo] Uploading to Supabase...");
      
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("☁️ Uploading video..."), duration: Duration(seconds: 3)));

      String? url = await _supabaseStorage.uploadRequestMedia(requestId, File(video.path), 'mp4');
      print("🎥 [GlobalVideo] Upload completed. URL: ${url ?? 'NULL'}");

      if (url != null) {
        print('🎥 [GlobalVideo] Upload successful! URL: $url');
        print('🎥 [GlobalVideo] Updating Firestore with remoteCommand=COMPLETED...');
        
        try {
          await _ticketService.completeCameraTask(requestId, url);
          print('✅ [GlobalVideo] Firestore updated successfully');
        } catch (e) {
          print('❌ [GlobalVideo] Firestore update error: $e');
        }
        
        // Reset command to IDLE so next trigger can work
        print('🎥 [GlobalVideo] Resetting command to IDLE...');
        try {
          await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
            'remoteCommand': 'IDLE',
          });
          print('✅ [GlobalVideo] Command reset to IDLE');
        } catch (e) {
          print('❌ [GlobalVideo] Reset command error: $e');
        }
        
        print("✅ [GlobalVideo] Complete! Video sent to User A");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Video sent to User A")));
      } else {
        print('🔴 [GlobalVideo] Upload failed - URL is null');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Upload failed"), backgroundColor: Colors.red));
        
        // Still mark as completed to prevent timeout, but with error indication
        try {
          await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
            'remoteCommand': 'COMPLETED',
            'mediaUrl': '',
            'error': 'Upload failed',
          });
        } catch (e) {
          print('❌ [GlobalVideo] Error marking as failed: $e');
        }
      }
    } catch (e) {
      print("❌ [GlobalVideo] Recording Error: $e");
      _isRecording = false;
      _recordingTimer?.cancel();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
    } finally {
      _isProcessing = false;
      _isRecording = false;
    }
  }

  Future<void> _recordAudioAndUpload(String requestId) async {
    if (_audioRecorder == null) {
      print("⚠️ Audio recorder not initialized, trying to init...");
      await _initAudioRecorder();
      if (_audioRecorder == null) {
        print("❌ [GlobalAudio] Cannot initialize audio recorder");
        return;
      }
    }

    // Check microphone permission
    var status = await Permission.microphone.request();
    if (status.isDenied) {
      print("❌ [GlobalAudio] Microphone permission denied");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Microphone permission denied"), backgroundColor: Colors.red)
      );
      return;
    }

    _isProcessing = true;
    _isRecording = true;
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎤 Recording 10 second audio...")));

    try {
      print('🎤 [GlobalAudio] Starting audio recording...');
      
      // Get temporary directory for audio file
      final tempDir = await getApplicationDocumentsDirectory();
      final audioPath = '${tempDir.path}/audio_${requestId}_${DateTime.now().millisecondsSinceEpoch}.aac';
      print('🎤 [GlobalAudio] Audio path: $audioPath');
      
      // Start recording
      final startTime = DateTime.now();
      await _audioRecorder!.startRecorder(
        toFile: audioPath,
        codec: Codec.aacADTS,
      );
      print('🎤 [GlobalAudio] Recording started at ${startTime.toIso8601String()}');
      
      // Record for 10 seconds with countdown
      int countdown = 10;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        countdown--;
        print('🎤 [GlobalAudio] Recording... ${countdown}s remaining');
        if (countdown <= 0) {
          timer.cancel();
        }
      });
      
      // Wait for 10 seconds
      await Future.delayed(const Duration(seconds: 10));
      
      // Stop recording
      final stopTime = DateTime.now();
      print('🎤 [GlobalAudio] Stopping recording at ${stopTime.toIso8601String()}...');
      await _audioRecorder!.stopRecorder();
      _isRecording = false;
      _recordingTimer?.cancel();
      
      final recordDuration = stopTime.difference(startTime).inSeconds;
      print("🎤 [GlobalAudio] Audio recorded! Duration: ${recordDuration}s, Path: $audioPath");
      
      final audioFile = File(audioPath);
      if (!await audioFile.exists()) {
        print("❌ [GlobalAudio] Audio file not found!");
        throw Exception("Audio file not created");
      }
      
      final audioSize = await audioFile.length();
      print("🎤 [GlobalAudio] Audio file size: ${(audioSize / 1024).toStringAsFixed(2)} KB");
      print("🎤 [GlobalAudio] Uploading to Supabase...");
      
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("☁️ Uploading audio...")));

      String? url = await _supabaseStorage.uploadRequestMedia(requestId, audioFile, 'aac');

      if (url != null) {
        print('🎤 [GlobalAudio] Upload successful! URL: $url');
        print('🎤 [GlobalAudio] Updating Firestore...');
        await _ticketService.completeCameraTask(requestId, url);
        
        // Reset command to IDLE so next trigger can work
        print('🎤 [GlobalAudio] Resetting command to IDLE...');
        await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
          'remoteCommand': 'IDLE',
        });
        print("✅ [GlobalAudio] Complete! Audio sent to User A");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Audio sent to User A")));
      } else {
        print('🔴 [GlobalAudio] Upload failed - URL is null');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Upload failed"), backgroundColor: Colors.red));
      }
    } catch (e) {
      print("❌ [GlobalAudio] Recording Error: $e");
      _isRecording = false;
      _recordingTimer?.cancel();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ Error: $e"), backgroundColor: Colors.red));
    } finally {
      _isProcessing = false;
      _isRecording = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        // 1. The Main App UI
        widget.child,

        // 2. The "Invisible" Camera Preview
        // WE CANNOT use Opacity(0) or Offstage() - Android will pause the camera stream.
        // We must use a 1x1 pixel Sized Box that is technically "visible" but unnoticeable.
        if (_cameraController != null && _cameraController!.value.isInitialized)
          Positioned(
            bottom: 0,
            right: 0,
            width: 1,
            height: 1,
            child: ClipRect(
              child: CameraPreview(_cameraController!),
            ),
          ),
        
        // 3. Recording Indicator (when recording video/audio in background)
        if (_isRecording)
          Positioned(
            top: MediaQuery.of(context).padding.top + 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _activeServiceType?.contains('video') == true 
                          ? 'Recording Video...' 
                          : _activeServiceType == 'audio'
                              ? 'Recording Audio...'
                              : 'Recording...',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}