import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';

import 'l10n/app_localizations.dart';
import 'auth/login.dart';
import 'auth/signup.dart';
import 'auth/forgot_password.dart';
import 'auth/confirm_email.dart';
import 'auth/reset_password.dart';
import 'auth/password_changed.dart';
import 'supabase_config.dart';
import 'services/supabase_service.dart';
import 'services/emergency_contacts_service.dart';
import 'services/locale_provider.dart';
import 'services/theme_provider.dart';
import 'home.dart';
import 'screens/profile.dart';
import 'screens/edit_profile.dart';
import 'screens/help.dart';
import 'screens/fuel_price.dart';
import 'screens/language.dart';
import 'screens/feedback.dart';
import 'screens/reminder_screen.dart';
import 'screens/trip_cost_calculator.dart';
import 'screens/media.dart';
import 'screens/media_add.dart';


import 'screens/media_photo_upload.dart';
import 'screens/media_video_upload.dart';
import 'screens/media_post_upload.dart';
import 'screens/media_success.dart';
import 'screens/analytics_wrapper.dart';
import 'screens/share.dart';

import 'screens/logout_confirm.dart';
import 'screens/petrol_station.dart';
import 'screens/fuel_management_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  } catch (e) {
    print('Warning: Supabase initialization failed: $e');
    // Continue anyway - app can work offline
  }

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  // Initialize default emergency contacts (non-blocking)
  try {
    final emergencyContactsService = EmergencyContactsService();
    await emergencyContactsService.initializeDefaultContacts();
  } catch (e) {
    print('Warning: Could not initialize emergency contacts: $e');
  }

  runApp(
    MultiProvider(

      providers: [
        ChangeNotifierProvider(create: (context) => LocaleProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _initializeAuthListener();
  }

  void _initializeAuthListener() {
    // Listen for auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      setState(() {
        _currentUser = event.session?.user;
      });
    });

    // Set initial user state
    _currentUser = Supabase.instance.client.auth.currentUser;
  }

  // Check if user is already logged in
  Widget _getInitialScreen() {
    final session = Supabase.instance.client.auth.currentSession;

    // If there's a valid session and user, go to home screen
    if (session != null && _currentUser != null) {
      return const HomeScreen();
    }

    // Otherwise, show login screen
    return const LoginPage();
  }

  // Light Theme
  static final ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF038124),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Colors.green),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.green, width: 2),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Colors.white,
      selectedItemColor: Color(0xFF038124),
      unselectedItemColor: Colors.grey,
    ),
  );

  // Dark Theme
  static final ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF121212),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E1E1E),
      foregroundColor: Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E1E),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: Colors.green),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.green, width: 2),
      ),
      filled: true,
      fillColor: const Color(0xFF2A2A2A),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFF1E1E1E),
      selectedItemColor: Colors.green,
      unselectedItemColor: Colors.grey,
    ),
  );

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return Consumer2<LocaleProvider, ThemeProvider>(
      builder: (context, localeProvider, themeProvider, child) {
        return MaterialApp(
          title: 'Ride Buddy',
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [
            Locale('en'), // English
            Locale('si'), // Sinhala
            Locale('ta'), // Tamil
          ],
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeProvider.themeMode,
          debugShowCheckedModeBanner: false,
          home: _getInitialScreen(),
          routes: {
            '/login': (_) => const LoginPage(),
            '/signup': (_) => const SignupPage(),
            '/forgot-password': (_) => const ForgotPasswordPage(),
            '/confirm-email': (_) => const ConfirmEmailPage(),
            '/reset-password': (_) => const ResetPasswordPage(),
            '/password-changed': (_) => const PasswordChangedPage(),
            '/home': (_) => const HomeScreen(),
            '/profile': (_) => const ProfilePage(),
            '/edit-profile': (_) => const EditProfilePage(),
            '/help': (_) => const HelpPage(),
            '/fuel-price': (_) => const FuelPricePage(),
            '/language': (_) => const LanguagePage(),
            '/feedback': (_) => const FeedbackPage(),
            '/trip-cost': (_) => const TripCostCalculatorPage(),
            '/media': (_) => const MediaPage(),
            '/media-add': (_) => const MediaAddPage(),
            '/media-photo-upload': (_) => const PhotoUploadPage(),
            '/media-video-upload': (_) => const VideoUploadPage(),
            '/media-post-upload': (_) => const PostUploadPage(),
            '/media-success': (_) => const SuccessUploadPage(),
            '/stats': (_) => const AnalyticsWrapperPage(),
            '/share': (_) => const SharePage(),
            '/logout-confirm': (_) => const LogoutConfirmPage(),
            '/reminder': (_) => const ReminderScreen(),
            '/petrol-station': (_) => const PetrolStationPage(),
            '/fuel-management': (_) => const FuelManagementScreen(),
          },
        );
      },
    );
  }
}
