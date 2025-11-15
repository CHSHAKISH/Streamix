import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:streamix/screens/auth/auth_wrapper.dart';
import 'package:streamix/services/theme_service.dart'; // <-- 1. IMPORT
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart'; // <-- 2. IMPORT
import 'firebase_options.dart';
import 'package:streamix/services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- 3. WRAP THE APP ---
  runApp(
    MultiProvider( // Change from ChangeNotifierProvider
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeService()),
        Provider(create: (context) => AuthService()), // Add this
      ],
      child: const StreamixApp(),
    ),
  );
  // --- END WRAP ---
}

final supabase = Supabase.instance.client;

class StreamixApp extends StatelessWidget {
  const StreamixApp({super.key});

  @override
  Widget build(BuildContext context) {
    // --- 4. CONSUME THE THEME ---
    // This watches for changes in our ThemeService
    final themeService = Provider.of<ThemeService>(context);
    // --- END CONSUME ---

    return MaterialApp(
      title: 'Streamix',
      debugShowCheckedModeBanner: false,

      // --- 5. SET THE THEMES ---
      themeMode: themeService.themeMode, // Use the provider's value

      // Light Theme (our existing theme)
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF007A7A),
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF007A7A),
          secondary: Color(0xFF00C2C2),
          background: Colors.white,
          surface: Colors.white,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF007A7A)),
          titleTextStyle: TextStyle(
            color: Color(0xFF007A7A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF007A7A), width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007A7A),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),

      // Dark Theme (new)
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00C2C2), // Use the brighter teal as primary
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00C2C2),
          secondary: Color(0xFF007A7A),
          background: Color(0xFF121212),
          surface: Color(0xFF1E1E1E), // For cards and dialogs
          onPrimary: Colors.black,
          onSecondary: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          elevation: 0,
          centerTitle: true,
          iconTheme: IconThemeData(color: Color(0xFF00C2C2)),
          titleTextStyle: TextStyle(
            color: Color(0xFF00C2C2),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey[700]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF00C2C2), width: 2),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C2C2),
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      // --- END OF THEMES ---

      home: const AuthWrapper(),
    );
  }
}