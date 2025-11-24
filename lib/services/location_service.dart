import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  final _supabase = Supabase.instance.client;
  final Location _location = Location();

  /// Sends the sender's location to the 'live_sessions' table.
  Future<void> updateSenderLocation(String ticketId, LocationData location) async {
    try {
      await _supabase.from('live_sessions').upsert({
        'ticket_id': ticketId,
        'lat': location.latitude,
        'lng': location.longitude,
      }, onConflict: 'ticket_id');
    } catch (e) {
      print('Error updating Supabase location: $e');
    }
  }

  /// Enable Background Mode with Notification (The Fix)
  Future<void> enableBackgroundMode() async {
    try {
      // Essential for Android to keep the service alive in background
      await _location.enableBackgroundMode(enable: true);

      // Configure the persistent notification
      await _location.changeNotificationOptions(
        title: 'Streamix Location Sharing',
        subtitle: 'You are sharing your location live.',
        iconName: '@mipmap/ic_launcher', // Ensure this icon exists
        onTapBringToFront: true,
      );
    } catch (e) {
      print("Error enabling background mode: $e");
    }
  }

  /// Disable Background Mode
  Future<void> disableBackgroundMode() async {
    try {
      await _location.enableBackgroundMode(enable: false);
    } catch (e) {
      print("Error disabling background mode: $e");
    }
  }

  /// Gets a REALTIME stream of location data for a specific ticket.
  Stream<Map<String, dynamic>> getSessionStream(String ticketId) {
    return _supabase
        .from('live_sessions')
        .stream(primaryKey: ['ticket_id'])
        .eq('ticket_id', ticketId)
        .map((listOfMaps) {
      if (listOfMaps.isEmpty) {
        return <String, dynamic>{};
      }
      return listOfMaps.first;
    });
  }

  /// Deletes the sender's location row from the 'live_sessions' table.
  Future<void> deleteSenderLocation(String ticketId) async {
    try {
      await _supabase
          .from('live_sessions')
          .delete()
          .eq('ticket_id', ticketId);
    } catch (e) {
      print('Error deleting Supabase location: $e');
    }
  }
}