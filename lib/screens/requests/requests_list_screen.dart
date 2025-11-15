import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/services/ticket_service.dart';

class RequestsListScreen extends StatefulWidget {
  const RequestsListScreen({super.key});

  @override
  State<RequestsListScreen> createState() => _RequestsListScreenState();
}

class _RequestsListScreenState extends State<RequestsListScreen> {
  final TicketService _ticketService = TicketService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All My Requests'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _ticketService.getIncomingRequestsStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('You have no pending requests.'));
          }

          var requests = snapshot.data!.docs;

          return ListView.builder(
            itemCount: requests.length,
            itemBuilder: (context, index) {
              var data = requests[index].data() as Map<String, dynamic>;
              String requestId = requests[index].id;

              String service = data['serviceType'];
              String requester = data['requesterName'];
              String time = DateFormat('MMM d, h:mm a')
                  .format((data['startTime'] as Timestamp).toDate());

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Request from: $requester',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Service: $service', style: const TextStyle(fontSize: 16)),
                      Text('At: $time', style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Deny Button
                          TextButton(
                            onPressed: () {
                              _ticketService.updateRequestStatus(requestId, false);
                            },
                            child: const Text('Deny', style: TextStyle(color: Colors.red)),
                          ),
                          const SizedBox(width: 12),
                          // Accept Button
                          ElevatedButton(
                            onPressed: () {
                              _ticketService.updateRequestStatus(requestId, true);
                            },
                            child: const Text('Accept'),
                          ),
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