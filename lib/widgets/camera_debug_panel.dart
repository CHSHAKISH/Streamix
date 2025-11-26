import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Temporary debug widget to diagnose camera photo visibility issues
/// Add this as a floating button in chat_screen.dart to test
class CameraDebugPanel extends StatelessWidget {
  final String requestId;

  const CameraDebugPanel({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      mini: true,
      backgroundColor: Colors.orange,
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.grey[900],
          builder: (context) => _DebugSheet(requestId: requestId),
        );
      },
      child: const Icon(Icons.bug_report, size: 20),
    );
  }
}

class _DebugSheet extends StatelessWidget {
  final String requestId;

  const _DebugSheet({required this.requestId});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('requests')
              .doc(requestId)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            final data = snapshot.data!.data() as Map<String, dynamic>?;
            if (data == null) {
              return const Center(
                child: Text(
                  'No data found for this request',
                  style: TextStyle(color: Colors.white),
                ),
              );
            }

            final mediaUrl = data['mediaUrl'] as String?;
            final command = data['remoteCommand'] as String?;
            final commandTimestamp = data['commandTimestamp'] as Timestamp?;
            final lastUpdated = data['lastUpdated'] as Timestamp?;

            return Container(
              padding: const EdgeInsets.all(20),
              child: ListView(
                controller: scrollController,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '🐛 Camera Debug Panel',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(color: Colors.grey),
                  const SizedBox(height: 10),

                  // Request ID
                  _buildInfoCard(
                    '📝 Request ID',
                    requestId,
                    Colors.blue,
                    copyable: true,
                  ),

                  // Command Status
                  _buildInfoCard(
                    '⚡ Remote Command',
                    command ?? 'NULL',
                    _getCommandColor(command),
                  ),

                  // Command Timestamp
                  _buildInfoCard(
                    '🕐 Command Timestamp',
                    commandTimestamp != null
                        ? '${commandTimestamp.toDate()}\n(${DateTime.now().difference(commandTimestamp.toDate()).inSeconds}s ago)'
                        : 'NULL',
                    Colors.purple,
                  ),

                  // Last Updated
                  _buildInfoCard(
                    '🕐 Last Updated',
                    lastUpdated != null
                        ? '${lastUpdated.toDate()}\n(${DateTime.now().difference(lastUpdated.toDate()).inSeconds}s ago)'
                        : 'NULL',
                    Colors.purple,
                  ),

                  // Media URL
                  _buildInfoCard(
                    '🖼️ Media URL',
                    mediaUrl ?? 'NULL - Photo not uploaded yet',
                    mediaUrl != null ? Colors.green : Colors.red,
                    copyable: mediaUrl != null,
                  ),

                  // Image Preview
                  if (mediaUrl != null) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '📷 Image Preview',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          mediaUrl,
                          key: ValueKey(mediaUrl + DateTime.now().toString()),
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: loadingProgress.expectedTotalBytes != null
                                    ? loadingProgress.cumulativeBytesLoaded /
                                        loadingProgress.expectedTotalBytes!
                                    : null,
                                color: Colors.white,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.red[900],
                              padding: const EdgeInsets.all(20),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 10),
                                  const Text(
                                    'Failed to Load Image',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    error.toString(),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.open_in_browser),
                      label: const Text('Open URL in Browser'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: mediaUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '📋 URL copied! Paste in browser to test.',
                            ),
                          ),
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 20),

                  // Diagnostic Info
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey[800],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '🔍 Diagnosis',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildDiagnosticResult(
                          'Firestore Connection',
                          snapshot.hasData,
                          'Connected',
                          'Not Connected',
                        ),
                        _buildDiagnosticResult(
                          'Photo Captured',
                          mediaUrl != null && mediaUrl.isNotEmpty,
                          'Yes - Photo uploaded',
                          'No - Waiting for User B',
                        ),
                        _buildDiagnosticResult(
                          'Command Status',
                          command == 'COMPLETED' || command == 'IDLE',
                          command == 'COMPLETED'
                              ? 'Completed successfully'
                              : 'Ready for new request',
                          command == 'REQUEST_CAPTURE'
                              ? 'Processing... (wait)'
                              : 'Unknown state',
                        ),
                        _buildDiagnosticResult(
                          'URL Format',
                          mediaUrl?.startsWith('http') ?? false,
                          'Valid HTTP/HTTPS URL',
                          'Invalid or missing URL',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Action Buttons
                  const Text(
                    '⚙️ Actions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('Trigger New Capture'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('requests')
                          .doc(requestId)
                          .update({
                        'remoteCommand': 'REQUEST_CAPTURE',
                        'commandTimestamp': FieldValue.serverTimestamp(),
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('📸 Capture request sent!'),
                          ),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Reset Command to IDLE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () async {
                      await FirebaseFirestore.instance
                          .collection('requests')
                          .doc(requestId)
                          .update({
                        'remoteCommand': 'IDLE',
                      });
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🔄 Command reset to IDLE'),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoCard(String title, String value, Color color,
      {bool copyable = false}) {
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (copyable)
                  IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    color: Colors.white70,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiagnosticResult(
      String label, bool isGood, String goodText, String badText) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            isGood ? Icons.check_circle : Icons.cancel,
            color: isGood ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
                Text(
                  isGood ? goodText : badText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _getCommandColor(String? command) {
    switch (command) {
      case 'IDLE':
        return Colors.grey;
      case 'REQUEST_CAPTURE':
        return Colors.orange;
      case 'COMPLETED':
        return Colors.green;
      default:
        return Colors.red;
    }
  }
}
