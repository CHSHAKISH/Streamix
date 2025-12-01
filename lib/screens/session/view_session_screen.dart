import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:streamix/services/location_service.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ViewSessionScreen extends StatefulWidget {
  final String requestId;
  final String serviceType;
  final String? initialMediaUrl; // Pre-loaded media URL to avoid Firestore sync delays

  const ViewSessionScreen({
    super.key,
    required this.requestId,
    required this.serviceType,
    this.initialMediaUrl,
  });

  @override
  State<ViewSessionScreen> createState() => _ViewSessionScreenState();
}

class _ViewSessionScreenState extends State<ViewSessionScreen> {

  Widget _buildDiagnosticRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          // Show loading state clearly
          if (!snapshot.hasData) {
            return Container(
              color: Colors.purple,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Loading from Firestore...',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ],
                ),
              ),
            );
          }

          // Show if snapshot has error
          if (snapshot.hasError) {
            return Container(
              color: Colors.orange,
              padding: EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Firestore Error: ${snapshot.error}',
                  style: TextStyle(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          var data = snapshot.data!.data() as Map<String, dynamic>?;
          
          // Show if data is null
          if (data == null) {
            return Container(
              color: Colors.pink,
              padding: EdgeInsets.all(20),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning, size: 80, color: Colors.white),
                    SizedBox(height: 20),
                    Text(
                      'Document not found!\nRequest ID: ${widget.requestId}',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          // Use pre-loaded URL if provided, otherwise read from Firestore
          String? mediaUrl = widget.initialMediaUrl ?? data['mediaUrl'];
          String command = data['remoteCommand'] ?? 'IDLE';
          String status = data['status'] ?? '';
          String? errorMessage = data['errorMessage'];

          // CAMERA SERVICE - Show captured photo
          if (widget.serviceType.contains('camera')) {
            if (mediaUrl != null && mediaUrl.isNotEmpty) {
              // RETURN ONLY THE IMAGE WIDGET - NOTHING ELSE
              return WillPopScope(
                onWillPop: () async {
                  Navigator.pop(context);
                  return false;
                },
                child: GestureDetector(
                  onTap: () => Navigator.pop(context), // Tap anywhere to go back
                  child: Container(
                    color: Colors.black, // Black background only
                    child: Center(
                      child: _RobustNetworkImage(url: mediaUrl),
                    ),
                  ),
                ),
              );
            } else {
              // No URL yet - show waiting state
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (command == 'REQUEST_CAPTURE') ...[
                      const CircularProgressIndicator(color: Colors.white),
                      const SizedBox(height: 20),
                      const Text(
                        'Capturing photo...',
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                    ] else ...[
                      const Icon(Icons.info_outline, size: 80, color: Colors.orange),
                      const SizedBox(height: 20),
                      const Text(
                        'No photo available',
                        style: TextStyle(color: Colors.orange, fontSize: 18),
                      ),
                    ],
                  ],
                ),
              );
            }
          }

          // VIDEO SERVICE
          if (widget.serviceType.contains('video')) {
            return Container(
              color: Colors.black,
              child: Stack(
                children: [
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
                                  'Recording video...',
                                  style: TextStyle(color: Colors.white70, fontSize: 16),
                                ),
                              ] else ...[
                                const Icon(Icons.videocam, size: 80, color: Colors.grey),
                                const SizedBox(height: 20),
                                const Text(
                                  "Waiting for video...",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey, fontSize: 16),
                                ),
                              ],
                            ],
                          ),
                  ),
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
                ],
              ),
            );
          }

          // AUDIO SERVICE
          if (widget.serviceType == 'audio') {
            return mediaUrl != null && mediaUrl.isNotEmpty
                ? _AudioPlayerWidget(audioUrl: mediaUrl)
                : const Center(
                    child: Text("Waiting for audio...", style: TextStyle(color: Colors.white)),
                  );
          }

          // LOCATION SERVICE
          if (widget.serviceType == 'location') {
            return _LocationViewer(requestId: widget.requestId);
          }

          return const Center(
            child: Text("Unknown service", style: TextStyle(color: Colors.white)),
          );
        },
      ),
    );
  }
}

