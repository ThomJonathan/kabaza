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
import 'package:kabanza/AuthManager.dart';

class RiderHomePage extends StatefulWidget {
  const RiderHomePage({Key? key}) : super(key: key);

  @override
  State<RiderHomePage> createState() => _RiderHomePageState();
}

class _RiderHomePageState extends State<RiderHomePage> {
  final supabase = Supabase.instance.client;
  late RiderHomeBackend _backend;

  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? currentRideRequest;
  List<Map<String, dynamic>> recentTrips = [];
  bool _isLoading = true;
  bool _isLocationLoading = false;
  bool _isUpdatingRideStatus = false;

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
    await _loadRideData();
  }

  Future<void> _loadRideData() async {
    await _loadCurrentRideRequest();
    await _loadRecentTrips();
  }
  Future<void> _loadCurrentRideRequest() async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return;

      final response = await supabase
          .from('ride_requests')
          .select('''
          *,
          driver:driver_id(full_name, phone)
        ''')
          .eq('user_id', userId)
          .inFilter('status', ['pending', 'accepted', 'in_progress']) // Changed from in_ to inFilter
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        setState(() {
          currentRideRequest = response.first;
        });
      }
    } catch (e) {
      print('Error loading current ride request: $e');
    }
  }

  Future<void> _loadRecentTrips() async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return;

      final response = await supabase
          .from('ride_requests')
          .select('''
            *,
            driver:driver_id(full_name, phone)
          ''')
          .eq('user_id', userId)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(10);

      setState(() {
        recentTrips = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      print('Error loading recent trips: $e');
    }
  }

  Future<void> _markRideAsCompleted() async {
    if (currentRideRequest == null || _isUpdatingRideStatus) return;

    setState(() {
      _isUpdatingRideStatus = true;
    });

    try {
      final rideId = currentRideRequest!['id'];
      final now = DateTime.now().toIso8601String();

      await supabase
          .from('ride_requests')
          .update({
        'status': 'completed',
        'completed_at': now,
      })
          .eq('id', rideId);

      _showSuccessSnackBar('Ride marked as completed successfully!');

      // Refresh the ride data
      await _loadRideData();

      setState(() {
        currentRideRequest = null;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to mark ride as completed: ${e.toString()}');
    } finally {
      setState(() {
        _isUpdatingRideStatus = false;
      });
    }
  }

  Future<void> _cancelRide() async {
    if (currentRideRequest == null || _isUpdatingRideStatus) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isUpdatingRideStatus = true;
    });

    try {
      final rideId = currentRideRequest!['id'];
      final userId = AppAuthManager.getCurrentUserId();
      final now = DateTime.now().toIso8601String();

      await supabase
          .from('ride_requests')
          .update({
        'status': 'cancelled',
        'cancelled_at': now,
        'cancelled_by': userId,
        'cancellation_reason': 'Cancelled by rider',
      })
          .eq('id', rideId);

      _showSuccessSnackBar('Ride cancelled successfully!');

      // Refresh the ride data
      await _loadRideData();

      setState(() {
        currentRideRequest = null;
      });
    } catch (e) {
      _showErrorSnackBar('Failed to cancel ride: ${e.toString()}');
    } finally {
      setState(() {
        _isUpdatingRideStatus = false;
      });
    }
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
      body: RefreshIndicator(
        onRefresh: _loadRideData,
        child: RiderHomeUI.buildBody(
          context: context,
          currentRideRequest: currentRideRequest,
          recentTrips: recentTrips,
          isUpdatingRideStatus: _isUpdatingRideStatus,
          onRequestRide: _requestRide,
          onViewRideHistory: _viewRideHistory,
          onMarkRideCompleted: _markRideAsCompleted,
          onCancelRide: _cancelRide,
        ),
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