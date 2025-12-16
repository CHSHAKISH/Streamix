import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/screens/session/active_session_screen.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/constants/app_colors.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final TicketService _ticketService = TicketService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  // Selection State
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};

  // Auto-Join Listener
  StreamSubscription? _autoJoinSubscription;

  @override
  void initState() {
    super.initState();
    _startAutoJoinListener();
  }

  @override
  void dispose() {
    _autoJoinSubscription?.cancel();
    super.dispose();
  }

  void _startAutoJoinListener() {
    // Listen for accepted requests where I am the peer (Sender)
    _autoJoinSubscription = FirebaseFirestore.instance
        .collection('requests')
        .where('peerUserId', isEqualTo: _currentUserId)
        .where('status', isEqualTo: 'accepted')
        .snapshots()
        .listen((snapshot) {

      final now = DateTime.now();

      for (var doc in snapshot.docs) {
        var data = doc.data();
        Timestamp? startTs = data['startTime'];
        Timestamp? endTs = data['endTime'];

        if (startTs != null && endTs != null) {
          DateTime startTime = startTs.toDate();
          DateTime endTime = endTs.toDate();

          // Check if currently inside the session window
          if (now.isAfter(startTime) && now.isBefore(endTime)) {

            // Basic check: Only launch if this screen is currently visible
            if (mounted && ModalRoute.of(context)?.isCurrent == true) {
              int duration = endTime.difference(startTime).inSeconds;

              // Pause listener to prevent double-launch
              _autoJoinSubscription?.pause();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Session time! Launching automatically...")),
              );

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ActiveSessionScreen(
                    requestId: doc.id,
                    serviceType: data['serviceType'],
                    durationInSeconds: duration,
                    scheduledStartTime: startTime,
                  ),
                ),
              ).then((_) {
                // Resume listening when user comes back
                _autoJoinSubscription?.resume();
              });

              return; // Stop checking other docs
            }
          }
        }
      }
    });
  }

  void _toggleSelection(String requestId) {
    setState(() {
      if (_selectedIds.contains(requestId)) {
        _selectedIds.remove(requestId);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(requestId);
      }
    });
  }

  void _selectAll(List<QueryDocumentSnapshot> docs) {
    setState(() {
      if (_selectedIds.length == docs.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds = docs.map((doc) => doc.id).toSet();
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelected() async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Requests"),
        content: Text("Delete ${_selectedIds.length} selected requests?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Delete", style: TextStyle(color: Colors.red))),
        ],
      ),
    ) ?? false;

    if (confirm) {
      for (String id in _selectedIds) {
        await _ticketService.deleteRequest(id);
      }
      setState(() { _selectedIds.clear(); _isSelectionMode = false; });
    }
  }

  String _getServiceIcon(String serviceType) {
    switch (serviceType) {
      case 'location': return 'assets/images/location.png';
      case 'audio': return 'assets/images/audio.png';
      case 'front_camera': return 'assets/images/front_image.png';
      case 'back_camera': return 'assets/images/back_image.png';
      case 'front_video': return 'assets/images/front_video.png';
      case 'back_video': return 'assets/images/back_video.png';
      case 'front_stream': return 'assets/images/front_live.png';
      case 'back_stream': return 'assets/images/back_live.png';
      default: return 'assets/images/location.png';
    }
  }

  String _formatServiceName(String serviceType) {
    switch (serviceType) {
      case 'location': return 'Location';
      case 'audio': return 'Audio';
      case 'front_camera': return 'Front Camera';
      case 'back_camera': return 'Back Camera';
      case 'front_video': return 'Front Video';
      case 'back_video': return 'Back Video';
      case 'front_stream': return 'Front Stream';
      case 'back_stream': return 'Back Stream';
      default: return serviceType;
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        var requests = snapshot.data?.docs ?? [];

        // Sort Newest First
        requests.sort((a, b) {
          Timestamp timeA = (a.data() as Map<String, dynamic>)['startTime'] ?? Timestamp.now();
          Timestamp timeB = (b.data() as Map<String, dynamic>)['startTime'] ?? Timestamp.now();
          return timeB.compareTo(timeA);
        });

        return Scaffold(
          backgroundColor: Colors.white,
          body: requests.isEmpty
              ? const Center(child: Text('You have no requests.', style: TextStyle(fontSize: 16)))
              : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                var data = requests[index].data() as Map<String, dynamic>;
                String requestId = requests[index].id;
                String status = data['status'];
                String service = data['serviceType'];
                String requester = data['requesterName'];

                DateTime startTime = (data['startTime'] as Timestamp).toDate();
                DateTime endTime = (data['endTime'] as Timestamp).toDate();
                final now = DateTime.now();

                bool isExpired = now.isAfter(endTime);
                int durationInSeconds = endTime.difference(startTime).inSeconds;

                // Status Logic
                String statusText;
                Color statusBgColor;
                Color statusTextColor;
                
                if (status == 'completed' || isExpired) {
                  statusText = 'Completed';
                  statusBgColor = const Color(0xFF1B5E20).withOpacity(0.15);
                  statusTextColor = const Color(0xFF1B5E20);
                } else if (status == 'accepted') {
                  statusText = 'Accepted';
                  statusBgColor = AppColors.lightBackground;
                  statusTextColor = AppColors.accent;
                } else if (status == 'denied') {
                  statusText = 'Rejected';
                  statusBgColor = Colors.red.withOpacity(0.15);
                  statusTextColor = Colors.red;
                } else {
                  statusText = 'Pending';
                  statusBgColor = Colors.yellow.withOpacity(0.2);
                  statusTextColor = const Color(0xFFF57C00);
                }

                String timeRange = "${DateFormat('M/d HH:mm').format(startTime)} - ${DateFormat('M/d HH:mm').format(endTime)}";

                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Service Icon
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(10),
                            child: Image.asset(
                              _getServiceIcon(service),
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Service Name and From
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _formatServiceName(service),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'From: $requester',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Status Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: statusBgColor,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: statusTextColor, width: 1),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                color: statusTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Time Info
                      Row(
                        children: [
                          Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                          const SizedBox(width: 6),
                          Text(
                            timeRange,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      // Action Buttons
                      if (status == 'pending') ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _ticketService.updateRequestStatus(requestId, false),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.pink,
                                  side: const BorderSide(color: Colors.pink),
                                  backgroundColor: Colors.pink.shade50,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text(
                                  'Reject',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  _ticketService.updateRequestStatus(requestId, true);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text("Accepted! Session will start automatically at the scheduled time."))
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.lightBackground,
                                  foregroundColor: AppColors.accent,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(30),
                                  ),
                                ),
                                child: const Text(
                                  'Accept',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (status == 'accepted' && !isExpired) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {
                              if (DateTime.now().isBefore(startTime)) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text("Starts at ${DateFormat('h:mm a').format(startTime)}"), backgroundColor: Colors.orange)
                                );
                                return;
                              }
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ActiveSessionScreen(
                                    requestId: requestId,
                                    serviceType: service,
                                    durationInSeconds: durationInSeconds,
                                    scheduledStartTime: startTime,
                                  ),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(color: AppColors.primary, width: 2),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            child: const Text(
                              'Open Session',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }
          ),
        );
      },
    );
  }
}