import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Stream for checking auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // ... (inside the AuthService class)

  /// --- NEW: Delete Account ---
  /// Re-authenticates and then permanently deletes the user's account.
  Future<String> deleteAccount({required String currentPassword}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return "No user signed in.";
      }

      // 1. Get the user's email and create a credential
      final email = user.email!;
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      // 2. Re-authenticate the user with their CURRENT password
      await user.reauthenticateWithCredential(credential);

      // 3. If re-auth is successful, first delete their Firestore data
      await _firestore.collection('users').doc(user.uid).delete();

      // 4. Finally, delete the Firebase Auth user
      await user.delete();

      return "Success";
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password') {
        return 'Wrong password. Please try again.';
      }
      return e.message ?? "An error occurred.";
    } catch (e) {
      return e.toString();
    }
  }

  /// Updates the 'mobile' field in the user's Firestore document.
  Future<String> updateContactNumber(String newNumber) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return "No user signed in.";
      }

      // Update the 'mobile' field in the 'users' collection
      await _firestore.collection('users').doc(user.uid).update({
        'mobile': newNumber,
      });

      return "Success";
    } catch (e) {
      return e.toString();
    }
  }

  /// --- NEW: Change Password ---
  /// Re-authenticates the user and changes their password.
  Future<String> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return "No user signed in.";
      }

      // 1. Get the user's email and create a credential
      final email = user.email!;
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );

      // 2. Re-authenticate the user with their CURRENT password
      await user.reauthenticateWithCredential(credential);

      // 3. If successful, update to the NEW password
      await user.updatePassword(newPassword);

      return "Success";
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An error occurred.";
    } catch (e) {
      return e.toString();
    }
  }

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