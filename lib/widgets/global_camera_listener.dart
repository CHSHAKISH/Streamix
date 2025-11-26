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
  Timer? _recordingTimer;
  Timer? _pollingTimer; // Backup polling mechanism

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_currentUserId.isNotEmpty) {
      _initAudioRecorder();
      _listenForActiveRequests();
      _startBackupPolling(); // Start backup polling every 3 seconds
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _cameraController?.dispose();
    } else if (state == AppLifecycleState.resumed && _activeRequestId != null && _activeServiceType != null) {
      // Re-awaken camera with the correct camera type
      _initializeHiddenCamera(_activeRequestId!, _activeServiceType!);
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
            print("⚡ [GlobalCamera] NEW COMMAND RECEIVED");
            _lastProcessedTriggerTime = commandTimestamp;
            
            // Route to photo, video, or audio based on service type
            if (serviceType.contains('video')) {
              _recordVideoAndUpload(doc.id, serviceType);
            } else if (serviceType == 'audio') {
              _recordAudioAndUpload(doc.id);
            } else {
              _takePictureAndUpload(doc.id, serviceType);
            }
          } else {
            print("⏭️ [GlobalCamera] Already processed this command");
          }
        }

      } else {
        _disposeCamera();
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
    if (_cameraController != null && _cameraController!.value.isInitialized) return;

    _activeRequestId = requestId;
    _activeServiceType = serviceType; // Store the service type
    print("🕵️ [GlobalCamera] Initializing Camera Hardware for $serviceType...");

    if (await Permission.camera.request().isDenied) return;

    try {
      final cameras = await availableCameras();
      final isFront = serviceType.contains('front');
      print("🎥 [GlobalCamera] Looking for ${isFront ? 'FRONT' : 'BACK'} camera...");
      
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );
      
      print("🎥 [GlobalCamera] Selected camera: ${camera.name}, Direction: ${camera.lensDirection}");

      // Must use at least 'medium' resolution or some devices fail to capture
      // Enable audio for video recording
      bool isVideo = serviceType.contains('video');
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: isVideo);
      await controller.initialize();
      print("🎥 [GlobalCamera] Audio ${isVideo ? 'ENABLED' : 'DISABLED'} for ${serviceType}");

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
    } catch (e) {
      print("❌ [GlobalCamera] Hardware Error: $e");
    }
  }

  void _disposeCamera() {
    // Don't dispose if actively recording!
    if (_isRecording) {
      print("⚠️ [GlobalCamera] Cannot dispose camera - recording in progress");
      return;
    }
    
    if (_cameraController != null) {
      print("💤 [GlobalCamera] Releasing Hardware");
      _cameraController?.dispose();
      _cameraController = null;
      _activeRequestId = null;
      _activeServiceType = null;
      if (mounted) setState(() {});
    }
  }

  Future<void> _takePictureAndUpload(String requestId, String serviceType) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("⚠️ Camera not ready, forcing init...");
      // Try one quick re-init attempt with correct camera type
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null) return;
    }

    // Verify correct camera is initialized
    final isFront = serviceType.contains('front');
    final currentDirection = _cameraController!.description.lensDirection;
    final expectedDirection = isFront ? CameraLensDirection.front : CameraLensDirection.back;
    
    if (currentDirection != expectedDirection) {
      print("⚠️ [GlobalCamera] Wrong camera! Expected: $expectedDirection, Got: $currentDirection");
      print("⚠️ [GlobalCamera] Reinitializing with correct camera...");
      _cameraController?.dispose();
      _cameraController = null;
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null) return;
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      print("⚠️ Camera not ready for video, forcing init...");
      await _initializeHiddenCamera(requestId, serviceType);
      await Future.delayed(const Duration(seconds: 1));
      if (_cameraController == null) return;
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

    _isProcessing = true;
    _isRecording = true;
    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("🎥 Recording 10 second video...")));

    try {
      print('🎥 [GlobalVideo] Starting video recording with ${isFront ? "FRONT" : "BACK"} camera...');
      print('🎥 [GlobalVideo] Camera audio enabled: ${_cameraController!.enableAudio}');
      
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
      
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("☁️ Uploading video...")));

      String? url = await _supabaseStorage.uploadRequestMedia(requestId, File(video.path), 'mp4');

      if (url != null) {
        print('🎥 [GlobalVideo] Upload successful! URL: $url');
        print('🎥 [GlobalVideo] Updating Firestore...');
        await _ticketService.completeCameraTask(requestId, url);
        
        // Reset command to IDLE so next trigger can work
        print('🎥 [GlobalVideo] Resetting command to IDLE...');
        await FirebaseFirestore.instance.collection('requests').doc(requestId).update({
          'remoteCommand': 'IDLE',
        });
        print("✅ [GlobalVideo] Complete! Video sent to User A");
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Video sent to User A")));
      } else {
        print('🔴 [GlobalVideo] Upload failed - URL is null');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("❌ Upload failed"), backgroundColor: Colors.red));
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