import 'dart:async';
import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:streamix/services/ticket_service.dart';

class LocationService {
  // 1. Singleton Factory
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  final _supabase = Supabase.instance.client;
  final Location _location = Location();
  final TicketService _ticketService = TicketService();

  StreamSubscription<LocationData>? _locationSubscription;
  bool _isSharing = false;
  String? _currentTicketId;

  // Getter to check status
  bool get isSharing => _isSharing;

  // --- START BACKGROUND SHARING (THIS WAS MISSING) ---
  Future<void> startBackgroundSharing({
    required String ticketId,
    required DateTime endTime
  }) async {
    if (_isSharing) return;

    try {
      _currentTicketId = ticketId;

      // Permission Check
      bool serviceEnabled = await _location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await _location.requestService();
        if (!serviceEnabled) return;
      }

      // Enable Background Mode
      await _location.enableBackgroundMode(enable: true);
      await _location.changeNotificationOptions(
        title: 'Streamix Active',
        subtitle: 'Sharing location...',
        onTapBringToFront: true,
        iconName: '@mipmap/ic_launcher',
      );

      // Force First Update
      LocationData initialLoc = await _location.getLocation();
      await _updateSupabase(ticketId, initialLoc);

      // Start Listener
      _locationSubscription = _location.onLocationChanged.listen((LocationData loc) async {
        if (DateTime.now().isAfter(endTime)) {
          stopSharing();
          return;
        }
        await _updateSupabase(ticketId, loc);
      });

      // Notify User A
      await _ticketService.notifySessionStarted(ticketId);

      _isSharing = true;

    } catch (e) {
      print("❌ [LocationService] Start Error: $e");
    }
  }

  // --- STOP SHARING ---
  Future<void> stopSharing() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;

    try {
      await _location.enableBackgroundMode(enable: false);
    } catch (_) {}

    if (_currentTicketId != null) {
      await _ticketService.completeRequest(_currentTicketId!);
      await _supabase.from('live_sessions').delete().eq('ticket_id', _currentTicketId!);
    }

    _isSharing = false;
    _currentTicketId = null;
  }

  // --- SUPABASE WRITE ---
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

  // Update methods for manual calls if needed
  Future<void> updateSenderLocation(String ticketId, LocationData location) async {
    await _updateSupabase(ticketId, location);
  }

  Future<void> enableBackgroundMode() async {
    await _location.enableBackgroundMode(enable: true);
  }

  Future<void> disableBackgroundMode() async {
    await _location.enableBackgroundMode(enable: false);
  }

  Future<void> deleteSenderLocation(String ticketId) async {
    await _supabase.from('live_sessions').delete().eq('ticket_id', ticketId);
  }
}