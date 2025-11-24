import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:streamix/services/location_service.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_sound/flutter_sound.dart';

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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('Viewing: ${widget.serviceType.toUpperCase()}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}", style: const TextStyle(color: Colors.red)));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String status = data['status'];
          String? mediaUrl = data['mediaUrl'];

          // 1. HANDLE MEDIA PLAYBACK
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            if (widget.serviceType == 'audio') {
              return _AudioPlayerWidget(audioUrl: mediaUrl);
            }
            if (widget.serviceType.contains('camera')) {
              return Center(child: Image.network(mediaUrl));
            }
            if (widget.serviceType.contains('video')) {
              return _VideoPlayerWidget(videoUrl: mediaUrl);
            }
          }

          // 2. HANDLE LIVE LOCATION
          if (widget.serviceType == 'location') {
            return _LocationViewer(requestId: widget.requestId);
          }

          // 3. WAITING STATE
          if (status == 'completed' && mediaUrl == null) {
            return const Center(child: Text('Session Ended (No Media)', style: TextStyle(color: Colors.white)));
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                Text(
                  widget.serviceType.contains('video')
                      ? "Waiting for video upload..."
                      : "Waiting for sender...",
                  style: const TextStyle(color: Colors.white),
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// --- 1. LOCATION VIEWER ---
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
  bool _isMapReady = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _locationService.getSessionStream(widget.requestId),
      builder: (context, snapshot) {

        String statusText = "Connecting to Signal...";
        Color statusColor = Colors.orange;

        if (snapshot.hasError) {
          statusText = "Connection Error";
          statusColor = Colors.red;
        } else if (snapshot.hasData) {
          if (snapshot.data!.isEmpty) {
            statusText = "Waiting for update...";
            statusColor = Colors.yellow;
          } else {
            var data = snapshot.data!.first;
            if (data['lat'] != null && data['lng'] != null) {
              _senderPosition = LatLng((data['lat'] as num).toDouble(), (data['lng'] as num).toDouble());
              statusText = "LIVE TRACKING ACTIVE";
              statusColor = Colors.green;
              if (_isMapReady) _mapController.move(_senderPosition!, 16.0);
            }
          }
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _senderPosition ?? const LatLng(20.5937, 78.9629),
                initialZoom: 4.0,
                onMapReady: () { _isMapReady = true; },
              ),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.streamix'),
                if (_senderPosition != null)
                  MarkerLayer(markers: [Marker(point: _senderPosition!, width: 80, height: 80, child: const Icon(Icons.location_on, color: Colors.red, size: 40))]),
              ],
            ),
            Positioned(
              bottom: 30, left: 20, right: 20,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.8), borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if(_senderPosition == null) const SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    const SizedBox(width: 10),
                    Text(statusText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          ],
        );
      },
    );
  }
}

// --- 2. VIDEO PLAYER ---
class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerWidget({required this.videoUrl});
  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _controller.setLooping(true);
          _controller.play();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) return const Center(child: CircularProgressIndicator());

    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying ? _controller.pause() : _controller.play();
                });
              },
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                      padding: const EdgeInsets.all(20),
                      child: const Icon(Icons.play_arrow, size: 60, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            VideoProgressIndicator(_controller, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// --- 3. AUDIO PLAYER ---
class _AudioPlayerWidget extends StatefulWidget {
  final String audioUrl;
  const _AudioPlayerWidget({required this.audioUrl});
  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  bool _isPlaying = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    await _player.openPlayer();
    setState(() => _isInitialized = true);
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_isInitialized) return;
    if (_isPlaying) {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } else {
      await _player.startPlayer(
          fromURI: widget.audioUrl,
          whenFinished: () { setState(() => _isPlaying = false); }
      );
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
                color: Colors.grey[900],
                shape: BoxShape.circle,
                border: Border.all(color: _isPlaying ? Colors.green : Colors.white, width: 2)
            ),
            child: Icon(Icons.music_note, size: 60, color: _isPlaying ? Colors.green : Colors.white),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            label: Text(_isPlaying ? "STOP AUDIO" : "PLAY RECORDING"),
            style: ElevatedButton.styleFrom(
                backgroundColor: _isPlaying ? Colors.red : Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15)
            ),
            onPressed: _togglePlay,
          ),
        ],
      ),
    );
  }
}