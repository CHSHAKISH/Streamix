import 'package:location/location.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationService {
  final _supabase = Supabase.instance.client;

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

  /// --- THIS IS THE CORRECTED FUNCTION ---
  /// Gets a REALTIME stream of location data for a specific ticket.
  Stream<Map<String, dynamic>> getSessionStream(String ticketId) {
    // Use the .stream() method to listen to changes on the table
    return _supabase
        .from('live_sessions')
        .stream(primaryKey: ['ticket_id']) // Tell Supabase what the primary key is
        .eq('ticket_id', ticketId) // Filter for *only* our ticket
        .map((listOfMaps) {
      // The stream returns a List, but we only ever want the first item.
      if (listOfMaps.isEmpty) {
        return <String, dynamic>{}; // Return an empty map if no data
      }
      return listOfMaps.first; // Return the first (and only) map
    });
  }
  /// --- END OF CORRECTION ---

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