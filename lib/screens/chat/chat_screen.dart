import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/screens/chat/request_dialog.dart';
import 'package:streamix/services/ticket_service.dart';

class ChatScreen extends StatefulWidget {
  final String peerUserId;
  final String peerUserName;

  const ChatScreen({
    super.key,
    required this.peerUserId,
    required this.peerUserName,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TicketService _ticketService = TicketService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;

  void _showRequestDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return RequestDialog(peerUserId: widget.peerUserId);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peerUserName),
      ),
      body: Column(
        children: [
          // --- Chat History ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _ticketService.getChatHistoryStream(widget.peerUserId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No requests yet.'));
                }

                var requests = snapshot.data!.docs;

                return ListView.builder(
                  reverse: true, // Shows latest at the bottom
                  padding: const EdgeInsets.all(8.0), // Add padding
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    var data = requests[index].data() as Map<String, dynamic>;
                    bool isMe = data['requesterId'] == _currentUserId;

                    // --- UPDATED ---
                    // Use Align to push bubbles left or right
                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: _buildRequestBubble(context, data, isMe),
                    );
                    // --- END UPDATE ---
                  },
                );
              },
            ),
          ),

          // --- Request Button Bar ---
          Container(
            padding: const EdgeInsets.all(12.0),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 5,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Send a new request...',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle, color: Theme.of(context).primaryColor),
                    iconSize: 40,
                    onPressed: _showRequestDialog,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UPDATED HELPER WIDGET ---
  Widget _buildRequestBubble(BuildContext context, Map<String, dynamic> data, bool isMe) {
    var service = data['serviceType'];
    var status = data['status'];
    var startTime = (data['startTime'] as Timestamp).toDate();

    // Get service icon
    IconData icon = Icons.help;
    if (service == 'location') icon = Icons.location_on;
    if (service.contains('video') || service.contains('stream')) icon = Icons.videocam;
    if (service.contains('audio')) icon = Icons.mic;
    if (service.contains('camera') || service == 'image_sample') icon = Icons.camera_alt;

    // --- NEW COLOR AND STATUS LOGIC ---
    // Set colors based on sender (me vs. them)
    final bubbleColor = isMe ? Theme.of(context).primaryColor.withOpacity(0.15) : Colors.grey[200];
    final textColor = Colors.black87;

    // Set status icon and color
    IconData statusIcon = Icons.pending_outlined;
    Color statusColor = Colors.orange.shade700;
    if (status == 'accepted') {
      statusIcon = Icons.check_circle_outline;
      statusColor = Colors.green.shade700;
    }
    if (status == 'denied') {
      statusIcon = Icons.cancel_outlined;
      statusColor = Colors.red.shade700;
    }
    // --- END NEW LOGIC ---

    String title = isMe ? 'You requested $service' : '${data['requesterName']} requested $service';
    String time = DateFormat('MMM d, h:mm a').format(startTime);

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      // Limit the width of the bubble
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min, // Make row wrap content
        children: [
          Icon(icon, color: Theme.of(context).primaryColor),
          const SizedBox(width: 12),
          // Flexible allows text to wrap neatly
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: textColor)),
                Text('At: $time', style: TextStyle(color: textColor.withOpacity(0.8))),
                const SizedBox(height: 4),
                // New status row with icon
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, color: statusColor, size: 16),
                    const SizedBox(width: 4),
                    Text(
                      'Status: $status',
                      style: TextStyle(fontStyle: FontStyle.italic, color: statusColor, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}