/// Displays a network image but falls back to downloading bytes and showing
/// the image from memory if the platform/network configuration prevents
/// Image.network from rendering (common in some release builds).
class _RobustNetworkImage extends StatefulWidget {
  final String url;
  const _RobustNetworkImage({required this.url});
  @override
  State<_RobustNetworkImage> createState() => _RobustNetworkImageState();
}

class _RobustNetworkImageState extends State<_RobustNetworkImage> {
  Uint8List? _bytes;
  bool _downloading = false;
  String? _errorMsg;
  int _retryCount = 0;

  @override
  void initState() {
    super.initState();
    print('🖼️🖼️🖼️ [RobustImage] initState called with URL: ${widget.url}');
    // Start download immediately
    if (widget.url.isNotEmpty) {
      _downloadAndSet();
    } else {
      print('❌❌❌ [RobustImage] URL IS EMPTY!');
      setState(() {
        _errorMsg = 'URL is empty';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    print('🖼️ [RobustImage] Building - bytes: ${_bytes != null ? "${_bytes!.length} bytes" : "null"}, downloading: $_downloading, error: $_errorMsg');
    
    // Show what we have
    if (_bytes != null && _bytes!.isNotEmpty) {
      print('✅✅✅ [RobustImage] SUCCESS! Displaying ${_bytes!.length} bytes');
      
      return Image.memory(
        _bytes!,
        fit: BoxFit.contain,
        // Explicitly set these to ensure no transparency/color filtering
        color: null,
        colorBlendMode: null,
        opacity: null,
        filterQuality: FilterQuality.high,
      );
    }

    if (_downloading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Downloading image...',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return _buildErrorWidget(_errorMsg!);
    }

    return Center(
      child: Text(
        'Initializing...',
        style: TextStyle(color: Colors.white38),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image, size: 80, color: Colors.red),
            SizedBox(height: 16),
            Text(
              'Failed to Load Image',
              style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                widget.url,
                style: TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
              ),
            ),
            SizedBox(height: 20),
            if (_retryCount < 3)
              ElevatedButton.icon(
                icon: Icon(Icons.refresh),
                label: Text('Retry'),
                onPressed: () {
                  setState(() {
                    _errorMsg = null;
                    _retryCount++;
                  });
                  _downloadAndSet();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAndSet() async {
    if (_downloading) return;
    
    setState(() { _downloading = true; });
    print('📥 [RobustImage] Starting download from: ${widget.url}');
    
    try {
      final uri = Uri.parse(widget.url);
      print('📥 [RobustImage] Parsed URI: $uri');
      
      // Build headers - include auth if available
      final headers = <String, String>{
        'Accept': 'image/*,*/*',
        'User-Agent': 'Mozilla/5.0 (Android) Streamix/1.0',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
      };
      
      // Add Supabase auth if needed (for public URLs that need it)
      try {
        final supabase = Supabase.instance.client;
        final session = supabase.auth.currentSession;
        if (session != null && session.accessToken.isNotEmpty) {
          headers['Authorization'] = 'Bearer ${session.accessToken}';
          print('📥 [RobustImage] Added auth header');
        }
      } catch (e) {
        print('📥 [RobustImage] No auth available (OK for signed URLs): $e');
      }
      
      print('📥 [RobustImage] Request headers: $headers');
      
      final res = await http.get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));
      
      print('📥 [RobustImage] Response status: ${res.statusCode}');
      print('📥 [RobustImage] Response content-type: ${res.headers['content-type']}');
      print('📥 [RobustImage] Response body length: ${res.bodyBytes.length}');
      
      if (res.statusCode == 200) {
        if (res.bodyBytes.isEmpty) {
          print('❌ [RobustImage] Response body is empty!');
          setState(() { 
            _downloading = false; 
            _errorMsg = 'Image file is empty (0 bytes)';
          });
          return;
        }
        
        // Verify it's actually an image
        final contentType = res.headers['content-type'] ?? '';
        if (!contentType.contains('image') && !contentType.contains('octet-stream')) {
          print('⚠️ [RobustImage] WARNING: Content-Type is not an image: $contentType');
          // Continue anyway as some servers don't set proper content-type
        }
        
        print('✅ [RobustImage] Download successful, setting bytes (${res.bodyBytes.length} bytes)');
        if (mounted) {
          setState(() { 
            _bytes = res.bodyBytes; 
            _downloading = false;
            _errorMsg = null;
          });
        }
      } else if (res.statusCode == 403) {
        print('❌ [RobustImage] 403 Forbidden - Supabase bucket may not be public or signed URL expired');
        if (mounted) {
          setState(() { 
            _downloading = false;
            _errorMsg = 'Access denied (403)\nBucket may not be public or URL expired';
          });
        }
      } else if (res.statusCode == 404) {
        print('❌ [RobustImage] 404 Not Found - File does not exist');
        if (mounted) {
          setState(() { 
            _downloading = false;
            _errorMsg = 'Image not found (404)\nFile may have been deleted';
          });
        }
      } else {
        print('❌ [RobustImage] Download failed with status ${res.statusCode}');
        if (mounted) {
          setState(() { 
            _downloading = false;
            _errorMsg = 'Download failed (Status ${res.statusCode})';
          });
        }
      }
    } catch (e, st) {
      print('❌ [RobustImage] Download exception: $e');
      print('❌ [RobustImage] Stack trace: $st');
      if (mounted) {
        setState(() { 
          _downloading = false;
          _errorMsg = 'Network error: ${e.toString().length > 100 ? e.toString().substring(0, 100) : e.toString()}';
        });
      }
    }
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
    _initializeController();
  }

  Future<void> _initializeController() async {
    // Try network-based playback first
    try {
      print('🎬 [VideoPlayer] Attempting network playback: ${widget.videoUrl}');
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl));
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
        _controller.setLooping(true);
        _controller.setVolume(1.0);
        _controller.play();
      });
      print('🎬 [VideoPlayer] Network playback initialized successfully');
      return;
    } catch (e, st) {
      print('⚠️ [VideoPlayer] Network playback FAILED: $e');
      print(st);
    }

    // Network playback failed — download to a local temp file and try file playback
    try {
      final file = await _downloadVideoToTempFile(widget.videoUrl);
      if (file == null) throw Exception('Download failed');
      print('🎬 [VideoPlayer] Playing from local file: ${file.path}');
      _controller = VideoPlayerController.file(file);
      await _controller.initialize();
      setState(() {
        _isInitialized = true;
        _controller.setLooping(true);
        _controller.setVolume(1.0);
        _controller.play();
      });
      print('🎬 [VideoPlayer] Local playback initialized successfully');
      return;
    } catch (e, st) {
      print('❌ [VideoPlayer] Local playback failed: $e');
      print(st);
      // Show error state by leaving _isInitialized false
    }
  }

  Future<File?> _downloadVideoToTempFile(String url) async {
    try {
      final uri = Uri.parse(url);
      final res = await http.get(uri);
      if (res.statusCode != 200) {
        print('❌ [VideoPlayer] Download failed, status ${res.statusCode}');
        return null;
      }
      final tmpDir = await getTemporaryDirectory();
      final filePath = '${tmpDir.path}/video_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final file = File(filePath);
      await file.writeAsBytes(res.bodyBytes);
      return file;
    } catch (e, st) {
      print('❌ [VideoPlayer] Exception while downloading video: $e');
      print(st);
      return null;
    }
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
    if (!_isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
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
