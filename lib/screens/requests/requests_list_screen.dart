import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/screens/session/active_session_screen.dart'; // Camera, Video & Audio
import 'package:streamix/services/background_stream_service.dart';    // Background Streaming
import 'package:streamix/services/location_service.dart';             // Location
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/services/notification_service.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final TicketService _ticketService = TicketService();
  final LocationService _locationService = LocationService();
  final NotificationService _notificationService = NotificationService();
  late final String _currentUserId;
  Timer? _timer;
  StreamSubscription? _newRequestSubscription;
  final Set<String> _shownRequests = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
    });
    if (_currentUserId.isNotEmpty) {
      _listenForNewRequests();
    }
  }

  void _listenForNewRequests() {
    // Listen for new incoming requests
    _newRequestSubscription = FirebaseFirestore.instance
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null) {
            final requestId = change.doc.id;
            
            // Don't show notification if we've already shown it
            if (_shownRequests.contains(requestId)) {
              continue;
            }
            _shownRequests.add(requestId);
            
            final requesterName = data['requesterName'] as String? ?? 'Someone';
            final serviceType = data['serviceType'] as String?;
            
            // Show notification after a small delay to ensure context is ready
            Future.delayed(const Duration(milliseconds: 500), () {
              if (context.mounted) {
                _notificationService.showInAppNotification(
                  context,
                  'New Request! 📩',
                  '$requesterName is requesting $serviceType',
                  backgroundColor: Colors.blue.shade900,
                );
              }
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _newRequestSubscription?.cancel();
    super.dispose();
  }

  void _openSession(String requestId, String service, DateTime start, DateTime end) {
    // For STREAM services: Use background service - NO navigation!
    // User B stays on current screen, stream runs in background
    if (service.contains('stream')) {
      print('🎬 Starting BACKGROUND stream service for $service');
      final backgroundService = BackgroundStreamService();
      backgroundService.startStream(
        requestId: requestId,
        serviceType: service,
        scheduledStartTime: start,
        scheduledEndTime: end,
      );
      
      // Show confirmation to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '📹 ${service == 'front_stream' ? 'Front' : 'Back'} camera stream started in background\n'
              'Keep app open. Stream will run until ${DateFormat('h:mm a').format(end)}',
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
    // For other services (camera, video, audio): Use ActiveSessionScreen
    else if (service.contains('video') || service.contains('camera') || service == 'audio') {
      if (context.mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionScreen(
            requestId: requestId,
            serviceType: service,
            scheduledStartTime: start,
            scheduledEndTime: end
        )));
      }
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
                                  // Permissions are requested at app startup, just accept the request
                                  await _ticketService.updateRequestStatus(requestId, true);
                                  
                                  if (isLocation && isTimeWindowOpen) {
                                    _locationService.startBackgroundSharing(ticketId: requestId, endTime: endTime);
                                  }
                                  
                                  // For STREAM services: Start background service immediately
                                  // User B stays on current screen - NO navigation!
                                  if (service.contains('stream')) {
                                    print('🎬 Starting background stream service for $service');
                                    final backgroundService = BackgroundStreamService();
                                    await backgroundService.startStream(
                                      requestId: requestId,
                                      serviceType: service,
                                      scheduledStartTime: startTime,
                                      scheduledEndTime: endTime,
                                    );
                                    
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '📹 ${service == 'front_stream' ? 'Front' : 'Back'} camera stream started in background\n'
                                            'Keep app open. Stream will run until ${DateFormat('h:mm a').format(endTime)}',
                                          ),
                                          backgroundColor: Colors.green,
                                          duration: const Duration(seconds: 4),
                                        ),
                                      );
                                    }
                                  }
                                  // For AUDIO service: Navigate to ActiveSessionScreen
                                  else if (service == 'audio') {
                                    if (context.mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ActiveSessionScreen(
                                            requestId: requestId,
                                            serviceType: service,
                                            scheduledStartTime: startTime,
                                            scheduledEndTime: endTime,
                                          ),
                                        ),
                                      );
                                    }
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

                        if (isMedia && (isAccepted || isCompleted) && isTimeWindowOpen && !service.contains('stream'))
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.videocam),
                              label: const Text("OPEN SESSION"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                              onPressed: () => _openSession(requestId, service, startTime, endTime),
                            ),
                          ),
                        
                        if (service.contains('stream') && (isAccepted || isCompleted) && !isExpired)
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.green),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.videocam, color: Colors.green, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Streaming in background',
                                    style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
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