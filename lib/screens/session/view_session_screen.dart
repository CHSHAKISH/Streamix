import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:streamix/services/location_service.dart';
import 'package:streamix/services/signaling_service.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class ViewSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType;

  const ViewSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType
  });

  @override
  State<ViewSessionScreen> createState() => _ViewSessionScreenState();
}

class _ViewSessionScreenState extends State<ViewSessionScreen> {

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Viewing: ${widget.serviceType}'),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String status = data['status'];
          String? mediaUrl = data['mediaUrl'];

          if (status == 'completed') {

            if (widget.serviceType == 'front_camera' || widget.serviceType == 'back_camera') {
              if (mediaUrl != null) {
                return Center(child: Image.network(mediaUrl,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator();
                  },
                ));
              } else {
                return const Center(child: Text('Error: Media URL not found.'));
              }
            }

            if (widget.serviceType == 'front_video' || widget.serviceType == 'back_video') {
              if (mediaUrl != null) {
                return _VideoPlayerWidget(videoUrl: mediaUrl);
              } else {
                return const Center(child: Text('Error: Media URL not found.'));
              }
            }

            if (widget.serviceType == 'audio') {
              if (mediaUrl != null) {
                return _AudioPlayerWidget(audioUrl: mediaUrl);
              } else {
                return const Center(child: Text('Error: Media URL not found.'));
              }
            }

            return const Center(
              child: Text(
                'Session has ended.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          if (status == 'accepted') {
            return _buildViewer(widget.serviceType);
          }

          if (status == 'denied') {
            return const Center(child: Text('Request was denied.'));
          }

          return const Center(child: Text('Waiting for request to be accepted...'));
        },
      ),
    );
  }

  // This helper builds the correct viewer widget for LIVE sessions
  Widget _buildViewer(String serviceType) {
    switch (serviceType) {
      case 'location':
        return _LocationViewer(requestId: widget.requestId);

      case 'front_stream':
      case 'back_stream':
        return _VideoStreamViewer(requestId: widget.requestId);

      case 'front_camera':
      case 'back_camera':
        return const Center(child: Text('Waiting for sender to take photo...'));
      case 'front_video':
      case 'back_video':
        return const Center(child: Text('Waiting for sender to record video...'));
      case 'audio':
        return const Center(child: Text('Waiting for sender to record audio...'));

      default:
        return Text('Viewer for ${serviceType}');
    }
  }
}

// --- UPDATED DEBUGGING WIDGET FOR LIVE VIDEO ---
class _VideoStreamViewer extends StatefulWidget {
  final String requestId;
  const _VideoStreamViewer({required this.requestId});

  @override
  State<_VideoStreamViewer> createState() => _VideoStreamViewerState();
}

class _VideoStreamViewerState extends State<_VideoStreamViewer> {
  final SignalingService _signalingService = SignalingService();
  RTCPeerConnection? _peerConnection;
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  StreamSubscription? _sessionSub;
  StreamSubscription? _candidateSub;

