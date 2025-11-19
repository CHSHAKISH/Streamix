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

  const ActiveSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
    required this.durationInSeconds,
  });

  @override
  State<ActiveSessionScreen> createState() => _ActiveSessionScreenState();
}

class _ActiveSessionScreenState extends State<ActiveSessionScreen> {
  final LocationService _locationService = LocationService();
  final TicketService _ticketService = TicketService();
  final SignalingService _signalingService = SignalingService();
  final SupabaseStorageService _supabaseStorage = SupabaseStorageService();

  // Audio
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _audioPath;

  // Location
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isSharing = false;
  Timer? _sessionTimer;

  // WebRTC (Live Streaming)
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isStreaming = false;
  StreamSubscription? _sessionSub;
  StreamSubscription? _candidateSub;
  bool _isMuted = false;

  // --- CAMERA CONTROLLER FOR AUTO CAPTURE ---
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  String _autoCaptureStatus = "Initializing Camera...";

  // Uploading State
  bool _isUploading = false;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();

    // 1. WebRTC Initialization
    if (widget.serviceType.contains('stream')) {
      _initRenderers();
    }

    // 2. Audio Initialization
    if (widget.serviceType == 'audio') {
      _initAudioRecorder();
    }

    // 3. Auto-Capture Initialization
    if (widget.serviceType.contains('camera')) {
      _initCameraAndAutoCapture();
    }
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    _sessionTimer?.cancel();
    _sessionSub?.cancel();
    _candidateSub?.cancel();
    _localStream?.getTracks().forEach((track) => track.stop());
    _localStream?.dispose();
    _peerConnection?.dispose();
    _localRenderer.dispose();
    _audioRecorder.closeRecorder();
    _cameraController?.dispose(); // Dispose camera
    super.dispose();
  }

  // --- AUTO CAPTURE LOGIC ---
  Future<void> _initCameraAndAutoCapture() async {
    var status = await Permission.camera.request();
    if (status.isDenied) {
      if (mounted) setState(() => _autoCaptureStatus = "Camera permission denied");
      return;
    }

    try {
      final cameras = await availableCameras();
      final isFront = widget.serviceType == 'front_camera';

      // Find the correct camera (front or back)
      final camera = cameras.firstWhere(
            (c) => c.lensDirection == (isFront ? CameraLensDirection.front : CameraLensDirection.back),
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
          camera,
          ResolutionPreset.high,
          enableAudio: false
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      setState(() {
        _isCameraInitialized = true;
        _autoCaptureStatus = "Ready. Capturing in 3 seconds...";
      });

      // Start Countdown
      _performAutoCapture();

    } catch (e) {
      if (mounted) setState(() => _autoCaptureStatus = "Error: $e");
    }
  }

  Future<void> _performAutoCapture() async {
    // 3 Second Countdown
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

  // --- GENERIC UPLOAD FUNCTION ---
  Future<void> _uploadMedia(File file, String ext, String typeName) async {
    setState(() { _isUploading = true; });

    String? downloadUrl = await _supabaseStorage.uploadRequestMedia(
      widget.requestId,
      file,
      ext,
    );

    if (downloadUrl != null) {
      await _ticketService.completeRequestWithMedia(widget.requestId, downloadUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$typeName sent successfully!')),
        );
        setState(() {
          _isUploading = false;
          _autoCaptureStatus = "Sent! You can close this screen.";
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error uploading $typeName.')),
        );
        setState(() { _isUploading = false; });
      }
    }
  }
  // --- END NEW LOGIC ---

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _initAudioRecorder() async {
    await _audioRecorder.openRecorder();
  }

  // --- Timer Functions ---
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

  // --- Location Sharing ---
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

  // --- Video Sample Logic ---
  Future<void> _handleVideoSample(String serviceType) async {
    final camera = serviceType == 'front_video' ? CameraDevice.front : CameraDevice.rear;
    var camStatus = await Permission.camera.request();
    var micStatus = await Permission.microphone.request();
    if (camStatus.isDenied || micStatus.isDenied) return;

    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: camera,
      maxDuration: Duration(seconds: widget.durationInSeconds),
    );

    if (video != null) {
      _uploadMedia(File(video.path), 'mp4', 'Video');
    }
  }

  // --- Audio Sample Logic ---
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

  // --- Live Video Stream Logic ---
  void _toggleMute() {
    if (_localStream == null) return;
    final audioTrack = _localStream!.getAudioTracks().first;
    setState(() {
      _isMuted = !_isMuted;
      audioTrack.enabled = !_isMuted;
    });
  }

  Future<void> _startVideoStream() async {
    await [Permission.camera, Permission.microphone].request();
    _peerConnection = await createPeerConnection(_iceConfig);

    // Candidates
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _signalingService.addCandidate(widget.requestId, candidate, false);
    };

    // Local Stream
    final facingMode = widget.serviceType == 'front_stream' ? 'user' : 'environment';
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': facingMode}
    });

    _localRenderer.srcObject = _localStream;
    _localStream?.getTracks().forEach((track) {
      _peerConnection?.addTrack(track, _localStream!);
    });

    // Offer
    RTCSessionDescription offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);
    await _signalingService.createOffer(widget.requestId, offer);

    // Listen for Answer
    _sessionSub = _signalingService.getSessionStream(widget.requestId).listen((doc) async {
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        if (data['answer'] != null && _peerConnection?.getRemoteDescription() == null) {
          var answer = RTCSessionDescription(data['answer']['sdp'], data['answer']['type']);
          await _peerConnection?.setRemoteDescription(answer);
        }
      }
    });

    // Listen for Candidates
    _candidateSub = _signalingService.getCandidateStream(widget.requestId, false).listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          _peerConnection?.addCandidate(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
        }
      }
    });

    setState(() { _isStreaming = true; });
    _startSessionTimer();
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

  // --- Build UI ---
  Widget _buildTaskWidget() {
    if (_isUploading) {
      // --- FIX: Center aligned uploading text ---
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Uploading automatically...', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    switch (widget.serviceType) {
      case 'location':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
              label: Text(_isSharing ? 'Stop Sharing' : 'Start Sharing Location'),
              onPressed: _isSharing ? _stopLocationSharing : _startLocationSharing,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSharing ? Colors.red : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isSharing)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text('Sharing live for ${_formatDurationForDisplay()}', textAlign: TextAlign.center),
              ),
          ],
        );

    // --- AUTO CAPTURE UI ---
      case 'front_camera':
      case 'back_camera':
        if (!_isCameraInitialized || _cameraController == null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(_autoCaptureStatus),
              ],
            ),
          );
        }
        return Column(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CameraPreview(_cameraController!),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _autoCaptureStatus,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
        );

      case 'front_video':
      case 'back_video':
        return ElevatedButton.icon(
          icon: const Icon(Icons.videocam),
          label: const Text('Record Video'),
          onPressed: () => _handleVideoSample(widget.serviceType),
        );

      case 'audio':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(_isRecording ? Icons.mic : Icons.mic_none, size: 80, color: _isRecording ? Colors.red : Colors.grey),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
              label: Text(_isRecording ? 'Stop Recording' : 'Start Recording'),
              onPressed: _isRecording ? _stopAudioRecording : _startAudioRecording,
            ),
          ],
        );

      case 'front_stream':
      case 'back_stream':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isStreaming ? Icons.stop_circle : Icons.play_circle),
              label: Text(_isStreaming ? 'Stop Stream' : 'Start Stream'),
              onPressed: _isStreaming ? _stopVideoStream : _startVideoStream,
              style: ElevatedButton.styleFrom(backgroundColor: _isStreaming ? Colors.red : Colors.blue),
            ),
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
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: _buildTaskWidget(),
      ),
    );
  }
}