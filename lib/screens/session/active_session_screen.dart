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

  final Location _location = Location();
  StreamSubscription<LocationData>? _locationSubscription;
  bool _isSharing = false;
  Timer? _sessionTimer;

  // (Other state variables)
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  bool _isStreaming = false;
  StreamSubscription? _sessionSub;
  StreamSubscription? _candidateSub;
  bool _isUploading = false;
  bool _isMuted = false;

  final Map<String, dynamic> _iceConfig = { /* ... */ };

  @override
  void initState() {
    super.initState();
    if (widget.serviceType.contains('stream')) {
      _localRenderer.initialize();
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
    super.dispose();
  }

  // --- TIMER FUNCTIONS (NOW CORRECT) ---
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
    }
  }

  String _formatDurationForDisplay() {
    final int minutes = (widget.durationInSeconds / 60).floor();
    final int seconds = widget.durationInSeconds % 60;
    return "$minutes min ${seconds} sec";
  }
  // --- END TIMER FUNCTIONS ---

  void _toggleMute() { /* ... */ }
  Future<void> _handleImageSample(String serviceType) async { /* ... */ }

  // --- (IMPLEMENTED) Location Sharing ---
  Future<void> _startLocationSharing() async {
    var status = await Permission.location.request();
    if (status.isDenied) { /*... snackbar ...*/ return; }

    await _location.changeSettings(accuracy: LocationAccuracy.high);
    _locationSubscription =
        _location.onLocationChanged.listen((LocationData newLocation) {
          _locationService.updateSenderLocation(widget.requestId, newLocation);
        });
    setState(() { _isSharing = true; });
    _startSessionTimer(); // <-- FIX: Start the timer
  }

  Future<void> _stopLocationSharing() async {
    _sessionTimer?.cancel();
    _locationSubscription?.cancel();

    // <-- FIX: Mark as complete in Firestore
    await _ticketService.completeRequest(widget.requestId);

    await _locationService.deleteSenderLocation(widget.requestId);

    setState(() { _isSharing = false; });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Location sharing stopped.')));
      Navigator.pop(context);
    }
  }

  // --- (Video placeholders) ---
  Future<void> _startVideoStream() async { _startSessionTimer(); }
  Future<void> _stopVideoStream() async {
    _sessionTimer?.cancel();
    await _ticketService.completeRequest(widget.requestId);
    /* ... rest of video stop logic ... */
  }

  // --- Main Build Function ---
  Widget _buildTaskWidget() {
    switch (widget.serviceType) {
      case 'location':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ElevatedButton.icon(
              icon: Icon(_isSharing ? Icons.stop : Icons.play_arrow),
              label: Text(_isSharing
                  ? 'Stop Sharing'
                  : 'Start Sharing Location'),
              onPressed: _isSharing
                  ? _stopLocationSharing
                  : _startLocationSharing,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isSharing ? Colors.red : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
            if (_isSharing)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Text(
                  'Sharing live for ${_formatDurationForDisplay()}', // <-- FIX: Uses correct text
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
              ),
          ],
        );

    // ... (other cases)
      default:
        return Text('Task UI for ${widget.serviceType}');
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