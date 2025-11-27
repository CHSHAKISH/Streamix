import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:streamix/screens/settings/avatar_selector_screen.dart';
import 'package:streamix/screens/settings/faqs_screen.dart';
import 'package:streamix/screens/settings/help_screen.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/services/theme_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final User? _currentUser = FirebaseAuth.instance.currentUser;
  final AuthService _authService = AuthService();

  // --- 1. CHANGE CONTACT NUMBER DIALOG ---
  void _showChangePhoneDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Center(
          child: Text("Change Contact Number", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.phone_outlined),
                labelText: "New Mobile Number",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({'phoneNumber': controller.text});
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Contact number updated!")));
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  // --- 2. CHANGE MAIL DIALOG ---
  void _showChangeMailDialog() {
    final emailController = TextEditingController();
    final passController = TextEditingController();
    bool obscurePass = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Center(
                child: Text("Change Email", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.mail_outline),
                      labelText: "New Email Address",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passController,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: "Current Password",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(
                        icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => obscurePass = !obscurePass),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (emailController.text.isNotEmpty && passController.text.isNotEmpty) {
                      try {
                        // Re-auth first
                        AuthCredential credential = EmailAuthProvider.credential(email: _currentUser!.email!, password: passController.text);
                        await _currentUser.reauthenticateWithCredential(credential);
                        // Update Email
                        await _currentUser.verifyBeforeUpdateEmail(emailController.text);
                        await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).update({'email': emailController.text});

                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Verification email sent! Please verify to complete change.")));
                        }
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Update"),
                ),
              ],
            );
          }
      ),
    );
  }

  // --- 3. CHANGE PASSWORD DIALOG ---
  void _showChangePasswordDialog() {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool obsCurrent = true;
    bool obsNew = true;
    bool obsConfirm = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Center(
                child: Text("Change Password", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentController,
                      obscureText: obsCurrent,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        labelText: "Current Password",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(icon: Icon(obsCurrent ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => obsCurrent = !obsCurrent)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newController,
                      obscureText: obsNew,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        labelText: "New Password",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(icon: Icon(obsNew ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => obsNew = !obsNew)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: obsConfirm,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        labelText: "Confirm New Password",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(icon: Icon(obsConfirm ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => obsConfirm = !obsConfirm)),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (newController.text != confirmController.text) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("New passwords do not match")));
                      return;
                    }
                    try {
                      final credential = EmailAuthProvider.credential(email: _currentUser!.email!, password: currentController.text);
                      await _currentUser.reauthenticateWithCredential(credential);
                      await _currentUser.updatePassword(newController.text);
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Password changed successfully!")));
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Change"),
                ),
              ],
            );
          }
      ),
    );
  }

  // --- 4. DELETE ACCOUNT DIALOG ---
  void _showDeleteAccountDialog() {
    final passController = TextEditingController();
    bool obscurePass = true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("Delete Account", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("This is permanent. All your data will be lost. Please enter your password to confirm.", style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passController,
                    obscureText: obscurePass,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: "Current Password",
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      suffixIcon: IconButton(icon: Icon(obscurePass ? Icons.visibility_off : Icons.visibility), onPressed: () => setState(() => obscurePass = !obscurePass)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final credential = EmailAuthProvider.credential(email: _currentUser!.email!, password: passController.text);
                      await _currentUser.reauthenticateWithCredential(credential);
                      await FirebaseFirestore.instance.collection('users').doc(_currentUser.uid).delete();
                      await _currentUser.delete();
                      // App will likely restart or go to login due to auth listener
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text("Delete My Account"),
                ),
              ],
            );
          }
      ),
    );
  }

  // --- 5. CLEAR CACHE ---
  void _clearCache() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cache cleared successfully!")));
  }

  // --- 6. THEME SELECTOR ---
  void _showThemeDialog(ThemeService themeService) {
    showDialog(
      context: context,
      builder: (context) {
        return SimpleDialog(
          title: const Text("Select Theme"),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          children: [
            RadioListTile<ThemeMode>(title: const Text("System Default"), value: ThemeMode.system, groupValue: themeService.themeMode, onChanged: (val) { themeService.setTheme(val!); Navigator.pop(context); }),
            RadioListTile<ThemeMode>(title: const Text("Light"), value: ThemeMode.light, groupValue: themeService.themeMode, onChanged: (val) { themeService.setTheme(val!); Navigator.pop(context); }),
            RadioListTile<ThemeMode>(title: const Text("Dark"), value: ThemeMode.dark, groupValue: themeService.themeMode, onChanged: (val) { themeService.setTheme(val!); Navigator.pop(context); }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);
    String themeText = "System";
    if (themeService.themeMode == ThemeMode.light) themeText = "Light";
    if (themeService.themeMode == ThemeMode.dark) themeText = "Dark";

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: false),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(_currentUser?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          var userData = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          String name = userData['name'] ?? 'User';
          String email = userData['email'] ?? _currentUser?.email ?? 'No Email';
          String phone = userData['phoneNumber'] ?? 'No Phone';
          String? avatar = userData['avatar'];

          // Logic to determine Avatar Widget
          Widget avatarWidget;
          if (avatar != null && avatar.startsWith('http')) {
            avatarWidget = CircleAvatar(radius: 40, backgroundImage: NetworkImage(avatar), backgroundColor: Colors.grey);
          } else if (avatar != null && avatar.isNotEmpty) {
            avatarWidget = CircleAvatar(radius: 40, backgroundColor: Theme.of(context).primaryColor, child: Text(avatar, style: const TextStyle(fontSize: 35)));
          } else {
            avatarWidget = CircleAvatar(radius: 40, backgroundColor: Theme.of(context).primaryColor, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(fontSize: 35, color: Colors.white)));
          }

          return SingleChildScrollView(
            child: Column(
              children: [
                // PROFILE HEADER
                Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AvatarSelectorScreen())),
                        child: Stack(
                          children: [
                            avatarWidget,
                            Positioned(
                              bottom: 0, right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                                child: const Icon(Icons.camera_alt, size: 14, color: Colors.white),
                              ),
                            )
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            Row(children: [const Icon(Icons.phone, size: 14, color: Colors.grey), const SizedBox(width: 6), Text(phone, style: const TextStyle(color: Colors.grey))]),
                            const SizedBox(height: 4),
                            Row(children: [const Icon(Icons.mail_outline, size: 14, color: Colors.grey), const SizedBox(width: 6), Expanded(child: Text(email, style: const TextStyle(color: Colors.grey), overflow: TextOverflow.ellipsis))]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),

                // SETTINGS LIST
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text("Theme"),
                  subtitle: Text(themeText),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _showThemeDialog(themeService),
                ),
                ListTile(
                  leading: const Icon(Icons.mail_outline),
                  title: const Text("Change Mail"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangeMailDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text("Change Password"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangePasswordDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.phone_in_talk_outlined),
                  title: const Text("Change Contact Number"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showChangePhoneDialog,
                ),
                // --- CLEAR CACHE BUTTON ---
                ListTile(
                  leading: const Icon(Icons.cleaning_services_outlined),
                  title: const Text("Clear Cache"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _clearCache,
                ),
                ListTile(
                  leading: const Icon(Icons.help_outline),
                  title: const Text("Help"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const HelpScreen())),
                ),
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text("FAQ's"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaqsScreen())),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 16.0), child: Divider()),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.red),
                  title: const Text("Delete Account", style: TextStyle(color: Colors.red)),
                  onTap: _showDeleteAccountDialog,
                ),
                ListTile(
                  leading: const Icon(Icons.logout),
                  title: const Text("Logout"),
                  onTap: () => _authService.signOut(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}