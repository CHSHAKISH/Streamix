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
      setState(() {
        _selectedIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Requests deleted.")));
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
          backgroundColor: Colors.grey[100], // Light background for better contrast
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
              ? const Center(child: Text('You have no requests.', style: TextStyle(color: Colors.grey, fontSize: 16)))
              : ListView.builder(
            padding: const EdgeInsets.only(top: 10, bottom: 80),
            itemCount: requests.length,
            itemBuilder: (context, index) {
              var data = requests[index].data() as Map<String, dynamic>;
              String requestId = requests[index].id;
              String service = data['serviceType'];
              String requester = data['requesterName'];
              String status = data['status'];

              DateTime startTime = (data['startTime'] as Timestamp).toDate();
              DateTime endTime = (data['endTime'] as Timestamp).toDate();
              final now = DateTime.now();

              bool isExpired = now.isAfter(endTime);
              bool isDone = status == 'completed' || isExpired;
              bool isSelected = _selectedIds.contains(requestId);

              // Colors and Text
              Color statusColor;
              String statusText;
              if (isDone) {
                statusColor = Colors.grey;
                statusText = "DONE";
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
                      color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected ? Border.all(color: Theme.of(context).primaryColor, width: 2) : null,
                      boxShadow: [
                        if (!isSelected) BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 6, offset: const Offset(0, 4))
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
                                      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                      child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(service.replaceAll('_', ' ').toUpperCase(), style: const TextStyle(fontSize: 13, color: Colors.black54, letterSpacing: 0.5)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                                    const SizedBox(width: 6),
                                    Text("$dateStr  •  $timeRange", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                                  ],
                                ),

                                // Action Buttons
                                if (!_isSelectionMode && !isDone) ...[
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
                                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accepted!")));
                                          },
                                          style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, foregroundColor: Colors.white),
                                          child: const Text("Accept"),
                                        ),
                                      ],
                                      if (status == 'accepted')
                                        ElevatedButton.icon(
                                          icon: const Icon(Icons.play_arrow, size: 18),
                                          label: const Text("Start Sharing"),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                                          onPressed: () {
                                            final now = DateTime.now();
                                            if (now.isBefore(startTime)) {
                                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Starts at ${DateFormat('h:mm a').format(startTime)}"), backgroundColor: Colors.orange));
                                              return;
                                            }
                                            if (now.isAfter(endTime)) {
                                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Expired"), backgroundColor: Colors.red));
                                              return;
                                            }
                                            Navigator.push(context, MaterialPageRoute(builder: (context) => ActiveSessionScreen(requestId: requestId, serviceType: service, durationInSeconds: durationInSeconds)));
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
            },
          ),
        );
      },
    );
  }
}