// main.dart - Simplified version using token-based password reset only
import 'package:flutter/material.dart';
import 'package:kabanza/routes.dart';
import 'package:kabanza/signup.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/login.dart';
import 'package:kabanza/config/supabaseConfig.dart';
import 'package:kabanza/Driver/home.dart';
import 'package:kabanza/Rider/home.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/LocationUpdater.dart';
import 'package:kabanza/Rider/Bookride/bookridepage.dart';
import 'package:kabanza/Rider/Bookride/rideTracking.dart';
import 'package:kabanza/AuthManager.dart';
import 'package:kabanza/VehiclesScreen.dart';
import 'package:kabanza/ForgotPassword.dart'; // Only token-based password reset
import 'package:kabanza/Driver/trips.dart';
import 'package:kabanza/Driver/ride_requests.dart';
import 'package:kabanza/Driver/active_ride.dart';
import 'package:kabanza/messaging/conversations_page.dart';
import 'package:kabanza/messaging/chat_page.dart';
import 'package:kabanza/Driver/hotspot.dart';
import 'package:kabanza/ProfileScreen.dart'; // <-- Add this import
import 'package:kabanza/Rider/riderHistory.dart'; // <-- Add this import

import 'package:kabanza/verifyResetscreen.dart';
import'forgotpasswordScreen.dart';

// Global instances
late final UserActivityService userActivityService;
late final AppLifecycleObserver lifecycleObserver;
late final LocationUpdater locationUpdater;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await SupabaseConfig.initialize();
    print('Supabase initialized successfully');
  } catch (e) {
    print('Supabase initialization error: $e');
  }

  // Initialize services
  userActivityService = UserActivityService(Supabase.instance.client);
  lifecycleObserver = AppLifecycleObserver(userActivityService);
  locationUpdater = LocationUpdater();

  // Initialize AppAuthManager with services
  AppAuthManager.initialize(
    userActivityService: userActivityService,
    lifecycleObserver: lifecycleObserver,
    supabase: Supabase.instance.client,
  );

  // Start services
  lifecycleObserver.initialize();
  locationUpdater.initialize();

  runApp(MyApp(
    userActivityService: userActivityService,
    appLifecycleObserver: lifecycleObserver,
    locationUpdater: locationUpdater,
  ));
}

class MyApp extends StatefulWidget {
  final UserActivityService userActivityService;
  final AppLifecycleObserver appLifecycleObserver;
  final LocationUpdater locationUpdater;

  const MyApp({
    super.key,
    required this.userActivityService,
    required this.appLifecycleObserver,
    required this.locationUpdater,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    _handleAuthStateChanges();
  }

  void _handleAuthStateChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final session = data.session;

      print('Auth state changed: $event');

      // Handle sign out event
      if (event == AuthChangeEvent.signedOut) {
        print('User signed out');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (navigatorKey.currentState?.mounted == true) {
            navigatorKey.currentState?.pushNamedAndRemoveUntil(
              AppRoutes.login,
                  (route) => false,
            );
          }
        });
      }
    });
  }

  String _getInitialRoute() {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      // User is logged in, determine which home screen to show
      final userRole = user.userMetadata?['role'] as String? ?? 'rider';
      return userRole.toLowerCase() == 'driver'
          ? AppRoutes.driverHome
          : AppRoutes.riderHome;
    }
    return AppRoutes.login;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QUICKlift',
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      initialRoute: _getInitialRoute(),
      routes: {
        AppRoutes.login: (context) => const LoginScreen(),
        AppRoutes.signUp: (context) => const SignupScreen(),
        AppRoutes.riderHome: (context) => const RiderHomePage(),
        AppRoutes.driverHome: (context) => const DriverHomePage(),
        AppRoutes.forgotPassword: (context) => const ForgotPasswordScreen(),
        AppRoutes.HotspotScreen: (context) => const HotspotScreen(),
        '/change-password': (context) => const ChangePasswordScreen(),
        AppRoutes.bookRide: (context) => const BookRidePage(apiKey: 'AIzaSyAwBZT0LlveffJVjzRXoRGPOfKsrrm8Y-o'),
        AppRoutes.vehicleDetails: (context) => const VehicleDetailsScreen(),
        AppRoutes.messages: (context) => const ConversationsPage(),
        AppRoutes.profile: (context) => const ProfileScreen(),
        // Driver routes
        AppRoutes.driverTrips: (context) => const DriverTripsPage(),
        AppRoutes.driverRideRequests: (context) => const DriverRideRequestsPage(),
        AppRoutes.driverActiveRide: (context) => const DriverActiveRidePage(),
        // Rider trip history route
        AppRoutes.rideHistory: (context) => const RiderHistoryPage(), // <-- Add this line
      },

      onGenerateRoute: (settings) {
        // Handle ride tracking route with arguments
        if (settings.name == AppRoutes.rideTracking) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => RideTrackingPage(
              rideRequestId: args['rideRequestId'],
              pickup: args['pickup'],
              destination: args['destination'],
            ),
          );
        }

        // Handle driver active ride route with arguments
        if (settings.name == AppRoutes.verifyResetCode) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => VerifyResetCodeScreen(email: args['email']),
          );
        }
        // Handle chat page route with arguments
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => ChatPage(
              otherUserId: args['otherUserId'],
              otherUserName: args['otherUserName'] as String?,
            ),
          );
        }

        // Handle verify reset code route with arguments
        if (settings.name == AppRoutes.verifyResetCode) {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => VerifyResetCodeScreen(email: args['email']),
          );
        }

        return null;
      },
    );
  }
}

// Keep the existing ChangePasswordScreen for authenticated users
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({Key? key}) : super(key: key);

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscureCurrentPassword = true;
  bool _obscureNewPassword = true;
  bool _obscureConfirmPassword = true;

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password changed successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to change password: ${error.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Password'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                TextFormField(
                  controller: _currentPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureCurrentPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureCurrentPassword = !_obscureCurrentPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureCurrentPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter your current password';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureNewPassword = !_obscureNewPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureNewPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter a new password';
                    }
                    if (value.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscureConfirmPassword = !_obscureConfirmPassword;
                        });
                      },
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your new password';
                    }
                    if (value != _newPasswordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _changePassword,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                      : const Text(
                    'Change Password',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}