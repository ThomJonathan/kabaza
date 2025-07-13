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

final _supabase = Supabase.instance.client;

class MyApp extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ride Hailing App',
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
        AppRoutes.bookRide: (context) => const BookRidePage(apiKey: 'AIzaSyAwBZT0LlveffJVjzRXoRGPOfKsrrm8Y-o'),
      },
      navigatorObservers: [],
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
        return null;
      },
    );
  }

  String _getInitialRoute() {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      appLifecycleObserver.setLoggedIn(true);
      userActivityService.setUserActive();

      // Initialize user data from database
      _initializeUserData(user);

      return AppAuthManager.getHomeRouteForUser(user);
    }
    return AppRoutes.login;
  }

  Future<void> _initializeUserData(User user) async {
    try {
      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .single();

      AppAuthManager.setUserData(userData);
      print('User data initialized: ${AppAuthManager.getCurrentUserId()}');
    } catch (e) {
      print('Error initializing user data: $e');
    }
  }
}