import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:streamix/screens/auth/login_screen.dart';
import 'package:streamix/screens/auth/signup_screen.dart';
import 'package:streamix/screens/home/home_screen.dart'; // We'll create this next
import 'package:streamix/services/auth_service.dart'; // For the Stream

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // Check if user is logged in
        if (snapshot.hasData) {
          // User is logged in, show the app
          return const HomeScreen(); // This is our next step
        } else {
          // User is logged out, show the auth toggle
          return const AuthToggle();
        }
      },
    );
  }
}

/// This widget handles toggling between the Login and Sign-up screens
class AuthToggle extends StatefulWidget {
  const AuthToggle({super.key});

  @override
  State<AuthToggle> createState() => _AuthToggleState();
}

class _AuthToggleState extends State<AuthToggle> {
  bool showLoginScreen = true;

  void toggleView() {
    setState(() {
      showLoginScreen = !showLoginScreen;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (showLoginScreen) {
      return LoginScreen(toggleView: toggleView);
    } else {
      return SignUpScreen(toggleView: toggleView);
    }
  }
}