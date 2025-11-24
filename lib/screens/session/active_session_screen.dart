import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_camera', 'back_camera', or 'audio'

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

  // Audio Controller
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();

  // Camera Controller
  CameraController? _cameraController;

  // State
  bool _isInitialized = false;
  bool _isUploading = false;
  String _statusMessage = "Initializing...";
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _routeService();
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  void _routeService() {
    if (widget.serviceType == 'audio') {
      _startAudioSequence();
    } else if (widget.serviceType.contains('camera')) {
      _startCameraSequence();
    }
  }

  // =========================================================
  // 🎙️ AUDIO LOGIC (Auto Record 10s)
  // =========================================================
  Future<void> _startAudioSequence() async {
    var status = await Permission.microphone.request();
    if (status.isDenied) {
      setState(() => _statusMessage = "Microphone Permission Denied");
      return;
    }

    try {
      await _audioRecorder.openRecorder();
      if (!mounted) return;

      setState(() {
        _isInitialized = true;
        _statusMessage = "Recording... 10s";
        _countdown = 10;
      });

      // Start Recording
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/${widget.requestId}.aac';

      await _audioRecorder.startRecorder(toFile: path);

      // 10 Second Countdown
      Timer.periodic(const Duration(seconds: 1), (timer) async {
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
          await _stopAudioAndUpload(path);
        }
      });

    } catch (e) {
      setState(() => _statusMessage = "Audio Error: $e");
    }
  }

  Future<void> _stopAudioAndUpload(String path) async {
    await _audioRecorder.stopRecorder();

    setState(() {
      _isUploading = true;
      _statusMessage = "Uploading Audio...";
    });

    String? url = await _supabaseStorage.uploadRequestMedia(widget.requestId, File(path), 'aac');
    _finishSession(url);
  }

  // =========================================================
  // 📸 CAMERA LOGIC (Reverted to Working Version)
  // =========================================================
  Future<void> _startCameraSequence() async {
    var status = await Permission.camera.request();
    if (status.isDenied) {
      setState(() => _statusMessage = "Camera Permission Denied");
      return;
    }

    try {
      final cameras = await availableCameras();
      final isFront = widget.serviceType.contains('front');
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _countdown = 3;
        _statusMessage = "Capturing in $_countdown...";
      });

      // 3-2-1 Countdown
      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
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

    } catch (e) {
      setState(() => _statusMessage = "Camera Error: $e");
    }
  }

  Future<void> _takePictureAndUpload() async {
    if (_cameraController == null) return;

    try {
      setState(() => _statusMessage = "Capturing...");
      final XFile image = await _cameraController!.takePicture();

      setState(() {
        _isUploading = true;
        _statusMessage = "Uploading Photo...";
      });

      String? url = await _supabaseStorage.uploadRequestMedia(widget.requestId, File(image.path), 'jpg');
      _finishSession(url);

    } catch (e) {
      setState(() => _statusMessage = "Capture Error: $e");
    }
  }

  // =========================================================
  // 🏁 COMMON FINISH LOGIC
  // =========================================================
  Future<void> _finishSession(String? url) async {
    if (url != null) {
      await _ticketService.completeRequestWithMedia(widget.requestId, url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sent Successfully!")));
        Navigator.pop(context); // AUTO CLOSE
      }
    } else {
      setState(() {
        _isUploading = false;
        _statusMessage = "Upload Failed.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. BACKGROUND CONTENT
          if (widget.serviceType.contains('camera'))
            if (_isInitialized && _cameraController != null)
              Center(child: CameraPreview(_cameraController!))
            else
              const Center(child: CircularProgressIndicator(color: Colors.white))
          else
          // AUDIO UI
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.mic, size: 100, color: Colors.redAccent),
                  const SizedBox(height: 20),
                  if (_isInitialized)
                    const SizedBox(width: 200, child: LinearProgressIndicator(color: Colors.red)),
                ],
              ),
            ),

          // 2. OVERLAY
          Container(color: Colors.black45),

          // 3. STATUS TEXT & COUNTDOWN
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_countdown > 0)
                  Text(
                    "$_countdown",
                    style: const TextStyle(fontSize: 100, color: Colors.white, fontWeight: FontWeight.bold),
                  ),

                const SizedBox(height: 50),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),

                if (_isUploading)
                  const Padding(
                    padding: EdgeInsets.only(top: 20.0),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
              ],
            ),
          ),

          // 4. CLOSE BUTTON (Top Left)
          SafeArea(
            child: Positioned(
              left: 10, top: 10,
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