import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';

class AudioSessionScreen extends StatefulWidget {
  final String requestId;

  const AudioSessionScreen({super.key, required this.requestId});

  @override
  State<AudioSessionScreen> createState() => _AudioSessionScreenState();
}

class _AudioSessionScreenState extends State<AudioSessionScreen> {
  final TicketService _ticketService = TicketService();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();

  bool _isInitialized = false;
  bool _isUploading = false;
  String _statusMessage = "Initializing Mic...";
  int _countdown = 10; // 10 Seconds Duration

  @override
  void initState() {
    super.initState();
    _startAudioSequence();
  }

  @override
  void dispose() {
    _audioRecorder.closeRecorder();
    super.dispose();
  }

  Future<void> _startAudioSequence() async {
    // 1. Permission
    var status = await Permission.microphone.request();
    if (status.isDenied) {
      setState(() => _statusMessage = "Microphone Permission Denied");
      return;
    }

    try {
      // 2. Init Recorder
      await _audioRecorder.openRecorder();

      if (!mounted) return;
      setState(() {
        _isInitialized = true;
        _statusMessage = "Recording... 10s";
      });

      // 3. Start Recording
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/${widget.requestId}.aac';

      await _audioRecorder.startRecorder(toFile: path);

      // 4. Countdown Timer (10s)
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

    // Upload
    String? url = await _supabaseStorage.uploadRequestMedia(widget.requestId, File(path), 'aac');

    // Finish
    if (url != null) {
      await _ticketService.completeRequestWithMedia(widget.requestId, url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Audio Sent Successfully!")));
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
          // Center Visuals
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                    _isUploading ? Icons.cloud_upload : Icons.mic,
                    size: 100,
                    color: _isUploading ? Colors.blue : Colors.redAccent
                ),
                const SizedBox(height: 20),

                // Status Text
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                      color: Colors.grey[900],
                      borderRadius: BorderRadius.circular(30)
                  ),
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 30),

                // Progress Bar
                if (_isInitialized && !_isUploading)
                  SizedBox(
                      width: 200,
                      child: LinearProgressIndicator(
                        value: (10 - _countdown) / 10, // Progress 0.0 to 1.0
                        color: Colors.red,
                        backgroundColor: Colors.grey[800],
                      )
                  ),

                if (_isUploading)
                  const CircularProgressIndicator(color: Colors.white)
              ],
            ),
          ),

          // Close Button
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