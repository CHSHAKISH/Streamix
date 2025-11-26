import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';

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
  StreamSubscription? _requestSubscription;

  String? _activeRequestId;
  String? _activeServiceType; // Store the camera type (front_camera/back_camera)
  Timestamp? _lastProcessedTriggerTime;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_currentUserId.isNotEmpty) {
      _listenForActiveRequests();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _requestSubscription?.cancel();
    _cameraController?.dispose();
    super.dispose();
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
    print("👀 [GlobalCamera] Service Started");
    _requestSubscription = FirebaseFirestore.instance
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {

      final now = DateTime.now();

      var activeDocs = snapshot.docs.where((doc) {
        var data = doc.data();
        String service = data['serviceType'] ?? '';
        if (!service.contains('camera')) return false;

        DateTime startTime = (data['startTime'] as Timestamp).toDate();
        DateTime endTime = (data['endTime'] as Timestamp).toDate();
        return now.isAfter(startTime) && now.isBefore(endTime);
      }).toList();

      if (activeDocs.isNotEmpty) {
        var doc = activeDocs.first;
        var data = doc.data();

        // 1. Wake Camera
        if (_activeRequestId != doc.id || _cameraController == null) {
          _activeServiceType = data['serviceType']; // Store the camera type
          _initializeHiddenCamera(doc.id, data['serviceType']);
        }

        // 2. Check Trigger - Use timestamp to detect new commands
        String command = data['remoteCommand'] ?? 'IDLE';
        Timestamp? commandTimestamp = data['commandTimestamp'] as Timestamp?;
        
        print("🔍 [GlobalCamera] Command: $command, Processing: $_isProcessing, LastTime: $_lastProcessedTriggerTime, NewTime: $commandTimestamp");
        
        if (command == 'REQUEST_CAPTURE' && !_isProcessing) {
          // Check if this is a NEW command (different timestamp)
          if (_lastProcessedTriggerTime == null || 
              commandTimestamp == null ||
              commandTimestamp.millisecondsSinceEpoch != _lastProcessedTriggerTime!.millisecondsSinceEpoch) {
            print("⚡ [GlobalCamera] NEW COMMAND RECEIVED");
            _lastProcessedTriggerTime = commandTimestamp;
            _takePictureAndUpload(doc.id, data['serviceType']); // Pass serviceType to capture
          } else {
            print("⏭️ [GlobalCamera] Already processed this command");
          }
        }

      } else {
        _disposeCamera();
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
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();

      if (mounted) {
        setState(() { _cameraController = controller; });
        print("✅ [GlobalCamera] ${isFront ? 'FRONT' : 'BACK'} CAMERA READY & HIDDEN");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("📷 ${isFront ? 'Front' : 'Back'} Camera in Standby Mode"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      print("❌ [GlobalCamera] Hardware Error: $e");
    }
  }

  void _disposeCamera() {
    if (_cameraController != null) {
      print("💤 [GlobalCamera] Releasing Hardware");
      _cameraController?.dispose();
      _cameraController = null;
      _activeRequestId = null;
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
      ],
    );
  }
}