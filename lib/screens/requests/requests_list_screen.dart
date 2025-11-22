import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/screens/session/active_session_screen.dart';
import 'package:streamix/services/ticket_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('peerUserId', isEqualTo: _currentUserId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(appBar: AppBar(title: const Text('My Requests')), body: const Center(child: CircularProgressIndicator()));
        }

        var requests = snapshot.data?.docs ?? [];

        // Sort Newest First
        requests.sort((a, b) {
          Timestamp timeA = (a.data() as Map<String, dynamic>)['startTime'] ?? Timestamp.now();
          Timestamp timeB = (b.data() as Map<String, dynamic>)['startTime'] ?? Timestamp.now();
          return timeB.compareTo(timeA);
        });

        return Scaffold(
          appBar: AppBar(
            leading: _isSelectionMode
                ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isSelectionMode = false; _selectedIds.clear(); }))
                : null,
            title: Text(_isSelectionMode ? '${_selectedIds.length} Selected' : 'My Requests'),
            actions: [
              if (_isSelectionMode) ...[
                IconButton(
                  icon: Icon(_selectedIds.length == requests.length ? Icons.deselect : Icons.select_all),
                  onPressed: () => _selectAll(requests),
                ),
                IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
              ]
            ],
          ),
          body: requests.isEmpty
              ? const Center(child: Text('You have no requests.', style: TextStyle(fontSize: 16)))
              : ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 80),
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
                bool isDone = status == 'completed' || isExpired;
                bool isSelected = _selectedIds.contains(requestId);

                // Status Logic
                String statusText = status.toUpperCase();
                Color statusColor = Colors.orange;
                if (isDone) {
                  statusText = "DONE"; statusColor = Colors.grey;
                } else if (status == 'accepted') {
                  statusColor = Colors.green;
                  statusText = "ACCEPTED";
                } else if (status == 'denied') {
                  statusColor = Colors.red;
                  statusText = "DENIED";
                } else {
                  statusColor = Colors.orange;
                  statusText = "PENDING";
                }

                // Dynamic Card Color
                Color cardColor;
                if (isSelected) {
                  cardColor = Theme.of(context).primaryColor.withOpacity(isDarkMode ? 0.3 : 0.1);
                } else if (status == 'accepted') {
                  cardColor = isDarkMode ? Colors.green.withOpacity(0.15) : Colors.green.shade50;
                } else {
                  cardColor = Theme.of(context).cardColor;
                }

                String dateStr = DateFormat('MMM d').format(startTime);
                String timeRange = "${DateFormat('h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}";
                int durationInSeconds = endTime.difference(startTime).inSeconds;

                return InkWell(
                  onLongPress: () {
                    setState(() {
                      _isSelectionMode = true;
                      _toggleSelection(requestId);
                    });
                  },
                  onTap: () {
                    if (_isSelectionMode) _toggleSelection(requestId);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                        boxShadow: [
                          if (!isSelected && !isDarkMode)
                            BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 4))
                        ]
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          // Status Strip
                          Container(
                            width: 6,
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                            ),
                          ),
                          // Content
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(requester, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: statusColor.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(service.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 13, color: isDarkMode ? Colors.grey[400] : Colors.black54, letterSpacing: 0.5)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.calendar_today, size: 14, color: isDarkMode ? Colors.grey[400] : Colors.grey),
                                      const SizedBox(width: 6),
                                      Text("$dateStr  •  $timeRange", style: TextStyle(fontSize: 14, color: isDarkMode ? Colors.white70 : Colors.black87)),
                                    ],
                                  ),

                                  // Action Buttons
                                  if (!_isSelectionMode && !isDone && status != 'denied') ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (status == 'pending') ...[
                                          OutlinedButton(
                                            onPressed: () => _ticketService.updateRequestStatus(requestId, false),
                                            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                                            child: const Text("Deny"),
                                          ),
                                          const SizedBox(width: 12),
                                          ElevatedButton(
                                            onPressed: () {
                                              _ticketService.updateRequestStatus(requestId, true);
                                              // We just accept; Auto-join listener will handle navigation when time comes
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accepted! Session will start automatically at the scheduled time.")));
                                            },
                                            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                                            child: const Text("Accept"),
                                          ),
                                        ],
                                        if (status == 'accepted')
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.open_in_new, size: 16),
                                            label: const Text("Open Session"),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                            onPressed: () {
                                              if (DateTime.now().isBefore(startTime)) {
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Starts at ${DateFormat('h:mm a').format(startTime)}"), backgroundColor: Colors.orange));
                                                return;
                                              }
                                              if (DateTime.now().isAfter(endTime)) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Expired"), backgroundColor: Colors.red));
                                                return;
                                              }
                                              Navigator.push(context, MaterialPageRoute(builder: (_) => ActiveSessionScreen(requestId: requestId, serviceType: service, durationInSeconds: durationInSeconds, scheduledStartTime: startTime)));
                                            },
                                          )
                                      ],
                                    )
                                  ]
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
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