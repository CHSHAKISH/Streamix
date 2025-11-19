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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Requests (Incoming)'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // --- 1. UPDATED STREAM ---
        // We now fetch 'pending' AND 'accepted' requests so they don't disappear
        // after accepting them.
        stream: FirebaseFirestore.instance
            .collection('requests')
            .where('peerUserId', isEqualTo: _currentUserId)
            .where('status', whereIn: ['pending', 'accepted'])
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You have no active requests.'));
          }

          var requests = snapshot.data!.docs;

          // Sort by Start Time (Earliest first)
          requests.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            Timestamp timeA = dataA['startTime'] ?? Timestamp.now();
            Timestamp timeB = dataB['startTime'] ?? Timestamp.now();
            return timeA.compareTo(timeB);
          });

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              var data = requests[index].data() as Map<String, dynamic>;
              String requestId = requests[index].id;

              String service = data['serviceType'];
              String requester = data['requesterName'];
              String status = data['status'];

              DateTime startTime = (data['startTime'] as Timestamp).toDate();
              DateTime endTime = (data['endTime'] as Timestamp).toDate();

              String timeStr = "${DateFormat('MMM d, h:mm a').format(startTime)} - ${DateFormat('h:mm a').format(endTime)}";

              // Calculate Duration based on Start/End time for the timer
              int durationInSeconds = endTime.difference(startTime).inSeconds;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                // Color code the card: White for pending, Greenish for Accepted
                color: status == 'accepted' ? Colors.green.shade50 : Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                              color: status == 'pending' ? Colors.orange : Colors.green,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              status.toUpperCase(),
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Service: $service', style: const TextStyle(fontSize: 16)),
                      Text('Scheduled: $timeStr', style: const TextStyle(fontSize: 14, color: Colors.grey)),
                      const SizedBox(height: 16),

                      // --- 2. LOGIC FOR BUTTONS ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // CASE A: Request is Pending -> Show Accept/Deny
                          if (status == 'pending') ...[
                            TextButton(
                              onPressed: () {
                                _ticketService.updateRequestStatus(requestId, false);
                              },
                              child: const Text('Deny', style: TextStyle(color: Colors.red)),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: () {
                                // Just update status, DO NOT navigate yet
                                _ticketService.updateRequestStatus(requestId, true);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Accepted! You can now start the service when it's time.")),
                                );
                              },
                              child: const Text('Accept'),
                            ),
                          ],

                          // CASE B: Request is Accepted -> Show Start Button with Time Check
                          if (status == 'accepted') ...[
                            ElevatedButton.icon(
                              icon: const Icon(Icons.play_arrow),
                              label: const Text('Start Sharing'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () {
                                final now = DateTime.now();

                                // 1. Check if Too Early
                                if (now.isBefore(startTime)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("You can start this service at ${DateFormat('h:mm a').format(startTime)}"),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                  return;
                                }

                                // 2. Check if Too Late (Expired)
                                if (now.isAfter(endTime)) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("This service time has passed."),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                  // Optional: Auto-complete it so it leaves the list
                                  // _ticketService.completeRequest(requestId);
                                  return;
                                }

                                // 3. On Time -> Go to Active Session
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => ActiveSessionScreen(
                                      requestId: requestId,
                                      serviceType: service,
                                      durationInSeconds: durationInSeconds, // Use calculated duration
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}