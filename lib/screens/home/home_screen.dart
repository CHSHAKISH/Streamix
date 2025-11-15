import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/chat/chat_screen.dart'; // Import placeholder
import 'package:streamix/screens/requests/requests_list_screen.dart'; // Import placeholder
import 'package:streamix/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AuthService _authService = AuthService();
  final String _currentUserId = FirebaseAuth.instance.currentUser!.uid;
  String _searchQuery = "";

  // Controller for the search bar
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
          // Logout Button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () {
              _authService.signOut();
            },
          ),
          // Sync User Button
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync Users',
            onPressed: () {
              // This just forces the StreamBuilder to rebuild
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
                labelText: 'Search users by name or email...',
                prefixIcon: const Icon(Icons.search),
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
              // Stream all users from the 'users' collection
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

                // --- Filter Logic ---
                final users = snapshot.data!.docs.where((doc) {
                  // Don't show the currently logged-in user in the list
                  if (doc['uid'] == _currentUserId) {
                    return false;
                  }

                  // Search filter logic
                  if (_searchQuery.isEmpty) {
                    return true; // Show all
                  }

                  final data = doc.data() as Map<String, dynamic>;
                  final name = (data['name'] as String? ?? '').toLowerCase();
                  final email = (data['email'] as String? ?? '').toLowerCase();

                  return name.contains(_searchQuery) || email.contains(_searchQuery);

                }).toList();
                // --- End Filter Logic ---

                if (users.isEmpty) {
                  return const Center(child: Text('No users match your search.'));
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
                        child: Text(userName[0].toUpperCase()),
                      ),
                      title: Text(userName),
                      subtitle: Text(userEmail),
                      onTap: () {
                        // Go to the chat-like page (Step 3)
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
      floatingActionButton: FloatingActionButton.extended(
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
  }
}