import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
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
        // Sort Newest First
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

                bool isPending = status == 'pending';
                bool isAccepted = status == 'accepted';
                bool isCompleted = status == 'completed';

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
                            Text(status.toUpperCase(), style: TextStyle(
                                color: isCompleted ? Colors.grey : (isAccepted ? Colors.green : Colors.orange),
                                fontWeight: FontWeight.bold
                            )),
                          ],
                        ),
                        Text("${service.toUpperCase()}  •  $dateStr"),

                        const SizedBox(height: 10),

                        // --- ACTION BUTTONS ---
                        if (isPending)
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
                                  // 1. Check Permission
                                  if (service.contains('camera')) {
                                    var status = await Permission.camera.request();
                                    if (status.isDenied) return;
                                  }

                                  // 2. Accept
                                  await _ticketService.updateRequestStatus(requestId, true);

                                  // 3. AUTOMATION TRIGGER
                                  if (service.contains('camera')) {
                                    // Open Camera UI Immediately
                                    if(mounted) {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => ActiveSessionScreen(
                                            requestId: requestId,
                                            serviceType: service,
                                          ),
                                        ),
                                      );
                                    }
                                  } else {
                                    // For other services (like Location), just show snackbar
                                    if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Accepted! Check session details.")));
                                  }
                                },
                                child: const Text("ACCEPT & START"),
                              ),
                            ],
                          ),

                        if (isAccepted && service.contains('camera'))
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.camera_alt),
                              label: const Text("Launch Camera"),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ActiveSessionScreen(
                                      requestId: requestId,
                                      serviceType: service,
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
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