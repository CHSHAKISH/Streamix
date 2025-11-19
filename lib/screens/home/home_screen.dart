import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/chat/chat_screen.dart';
import 'package:streamix/screens/requests/requests_list_screen.dart';
import 'package:streamix/screens/settings/settings_screen.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/services/ticket_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final TicketService _ticketService = TicketService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  String _searchQuery = "";

  final TextEditingController _searchController = TextEditingController();

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

          // --- User List with Sorting ---
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

                // 2. Fetch Requests (Without sorting in DB to avoid Index errors)
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('requests')
                      .where(Filter.or(
                    Filter('requesterId', isEqualTo: _currentUserId),
                    Filter('peerUserId', isEqualTo: _currentUserId),
                  ))
                      .snapshots(),
                  builder: (context, requestSnapshot) {

                    // Calculate "Last Interaction Time" for each user
                    Map<String, DateTime> lastInteractionMap = {};

                    if (requestSnapshot.hasData) {
                      print("DEBUG: Found ${requestSnapshot.data!.docs.length} requests involving me.");

                      for (var doc in requestSnapshot.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        String rId = data['requesterId'];
                        String pId = data['peerUserId'];
                        Timestamp? time;

                        // Try to get start time, fallback to createdAt if scheduled time is null
                        if (data['startTime'] != null) {
                          time = data['startTime'] as Timestamp;
                        } else if (data['createdAt'] != null) {
                          time = data['createdAt'] as Timestamp;
                        }

                        // Determine who the "other" person is
                        String otherUserId = (rId == _currentUserId) ? pId : rId;

                        // Save the LATEST time we found for this user
                        if (time != null) {
                          DateTime docTime = time.toDate();
                          // If we haven't seen this user yet, OR this doc is newer than what we have
                          if (!lastInteractionMap.containsKey(otherUserId) ||
                              docTime.isAfter(lastInteractionMap[otherUserId]!)) {
                            lastInteractionMap[otherUserId] = docTime;
                          }
                        }
                      }
                    } else if (requestSnapshot.hasError) {
                      print("DEBUG ERROR: ${requestSnapshot.error}");
                    }

                    // Filter the Users based on Search
                    final users = userSnapshot.data!.docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;

                      // Hide Self
                      if (data['uid'] == _currentUserId) return false;

                      // Search Filter
                      if (_searchQuery.isEmpty) return true;
                      final name = (data['name'] as String? ?? '').toLowerCase();
                      final email = (data['email'] as String? ?? '').toLowerCase();
                      return name.contains(_searchQuery) || email.contains(_searchQuery);
                    }).toList();

                    // --- SORTING LOGIC ---
                    users.sort((a, b) {
                      final dataA = a.data() as Map<String, dynamic>;
                      final dataB = b.data() as Map<String, dynamic>;
                      final uidA = dataA['uid'];
                      final uidB = dataB['uid'];

                      DateTime? timeA = lastInteractionMap[uidA];
                      DateTime? timeB = lastInteractionMap[uidB];

                      // 1. If both have interaction times, sort by time (Desc: Newest First)
                      if (timeA != null && timeB != null) {
                        return timeB.compareTo(timeA);
                      }

                      // 2. If A has time but B doesn't, A comes first
                      if (timeA != null) return -1;

                      // 3. If B has time but A doesn't, B comes first
                      if (timeB != null) return 1;

                      // 4. If neither has time, sort Alphabetically by Name
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

                        // Check if this is a recent contact to show a small indicator
                        bool isRecent = lastInteractionMap.containsKey(peerUserId);

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isRecent ? Colors.green : Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?'),
                          ),
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
      // --- "All Requests" Button ---
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