import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/screens/session/active_session_screen.dart'; // Camera
import 'package:streamix/screens/session/audio_session_screen.dart';  // Audio
import 'package:streamix/screens/session/video_session_screen.dart';  // Video
// REMOVED STREAM IMPORT
import 'package:streamix/services/location_service.dart';             // Location
import 'package:streamix/services/ticket_service.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final TicketService _ticketService = TicketService();
  final LocationService _locationService = LocationService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _openSession(String requestId, String service, DateTime start, DateTime end) {
    if (service == 'audio') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AudioSessionScreen(requestId: requestId)));
    } else if (service.contains('video')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoSessionScreen(requestId: requestId, serviceType: service)));
    } else if (service.contains('camera')) {
      // Route to Standard Camera Session (No Remote Trigger)
      Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionScreen(
          requestId: requestId,
          serviceType: service,
          scheduledStartTime: start,
          scheduledEndTime: end
      )));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('requests').where('peerUserId', isEqualTo: _currentUserId).snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        var requests = snapshot.data!.docs;
        requests.sort((a, b) {
          Timestamp tA = (a.data() as Map)['createdAt'] ?? Timestamp.now();
          Timestamp tB = (b.data() as Map)['createdAt'] ?? Timestamp.now();
          return tB.compareTo(tA);
        });

        return Scaffold(
          appBar: AppBar(title: const Text('My Requests')),
          body: requests.isEmpty ? const Center(child: Text('No requests.')) : ListView.builder(
              itemCount: requests.length,
              itemBuilder: (context, index) {
                var data = requests[index].data() as Map<String, dynamic>;
                String requestId = requests[index].id;
                String status = data['status'];
                String service = data['serviceType'];
                String requester = data['requesterName'];

                DateTime startTime = (data['startTime'] as Timestamp).toDate();
                DateTime endTime = (data['endTime'] as Timestamp).toDate();
                String dateStr = DateFormat('MMM d, h:mm a').format(startTime);
                final now = DateTime.now();

                bool isPending = status == 'pending';
                bool isAccepted = status == 'accepted';
                bool isCompleted = status == 'completed';
                bool isExpired = now.isAfter(endTime);
                bool isTimeWindowOpen = !now.isBefore(startTime) && !isExpired;

                bool isLocation = service == 'location';
                bool isMedia = !isLocation;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(requester, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(status.toUpperCase(), style: TextStyle(color: isAccepted ? Colors.green : Colors.grey, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Text("${service.toUpperCase()}  •  $dateStr"),
                        const SizedBox(height: 10),

                        if (isPending && !isExpired)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(onPressed: () => _ticketService.updateRequestStatus(requestId, false), child: const Text("Deny")),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () async {
                                  if (isLocation) await Permission.location.request();
                                  else await Permission.camera.request();

                                  await _ticketService.updateRequestStatus(requestId, true);
                                  if (isLocation && isTimeWindowOpen) {
                                    _locationService.startBackgroundSharing(ticketId: requestId, endTime: endTime);
                                  }
                                },
                                child: const Text("ACCEPT"),
                              ),
                            ],
                          ),

                        if (isLocation && isAccepted && !isExpired)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(_locationService.isSharing ? "SHARING LIVE" : (isTimeWindowOpen ? "Ready" : "Scheduled"), style: TextStyle(color: _locationService.isSharing ? Colors.red : Colors.grey)),
                              if (_locationService.isSharing)
                                ElevatedButton.icon(icon: const Icon(Icons.stop), label: const Text("Stop"), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), onPressed: () async { await _locationService.stopSharing(); setState((){}); })
                              else if (isTimeWindowOpen)
                                ElevatedButton.icon(icon: const Icon(Icons.play_arrow), label: const Text("Resume"), style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: () async { await _locationService.startBackgroundSharing(ticketId: requestId, endTime: endTime); setState((){}); })
                            ],
                          ),

                        if (isMedia && (isAccepted || isCompleted) && isTimeWindowOpen)
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.videocam),
                              label: const Text("OPEN SESSION"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                              onPressed: () => _openSession(requestId, service, startTime, endTime),
                            ),
                          ),

                        if (isExpired) const Align(alignment: Alignment.centerRight, child: Text("Expired", style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  ),
                );
              }
          ),
        );
      },
    );
  }
}