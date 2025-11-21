import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AvatarSelectorScreen extends StatelessWidget {
  const AvatarSelectorScreen({super.key});

  // List of assets or network URLs.
  // For simplicity, I'm using standard emojis/colors as placeholders.
  // You can replace these with Image.asset('assets/avatar_1.png') later.
  final List<String> avatarOptions = const [
    '👨‍💻', '👩‍🎨', '🦸‍♂️', '🦸‍♀️', '🐶', '🐱', '🦊', '🐼', '🐸'
  ];

  Future<void> _selectAvatar(BuildContext context, String avatarChar) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    // Update Firestore
    await FirebaseFirestore.instance.collection('users').doc(uid).update({
      'avatar': avatarChar, // Saving the emoji as the 'image'
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated!")));
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Avatar")),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
        ),
        itemCount: avatarOptions.length,
        itemBuilder: (context, index) {
          final avatar = avatarOptions[index];
          return InkWell(
            onTap: () => _selectAvatar(context, avatar),
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Colors.blue.shade50,
              child: Text(avatar, style: const TextStyle(fontSize: 40)),
            ),
          );
        },
      ),
    );
  }
}