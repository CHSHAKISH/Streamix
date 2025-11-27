import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/services/notification_service.dart';

class InAppNotificationListener extends StatefulWidget {
  final Widget child;
  
  const InAppNotificationListener({super.key, required this.child});

  @override
  State<InAppNotificationListener> createState() => _InAppNotificationListenerState();
}

class _InAppNotificationListenerState extends State<InAppNotificationListener> {
  String? _currentUserId;
  final NotificationService _notificationService = NotificationService();
  StreamSubscription? _requestSubscription;
  final Set<String> _processedRequests = {};

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (_currentUserId != null) {
      _listenToRequests();
    }
  }

  void _listenToRequests() {
    if (_currentUserId == null) return;
    
    // Listen to requests where current user is the requester (User A)
    // to get notified when requests are accepted/rejected
    _requestSubscription = FirebaseFirestore.instance
        .collection('requests')
        .where('requesterId', isEqualTo: _currentUserId)
        .snapshots()
        .listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.modified) {
          final data = change.doc.data();
          if (data != null) {
            final requestId = change.doc.id;
            final status = data['status'] as String?;
            final serviceType = data['serviceType'] as String?;
            final peerName = data['peerUserName'] as String? ?? 'User B';
            
            // Check if we've already processed this notification
            final notificationKey = '$requestId-$status';
            if (_processedRequests.contains(notificationKey)) {
              continue;
            }
            _processedRequests.add(notificationKey);
            
            // Show notification for status changes
            if (status == 'accepted' && context.mounted) {
              _notificationService.showInAppNotification(
                context,
                'Request Accepted! ✅',
                '$peerName accepted your $serviceType request',
                backgroundColor: Colors.green.shade900,
              );
            } else if (status == 'denied' && context.mounted) {
              _notificationService.showInAppNotification(
                context,
                'Request Denied ❌',
                '$peerName denied your $serviceType request',
                backgroundColor: Colors.red.shade900,
              );
            }
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
