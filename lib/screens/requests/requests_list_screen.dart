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

  // --- NEW: Selection State ---
  bool _isSelectionMode = false;
  Set<String> _selectedIds = {};

  void _toggleSelection(String requestId) {
    setState(() {
      if (_selectedIds.contains(requestId)) {
        _selectedIds.remove(requestId);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
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
    // Show confirmation dialog
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Requests"),
        content: Text("Delete ${_selectedIds.length} selected requests? This cannot be undone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Requests deleted.")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('peerUserId', isEqualTo: _currentUserId)
      // We removed the status filter so we can see 'completed' ones too if you want,
      // or keep it restricted. For now, let's show everything so we can delete old ones.
          .snapshots(),
      builder: (context, snapshot) {
        // If waiting
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
              appBar: AppBar(title: const Text('My Requests')),
              body: const Center(child: CircularProgressIndicator())
          );
        }

        var requests = snapshot.data?.docs ?? [];

        // Sort Newest First
        requests.sort((a, b) {
          var dataA = a.data() as Map<String, dynamic>;
          var dataB = b.data() as Map<String, dynamic>;
          Timestamp timeA = dataA['startTime'] ?? Timestamp.now();
          Timestamp timeB = dataB['startTime'] ?? Timestamp.now();
          return timeB.compareTo(timeA);
        });

        return Scaffold(
          appBar: AppBar(
            leading: _isSelectionMode
                ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() {
                  _isSelectionMode = false;
                  _selectedIds.clear();
                })
            )
                : null,
            title: Text(_isSelectionMode ? '${_selectedIds.length} Selected' : 'My Requests'),
            actions: [
              if (_isSelectionMode) ...[
                IconButton(
                  icon: Icon(_selectedIds.length == requests.length ? Icons.deselect : Icons.select_all),
                  tooltip: 'Select All',
                  onPressed: () => _selectAll(requests),
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  tooltip: 'Delete Selected',
                  onPressed: _deleteSelected,
                ),
              ]
            ],
          ),
          body: requests.isEmpty
              ? const Center(child: Text('You have no requests.'))
              : ListView.builder(
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

              // --- LOGIC: Determine Display Status ---
              String displayStatus = status.toUpperCase();
              Color statusColor = Colors.blue;
              bool isExpired = false;

              // Check Expiry
              if (now.isAfter(endTime)) {
                displayStatus = "DONE"; // Or "EXPIRED"
                statusColor = Colors.grey;
                isExpired = true;
              } else if (status == 'accepted') {
                statusColor = Colors.green;
              } else if (status == 'pending') {
                statusColor = Colors.orange;
              } else if (status == 'denied') {
                statusColor = Colors.red;
              }

              String timeStr = "${DateFormat('MMM d, h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}";
              int durationInSeconds = endTime.difference(startTime).inSeconds;

              bool isSelected = _selectedIds.contains(requestId);

              return InkWell(
                // --- SELECTION GESTURES ---
                onLongPress: () {
                  setState(() {
                    _isSelectionMode = true;
                    _toggleSelection(requestId);
                  });
                },
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(requestId);
                  }
                },
                child: Card(
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.2) : Colors.white,
                  shape: isSelected
                      ? RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).primaryColor, width: 2), borderRadius: BorderRadius.circular(12))
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header Row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$requester',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                displayStatus,
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Service: $service', style: const TextStyle(fontSize: 16)),
                        Text('Scheduled: $timeStr', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                        const SizedBox(height: 16),

                        // --- ACTION BUTTONS ---
                        // Hide buttons if we are in Selection Mode (to prevent accidental clicks)
                        // Also hide buttons if the request is Expired/Done
                        if (!_isSelectionMode && !isExpired)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (status == 'pending') ...[
                                TextButton(
                                  onPressed: () => _ticketService.updateRequestStatus(requestId, false),
                                  child: const Text('Deny', style: TextStyle(color: Colors.red)),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton(
                                  onPressed: () {
                                    _ticketService.updateRequestStatus(requestId, true);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text("Accepted! You can start when it's time.")),
                                    );
                                  },
                                  child: const Text('Accept'),
                                ),
                              ],

                              if (status == 'accepted') ...[
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Start Sharing'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Theme.of(context).primaryColor,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: () {
                                    if (now.isBefore(startTime)) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Starts at ${DateFormat('h:mm a').format(startTime)}"), backgroundColor: Colors.orange),
                                      );
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ActiveSessionScreen(
                                          requestId: requestId,
                                          serviceType: service,
                                          durationInSeconds: durationInSeconds,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),

                        // Optional: Show "Expired" text if buttons are hidden
                        if (isExpired && !_isSelectionMode)
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text("Time Ended", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                          )
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