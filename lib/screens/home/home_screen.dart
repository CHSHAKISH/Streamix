import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/chat/chat_screen.dart';
import 'package:streamix/screens/requests/requests_list_screen.dart';
import 'package:streamix/screens/settings/settings_screen.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/services/background_stream_service.dart';
import 'package:permission_handler/permission_handler.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final TicketService _ticketService = TicketService();
  String get _currentUserId => FirebaseAuth.instance.currentUser?.uid ?? '';
  String _searchQuery = "";

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _requestAllPermissions();
    _checkAndStartActiveStreams();
  }

  Future<void> _requestAllPermissions() async {
    print('🔐 Requesting all permissions at app startup...');
    
    // Request all permissions at once
    await [
      Permission.camera,
      Permission.microphone,
      Permission.location,
      Permission.locationWhenInUse,
      Permission.notification,
    ].request();
    
    print('✅ All permissions requested');
  }

  /// Check for accepted stream requests and start them in background
  /// This ensures streams are running even if User B closed and reopened the app
  Future<void> _checkAndStartActiveStreams() async {
    print('🔍 Checking for active stream requests...');
    
    try {
      final now = DateTime.now();
      final snapshot = await FirebaseFirestore.instance
          .collection('requests')
          .where('peerUserId', isEqualTo: _currentUserId)
          .where('status', isEqualTo: 'accepted')
          .get();

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final serviceType = data['serviceType'] as String?;
        final startTime = (data['startTime'] as Timestamp?)?.toDate();
        final endTime = (data['endTime'] as Timestamp?)?.toDate();

        // Only start stream services
        if (serviceType != null &&
            serviceType.contains('stream') &&
            startTime != null &&
            endTime != null) {
          // Check if within time window
          if (!now.isBefore(startTime) && !now.isAfter(endTime)) {
            print('🎬 Found active stream request: ${doc.id} ($serviceType)');
            
            final backgroundService = BackgroundStreamService();
            if (!backgroundService.isStreamActive(doc.id)) {
              await backgroundService.startStream(
                requestId: doc.id,
                serviceType: serviceType,
                scheduledStartTime: startTime,
                scheduledEndTime: endTime,
              );
              print('✅ Background stream started for ${doc.id}');
            } else {
              print('⏭️ Stream already running for ${doc.id}');
            }
          }
        }
      }
    } catch (e) {
      print('❌ Error checking active streams: $e');
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Streamix'),
        actions: [
          // Sync Button (Manual Refresh)
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Users',
            onPressed: () {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User list synced!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              _authService.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // --- GlobalCamera Status Indicator ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.green.withValues(alpha: 0.2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Ready to receive camera/video requests',
                  style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          
          // --- Search Bar ---
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.light
                    ? Colors.grey[200]
                    : Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = "";
                    });
                  },
                )
                    : null,
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),

          // --- User List with Sorting & Smart Avatars ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // 1. Fetch All Users
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, userSnapshot) {
                if (userSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                // 2. Fetch Requests (To determine sorting order)
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('requests')
                      .where(Filter.or(
                    Filter('requesterId', isEqualTo: _currentUserId),
                    Filter('peerUserId', isEqualTo: _currentUserId),
                  ))
                      .snapshots(),
                  builder: (context, requestSnapshot) {

                    // Logic: Map UserID -> Last Interaction Date
                    Map<String, DateTime> lastInteractionMap = {};

                    if (requestSnapshot.hasData) {
                      for (var doc in requestSnapshot.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        String rId = data['requesterId'];
                        String pId = data['peerUserId'];
                        Timestamp? time;

                        // Prioritize scheduled start time, fallback to created time
                        if (data['startTime'] != null) {
                          time = data['startTime'] as Timestamp;
                        } else if (data['createdAt'] != null) {
                          time = data['createdAt'] as Timestamp;
                        }

                        String otherUserId = (rId == _currentUserId) ? pId : rId;

                        if (time != null) {
                          DateTime docTime = time.toDate();
                          // Keep the LATEST time found
                          if (!lastInteractionMap.containsKey(otherUserId) ||
                              docTime.isAfter(lastInteractionMap[otherUserId]!)) {
                            lastInteractionMap[otherUserId] = docTime;
                          }
                        }
                      }
                    }

                    // Filter Users (Remove self + Apply search)
                    final users = userSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      if (data['uid'] == _currentUserId) return false;

                      if (_searchQuery.isEmpty) return true;
                      final name = (data['name'] as String? ?? '').toLowerCase();
                      final email = (data['email'] as String? ?? '').toLowerCase();
                      return name.contains(_searchQuery) || email.contains(_searchQuery);
                    }).toList();

                    // --- SORTING LOGIC ---
                    // 1. Recent interactions first. 2. Alphabetical.
                    users.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;
                      final uidA = dataA['uid'];
                      final uidB = dataB['uid'];

                      DateTime? timeA = lastInteractionMap[uidA];
                      DateTime? timeB = lastInteractionMap[uidB];

                      if (timeA != null && timeB != null) return timeB.compareTo(timeA);
                      if (timeA != null) return -1;
                      if (timeB != null) return 1;

                      String nameA = (dataA['name'] as String? ?? '').toLowerCase();
                      String nameB = (dataB['name'] as String? ?? '').toLowerCase();
                      return nameA.compareTo(nameB);
                    });

                    if (users.isEmpty) {
                      return const Center(child: Text('No other users found.'));
                    }

                    return ListView.builder(
                      itemCount: users.length,
                      itemBuilder: (context, index) {
                        final userDoc = users[index];
                        final userData = userDoc.data() as Map<String, dynamic>;
                        final userName = userData['name'] ?? 'No Name';
                        final userEmail = userData['email'] ?? 'No Email';
                        final peerUserId = userData['uid'];

                        // Get Avatar Field
                        final userAvatar = userData['avatar'] as String?;

                        // Check if this is a recent contact (Green Ring logic)
                        bool isRecent = lastInteractionMap.containsKey(peerUserId);
                        Color avatarBg = isRecent ? Colors.green : Theme.of(context).primaryColor;

                        // --- SMART AVATAR WIDGET ---
                        Widget avatarWidget;
                        if (userAvatar != null && userAvatar.startsWith('http')) {
                          // Case 1: Image URL (Photo)
                          avatarWidget = CircleAvatar(
                            backgroundColor: avatarBg,
                            backgroundImage: NetworkImage(userAvatar),
                          );
                        } else if (userAvatar != null && userAvatar.isNotEmpty) {
                          // Case 2: Emoji
                          avatarWidget = CircleAvatar(
                            backgroundColor: avatarBg,
                            child: Text(userAvatar, style: const TextStyle(fontSize: 24)),
                          );
                        } else {
                          // Case 3: Initials Fallback
                          avatarWidget = CircleAvatar(
                            backgroundColor: avatarBg,
                            child: Text(
                              userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                              style: const TextStyle(color: Colors.white),
                            ),
                          );
                        }

                        return ListTile(
                          leading: avatarWidget,
                          title: Text(
                            userName,
                            style: TextStyle(
                                fontWeight: isRecent ? FontWeight.bold : FontWeight.normal
                            ),
                          ),
                          subtitle: Text(userEmail),
                          trailing: isRecent
                              ? const Icon(Icons.history, size: 16, color: Colors.green)
                              : null,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  peerUserId: peerUserId,
                                  peerUserName: userName,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      // --- "My Requests" FAB with Count Badge ---
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _ticketService.getIncomingRequestsStream(),
        builder: (context, snapshot) {
          int requestCount = 0;
          if (snapshot.hasData) {
            requestCount = snapshot.data!.docs.length;
          }

          return Badge(
            label: Text('$requestCount'),
            isLabelVisible: requestCount > 0,
            child: FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const RequestsListScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.inbox),
              label: const Text('My Requests'),
              backgroundColor: Theme.of(context).colorScheme.secondary,
              foregroundColor: Colors.black,
            ),
          );
        },
      ),
    );
  }
}