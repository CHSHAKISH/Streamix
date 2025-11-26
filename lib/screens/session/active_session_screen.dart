import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType; // 'front_camera', 'back_camera', 'front_video', 'back_video', or 'audio'
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

  // Timers
  Timer? _scheduleTimer;

  @override
  void initState() {
    super.initState();
    _checkSchedule();
  }

  @override
  void dispose() {
    _scheduleTimer?.cancel();
    super.dispose();
  }

  // --- 1. SCHEDULE LOGIC ---
  void _checkSchedule() {
    final now = DateTime.now();

    // A. Too Early -> Wait
    if (now.isBefore(widget.scheduledStartTime)) {
      final waitDuration = widget.scheduledStartTime.difference(now);
      setState(() {
        _statusMessage = "Auto-start in ${waitDuration.inMinutes}:${(waitDuration.inSeconds % 60).toString().padLeft(2, '0')}";
      });

      // Update countdown every second until start time
      _scheduleTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final timeLeft = widget.scheduledStartTime.difference(DateTime.now());
        if (timeLeft.isNegative) {
          timer.cancel();
          setState(() {
            _statusMessage = "Camera Ready for Remote Capture";
          });
        } else {
          if (mounted) {
            setState(() {
              _statusMessage = "Auto-start in ${timeLeft.inHours}:${(timeLeft.inMinutes % 60).toString().padLeft(2, '0')}:${(timeLeft.inSeconds % 60).toString().padLeft(2, '0')}";
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
    // C. On Time -> Show standby message for camera/video/audio services
    else {
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
          
          String processingText = isVideo 
              ? "User A viewing file\nRecording 10s video automatically..." 
              : isAudio
                  ? "User A viewing file\nRecording 10s audio automatically..."
                  : "User A viewing file\nTaking photo automatically...";
          
          String successText = isVideo ? "Video Sent!" : isAudio ? "Audio Sent!" : "Photo Sent!";
          
          String detailText = isVideo
              ? "Video sent successfully!\n\nVideo still active.\nUser A can view again anytime.\n\nTap STOP SHARING to end."
              : isAudio
                  ? "Audio sent successfully!\n\nAudio still active.\nUser A can request again anytime.\n\nTap STOP SHARING to end."
                  : "Photo sent successfully!\n\nCamera still active.\nUser A can view again anytime.\n\nTap STOP SHARING to end.";

          return Stack(
            fit: StackFit.expand,
            children: [
              // BLACK BACKGROUND
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