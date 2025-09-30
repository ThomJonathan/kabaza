import 'dart:ffi';

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
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kabanza/PayChangu/paymentHelper.dart'; // Import the payment helper

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
    _restoreSessionAndInitialize();
  }

  Future<void> _restoreSessionAndInitialize() async {
    // Check if Supabase session exists
    final session = supabase.auth.currentSession;
    final user = supabase.auth.currentUser;

    if (session != null && user != null) {
      // Fetch user profile from DB and set in AppAuthManager
      final userProfileResponse = await supabase
          .from('users')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (userProfileResponse != null) {
        AppAuthManager.setUserData(userProfileResponse);
      }
    }
    await _initializeApp();
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
          .not('status', 'in', ['completed', 'cancelled']) // Not completed or cancelled
          .order('created_at', ascending: false)
          .limit(1);

      if (response.isNotEmpty) {
        setState(() {
          currentRideRequest = response.first;
        });
      } else {
        setState(() {
          currentRideRequest = null;
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
            id,
            pickup_address,
            destination_address,
            completed_at,
            cancelled_at,
            estimated_fare,
            actual_fare,
            payment_status,
            status,
            driver:driver_id(full_name, phone)
          ''')
          .eq('user_id', userId)
          .not('accepted_at', 'is', null) // Was accepted by a driver
          .inFilter('status', ['completed', 'cancelled']) // Show completed or cancelled
          .order('completed_at', ascending: false)
          .limit(2); // Only 2 recent trips

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

  Future<void> _trackCurrentRide() async {
    if (currentRideRequest == null) return;

    try {
      final pickup = LatLng(
        currentRideRequest!['pickup_latitude'] as double,
        currentRideRequest!['pickup_longitude'] as double,
      );
      final destination = LatLng(
        currentRideRequest!['destination_latitude'] as double,
        currentRideRequest!['destination_longitude'] as double,
      );

      Navigator.pushNamed(
        context,
        AppRoutes.rideTracking,
        arguments: {
          'rideRequestId': currentRideRequest!['id'],
          'pickup': pickup,
          'destination': destination,
        },
      ).then((_) => _loadRideData());  // Refresh after returning
    } catch (e) {
      _showErrorSnackBar('Failed to start tracking: $e');
    }
  }

  Future<void> _payRide() async {
    if (currentRideRequest == null) return;

    try {
      final rideId = currentRideRequest!['id'];
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return;

      // Use actual_fare if available, else estimated_fare
      double fare = 0.0;
      if (currentRideRequest!['actual_fare'] != null) {
        fare = currentRideRequest!['actual_fare'] is String
            ? double.tryParse(currentRideRequest!['actual_fare']) ?? 0.0
            : currentRideRequest!['actual_fare'] as double;
      } else if (currentRideRequest!['estimated_fare'] != null) {
        // Remove 'MK ' prefix if present
        final estFare = currentRideRequest!['estimated_fare'].toString().replaceAll(RegExp(r'[^\d.]'), '');
        fare = double.tryParse(estFare) ?? 0.0;
      }

      final firstName = userProfile?['first_name'] ?? 'Guest';
      final lastName = userProfile?['last_name'];
      final email = userProfile?['email'];

      await RidePaymentHelper.launchRidePayment(
        context: context,
        rideId: rideId,
        userId: userId,
        firstName: firstName,
        lastName: lastName,
        email: email,
        fareAmount: fare,
        onPaymentComplete: () {
          _showSuccessSnackBar('Payment completed successfully!');
          _loadRideData();
        },
        onPaymentFailed: () {
          _showErrorSnackBar('Payment failed. Please try again.');
          _loadRideData();
        },
      );

      // Refresh data after payment process completes
      await _loadRideData();
    } catch (e) {
      _showErrorSnackBar('Failed to initiate payment: $e');
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

  void _viewRideHistory() {
    Navigator.pushNamed(context, AppRoutes.rideHistory);
  }

  void _viewProfile() {
    Navigator.pushNamed(context, AppRoutes.profile);
  }

  void _viewMessages() {
    Navigator.pushNamed(context, '/messages');
  }


  Future<void> _signOut() async {
    // Invalidate user session
    await supabase.auth.signOut();
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
        onRefresh: _loadRideData, // Pass refresh callback
      ),
      body: RefreshIndicator(
        onRefresh: _loadRideData,
        child: RiderHomeUI.buildBody(
          context: context,
          currentRideRequest: currentRideRequest,
          recentTrips: recentTrips,
          isUpdatingRideStatus: _isUpdatingRideStatus,
          onRequestRide: _requestRide,
          onViewRideHistory: _viewRideHistory, // Pass view history callback
          onMarkRideCompleted: _markRideAsCompleted,
          onCancelRide: _cancelRide,
          onTrackCurrentRide: _trackCurrentRide, // <-- Pass this
          onPayRide: _payRide,
        ),
      ),
      bottomNavigationBar: RiderBottomNavigation(
        currentIndex: 0,
        onTap: (index) {
          switch (index) {
            case 1:
              _viewRideHistory(); // History tab
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