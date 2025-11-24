import 'dart:async';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:streamix/services/ticket_service.dart';

class LocationService {
  // Singleton
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final _supabase = Supabase.instance.client;
  final Location _location = Location();
  final TicketService _ticketService = TicketService();

  StreamSubscription<LocationData>? _locationSubscription;
  Timer? _heartbeatTimer;
  bool _isSharing = false;
  String? _currentTicketId;

  bool get isSharing => _isSharing;

  // --- START SHARING (Fault Tolerant) ---
  Future<void> startBackgroundSharing({
    required String ticketId,
    required DateTime endTime
  }) async {
    if (_isSharing) return;

    try {
      _currentTicketId = ticketId;
      print("🚀 [LocationService] Attempting to start for ID: $ticketId");

      // 1. Basic Permission (While using app)
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) {
          print("❌ GPS Service Disabled by User");
          return;
        }
      }

      PermissionStatus permission = await _location.hasPermission();
      if (permission == PermissionStatus.denied) {
        permission = await _location.requestPermission();
        if (permission != PermissionStatus.granted) {
          print("❌ Permission Denied");
          return;
        }
      }

      // 2. Try Background Mode (The "Allow all the time" part)
      try {
        await _location.enableBackgroundMode(enable: true);

        // Android Notification
        await _location.changeNotificationOptions(
          title: 'Streamix Location Live',
          subtitle: 'Sharing location with User A...',
          onTapBringToFront: true,
          iconName: '@mipmap/ic_launcher',
        );
        print("✅ Background Mode Enabled");
      } catch (e) {
        // IF BACKGROUND FAILS, CONTINUE ANYWAY (Fallback)
        print("⚠️ Background mode failed ($e). Running in Foreground mode.");
      }

      // 3. Update State Immediately
      _isSharing = true;

      // 4. FORCE IMMEDIATE UPLOAD
      try {
        LocationData initialLoc = await _location.getLocation();
        await _updateSupabase(ticketId, initialLoc);
        print("📍 Initial Location Uploaded: ${initialLoc.latitude}, ${initialLoc.longitude}");
      } catch (e) {
        print("⚠️ Could not get initial location, waiting for stream: $e");
      }

      // 5. Start Stream
      _locationSubscription = _location.onLocationChanged.listen((LocationData loc) {
        if (DateTime.now().isAfter(endTime)) {
          stopSharing();
          return;
        }
        _updateSupabase(ticketId, loc);
      });

      // 6. Heartbeat (Keep connection alive)
      _heartbeatTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
        if (!_isSharing) { timer.cancel(); return; }
        try {
          LocationData current = await _location.getLocation();
          _updateSupabase(ticketId, current);
        } catch (_) {}
      });

      // 7. Notify User A
      await _ticketService.notifySessionStarted(ticketId);

    } catch (e) {
      print("❌ [LocationService] CRITICAL ERROR: $e");
      _isSharing = false; // Reset on failure
    }
  }

  // --- STOP SHARING ---
  Future<void> stopSharing() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    _heartbeatTimer?.cancel();

    try { await _location.enableBackgroundMode(enable: false); } catch (_) {}

    if (_currentTicketId != null) {
      await _ticketService.completeRequest(_currentTicketId!);
      // We DELETE the row so User A knows session ended
      await _supabase.from('live_sessions').delete().eq('ticket_id', _currentTicketId!);
    }

    _isSharing = false;
    _currentTicketId = null;
    print("🛑 Service Stopped");
  }

  // --- DATABASE WRITE ---
  Future<void> _updateSupabase(String ticketId, LocationData loc) async {
    try {
      await _supabase.from('live_sessions').upsert({
        'ticket_id': ticketId,
        'lat': loc.latitude,
        'lng': loc.longitude,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'ticket_id');
    } catch (e) {
      print("❌ Supabase Write Error: $e");
    }
  }

  // --- RECEIVER STREAM ---
  Stream<List<Map<String, dynamic>>> getSessionStream(String ticketId) {
    return _supabase
        .from('live_sessions')
        .stream(primaryKey: ['ticket_id'])
        .eq('ticket_id', ticketId);
  }
}