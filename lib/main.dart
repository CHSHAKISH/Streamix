import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:streamix/screens/auth/auth_wrapper.dart';
import 'package:streamix/services/theme_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'package:streamix/services/auth_service.dart';
import 'package:streamix/services/notification_service.dart';
import 'package:streamix/widgets/global_camera_listener.dart';
import 'package:streamix/widgets/notification_listener.dart'
    show InAppNotificationListener;

// Global Navigator Key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load Secrets & Supabase
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );

  // 2. Init Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 3. Setup Background Handler (use function from notification_service.dart)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // 4. RUN APP IMMEDIATELY
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeService()),
        Provider(create: (context) => AuthService()),
      ],
      child: const StreamixApp(),
    ),
  );
}

class StreamixApp extends StatefulWidget {
  const StreamixApp({super.key});

  @override
  State<StreamixApp> createState() => _StreamixAppState();
}

class _StreamixAppState extends State<StreamixApp> {
  @override
  void initState() {
    super.initState();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    final notificationService = NotificationService();
    await notificationService.initNotifications();
    await notificationService.setupInteractedMessage(navigatorKey);
  }

  @override
  Widget build(BuildContext context) {
    final themeService = Provider.of<ThemeService>(context);

    return MaterialApp(
      title: 'Streamix',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      themeMode: themeService.themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF007A7A),
        scaffoldBackgroundColor: Colors.white,
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
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF007A7A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF00C2C2),
        scaffoldBackgroundColor: const Color(0xFF121212),
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
      ),
      // Wrap with GlobalCameraHandler for remote camera triggering
      home: GlobalCameraHandler(
        child: InAppNotificationListener(child: const AuthWrapper()),
      ),
    );
  }
}
