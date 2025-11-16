import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:streamix/services/location_service.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_sound/flutter_sound.dart';
// Note: We'll need to add signaling_service.dart and flutter_webrtc back
// when we fix the live stream feature.

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

      case 'front_camera':
      case 'back_camera':
        return const Center(child: Text('Waiting for sender to take photo...'));
      case 'front_video':
      case 'back_video':
        return const Center(child: Text('Waiting for sender to record video...'));
      case 'audio':
        return const Center(child: Text('Waiting for sender to record audio...'));

    // ... (other placeholders)
      default:
        return Text('Viewer for ${serviceType}');
    }
  }
}

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