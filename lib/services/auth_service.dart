import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream for checking auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Sign In with Email & Password
  Future<String> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return "Success";
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred";
    } catch (e) {
      return e.toString();
    }
  }

  /// Sign Up with Email, Password, Name, and Mobile
  Future<String> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String mobile,
  }) async {
    try {
      // 1. Create the user in Firebase Auth
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // 2. Save the extra user data to Firestore
      if (userCredential.user != null) {
        await _saveUserToFirestore(
          user: userCredential.user!,
          name: name,
          mobile: mobile,
        );
      }
      return "Success";
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred";
    } catch (e) {
      return e.toString();
    }
  }

  /// Helper function to save user data to 'users' collection
  Future<void> _saveUserToFirestore({
    required User user,
    required String name,
    required String mobile,
  }) async {
    await _firestore.collection('users').doc(user.uid).set({
      'uid': user.uid,
      'name': name,
      'email': user.email,
      'mobile': mobile,
      'createdAt': Timestamp.now(),
    });
  }

  /// Sign Out
  Future<void> signOut() async {
    await _auth.signOut();
  }
}