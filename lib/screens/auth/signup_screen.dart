import 'package:flutter/material.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/constants/app_colors.dart';

class SignUpScreen extends StatefulWidget {
  final VoidCallback toggleView; // To switch to the login screen
  const SignUpScreen({super.key, required this.toggleView});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final AuthService _auth = AuthService();
  final _formKey = GlobalKey<FormState>();

  // Text controllers
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _mobileController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // State for password visibility
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;
  String _error = '';
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _mobileController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleSignUp() async {
    if (_formKey.currentState!.validate()) {
      setState(() { _isLoading = true; _error = ''; });

      // Check if passwords match
      if (_passwordController.text != _confirmPasswordController.text) {
        setState(() {
          _error = "Passwords do not match";
          _isLoading = false;
        });
        return;
      }

      // Call AuthService
      String result = await _auth.signUpWithEmail(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        name: _nameController.text.trim(),
        mobile: _mobileController.text.trim(),
      );

      if (result != "Success" && mounted) {
        setState(() {
          _error = result;
          _isLoading = false;
        });
      }
      // If successful, the AuthWrapper will handle navigation
    }
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(color: isDark ? Colors.white : Colors.black),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: isDark ? Colors.white54 : Colors.black54,
            fontSize: 16,
          ),
          prefixIcon: Icon(icon, color: isDark ? Colors.white54 : Colors.black54),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 18,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                // Logo/Brand Name
                const Text(
                  'URmine',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                    letterSpacing: -1,
                  ),
                ),
                const SizedBox(height: 40),
                // Title
                Text(
                  'Create Your Account',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 32),
                // Full Name Field
                _buildTextField(
                  controller: _nameController,
                  hint: 'Full Name',
                  icon: Icons.person_outline,
                  validator: (val) => val!.isEmpty ? 'Enter your name' : null,
                ),
                const SizedBox(height: 16),
                // Email Field
                _buildTextField(
                  controller: _emailController,
                  hint: 'Email',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                  validator: (val) => val!.isEmpty ? 'Enter an email' : null,
                ),
                const SizedBox(height: 16),
                // Mobile Field
                _buildTextField(
                  controller: _mobileController,
                  hint: 'Mobile',
                  icon: Icons.phone_android_outlined,
                  keyboardType: TextInputType.phone,
                  validator: (val) => val!.isEmpty ? 'Enter your mobile number' : null,
                ),
                const SizedBox(height: 16),
                // Password Field
                _buildTextField(
                  controller: _passwordController,
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: !_passwordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _passwordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
                    ),
                    onPressed: () {
                      setState(() { _passwordVisible = !_passwordVisible; });
                    },
                  ),
                  validator: (val) => val!.length < 6 ? 'Enter a password 6+ chars long' : null,
                ),
                const SizedBox(height: 16),
                // Confirm Password Field
                _buildTextField(
                  controller: _confirmPasswordController,
                  hint: 'Confirm Password',
                  icon: Icons.lock_outline,
                  obscureText: !_confirmPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _confirmPasswordVisible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
                    ),
                    onPressed: () {
                      setState(() { _confirmPasswordVisible = !_confirmPasswordVisible; });
                    },
                  ),
                  validator: (val) => val!.isEmpty ? 'Please confirm your password' : null,
                ),
                const SizedBox(height: 32),
                // Sign Up Button
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.accent,
                    ),
                  )
                else
                  SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _handleSignUp,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Sign Up',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                // Error Message
                if (_error.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Text(
                      _error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                const SizedBox(height: 20),
                // Sign In Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Already have an account? ',
                      style: TextStyle(
                        color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54,
                        fontSize: 14,
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.toggleView,
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          color: AppColors.accent,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}