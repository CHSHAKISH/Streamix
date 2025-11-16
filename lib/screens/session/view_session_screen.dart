import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:streamix/services/location_service.dart';

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

  // --- THIS IS THE NEW LOGIC ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Viewing: ${widget.serviceType}'),
      ),
      // We listen to the TICKET document to get the status
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

          // Now we show the correct UI based on the status
          // --- FIX: Show "Session Ended" ---
          if (status == 'completed') {
            return const Center(
              child: Text(
                'Session has ended.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            );
          }

          if (status == 'accepted') {
            // The session is live! Show the correct viewer.
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
  // --- END OF NEW LOGIC ---

  // This helper builds the correct viewer widget
  Widget _buildViewer(String serviceType) {
    switch (serviceType) {
      case 'location':
        return _LocationViewer(requestId: widget.requestId);

    // ... (other cases)
      default:
        return Text('Viewer for ${widget.serviceType}');
    }
  }
}

// --- LOCATION VIEWER WIDGET (Unchanged) ---
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