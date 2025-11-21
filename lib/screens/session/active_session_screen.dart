import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:camera/camera.dart';
import 'package:streamix/services/location_service.dart';
import 'package:streamix/services/supabase_storage_service.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/services/signaling_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

class ActiveSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType;
  final int durationInSeconds;
  final DateTime scheduledStartTime; // --- NEW PARAMETER ---

  const ActiveSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
    required this.durationInSeconds,
    required this.scheduledStartTime,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final LocationService _locationService = LocationService();
  final TicketService _ticketService = TicketService();
  final SignalingService _signalingService = SignalingService();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();

  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _audioPath;

  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isSharing = false;
  Timer? _sessionTimer;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isStreaming = false;
  StreamSubscription? _sessionSub;
  StreamSubscription? _candidateSub;
  bool _isMuted = false;
  List<RTCIceCandidate> _candidateQueue = [];
  bool _isRemoteDescriptionSet = false;

  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String _autoCaptureStatus = "Initializing Camera...";
  bool _isUploading = false;

  // --- NEW: WAITING STATE ---
  bool _isWaitingForStartTime = true;
  Timer? _startCountdownTimer;
  String _waitMessage = "Checking schedule...";

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:stun.services.mozilla.com'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();
    _checkSchedule();
  }

  // --- AUTOMATION LOGIC ---
  void _checkSchedule() {
    final now = DateTime.now();

    // If current time is BEFORE start time, wait.
    if (now.isBefore(widget.scheduledStartTime)) {
      final waitDuration = widget.scheduledStartTime.difference(now);
      setState(() {
        _isWaitingForStartTime = true;
        _waitMessage = "Session starts in ${waitDuration.inMinutes}m ${waitDuration.inSeconds % 60}s";
      });

      // Update UI every second
      _startCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        final timeLeft = widget.scheduledStartTime.difference(DateTime.now());
        if (timeLeft.isNegative) {
          timer.cancel();
          _launchService(); // START NOW
        } else {
          if (mounted) {
            setState(() {
              _waitMessage = "Session starts in ${timeLeft.inHours}h ${timeLeft.inMinutes % 60}m ${timeLeft.inSeconds % 60}s";
            });
          }
        }
      });
    } else {
      // Start immediately
      _launchService();
    }
  }

  void _launchService() {
    if (!mounted) return;
    setState(() {
      _isWaitingForStartTime = false;
    });

    if (widget.serviceType.contains('stream')) {
      _initRenderers().then((_) => _startVideoStream());
    }
    if (widget.serviceType == 'audio') {
      _initAudioRecorder();
    }
    if (widget.serviceType.contains('camera')) {
      _initCameraAndAutoCapture(); // Triggers 3-2-1 Capture
    }
    if (widget.serviceType == 'location') {
      _startLocationSharing(); // Auto-start location
    }
  }
  // -----------------------

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _sessionTimer?.cancel();
    _startCountdownTimer?.cancel(); // Cancel wait timer
    _sessionSub?.cancel();
    _candidateSub?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _audioRecorder.closeRecorder();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    if (mounted) setState(() {});
  }

  void _toggleMute() {
    if (_localStream == null) return;
    final audioTracks = _localStream!.getAudioTracks();
    if (audioTracks.isNotEmpty) {
      bool newState = !_isMuted;
      audioTracks[0].enabled = !newState;
      setState(() { _isMuted = newState; });
    }
  }

  Future<void> _startVideoStream() async {
    try {
      await [Permission.camera, Permission.microphone].request();
      _peerConnection = await createPeerConnection(_iceConfig);

      _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
        _signalingService.addCandidate(widget.requestId, candidate, false);
      };

      final facingMode = widget.serviceType == 'front_stream' ? 'user' : 'environment';
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': true,
        'video': {'facingMode': facingMode, 'width': 640, 'height': 480}
      });

      _localRenderer.srcObject = _localStream;
      _localStream?.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });

      RTCSessionDescription offer = await _peerConnection!.createOffer();
      await _peerConnection!.setLocalDescription(offer);
      await _signalingService.createOffer(widget.requestId, offer);

      _sessionSub = _signalingService.getSessionStream(widget.requestId).listen((doc) async {
        if (doc.exists) {
          var data = doc.data() as Map<String, dynamic>;
          if (data['answer'] != null && _peerConnection?.getRemoteDescription() == null) {
            var answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
            await _peerConnection?.setRemoteDescription(answer);

            _isRemoteDescriptionSet = true;
            for (var candidate in _candidateQueue) {
              await _peerConnection?.addCandidate(candidate);
            }
            _candidateQueue.clear();
          }
        }
      });

      _candidateSub = _signalingService.getCandidateStream(widget.requestId, false).listen((snapshot) async {
        for (var change in snapshot.docChanges) {
          if (change.type == DocumentChangeType.added) {
            var data = change.doc.data() as Map<String, dynamic>;
            var candidate = RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']);
            if (_isRemoteDescriptionSet && _peerConnection != null) {
              await _peerConnection?.addCandidate(candidate);
            } else {
              _candidateQueue.add(candidate);
            }
          }
        }
      });

      if (mounted) setState(() { _isStreaming = true; });
      _startSessionTimer();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Stream Error: $e"), backgroundColor: Colors.red));
    }
  }

  Future<void> _stopVideoStream() async {
    _sessionTimer?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    await _localStream?.dispose();
    await _peerConnection?.close();
    await _peerConnection?.dispose();
    _sessionSub?.cancel();
    _candidateSub?.cancel();
    await _ticketService.completeRequest(widget.requestId);
    setState(() { _isStreaming = false; });
    if (mounted) Navigator.pop(context);
  }

  Future<void> _initCameraAndAutoCapture() async {
    var status = await Permission.camera.request();
    if (status.isDenied) {
      if (mounted) setState(() => _autoCaptureStatus = "Camera permission denied");
      return;
    }

    try {
      final cameras = await availableCameras();
      final isFront = widget.serviceType == 'front_camera';
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(camera, ResolutionPreset.high, enableAudio: false);
      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _autoCaptureStatus = "Ready. Capturing in 3 seconds...";
      });
      _performAutoCapture();
    } catch (e) {
      if (mounted) setState(() => _autoCaptureStatus = "Error: $e");
    }
  }

  Future<void> _performAutoCapture() async {
    for (int i = 3; i > 0; i--) {
      if (!mounted) return;
      setState(() => _autoCaptureStatus = "Capturing in $i...");
      await Future.delayed(const Duration(seconds: 1));
    }
    if (!mounted) return;
    setState(() => _autoCaptureStatus = "Capturing now!");

    try {
      final XFile image = await _cameraController!.takePicture();
      _uploadMedia(File(image.path), 'jpg', 'Image');
    } catch (e) {
      setState(() => _autoCaptureStatus = "Capture failed: $e");
    }
  }

  Future<void> _uploadMedia(File file, String ext, String typeName) async {
    setState(() { _isUploading = true; });
    String? downloadUrl = await _supabaseStorage.uploadRequestMedia(widget.requestId, file, ext);

    if (downloadUrl != null) {
      await _ticketService.updateRequestMedia(widget.requestId, downloadUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$typeName sent successfully!')));
        setState(() { _isUploading = false; _autoCaptureStatus = "Sent! You can close this screen."; });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error uploading $typeName.')));
        setState(() { _isUploading = false; });
      }
    }
  }

  Future<void> _initAudioRecorder() async {
    await _audioRecorder.openRecorder();
  }

  void _startSessionTimer() {
    _sessionTimer?.cancel();
    _sessionTimer = Timer(Duration(seconds: widget.durationInSeconds), () {
      _autoStopSession();
    });
  }

  void _autoStopSession() {
    if (widget.serviceType == 'location' && _isSharing) {
      _stopLocationSharing();
    } else if (widget.serviceType.contains('stream') && _isStreaming) {
      _stopVideoStream();
    } else if (widget.serviceType == 'audio' && _isRecording) {
      _stopAudioRecording();
    }
  }

  String _formatDurationForDisplay() {
    final int minutes = (widget.durationInSeconds / 60).floor();
    final int seconds = widget.durationInSeconds % 60;
    return "$minutes min ${seconds} sec";
  }

  Future<void> _startLocationSharing() async {
    var status = await Permission.location.request();
    if (status.isDenied) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location permission is required.')));
      return;
    }
    await _location.changeSettings(accuracy: LocationAccuracy.high);
    _locationSubscription = _location.onLocationChanged.listen((LocationData newLocation) {
      _locationService.updateSenderLocation(widget.requestId, newLocation);
    });
    setState(() { _isSharing = true; });
    _startSessionTimer();
  }

  Future<void> _stopLocationSharing() async {
    _sessionTimer?.cancel();
    _locationSubscription?.cancel();
    await _ticketService.completeRequest(widget.requestId);
    await _locationService.deleteSenderLocation(widget.requestId);
    setState(() { _isSharing = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location sharing stopped.')));
      Navigator.pop(context);
    }
  }

  Future<void> _handleVideoSample(String serviceType) async {
    // Kept manual for video sample as video usually needs explicit start/stop interaction
    final camera = serviceType == 'front_video' ? CameraDevice.front : CameraDevice.rear;
    var camStatus = await Permission.camera.request();
    var micStatus = await Permission.microphone.request();
    if (camStatus.isDenied || micStatus.isDenied) return;

    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(source: ImageSource.camera, preferredCameraDevice: camera, maxDuration: Duration(seconds: widget.durationInSeconds));
    if (video != null) {
      _uploadMedia(File(video.path), 'mp4', 'Video');
    }
  }

  Future<void> _startAudioRecording() async {
    var status = await Permission.microphone.request();
    if (status.isDenied) return;
    final tempDir = await getTemporaryDirectory();
    _audioPath = '${tempDir.path}/streamix_audio.aac';
    await _audioRecorder.startRecorder(toFile: _audioPath, codec: Codec.aacADTS);
    setState(() { _isRecording = true; });
    _startSessionTimer();
  }

  Future<void> _stopAudioRecording() async {
    await _audioRecorder.stopRecorder();
    _sessionTimer?.cancel();
    setState(() { _isRecording = false; });
    if (_audioPath != null) {
      _uploadMedia(File(_audioPath!), 'aac', 'Audio');
    }
  }

  Widget _buildTaskWidget() {
    // --- NEW: WAITING SCREEN ---
    if (_isWaitingForStartTime) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              _waitMessage,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text("Please keep this screen open.", style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_isUploading) {
      return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 20), Text('Uploading automatically...', textAlign: TextAlign.center)]));
    }

    switch (widget.serviceType) {
      case 'location':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.location_on, size: 80, color: Colors.red),
            const SizedBox(height: 20),
            const Text("Sharing Location Automatically", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (_isSharing)
              Padding(padding: const EdgeInsets.only(top: 20), child: Text('Live for ${_formatDurationForDisplay()}', textAlign: TextAlign.center)),
          ],
        );

      case 'front_camera':
      case 'back_camera':
        if (!_isCameraInitialized || _cameraController == null) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text(_autoCaptureStatus)]));
        }
        return Column(
          children: [
            Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: CameraPreview(_cameraController!))),
            const SizedBox(height: 16),
            Text(_autoCaptureStatus, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red), textAlign: TextAlign.center),
            const SizedBox(height: 16),
          ],
        );

      case 'front_video':
      case 'back_video':
        return Center(child: ElevatedButton.icon(icon: const Icon(Icons.videocam), label: const Text('Record Video'), onPressed: () => _handleVideoSample(widget.serviceType)));

      case 'audio':
        return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [Icon(_isRecording ? Icons.mic : Icons.mic_none, size: 80, color: _isRecording ? Colors.red : Colors.grey), const SizedBox(height: 20), ElevatedButton.icon(icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow), label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'), onPressed: _isRecording ? _stopAudioRecording : _startAudioRecording)]));

      case 'front_stream':
      case 'back_stream':
        return Stack(
          children: [
            Container(color: Colors.black, width: double.infinity, height: double.infinity, child: RTCVideoView(_localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
            Positioned(
              bottom: 30, right: 30,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(heroTag: "mute_btn", onPressed: _toggleMute, backgroundColor: _isMuted ? Colors.red : Colors.white, child: Icon(_isMuted ? Icons.mic_off : Icons.mic, color: _isMuted ? Colors.white : Colors.black)),
                  const SizedBox(height: 16),
                  FloatingActionButton(heroTag: "stop_btn", onPressed: _stopVideoStream, backgroundColor: Colors.red, child: const Icon(Icons.stop, color: Colors.white)),
                ],
              ),
            ),
            if (_isStreaming)
              Positioned(top: 10, left: 0, right: 0, child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)), child: Text('LIVE: ${_formatDurationForDisplay()}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
          ],
        );

      default:
        return Text('Unknown service: ${widget.serviceType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Active: ${widget.serviceType}')),
      body: Padding(padding: const EdgeInsets.all(20.0), child: _buildTaskWidget()),
    );
  }
}