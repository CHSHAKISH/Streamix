import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:streamix/screens/session/active_session_screen.dart'; // Photo
import 'package:streamix/screens/session/audio_session_screen.dart';  // Audio
import 'package:streamix/screens/session/video_session_screen.dart';  // NEW: Video
import 'package:streamix/services/ticket_service.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final TicketService _ticketService = TicketService();
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

  // --- CENTRALIZED ROUTER ---
  void _openSession(String requestId, String service) {
    if (service == 'audio') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => AudioSessionScreen(requestId: requestId)));
    } else if (service.contains('video')) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VideoSessionScreen(requestId: requestId, serviceType: service)));
    } else {
      // Camera (Front/Back Photo)
      Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionScreen(requestId: requestId, serviceType: service)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('peerUserId', isEqualTo: _currentUserId)
          .snapshots(),
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
          body: requests.isEmpty
              ? const Center(child: Text('No requests.'))
              : ListView.builder(
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

                // Check if service supports Auto-Start (Camera, Audio, Video)
                bool isAutoService = service.contains('camera') || service == 'audio' || service.contains('video');

                bool isExpired = now.isAfter(endTime);
                bool isFuture = now.isBefore(startTime);

                // Button Logic
                bool showRetryButton = isCompleted && !isExpired;

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(requester, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCompleted ? Colors.blue.withOpacity(0.1) : (isAccepted ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(status.toUpperCase(), style: TextStyle(
                                  color: isCompleted ? Colors.blue : (isAccepted ? Colors.green : Colors.orange),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12
                              )),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text("${service.toUpperCase()}"),
                        Text(dateStr, style: TextStyle(color: Colors.grey[600], fontSize: 12)),

                        const SizedBox(height: 12),

                        // --- 1. PENDING ---
                        if (isPending && !isExpired)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton(
                                onPressed: () => _ticketService.updateRequestStatus(requestId, false),
                                child: const Text("Deny"),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () async {
                                  if (isAutoService) {
                                    // Permission Check based on Type
                                    var perms = <Permission>[];
                                    if (service.contains('camera') || service.contains('video')) perms.add(Permission.camera);
                                    if (service == 'audio' || service.contains('video')) perms.add(Permission.microphone);

                                    Map<Permission, PermissionStatus> statuses = await perms.request();
                                    if (statuses.values.any((s) => s.isDenied)) return;
                                  }
                                  await _ticketService.updateRequestStatus(requestId, true);

                                  if (isAutoService && mounted) {
                                    _openSession(requestId, service);
                                  }
                                },
                                child: const Text("ACCEPT & START"),
                              ),
                            ],
                          ),

                        // --- 2. RETRY / RE-OPEN ---
                        if (isAutoService)
                          if (isAccepted && !isExpired)
                            Align(
                              alignment: Alignment.centerRight,
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.play_arrow),
                                label: const Text("OPEN SESSION"),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                onPressed: () => _openSession(requestId, service),
                              ),
                            )
                          else if (showRetryButton)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                    "Expires in ${endTime.difference(now).inMinutes}m",
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  // Dynamic Label
                                  label: Text(
                                      service == 'audio' ? "RECORD AGAIN" :
                                      service.contains('video') ? "REC VIDEO AGAIN" : "CLICK AGAIN"
                                  ),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                  onPressed: () => _openSession(requestId, service),
                                ),
                              ],
                            )
                          else if (isExpired)
                              const Align(alignment: Alignment.centerRight, child: Text("Session Expired", style: TextStyle(color: Colors.red, fontStyle: FontStyle.italic)))
                            else if (isFuture)
                                Align(alignment: Alignment.centerRight, child: Text("Starts at ${DateFormat('h:mm a').format(startTime)}", style: const TextStyle(color: Colors.grey))),
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