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
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          var data = snapshot.data!.data() as Map<String, dynamic>;
          // Use pre-loaded URL if provided, otherwise read from Firestore
          String? mediaUrl = widget.initialMediaUrl ?? data['mediaUrl'];
          String command = data['remoteCommand'] ?? 'IDLE';
          String status = data['status'] ?? '';
          String? errorMessage = data['errorMessage'];
          
          print('🔍🔍🔍 [ViewSession] ========== DIAGNOSTIC INFO ==========');
          print('🔍 [ViewSession] RequestId: ${widget.requestId}');
          print('🔍 [ViewSession] ServiceType: ${widget.serviceType}');
          print('🔍 [ViewSession] mediaUrl: $mediaUrl');
          print('🔍 [ViewSession] mediaUrl.length: ${mediaUrl?.length ?? 0}');
          print('🔍 [ViewSession] command: $command');
          print('🔍 [ViewSession] status: $status');
          print('🔍 [ViewSession] errorMessage: $errorMessage');
          print('🔍 [ViewSession] Full document keys: ${data.keys.toList()}');
          
          // Check for ERROR state from User B
          if (command == 'ERROR' && errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 80),
                    const SizedBox(height: 20),
                    const Text(
                      'Capture Failed',
                      style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      errorMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 30),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Go Back'),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
            );
          }
          
          // Debug: If command is COMPLETED but mediaUrl is null, log full data
          if (command == 'COMPLETED' && (mediaUrl == null || mediaUrl.isEmpty)) {
            print('⚠️⚠️⚠️ [ViewSession] CRITICAL: Command is COMPLETED but mediaUrl is MISSING!');
            print('⚠️ [ViewSession] Full document data: $data');
          }
          
          // Check if mediaUrl exists but is invalid
          if (mediaUrl != null && mediaUrl.isNotEmpty) {
            if (!mediaUrl.startsWith('http')) {
              print('❌❌❌ [ViewSession] INVALID URL: Does not start with http!');
            }
            if (mediaUrl.contains('null') || mediaUrl.contains('undefined')) {
              print('❌❌❌ [ViewSession] INVALID URL: Contains null/undefined!');
            }
          }
          print('🔍 [ViewSession] ========================================');
          
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
            // Debug output
            print('🔍 [ViewSession] Camera view - mediaUrl: $mediaUrl');
            print('🔍 [ViewSession] mediaUrl isEmpty: ${mediaUrl?.isEmpty}');
            print('🔍 [ViewSession] mediaUrl length: ${mediaUrl?.length}');
            
            return Container(
              color: Colors.black,
              child: Stack(
                children: [
                  // Fullscreen Image Display
                  Center(
                    child: mediaUrl != null && mediaUrl.isNotEmpty
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Loading image...',
                                style: TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                              SizedBox(height: 10),
                              Text(
                                'URL: ${mediaUrl.substring(0, mediaUrl.length > 50 ? 50 : mediaUrl.length)}...',
                                style: TextStyle(color: Colors.white38, fontSize: 10),
                              ),
                              SizedBox(height: 20),
                              Expanded(
                                child: InteractiveViewer(
                                  child: _RobustNetworkImage(url: mediaUrl),
                                ),
                              ),
                            ],
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
                              ] else if (errorMessage != null && errorMessage.isNotEmpty) ...[
                                const Icon(Icons.error_outline, size: 80, color: Colors.red),
                                const SizedBox(height: 20),
                                Text(
                                  'Error:\n$errorMessage',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red, fontSize: 16),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.settings),
                                  label: const Text('Check Settings'),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Ask User B to enable Camera permissions in Settings'))
                                    );
                                  },
                                ),
                              ] else ...[
                                const Icon(Icons.photo_camera, size: 80, color: Colors.grey),
                                const SizedBox(height: 20),
                                Text(
                                  "Waiting for photo...\nURL available: ${mediaUrl != null}\nURL empty: ${mediaUrl?.isEmpty ?? true}",
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
                              ] else if (errorMessage != null && errorMessage.isNotEmpty) ...[
                                const Icon(Icons.error_outline, size: 80, color: Colors.red),
                                const SizedBox(height: 20),
                                Text(
                                  'Error:\n$errorMessage',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red, fontSize: 16),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.settings),
                                  label: const Text('Check Settings'),
                                  onPressed: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Ask User B to enable Camera and Microphone permissions'))
                                    );
                                  },
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
          if (widget.serviceType == 'location') {
            return _LocationViewer(requestId: widget.requestId);
          }

          return const Center(
            child: Text("Waiting...", style: TextStyle(color: Colors.white)),
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
      return Container(
        color: Colors.black,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: Image.memory(
                _bytes!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  print('❌ [RobustImage] Image.memory error: $error');
                  return _buildErrorWidget('Memory display failed: $error');
                },
              ),
            ),
            Container(
              color: Colors.black87,
              padding: EdgeInsets.all(8),
              child: Text(
                '✅ Image loaded (${(_bytes!.length / 1024).toStringAsFixed(1)} KB)',
                style: TextStyle(color: Colors.green, fontSize: 10),
              ),
            ),
          ],
        ),
      );
    }

    if (_downloading) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Downloading image...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
              if (_retryCount > 0)
                Text(
                  'Attempt ${_retryCount + 1}',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              SizedBox(height: 8),
              Text(
                widget.url.length > 80 
                    ? '${widget.url.substring(0, 80)}...' 
                    : widget.url,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white24, fontSize: 8),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMsg != null) {
      return _buildErrorWidget(_errorMsg!);
    }

    return Container(
      color: Colors.black,
      child: Center(
        child: Text(
          'Initializing...',
          style: TextStyle(color: Colors.white38),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String message) {
    return Container(
      color: Colors.black,
      padding: EdgeInsets.all(24),
      child: Center(
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
