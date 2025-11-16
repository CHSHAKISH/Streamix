import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  bool _isUploading = false;
  bool _isMuted = false;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ]
  };

  @override
  void initState() {
    super.initState();
    if (widget.serviceType.contains('stream')) {
      _localRenderer.initialize();
    }
    if (widget.serviceType == 'audio') {
      _initAudioRecorder();
    }
  }

  Future<void> _initAudioRecorder() async {
    await _audioRecorder.openRecorder();
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
    super.dispose();
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

  void _toggleMute() {
    if (_localStream == null) return;
    final audioTrack = _localStream!.getAudioTracks().first;
    setState(() {
      _isMuted = !_isMuted;
      audioTrack.enabled = !_isMuted;
    });
  }

  // --- Location Sharing ---
  Future<void> _startLocationSharing() async {
    var status = await Permission.location.request();
    if (status.isDenied) { /*... snackbar ...*/ return; }

    await _location.changeSettings(accuracy: LocationAccuracy.high);
    _locationSubscription =
        _location.onLocationChanged.listen((LocationData newLocation) {
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

  // --- Image Sample Logic ---
  Future<void> _handleImageSample(String serviceType) async {
    final camera = serviceType == 'front_camera'
        ? CameraDevice.front
        : CameraDevice.rear;

    var status = await Permission.camera.request();
    if (status.isDenied) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera permission is required.')),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: camera,
    );

    if (image != null) {
      setState(() { _isUploading = true; });
      File imageFile = File(image.path);

      String? downloadUrl = await _supabaseStorage.uploadRequestMedia(
        widget.requestId,
        imageFile,
        'jpg',
      );

      if (downloadUrl != null) {
        await _ticketService.completeRequestWithMedia(widget.requestId, downloadUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Image uploaded successfully!')),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error uploading image.')),
        );
      }
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  // --- Video Sample Logic ---
  Future<void> _handleVideoSample(String serviceType) async {
    final camera = serviceType == 'front_video'
        ? CameraDevice.front
        : CameraDevice.rear;

    var camStatus = await Permission.camera.request();
    var micStatus = await Permission.microphone.request();
    if (camStatus.isDenied || micStatus.isDenied) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera & Microphone permissions are required.')),
      );
      return;
    }

    final ImagePicker picker = ImagePicker();
    final XFile? video = await picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: camera,
      maxDuration: Duration(seconds: widget.durationInSeconds),
    );

    if (video != null) {
      setState(() { _isUploading = true; });
      File videoFile = File(video.path);

      String? downloadUrl = await _supabaseStorage.uploadRequestMedia(
        widget.requestId,
        videoFile,
        'mp4',
      );

      if (downloadUrl != null) {
        await _ticketService.completeRequestWithMedia(widget.requestId, downloadUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Video uploaded successfully!')),
          );
          Navigator.pop(context);
        }
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error uploading video.')),
        );
      }
      if (mounted) setState(() { _isUploading = false; });
    }
  }

  // --- Audio Sample Logic ---
  Future<void> _startAudioRecording() async {
    var status = await Permission.microphone.request();
    if (status.isDenied) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone permission is required.')),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    _audioPath = '${tempDir.path}/streamix_audio.aac';

    await _audioRecorder.startRecorder(
      toFile: _audioPath,
      codec: Codec.aacADTS,
    );

    setState(() { _isRecording = true; });
    _startSessionTimer();
  }

  Future<void> _stopAudioRecording() async {
    await _audioRecorder.stopRecorder();
    _sessionTimer?.cancel();
    setState(() { _isRecording = false; _isUploading = true; });

    if (_audioPath == null) {
      setState(() { _isUploading = false; });
      return;
    }

    File audioFile = File(_audioPath!);

    String? downloadUrl = await _supabaseStorage.uploadRequestMedia(
      widget.requestId,
      audioFile,
      'aac',
    );

    if (downloadUrl != null) {
      await _ticketService.completeRequestWithMedia(widget.requestId, downloadUrl);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Audio uploaded successfully!')),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error uploading audio.')),
      );
    }
    if (mounted) setState(() { _isUploading = false; });
  }

  // --- (Buggy Feature) Video Streaming ---
  Future<void> _startVideoStream() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Live Stream feature not enabled.')),
    );
    // _startSessionTimer();
  }
  Future<void> _stopVideoStream() async {
    _sessionTimer?.cancel();
    await _ticketService.completeRequest(widget.requestId);
    // ...
  }

  // --- Main Build Function ---
  Widget _buildTaskWidget() {
    if (_isUploading) {
      return const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Uploading media...'),
        ],
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
                child: Text(
                  'Sharing live for ${_formatDurationForDisplay()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
          ],
        );

      case 'front_camera':
      case 'back_camera':
        return ElevatedButton.icon(
          icon: const Icon(Icons.camera_alt),
          label: Text(widget.serviceType == 'front_camera'
              ? 'Open Front Camera'
              : 'Open Back Camera'),
          onPressed: () => _handleImageSample(widget.serviceType),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        );

      case 'front_video':
      case 'back_video':
        return ElevatedButton.icon(
          icon: const Icon(Icons.videocam),
          label: Text(widget.serviceType == 'front_video'
              ? 'Record with Front Camera'
              : 'Record with Back Camera'),
          onPressed: () => _handleVideoSample(widget.serviceType),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
          ),
        );

      case 'audio':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isRecording ? 'Recording...' : 'Ready to record audio',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: _isRecording ? Colors.red : Theme.of(context).primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            Icon(
              _isRecording ? Icons.mic : Icons.mic_none,
              size: 80,
              color: _isRecording ? Colors.red : Theme.of(context).primaryColor,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.play_arrow),
              label: Text(_isRecording
                  ? 'Stop Recording'
                  : 'Start Recording'),
              onPressed: _isRecording
                  ? _stopAudioRecording
                  : _startAudioRecording,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isRecording)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  'Recording for ${_formatDurationForDisplay()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
          ],
        );

      case 'front_stream':
      case 'back_stream':
        return ElevatedButton.icon(
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Live Stream'),
          onPressed: _startVideoStream,
        );

      default:
        return Text('Unknown service type: ${widget.serviceType}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Active Session: ${widget.serviceType}'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: _buildTaskWidget(),
        ),
      ),
    );
  }
}