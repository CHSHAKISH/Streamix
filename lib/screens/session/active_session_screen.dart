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

  // Audio
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _audioPath;

  // Location
  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isSharing = false;
  Timer? _sessionTimer;

  // WebRTC
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
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  @override
  void initState() {
    super.initState();

    // FIX 5: Initialize Video Renderer Asynchronously
    if (widget.serviceType.contains('stream')) {
      _initRenderers();
    }

    // Initialize Audio Recorder
    if (widget.serviceType == 'audio') {
      _initAudioRecorder();
    }
  }

  // --- NEW FUNCTION FOR VIDEO INITIALIZATION ---
  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    // Refresh UI to show the view once initialized
    if (mounted) {
      setState(() {});
    }
  }

  // --- NEW FUNCTION FOR AUDIO INITIALIZATION ---
  Future<void> _initAudioRecorder() async {
    // Initialize the audio session
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

  // --- Location Sharing ---
  Future<void> _startLocationSharing() async {
    var status = await Permission.location.request();
    if (status.isDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      return;
    }

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

  // --- FULL: Live Video Stream Logic ---
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

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('SENDER: ICE Connection State: $state');
    };

    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _signalingService.addCandidate(widget.requestId, candidate, false);
    };

    final facingMode = widget.serviceType == 'front_stream' ? 'user' : 'environment';
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': facingMode}
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
          var answer = RTCSessionDescription(
            data['answer']['sdp'],
            data['answer']['type'],
          );
          await _peerConnection?.setRemoteDescription(answer);
        }
      }
    });

    _candidateSub = _signalingService.getCandidateStream(widget.requestId, false).listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          var data = change.doc.data() as Map<String, dynamic>;
          _peerConnection?.addCandidate(RTCIceCandidate(
            data['candidate'],
            data['sdpMid'],
            data['sdpMLineIndex'],
          ));
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
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isStreaming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  'Streaming live for ${_formatDurationForDisplay()}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: Colors.grey),
                ),
                child: RTCVideoView(_localRenderer, mirror: true),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: Icon(_isStreaming ? Icons.stop_circle : Icons.play_circle),
                  label: Text(_isStreaming ? 'Stop Stream' : 'Start Stream'),
                  onPressed: _isStreaming ? _stopVideoStream : _startVideoStream,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isStreaming ? Colors.red : Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
                  ),
                ),
                IconButton.filled(
                  icon: Icon(_isMuted ? Icons.mic_off : Icons.mic),
                  iconSize: 30,
                  padding: const EdgeInsets.all(16),
                  onPressed: _isStreaming ? _toggleMute : null,
                  style: IconButton.styleFrom(
                    backgroundColor: _isMuted ? Colors.red : Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
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