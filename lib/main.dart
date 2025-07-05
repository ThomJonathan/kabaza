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
import 'package:kabanza/Rider/fromV0/bookridePage.dart';
import 'package:kabanza/messages.dart';
import 'package:kabanza/Rider/fromV0/rideService.dart';

// Global instances
late final UserActivityService userActivityService;
late final AppLifecycleObserver lifecycleObserver;
late final LocationUpdater locationUpdater;
late final RideBookingService rideBookingService;

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
  rideBookingService = RideBookingService(Supabase.instance.client);

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
        AppRoutes.BookRide: (context) => const EnhancedBookRidePage(),
        AppRoutes.messages: (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

          return MessagesPage(
            driverId: args?['driverId'] ?? '',
            driverName: args?['driverName'] ?? 'Driver',
            rideService: args?['rideService'] ?? rideBookingService,
            bookingId: args?['bookingId'],
          );
        },
      },
      navigatorObservers: [],
    );
  }

  String _getInitialRoute() {
    final user = _supabase.auth.currentUser;
    if (user != null) {
      appLifecycleObserver.setLoggedIn(true);
      userActivityService.setUserActive();
      return _getHomeRouteForUser(user);
    }
    return AppRoutes.login;
  }

  String _getHomeRouteForUser(User user) {
    final userRole = user.userMetadata?['role'] as String? ?? 'rider';

    switch (userRole.toLowerCase()) {
      case 'driver':
        return AppRoutes.driverHome;
      case 'rider':
      default:
        return AppRoutes.riderHome;
    }
  }
}

class AppAuthManager {
  static void onLoginSuccess() {
    lifecycleObserver.setLoggedIn(true);
    userActivityService.setUserActive();
  }

  static Future<void> onLogout(BuildContext context) async {
    try {
      lifecycleObserver.setLoggedIn(false);
      await userActivityService.setUserInactive();
      await _supabase.auth.signOut();

      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
              (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
      }
    }
  }

  static String getHomeRouteForUser(User user) {
    final userRole = user.userMetadata?['role'] as String? ?? 'rider';

    switch (userRole.toLowerCase()) {
      case 'driver':
        return AppRoutes.driverHome;
      case 'rider':
      default:
        return AppRoutes.riderHome;
    }
  }
}

class MessagesNavigation {
  static void navigateToMessages(
      BuildContext context, {
        required String driverId,
        required String driverName,
        RideBookingService? rideService,
        String? bookingId,
      }) {
    Navigator.pushNamed(
      context,
      AppRoutes.messages,
      arguments: {
        'driverId': driverId,
        'driverName': driverName,
        'rideService': rideService ?? rideBookingService,
        'bookingId': bookingId,
      },
    );
  }

  static void pushReplacementToMessages(
      BuildContext context, {
        required String driverId,
        required String driverName,
        RideBookingService? rideService,
        String? bookingId,
      }) {
    Navigator.pushReplacementNamed(
      context,
      AppRoutes.messages,
      arguments: {
        'driverId': driverId,
        'driverName': driverName,
        'rideService': rideService ?? rideBookingService,
        'bookingId': bookingId,
      },
    );
  }
}