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
    required this.serviceType,
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
        title: Text('Monitor: ${widget.serviceType.toUpperCase()}'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

          var data = snapshot.data!.data() as Map<String, dynamic>;
          String? mediaUrl = data['mediaUrl'];
          String command = data['remoteCommand'] ?? 'IDLE';
          String status = data['status'] ?? '';
          
          print('🔍 [ViewSession] mediaUrl: $mediaUrl');
          print('🔍 [ViewSession] command: $command');
          print('🔍 [ViewSession] status: $status');
          
          // Check if User B stopped sharing
          if (status == 'stopped_by_provider' || command == 'STOPPED') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('⚠️ User B has stopped sharing the camera'),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
                Navigator.pop(context);
              }
            });
          }

          // 1. REMOTE CAMERA
          if (widget.serviceType.contains('camera')) {
            return Container(
              color: Colors.black,
              child: Stack(
                children: [
                  // Fullscreen Image Display
                  Center(
                    child: mediaUrl != null && mediaUrl.isNotEmpty
                        ? InteractiveViewer(
                            child: Image.network(
                              mediaUrl,
                              key: ValueKey(mediaUrl + DateTime.now().millisecondsSinceEpoch.toString()),
                              fit: BoxFit.contain,
                              loadingBuilder: (c, child, p) => p == null
                                  ? child
                                  : const Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          CircularProgressIndicator(
                                            color: Colors.white,
                                          ),
                                          SizedBox(height: 20),
                                          Text(
                                            'Loading photo...',
                                            style: TextStyle(color: Colors.white70),
                                          ),
                                        ],
                                      ),
                                    ),
                              errorBuilder: (context, error, stackTrace) {
                                print('Image load error: $error');
                                return Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.error_outline, color: Colors.red, size: 60),
                                      const SizedBox(height: 10),
                                      Text(
                                        'Failed to load image\n$error',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.grey[400]),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (command == 'REQUEST_CAPTURE') ...[
                                const CircularProgressIndicator(color: Colors.white),
                                const SizedBox(height: 20),
                                const Text(
                                  'Capturing photo from User B...',
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                              ] else ...[
                                const Icon(Icons.photo_camera, size: 80, color: Colors.grey),
                                const SizedBox(height: 20),
                                const Text(
                                  "Waiting for photo...\nClose and try again if needed",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ],
                          ),
                  ),
                  
                  // Close button
                  SafeArea(
                    child: Positioned(
                      top: 10,
                      right: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  
                  // Photo info overlay
                  if (mediaUrl != null && mediaUrl.isNotEmpty)
                    SafeArea(
                      child: Positioned(
                        bottom: 20,
                        left: 0,
                        right: 0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle, color: Colors.green, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'Photo captured successfully',
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }

          // 2. VIDEO PLAYBACK (Similar to camera - fullscreen with controls)
          if (widget.serviceType.contains('video')) {
            return Container(
              color: Colors.black,
              child: Stack(
                children: [
                  // Fullscreen Video Player
                  Center(
                    child: mediaUrl != null && mediaUrl.isNotEmpty
                        ? _VideoPlayerWidget(videoUrl: mediaUrl)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (command == 'REQUEST_CAPTURE') ...[
                                const CircularProgressIndicator(color: Colors.white),
                                const SizedBox(height: 20),
                                const Text(
                                  'Recording 10s video from User B...',
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                              ] else ...[
                                const Icon(Icons.videocam, size: 80, color: Colors.grey),
                                const SizedBox(height: 20),
                                const Text(
                                  "Waiting for video...\nClose and try again if needed",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ],
                          ),
                  ),
                  
                  // Close button
                  SafeArea(
                    child: Positioned(
                      top: 10,
                      left: 10,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white, size: 32),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                  
                  // Video info overlay
                  if (mediaUrl != null && mediaUrl.isNotEmpty)
                    SafeArea(
                      child: Positioned(
                        bottom: 60, // Above progress bar
                        left: 0,
                        right: 0,
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text(
                                '10-second video recorded',
                                style: TextStyle(color: Colors.white, fontSize: 14),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }
          
          // 3. AUDIO PLAYBACK
          if (widget.serviceType == 'audio') {
            return mediaUrl != null && mediaUrl.isNotEmpty
                ? _AudioPlayerWidget(audioUrl: mediaUrl)
                : const Center(
                    child: Text("Waiting for audio...", style: TextStyle(color: Colors.white)),
                  );
          }

          // 4. LOCATION
          if (widget.serviceType == 'location')
            return _LocationViewer(requestId: widget.requestId);

          return const Center(
            child: Text("Waiting...", style: TextStyle(color: Colors.white)),
          );
        },
      ),
    );
  }
}

// ... (Keep _LocationViewer, _VideoPlayerWidget, _AudioPlayerWidget EXACTLY as they were) ...
// ... (Pasted for convenience below) ...
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
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          var data = snapshot.data!.first;
          if (data['lat'] != null && data['lng'] != null) {
            _senderPosition = LatLng(
              (data['lat'] as num).toDouble(),
              (data['lng'] as num).toDouble(),
            );
            if (_isMapReady) _mapController.move(_senderPosition!, 16.0);
          }
        }
        return FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _senderPosition ?? const LatLng(20.5937, 78.9629),
            initialZoom: 4.0,
            onMapReady: () {
              _isMapReady = true;
            },
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
                    child: const Icon(
                      Icons.location_on,
                      color: Colors.red,
                      size: 40,
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  const _VideoPlayerWidget({required this.videoUrl});
  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isMuted = false;
  
  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        setState(() {
          _isInitialized = true;
          _controller.setLooping(true);
          _controller.setVolume(1.0); // Enable audio by default
          _controller.play();
        });
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized)
      return const Center(child: CircularProgressIndicator());
    return Center(
      child: AspectRatio(
        aspectRatio: _controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            VideoPlayer(_controller),
            
            // Play/Pause overlay
            GestureDetector(
              onTap: () {
                setState(() {
                  _controller.value.isPlaying
                      ? _controller.pause()
                      : _controller.play();
                });
              },
              child: Container(
                color: Colors.transparent,
                child: Center(
                  child: AnimatedOpacity(
                    opacity: _controller.value.isPlaying ? 0.0 : 1.0,
                    duration: const Duration(milliseconds: 300),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.black45,
                        shape: BoxShape.circle,
                      ),
                      padding: const EdgeInsets.all(20),
                      child: const Icon(
                        Icons.play_arrow,
                        size: 60,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Mute/Unmute button (top right)
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: Icon(
                    _isMuted ? Icons.volume_off : Icons.volume_up,
                    color: Colors.white,
                    size: 28,
                  ),
                  onPressed: _toggleMute,
                  tooltip: _isMuted ? 'Unmute' : 'Mute',
                ),
              ),
            ),
            
            // Progress bar
            VideoProgressIndicator(
              _controller,
              allowScrubbing: true,
              colors: const VideoProgressColors(playedColor: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}

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
    try {
      await _player.openPlayer();
      print('🎵 [AudioPlayer] Player opened successfully');
      print('🎵 [AudioPlayer] Audio URL: ${widget.audioUrl}');
      setState(() => _isInitialized = true);
      
      // Auto-play the audio when ready
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted && _isInitialized) {
        _togglePlay();
      }
    } catch (e) {
      print('❌ [AudioPlayer] Failed to open player: $e');
    }
  }

  @override
  void dispose() {
    _player.closePlayer();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (!_isInitialized) {
      print('⚠️ [AudioPlayer] Player not initialized');
      return;
    }
    
    try {
      if (_isPlaying) {
        print('🎵 [AudioPlayer] Stopping playback');
        await _player.stopPlayer();
        setState(() => _isPlaying = false);
      } else {
        print('🎵 [AudioPlayer] Starting playback from: ${widget.audioUrl}');
        
        // Set volume to maximum
        await _player.setVolume(1.0);
        
        await _player.startPlayer(
          fromURI: widget.audioUrl,
          codec: Codec.aacADTS,
          whenFinished: () {
            print('🎵 [AudioPlayer] Playback finished');
            if (mounted) {
              setState(() => _isPlaying = false);
            }
          },
        );
        setState(() => _isPlaying = true);
        print('🎵 [AudioPlayer] Playback started successfully');
      }
    } catch (e) {
      print('❌ [AudioPlayer] Error during playback: $e');
      setState(() => _isPlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing audio: $e'), backgroundColor: Colors.red)
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Audio Icon with Animation
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.grey[900],
              shape: BoxShape.circle,
              border: Border.all(
                color: _isPlaying ? Colors.green : Colors.white,
                width: 2,
              ),
            ),
            child: Icon(
              _isPlaying ? Icons.volume_up : Icons.music_note,
              size: 60,
              color: _isPlaying ? Colors.green : Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          
          // Status Text
          Text(
            _isPlaying ? 'Playing 10-second recording...' : 'Tap to play',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          
          const SizedBox(height: 40),
          
          // Play/Stop Button
          ElevatedButton.icon(
            icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
            label: Text(_isPlaying ? "STOP AUDIO" : "PLAY RECORDING"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isPlaying ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
            ),
            onPressed: _isInitialized ? _togglePlay : null,
          ),
          
          // Debug info
          if (!_isInitialized)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Text(
                'Initializing player...',
                style: TextStyle(color: Colors.orange),
              ),
            ),
        ],
      ),
    );
  }
}
