import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';

class VideoSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_video' or 'back_video'

  const VideoSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
  });

  @override
  State<VideoSessionScreen> createState() => _VideoSessionScreenState();
}

class _VideoSessionScreenState extends State<VideoSessionScreen> {
  final TicketService _ticketService = TicketService();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();

  CameraController? _cameraController;
  bool _isCameraInitialized = false;

  // State
  bool _isRecording = false;
  bool _isUploading = false;
  bool _videoSent = false; // Shows "Record Again"
  String _statusMessage = "Initializing Camera...";
  int _countdown = 10;

  @override
  void initState() {
    super.initState();
    _startVideoSequence();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _startVideoSequence() async {
    setState(() {
      _statusMessage = "Initializing...";
      _videoSent = false;
      _countdown = 10;
    });

    // 1. Request Permissions (Camera + Mic)
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera]!.isDenied || statuses[Permission.microphone]!.isDenied) {
      setState(() => _statusMessage = "Permissions Denied");
      return;
    }

    try {
      // 2. Setup Camera
      final cameras = await availableCameras();
      final isFront = widget.serviceType.contains('front');
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(camera, ResolutionPreset.high, enableAudio: true);
      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() { _isCameraInitialized = true; });

      // 3. Start Recording Immediately
      await _startRecording();

    } catch (e) {
      setState(() => _statusMessage = "Error: $e");
    }
  }

  Future<void> _startRecording() async {
    try {
      await _cameraController!.startVideoRecording();

      setState(() {
        _isRecording = true;
        _statusMessage = "Recording... 10s";
      });

      // 10s Countdown
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        setState(() {
          _countdown--;
          _statusMessage = "Recording... ${_countdown}s";
        });

        if (_countdown <= 0) {
          timer.cancel();
          _stopRecordingAndUpload();
        }
      });

    } catch (e) {
      setState(() => _statusMessage = "Record Error: $e");
    }
  }

  Future<void> _stopRecordingAndUpload() async {
    if (!_cameraController!.value.isRecordingVideo) return;

    try {
      final XFile video = await _cameraController!.stopVideoRecording();

      setState(() {
        _isRecording = false;
        _isUploading = true;
        _statusMessage = "Uploading Video...";
      });

      // Upload .mp4
      String? url = await _supabaseStorage.uploadRequestMedia(
          widget.requestId,
          File(video.path),
          'mp4'
      );

      if (url != null) {
        await _ticketService.completeRequestWithMedia(widget.requestId, url);

        if (mounted) {
          setState(() {
            _isUploading = false;
            _videoSent = true; // Enables "Record Again"
            _statusMessage = "Video Sent Successfully!";
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video Sent!")));
        }
      } else {
        setState(() {
          _isUploading = false;
          _videoSent = true; // Allow retry
          _statusMessage = "Upload Failed.";
        });
      }

    } catch (e) {
      setState(() => _statusMessage = "Upload Error: $e");
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

          // 2. Overlay
          Container(color: Colors.black45),

          // 3. UI Elements
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Progress Ring
                if (_isRecording)
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      const SizedBox(width: 120, height: 120, child: CircularProgressIndicator(color: Colors.red, strokeWidth: 8)),
                      Text("$_countdown", style: const TextStyle(fontSize: 50, color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),

                const SizedBox(height: 40),

                // Status Message
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                // Uploading
                if (_isUploading)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: CircularProgressIndicator(color: Colors.white),
                  ),

                // RECORD AGAIN BUTTON
                if (_videoSent)
                  Padding(
                    padding: const EdgeInsets.only(top: 40.0),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.videocam),
                      label: const Text("RECORD AGAIN"),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                      ),
                      onPressed: _startVideoSequence, // Restart Loop
                    ),
                  ),

                if (_videoSent)
                  Padding(
                    padding: const EdgeInsets.only(top: 20.0),
                    child: TextButton(
                      child: const Text("Close Session", style: TextStyle(color: Colors.grey, fontSize: 16)),
                      onPressed: () => Navigator.pop(context),
                    ),
                  )
              ],
            ),
          ),

          // 4. Top Left Close
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