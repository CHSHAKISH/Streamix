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

  void _enterSession(String requestId, String service, DateTime startTime, DateTime endTime) {
    // Calculate how long the session should run
    // If we are starting late (e.g. 1 min after start time), we reduce the duration.
    final now = DateTime.now();

    // Default duration is total time between start and end
    int duration = endTime.difference(startTime).inSeconds;

    // If starting late, adjust duration so it still stops at endTime
    if (now.isAfter(startTime)) {
      duration = endTime.difference(now).inSeconds;
    }

    if (duration <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This session has already expired."), backgroundColor: Colors.red));
      return;
    }

    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ActiveSessionScreen(
              requestId: requestId,
              serviceType: service,
              durationInSeconds: duration,
              scheduledStartTime: startTime, // Pass start time for auto-wait logic
            )
        )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() { _isSelectionMode = false; _selectedIds.clear(); })) : null,
        title: Text(_isSelectionMode ? '${_selectedIds.length} Selected' : 'My Requests'),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(icon: const Icon(Icons.select_all), onPressed: () {}),
            IconButton(icon: const Icon(Icons.delete), onPressed: _deleteSelected),
          ]
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('requests').where('peerUserId', isEqualTo: _currentUserId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var requests = snapshot.data!.docs;

          // Sort Newest First
          requests.sort((a, b) {
            Timestamp t1 = (a.data() as Map)['startTime'] ?? Timestamp.now();
            Timestamp t2 = (b.data() as Map)['startTime'] ?? Timestamp.now();
            return t2.compareTo(t1);
          });

          if (requests.isEmpty) return const Center(child: Text("No requests yet."));

          return ListView.builder(
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
                if (isExpired) { statusText = "DONE"; statusColor = Colors.grey; }
                else if (status == 'accepted') { statusColor = Colors.green; }
                else if (status == 'denied') { statusColor = Colors.red; }

                return InkWell(
                  onLongPress: () { setState(() { _isSelectionMode = true; _toggleSelection(requestId); }); },
                  onTap: () { if (_isSelectionMode) _toggleSelection(requestId); },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: isSelected ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                        boxShadow: [ BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, 2)) ]
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            decoration: BoxDecoration(color: statusColor, borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12))),
                          ),
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
                                        decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                        child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                      )
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(service.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 13, color: Colors.grey)),
                                  const SizedBox(height: 8),
                                  Text("${DateFormat('MMM d, h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}", style: const TextStyle(fontSize: 14)),

                                  // Action Buttons
                                  if (!_isSelectionMode && !isDone) ...[
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        if (status == 'pending') ...[
                                          TextButton(onPressed: () => _ticketService.updateRequestStatus(requestId, false), child: const Text("Deny", style: TextStyle(color: Colors.red))),
                                          const SizedBox(width: 8),
                                          // ACCEPT & ENTER IMMEDIATELY
                                          ElevatedButton(
                                            onPressed: () {
                                              _ticketService.updateRequestStatus(requestId, true);
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request Accepted. Loading session...")));
                                              _enterSession(requestId, service, startTime, endTime);
                                            },
                                            child: const Text("Accept"),
                                          ),
                                        ],
                                        // OPEN SESSION (If already accepted but not started/finished)
                                        if (status == 'accepted')
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.open_in_new, size: 16),
                                            label: const Text("Open Session"),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                            onPressed: () => _enterSession(requestId, service, startTime, endTime),
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
          );
        },
      ),
    );
  }
}