import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/chat/chat_screen.dart';
import 'package:streamix/screens/requests/requests_list_screen.dart';
import 'package:streamix/screens/settings/settings_screen.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/services/ticket_service.dart';
import 'package:streamix/constants/app_colors.dart';

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
  int _currentIndex = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _buildCurrentPage() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab();
      case 1:
        return const RequestsListScreen();
      case 2:
        return const SettingsScreen();
      default:
        return _buildHomeTab();
    }
  }

  Widget _buildHomeTab() {
    return Column(
      children: [
        // Search Bar
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(30),
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search Users',
                hintStyle: TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.toLowerCase();
                });
              },
            ),
          ),
        ),
        // User List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance.collection('users').snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (!userSnapshot.hasData || userSnapshot.data!.docs.isEmpty) {
                return const Center(child: Text('No users found.'));
              }

              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('requests')
                    .where(Filter.or(
                  Filter('requesterId', isEqualTo: _currentUserId),
                  Filter('peerUserId', isEqualTo: _currentUserId),
                ))
                    .snapshots(),
                builder: (context, requestSnapshot) {
                  Map<String, DateTime> lastInteractionMap = {};

                  if (requestSnapshot.hasData) {
                    for (var doc in requestSnapshot.data!.docs) {
                      var data = doc.data() as Map<String, dynamic>;
                      String rId = data['requesterId'];
                      String pId = data['peerUserId'];
                      Timestamp? time;

                      if (data['startTime'] != null) {
                        time = data['startTime'] as Timestamp;
                      } else if (data['createdAt'] != null) {
                        time = data['createdAt'] as Timestamp;
                      }

                      String otherUserId = (rId == _currentUserId) ? pId : rId;

                      if (time != null) {
                        DateTime docTime = time.toDate();
                        if (!lastInteractionMap.containsKey(otherUserId) ||
                            docTime.isAfter(lastInteractionMap[otherUserId]!)) {
                          lastInteractionMap[otherUserId] = docTime;
                        }
                      }
                    }
                  }

                  final users = userSnapshot.data!.docs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    if (data['uid'] == _currentUserId) return false;

                    if (_searchQuery.isEmpty) return true;
                    final name = (data['name'] as String? ?? '').toLowerCase();
                    final email = (data['email'] as String? ?? '').toLowerCase();
                    return name.contains(_searchQuery) || email.contains(_searchQuery);
                  }).toList();

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
                      final userAvatar = userData['avatar'] as String?;

                      bool isRecent = lastInteractionMap.containsKey(peerUserId);

                      Widget avatarWidget;
                      if (userAvatar != null && userAvatar.startsWith('http')) {
                        avatarWidget = CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primary,
                          backgroundImage: NetworkImage(userAvatar),
                        );
                      } else if (userAvatar != null && userAvatar.isNotEmpty) {
                        avatarWidget = CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primary,
                          child: Text(userAvatar, style: const TextStyle(fontSize: 24)),
                        );
                      } else {
                        avatarWidget = CircleAvatar(
                          radius: 24,
                          backgroundColor: AppColors.primary,
                          child: Text(
                            userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 18),
                          ),
                        );
                      }

                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        leading: avatarWidget,
                        title: Text(
                          userName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          'Requested for Front Camera',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 13,
                          ),
                        ),
                        trailing: Text(
                          _formatTime(lastInteractionMap[peerUserId]),
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
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
    );
  }

  String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '';
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final date = DateTime(dateTime.year, dateTime.month, dateTime.day);

    if (date == today) {
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : (dateTime.hour == 0 ? 12 : dateTime.hour);
      final minute = dateTime.minute.toString().padLeft(2, '0');
      final period = dateTime.hour >= 12 ? 'pm' : 'am';
      return '$hour:$minute $period';
    } else if (date == yesterday) {
      return 'Yesterday';
    } else if (now.difference(dateTime).inDays < 7) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[dateTime.weekday - 1];
    } else {
      return '${dateTime.month}/${dateTime.day}/${dateTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'URmine',
          style: TextStyle(
            color: AppColors.accent,
            fontSize: 28,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.5,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, color: Colors.black54),
            tooltip: 'Sync Users',
            onPressed: () {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('User list synced!')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black54),
            tooltip: 'Logout',
            onPressed: () {
              _authService.signOut();
            },
          ),
        ],
      ),
      body: _buildCurrentPage(),
      bottomNavigationBar: StreamBuilder<QuerySnapshot>(
        stream: _ticketService.getIncomingRequestsStream(),
        builder: (context, snapshot) {
          int requestCount = 0;
          if (snapshot.hasData) {
            requestCount = snapshot.data!.docs.length;
          }

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: AppColors.accent,
              unselectedItemColor: Colors.black54,
              selectedFontSize: 12,
              unselectedFontSize: 12,
              elevation: 0,
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.home),
                  label: 'Home',
                ),
                BottomNavigationBarItem(
                  icon: requestCount > 0
                      ? Badge(
                          label: Text('$requestCount'),
                          backgroundColor: AppColors.accent,
                          child: const Icon(Icons.notifications),
                        )
                      : const Icon(Icons.notifications),
                  label: 'Request',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: 'Settings',
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}