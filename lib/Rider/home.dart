// rider_home_page.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/LocationUpdater.dart';
import '../routes.dart';
import 'backend/homebackend.dart';
import 'homeUI.dart';
import 'BottomNavBar.dart';


class RiderHomePage extends StatefulWidget {
  const RiderHomePage({Key? key}) : super(key: key);

  @override
  State<RiderHomePage> createState() => _RiderHomePageState();
}

class _RiderHomePageState extends State<RiderHomePage> {
  final supabase = Supabase.instance.client;
  late RiderHomeBackend _backend;

  Map<String, dynamic>? userProfile;
  bool _isLoading = true;
  bool _isLocationLoading = false;

  // Service instances
  late UserActivityService _userActivityService;
  late AppLifecycleObserver _appLifecycleObserver;
  late LocationUpdater _locationUpdater;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _initializeApp();
  }

  void _initializeServices() {
    _userActivityService = UserActivityService(supabase);
    _appLifecycleObserver = AppLifecycleObserver(_userActivityService);
    _locationUpdater = LocationUpdater();

    _backend = RiderHomeBackend(
      supabase: supabase,
      userActivityService: _userActivityService,
      appLifecycleObserver: _appLifecycleObserver,
      locationUpdater: _locationUpdater,
      onUserProfileLoaded: (profile) {
        setState(() {
          userProfile = profile;
          _isLoading = false;
        });
      },
      onLoadingStateChanged: (isLoading) {
        setState(() => _isLoading = isLoading);
      },
      onLocationLoadingStateChanged: (isLocationLoading) {
        setState(() => _isLocationLoading = isLocationLoading);
      },
      onShowErrorSnackBar: _showErrorSnackBar,
      onShowSuccessSnackBar: _showSuccessSnackBar,
      context: context,
    );
  }

  Future<void> _initializeApp() async {
    await _backend.initializeApp();
  }

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  // Navigation methods
  void _requestRide() {
    Navigator.pushNamed(context, AppRoutes.bookRide);
  }

  void _requestDelivery() {
    Navigator.pushNamed(context, '/book-delivery');
  }

  void _viewRideHistory() {
    Navigator.pushNamed(context, '/ride-history');
  }

  void _viewProfile() {
    Navigator.pushNamed(context, '/profile');
  }

  void _viewMessages() {
    Navigator.pushNamed(context, '/messages');
  }

  Future<void> _signOut() async {
    await _backend.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: RiderHomeUI.buildAppBar(
        context: context,
        userProfile: userProfile,
        isLocationLoading: _isLocationLoading,
        locationUpdater: _locationUpdater,
        onForceLocationUpdate: _backend.forceLocationUpdate,
        onProfileSelected: _viewProfile,
        onSettingsSelected: () => Navigator.pushNamed(context, '/settings'),
        onLogoutSelected: _signOut,
      ),
      body: RiderHomeUI.buildBody(
        context: context,
        onRequestRide: _requestRide,
        onRequestDelivery: _requestDelivery,
        onViewRideHistory: _viewRideHistory,
      ),
      bottomNavigationBar: RiderBottomNavigation(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 1:
              _viewRideHistory();
              break;
            case 2:
              _viewMessages();
              break;
            case 3:
              _viewProfile();
              break;
          }
        },
      ),
    );
  }
}