import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_camera' or 'back_camera'

  const ActiveSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final TicketService _ticketService = TicketService();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();

  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // State Variables
  int _countdown = 3;
  String _statusMessage = "Initializing Camera...";
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _startAutoSequence();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _startAutoSequence() async {
    // 1. Request Camera Permission
    var status = await Permission.camera.request();
    if (status.isDenied) {
      setState(() => _statusMessage = "Permission Denied");
      return;
    }

    try {
      // 2. Find Correct Camera (Front vs Back)
      final cameras = await availableCameras();
      final isFront = widget.serviceType.contains('front');
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      // 3. Initialize Controller
      _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _statusMessage = "Ready";
      });

      // 4. Start Countdown
      _runCountdown();

    } catch (e) {
      setState(() => _statusMessage = "Camera Error: $e");
    }
  }

  void _runCountdown() {
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown > 1) {
        setState(() {
          _countdown--;
          _statusMessage = "Capturing in $_countdown...";
        });
      } else {
        timer.cancel();
        _takePictureAndUpload();
      }
    });
  }

  Future<void> _takePictureAndUpload() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    try {
      setState(() {
        _statusMessage = "Capturing...";
        _countdown = 0; // Hides countdown text
      });

      // 1. Snap Picture
      final XFile image = await _cameraController!.takePicture();

      // 2. Upload to Supabase
      setState(() {
        _isUploading = true;
        _statusMessage = "Uploading Evidence...";
      });

      String? downloadUrl = await _supabaseStorage.uploadRequestMedia(
          widget.requestId,
          File(image.path),
          'jpg'
      );

      if (downloadUrl != null) {
        // 3. Update Firestore & Finish
        await _ticketService.completeRequestWithMedia(widget.requestId, downloadUrl);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Photo Sent Successfully!")));
          Navigator.pop(context); // CLOSE SCREEN AUTOMATICALLY
        }
      } else {
        setState(() {
          _isUploading = false;
          _statusMessage = "Upload Failed. Please try again.";
        });
      }

    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Camera Preview
          if (_isCameraInitialized)
            Center(child: CameraPreview(_cameraController!))
          else
            const Center(child: CircularProgressIndicator()),

          // 2. Dark Overlay for Text Clarity
          Container(color: Colors.black38),

          // 3. Status & Countdown Text
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isUploading)
                  const CircularProgressIndicator(color: Colors.white)
                else if (_countdown > 0)
                  Text(
                    "$_countdown",
                    style: const TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.bold,
                        color: Colors.white
                    ),
                  ),

                const SizedBox(height: 20),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20)
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ],
            ),
          ),

          // 4. Manual Close Button (Top Left)
          SafeArea(
            child: Positioned(
              left: 16, top: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          )
        ],
      ),
    );
  }
}