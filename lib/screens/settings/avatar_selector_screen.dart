import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:streamix/services/supabase_storage_service.dart';

class AvatarSelectorScreen extends StatefulWidget {
  const AvatarSelectorScreen({super.key});

  @override
  State<AvatarSelectorScreen> createState() => _AvatarSelectorScreenState();
}

class _AvatarSelectorScreenState extends State<AvatarSelectorScreen> {
  bool _isUploading = false;
  final SupabaseStorageService _supabaseService = SupabaseStorageService();

  // Emoji placeholders
  final List<String> avatarOptions = const [
    '👨‍💻', '👩‍🎨', '🦸‍♂️', '🦸‍♀️', '🐶', '🐱', '🦊', '🐼', '🐸', '🤖', '👻', '👽'
  ];

  Future<void> _saveAvatar(String avatarValue) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'avatar': avatarValue,
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile picture updated!")));
      Navigator.pop(context);
    }
  }

  Future<void> _pickAndUploadImage(ImageSource source) async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: source, imageQuality: 50);

    if (image == null) return;

    setState(() => _isUploading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not logged in');
      }
      
      // 1. Upload to Supabase bucket 'profile_pics'
      // (Make sure you create a bucket named 'profile_pics' in Supabase and set it to Public)
      String? url = await _supabaseService.uploadRequestMedia(
        "profile_${user.uid}", // Unique ID
        File(image.path),
        'jpg',
      );

      // 2. Save URL to Firestore
      if (url != null) {
        await _saveAvatar(url);
      } else {
        throw "Upload failed";
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Choose Profile Picture")),
      body: _isUploading
          ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [CircularProgressIndicator(), SizedBox(height: 16), Text("Uploading...")]))
          : Column(
        children: [
          const SizedBox(height: 20),
          // Custom Upload Options
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildUploadBtn(Icons.camera_alt, "Camera", ImageSource.camera),
              _buildUploadBtn(Icons.photo_library, "Gallery", ImageSource.gallery),
            ],
          ),
          const Divider(height: 40),
          const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Text("Or choose an avatar", style: TextStyle(fontSize: 16, color: Colors.grey)),
          ),
          // Emoji Grid
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, crossAxisSpacing: 16, mainAxisSpacing: 16,
              ),
              itemCount: avatarOptions.length,
              itemBuilder: (context, index) {
                final avatar = avatarOptions[index];
                return InkWell(
                  onTap: () => _saveAvatar(avatar),
                  child: CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                    child: Text(avatar, style: const TextStyle(fontSize: 30)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUploadBtn(IconData icon, String label, ImageSource source) {
    return Column(
      children: [
        InkWell(
          onTap: () => _pickAndUploadImage(source),
          child: CircleAvatar(
            radius: 30,
            backgroundColor: Theme.of(context).primaryColor,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label)
      ],
    );
  }
}