  // Debugging State
  String _status = "Initializing...";
  bool _hasStream = false;

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
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _status = "Initializing Renderer...");
    await _remoteRenderer.initialize();

    setState(() => _status = "Creating PeerConnection...");
    _peerConnection = await createPeerConnection(_iceConfig);

    // --- THIS IS THE NEW DEBUG LINE ---
    if (mounted) {
      setState(() => _status = "Waiting for Sender to join...");
    }

    // 1. Monitor Connection State
    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      print('REQUESTER: ICE Connection State: $state');
      if (mounted) {
        setState(() => _status = "ICE State: ${state.toString().split('.').last}");
      }
    };

    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      print('REQUESTER: Connection State: $state');
      if (mounted) {
        setState(() => _status = "Connection: ${state.toString().split('.').last}");
      }
    };

    // 2. Listen for Video Track
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      print("--- REQUESTER: ON TRACK EVENT FIRED ---");
      if (event.streams.isNotEmpty) {
        print("--- REQUESTER: GOT STREAM ---");
        if (mounted) {
          setState(() {
            _remoteRenderer.srcObject = event.streams[0];
            _hasStream = true;
            _status = "Stream Received!";
          });
        }
      }
    };

    // 3. ICE Candidates
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      _signalingService.addCandidate(widget.requestId, candidate, true);
    };

    // 4. Signaling Listener
    _sessionSub = _signalingService.getSessionStream(widget.requestId).listen((doc) async {
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;

        if (data['offer'] != null && _peerConnection?.getRemoteDescription() == null) {
          print("--- REQUESTER: RECEIVED OFFER ---");
          if (mounted) setState(() => _status = "Received Offer...");

          var offer = RTCSessionDescription(
            data['offer']['sdp'],
            data['offer']['type'],
          );

          await _peerConnection?.setRemoteDescription(offer);

          var answer = await _peerConnection!.createAnswer();
          print("--- REQUESTER: CREATED ANSWER ---");

          await _peerConnection!.setLocalDescription(answer);
          await _signalingService.createAnswer(widget.requestId, answer);
          if (mounted) setState(() => _status = "Sent Answer. Connecting...");
        }
      }
    });

    _candidateSub = _signalingService.getCandidateStream(widget.requestId, true).listen((snapshot) {
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
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _candidateSub?.cancel();
    _peerConnection?.dispose();
    _remoteRenderer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // The Video View
          if (_hasStream)
            Positioned.fill(
              child: RTCVideoView(
                _remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

          // The Debug Status Overlay
          Center(
            child: _hasStream
                ? null // Hide text if stream is active
                : Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: Colors.white),
                  const SizedBox(height: 16),
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
// --- END UPDATED WIDGET ---


// --- AUDIO PLAYER WIDGET ---
class _AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  const _AudioPlayerWidget({required this.audioUrl});
  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}
class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  bool _isPlayerReady = false;
  bool _isPlaying = false;
  @override
  void initState() {
    super.initState();
    _initAudioPlayer();
  }
  Future<void> _initAudioPlayer() async {
    await _audioPlayer.openPlayer();
    setState(() {
      _isPlayerReady = true;
    });
  }
  @override
  void dispose() {
    _audioPlayer.closePlayer();
    super.dispose();
  }
  Future<void> _togglePlayer() async {
    if (!_isPlayerReady) return;
    if (_isPlaying) {
      await _audioPlayer.stopPlayer();
      setState(() { _isPlaying = false; });
    } else {
      await _audioPlayer.startPlayer(
        fromURI: widget.audioUrl,
        codec: Codec.aacADTS,
        whenFinished: () {
          setState(() { _isPlaying = false; });
        },
      );
      setState(() { _isPlaying = true; });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton.filled(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            iconSize: 60,
            onPressed: _isPlayerReady ? _togglePlayer : null,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Text(_isPlaying ? 'Playing...' : 'Tap to play audio', style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}


// --- VIDEO PLAYER WIDGET ---
class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerWidget({required this.videoUrl});
  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}
class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  late Future<void> _initializeVideoPlayerFuture;
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(widget.videoUrl),
    );
    _initializeVideoPlayerFuture = _controller.initialize();
    _controller.setLooping(true);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeVideoPlayerFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          return Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  VideoPlayer(_controller),
                  IconButton(
                    iconSize: 60,
                    color: Colors.white.withOpacity(0.8),
                    icon: Icon(
                      _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    ),
                    onPressed: () {
                      setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      });
                    },
                  ),
                ],
              ),
            ),
          );
        } else {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }
      },
    );
  }
}

// --- LOCATION VIEWER WIDGET ---
class _LocationViewer extends StatefulWidget {
  final String requestId;
  const _LocationViewer({required this.requestId});
  @override
  State<_LocationViewer> createState() => _LocationViewerState();
}
class _LocationViewerState extends State<_LocationViewer> {
  final LocationService _locationService = LocationService();
  final MapController _mapController = MapController();
  LatLng? _senderPosition;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Map<String, dynamic>>(
      stream: _locationService.getSessionStream(widget.requestId),
      builder: (context, snapshot) {

        if (snapshot.hasData && snapshot.data != null) {
          var data = snapshot.data!;
          if (data['lat'] != null && data['lng'] != null) {
            _senderPosition = LatLng(data['lat'], data['lng']);
            _mapController.move(_senderPosition!, 16.0);
          }
        }

        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _senderPosition ?? const LatLng(20.5937, 78.9629),
            initialZoom: _senderPosition == null ? 4.0 : 16.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.streamix',
            ),
            if (_senderPosition != null)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _senderPosition!,
                    width: 80,
                    height: 80,
                    child: Icon(
                      Icons.location_on,
                      color: Theme.of(context).primaryColor,
                      size: 40,
                    ),
                  ),
                ],
              ),
            if (_senderPosition == null)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Waiting for sender to start sharing...',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}