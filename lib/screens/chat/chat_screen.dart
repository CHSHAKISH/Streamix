import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:streamix/screens/chat/request_dialog.dart';
import 'package:streamix/screens/session/view_session_screen.dart';
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
                  reverse: true,
                  padding: const EdgeInsets.all(8.0),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
                    var data = requests[index].data() as Map<String, dynamic>;
                    String requestId = requests[index].id;
                    bool isMe = data['requesterId'] == _currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: _buildRequestBubble(context, data, isMe, requestId),
                    );
                  },
                );
              },
            ),
          ),
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

  Widget _buildRequestBubble(BuildContext context, Map<String, dynamic> data, bool isMe, String requestId) {
    var service = data['serviceType'];
    var status = data['status'];
    String? mediaUrl = data['mediaUrl'];

    DateTime? startTime;
    DateTime? endTime;

    if (data['startTime'] != null) {
      startTime = (data['startTime'] as Timestamp).toDate();
    }
    if (data['endTime'] != null) {
      endTime = (data['endTime'] as Timestamp).toDate();
    }

    IconData icon = Icons.help;
    if (service == 'location') icon = Icons.location_on;
    if (service.contains('video') || service.contains('stream')) icon = Icons.videocam;
    if (service.contains('audio')) icon = Icons.mic;
    if (service.contains('camera') || service == 'image_sample') icon = Icons.camera_alt;

    final bubbleColor = isMe ? Theme.of(context).primaryColor : Colors.grey[200];
    final textColor = isMe ? Colors.white : Colors.black87;

    IconData statusIcon = Icons.pending_outlined;
    Color statusColor = isMe ? Colors.white70 : Colors.orange.shade700;
    if (status == 'accepted') {
      statusIcon = Icons.check_circle_outline;
      statusColor = isMe ? Colors.white : Colors.green.shade700;
    }
    if (status == 'denied') {
      statusIcon = Icons.cancel_outlined;
      statusColor = isMe ? Colors.white70 : Colors.red.shade700;
    }
    if (status == 'completed') {
      statusIcon = Icons.task_alt;
      statusColor = isMe ? Colors.white70 : Colors.grey[700]!;
    }
    if (status == 'stopped_by_provider') {
      statusIcon = Icons.block;
      statusColor = isMe ? Colors.white70 : Colors.orange.shade700;
    }

    String title = isMe ? 'You requested $service' : '${data['requesterName']} requested $service';

    String timeInfo = "Processing...";
    if (startTime != null && endTime != null) {
      String dateStr = DateFormat('MMM d').format(startTime);
      String startStr = DateFormat('h:mm a').format(startTime);
      String endStr = DateFormat('h:mm a').format(endTime);
      timeInfo = "$dateStr, $startStr - $endStr";
    }

    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 4),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(0),
          bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(16),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isMe ? Colors.white : Theme.of(context).primaryColor, size: 30),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: textColor, fontSize: 16)),
                    Text(timeInfo, style: TextStyle(color: textColor.withOpacity(0.8), fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(statusIcon, color: statusColor, size: 16),
              const SizedBox(width: 4),
              Text(
                status == 'stopped_by_provider' 
                    ? 'Status: Stopped by User B' 
                    : 'Status: $status',
                style: TextStyle(fontStyle: FontStyle.italic, color: statusColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),

          if ((status == 'accepted' || status == 'completed') && isMe && status != 'stopped_by_provider')
            Padding(
              padding: const EdgeInsets.only(top: 10.0),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.remove_red_eye_outlined, size: 18),
                label: const Text('View Live / File'),
                onPressed: () async {
                  final now = DateTime.now();

                  // --- FIX 3 & 4: Block access after end time ---
                  if (endTime != null && now.isAfter(endTime)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("This service has ended. File is no longer accessible."),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  if (startTime != null && now.isBefore(startTime)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("This service will start at ${DateFormat('h:mm a').format(startTime)}"),
                        backgroundColor: Colors.orange,
                      ),
                    );
                    return;
                  }

                  // For camera, video, and audio services, trigger capture/recording and wait for media
                  if (service.contains('camera') || service.contains('video') || service == 'audio') {
                    bool isVideo = service.contains('video');
                    bool isAudio = service == 'audio';
                    
                    // Show loading dialog
                    if (context.mounted) {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (dialogContext) => AlertDialog(
                          backgroundColor: Colors.grey[900],
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: Colors.white),
                              const SizedBox(height: 20),
                              Text(
                                isVideo 
                                    ? '🎥 Recording 10s video from User B...' 
                                    : isAudio
                                        ? '🎤 Recording 10s audio from User B...'
                                        : '📸 Capturing photo from User B...',
                                style: const TextStyle(color: Colors.white),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    
                    // Trigger the capture/recording
                    await _ticketService.sendCameraTrigger(requestId);
                    
                    // Wait for media to be uploaded (listen to Firestore)
                    bool mediaReady = false;
                    String? mediaUrl;
                    
                    final subscription = FirebaseFirestore.instance
                        .collection('requests')
                        .doc(requestId)
                        .snapshots()
                        .listen((snapshot) {
                      if (snapshot.exists) {
                        final data = snapshot.data();
                        final command = data?['remoteCommand'] as String?;
                        final url = data?['mediaUrl'] as String?;
                        
                        if (command == 'COMPLETED' && url != null && url.isNotEmpty) {
                          mediaReady = true;
                          mediaUrl = url;
                        }
                      }
                    });
                    
                    // Wait up to 20 seconds for video/audio (10s recording + 10s processing/upload) or 12s for photo
                    int waitCount = 0;
                    int maxWait = (isVideo || isAudio) ? 40 : 24; // 40 * 500ms = 20s for video/audio, 24 * 500ms = 12s for photo
                    while (!mediaReady && waitCount < maxWait) {
                      await Future.delayed(const Duration(milliseconds: 500));
                      waitCount++;
                      
                      // Log progress every 5 seconds
                      if (waitCount % 10 == 0) {
                        print('⏳ Waiting for ${isVideo ? 'video' : isAudio ? 'audio' : 'photo'}... ${waitCount * 500 ~/ 1000}s elapsed');
                      }
                    }
                    
                    // Cancel subscription
                    await subscription.cancel();
                    
                    // Close loading dialog
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true).pop();
                    }
                    
                    // Open viewer if media is ready
                    if (mediaReady && mediaUrl != null && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ViewSessionScreen(
                            requestId: requestId,
                            serviceType: data['serviceType'],
                          ),
                        ),
                      );
                    } else if (context.mounted) {
                      // Check the command status to give better error message
                      final finalDoc = await FirebaseFirestore.instance
                          .collection('requests')
                          .doc(requestId)
                          .get();
                      final finalCommand = finalDoc.data()?['remoteCommand'] as String?;
                      
                      String errorMsg;
                      if (finalCommand == 'REQUEST_CAPTURE') {
                        errorMsg = isVideo 
                            ? '⚠️ Video recording in progress but not completed yet. Please wait or try again.'
                            : isAudio
                                ? '⚠️ Audio recording in progress but not completed yet. Please wait or try again.'
                                : '⚠️ Photo capture in progress but not completed yet. Please wait or try again.';
                      } else {
                        errorMsg = isVideo 
                            ? '⚠️ Video recording timeout. Make sure User B has opened the session first.'
                            : isAudio
                                ? '⚠️ Audio recording timeout. Make sure User B has opened the session first.'
                                : '⚠️ Photo capture timeout. Make sure User B has opened the session first.';
                      }
                      
                      // Show error if timeout
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMsg),
                          backgroundColor: Colors.orange,
                          duration: const Duration(seconds: 5),
                          action: SnackBarAction(
                            label: 'Retry',
                            textColor: Colors.white,
                            onPressed: () {
                              // Trigger again
                              _ticketService.sendCameraTrigger(requestId);
                            },
                          ),
                        ),
                      );
                    }
                    return;
                  }

                  // For other services
                  if (status == 'completed' || (mediaUrl != null && mediaUrl.isNotEmpty)) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ViewSessionScreen(
                          requestId: requestId,
                          serviceType: data['serviceType'],
                        ),
                      ),
                    );
                    return;
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ViewSessionScreen(
                        requestId: requestId,
                        serviceType: data['serviceType'],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.secondary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            )
        ],
      ),
    );
  }
}