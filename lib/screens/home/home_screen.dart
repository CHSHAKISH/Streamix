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
          // --- User List ---
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return const Center(child: Text('Something went wrong.'));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('No users found.'));
                }

                // --- NEW: DEBUGGING PRINT ---
                print('--- DEBUG: Filtering user list ---');
                print('Current User ID: $_currentUserId');
                // --- END NEW ---

                // --- Filter Logic ---
                final users = snapshot.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;

                  // --- NEW: DEBUGGING PRINT ---
                  print('Checking user: ${data['email']}, uid: ${data['uid']}');
                  // --- END NEW ---

                  // Don't show the currently logged-in user in the list
                  if (data['uid'] == _currentUserId) {
                    print('-> Filtering out self.');
                    return false;
                  }

                  if (_searchQuery.isEmpty) {
                    print('-> Including (no search).');
                    return true;
                  }

                  final name = (data['name'] as String? ?? '').toLowerCase();
                  final email = (data['email'] as String? ?? '').toLowerCase();

                  bool matches = name.contains(_searchQuery) || email.contains(_searchQuery);
                  print('-> Search result: $matches');
                  return matches;

                }).toList();
                // --- End Filter Logic ---

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

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?'),
                      ),
                      title: Text(userName),
                      subtitle: Text(userEmail),
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