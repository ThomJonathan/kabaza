import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/LocationUpdater.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';

class DriverService with WidgetsBindingObserver {
  final SupabaseClient supabase;
  final UserActivityService _userActivityService;
  final AppLifecycleObserver _appLifecycleObserver;
  final LocationUpdater _locationUpdater;
  final Connectivity _connectivity = Connectivity();

  Timer? _connectionTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _hasInternetConnection = true;
  DateTime? _lastConnectionLoss;

  // Status callbacks
  Function(bool isOnline, String status)? onStatusChanged;
  Function(String message, {bool isError})? onMessage;
  Function(bool isLoading)? onLoadingChanged;

  DriverService(this.supabase)
      : _userActivityService = UserActivityService(supabase),
        _appLifecycleObserver = AppLifecycleObserver(UserActivityService(supabase)),
        _locationUpdater = LocationUpdater();

  Future<void> initialize() async {
    try {
      print('Initializing driver service...');

      // Initialize services
      _appLifecycleObserver.initialize();
      _locationUpdater.initialize();
      await _userActivityService.setUserActive();

      // Set up connectivity monitoring
      _setupConnectivityMonitoring();

      // Set up app lifecycle monitoring
      _setupAppLifecycleMonitoring();

      _appLifecycleObserver.setLoggedIn(true);

      print('Driver service initialized successfully');
    } catch (e) {
      print('Error initializing driver service: $e');
      _showUserFriendlyMessage('Failed to initialize services. Please restart the app.', isError: true);
      rethrow;
    }
  }

  void _setupConnectivityMonitoring() {
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
          (List<ConnectivityResult> results) {
        _handleConnectivityChange(results);
      },
    );
  }

  void _setupAppLifecycleMonitoring() {
    // Add this service as a lifecycle observer
    WidgetsBinding.instance.addObserver(this);
    print('App lifecycle monitoring set up');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    _handleAppLifecycleChange(state);
  }

  void _handleConnectivityChange(List<ConnectivityResult> results) {
    // Check if any of the results indicate a connection
    final bool hasConnection = results.any((result) => result != ConnectivityResult.none);

    if (hasConnection != _hasInternetConnection) {
      _hasInternetConnection = hasConnection;
      print('Connectivity changed: ${hasConnection ? 'Connected' : 'Disconnected'}');

      if (!hasConnection) {
        _lastConnectionLoss = DateTime.now();
        _startConnectionTimer();
      } else {
        _cancelConnectionTimer();
        _lastConnectionLoss = null;
        _showUserFriendlyMessage('Internet connection restored');
      }
    }
  }

  void _startConnectionTimer() {
    _cancelConnectionTimer();
    _connectionTimer = Timer(const Duration(minutes: 1), () {
      print('Connection lost for 1 minute, setting driver offline');
      _forceOfflineDueToConnection();
    });
  }

  void _cancelConnectionTimer() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
  }

  void _handleAppLifecycleChange(AppLifecycleState state) {
    print('App lifecycle changed: $state');

    switch (state) {
      case AppLifecycleState.paused:
      // App is in background - keep online status but pause location updates temporarily
        print('App paused - maintaining online status');
        break;
      case AppLifecycleState.resumed:
      // App is back in foreground - resume location updates if online
        print('App resumed');
        _resumeServicesIfOnline();
        break;
      case AppLifecycleState.detached:
      // App is being closed - set offline
        print('App detached - setting offline');
        _handleAppClosure();
        break;
      case AppLifecycleState.inactive:
      // Transitional state - no action needed
        break;
      case AppLifecycleState.hidden:
      // App is hidden but still running
        break;
    }
  }

  Future<void> _forceOfflineDueToConnection() async {
    try {
      print('Forcing driver offline due to connection loss');
      await _setDriverStatus(false, 'offline');
      _showUserFriendlyMessage('You\'ve been set offline due to poor internet connection', isError: true);
    } catch (e) {
      print('Error forcing offline: $e');
    }
  }

  Future<void> _handleAppClosure() async {
    try {
      print('Handling app closure');
      await _setDriverStatus(false, 'offline');
      await cleanup();
    } catch (e) {
      print('Error handling app closure: $e');
    }
  }

  Future<void> _resumeServicesIfOnline() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Check current status from database
      final driverData = await _getDriverData(user.id);
      final isOnline = driverData?['driver_status'] == 'online';

      if (isOnline && _hasInternetConnection) {
        await _locationUpdater.startIfNeeded();
        print('Resumed location services');
      }
    } catch (e) {
      print('Error resuming services: $e');
    }
  }

  Future<Map<String, dynamic>?> loadUserProfile() async {
    try {
      print('Loading user profile...');

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Load user profile
      final profile = await supabase
          .from('users')
          .select()
          .eq('email', user.email!)
          .single();

      print('User profile loaded successfully');
      return profile;
    } catch (e) {
      print('Error loading user profile: $e');
      _showUserFriendlyMessage('Failed to load your profile', isError: true);
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> loadDriverProfile() async {
    try {
      print('Loading driver profile...');

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Try to load driver profile
      List<Map<String, dynamic>> driverQuery = await supabase
          .from('drivers')
          .select()
          .eq('user_id', user.id);

      Map<String, dynamic>? driver;

      if (driverQuery.isEmpty) {
        print('Driver profile not found, creating new one');
        driver = await _createDriverRecord(user.id);
      } else {
        driver = driverQuery.first;
      }

      print('Driver profile loaded successfully');
      return driver;
    } catch (e) {
      print('Error loading driver profile: $e');
      _showUserFriendlyMessage('Failed to load driver information', isError: true);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _createDriverRecord(String userId) async {
    try {
      final newDriver = await supabase
          .from('drivers')
          .insert({
        'user_id': userId,
        'is_available': false,
        'driver_status': 'offline',
        'total_trips': 0,
        'average_rating': 0.00,
        'total_reviews': 0,
      })
          .select()
          .single();

      print('Created new driver record successfully');
      return newDriver;
    } catch (e) {
      print('Error creating driver record: $e');
      _showUserFriendlyMessage('Failed to set up driver account', isError: true);

      // Return default values if creation fails
      return {
        'user_id': userId,
        'is_available': false,
        'driver_status': 'offline',
        'total_trips': 0,
        'average_rating': 0.00,
        'total_reviews': 0,
      };
    }
  }

  Future<Map<String, dynamic>?> _getDriverData(String userId) async {
    try {
      final driver = await supabase
          .from('drivers')
          .select()
          .eq('user_id', userId)
          .maybeSingle();

      return driver;
    } catch (e) {
      print('Error getting driver data: $e');
      return null;
    }
  }

  Future<bool> toggleOnlineStatus(bool currentStatus) async {
    if (!_hasInternetConnection) {
      _showUserFriendlyMessage('Cannot go online without internet connection', isError: true);
      return currentStatus;
    }

    final newOnlineStatus = !currentStatus;
    final newDriverStatus = newOnlineStatus ? 'online' : 'offline';

    try {
      print('Toggling online status to: $newOnlineStatus');
      onLoadingChanged?.call(true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Ensure driver record exists
      await _ensureDriverRecordExists(user.id);

      await _setDriverStatus(newOnlineStatus, newDriverStatus);

      final message = newOnlineStatus
          ? 'You are now online and available for rides'
          : 'You are now offline';
      _showUserFriendlyMessage(message);

      return newOnlineStatus;
    } catch (e) {
      print('Error toggling online status: $e');
      _showUserFriendlyMessage('Failed to update your status. Please try again.', isError: true);
      return currentStatus;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  Future<void> _setDriverStatus(bool isOnline, String status) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (isOnline) {
      // Start location updates when going online
      await _locationUpdater.startIfNeeded();

      // Update driver status in database
      await supabase
          .from('drivers')
          .update({
        'is_available': true,
        'driver_status': 'online',
        'last_online': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', user.id);
    } else {
      // Stop location updates when going offline
      _locationUpdater.stopUpdating();

      // Update driver status in database
      await supabase
          .from('drivers')
          .update({
        'is_available': false,
        'driver_status': 'offline',
        'last_online': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('user_id', user.id);
    }

    onStatusChanged?.call(isOnline, _getStatusDisplay(status));
  }

  Future<void> _ensureDriverRecordExists(String userId) async {
    try {
      final existingDriver = await supabase
          .from('drivers')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existingDriver == null) {
        await _createDriverRecord(userId);
      }
    } catch (e) {
      print('Error ensuring driver record exists: $e');
      _showUserFriendlyMessage('Failed to verify driver account', isError: true);
    }
  }

  Future<void> forceLocationUpdate() async {
    try {
      print('Forcing location update...');
      onLoadingChanged?.call(true);

      await _locationUpdater.forceUpdate();
      _showUserFriendlyMessage('Location updated successfully');
    } catch (e) {
      print('Error forcing location update: $e');
      _showUserFriendlyMessage('Failed to update location', isError: true);
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  Future<void> signOut() async {
    try {
      print('Signing out driver...');

      final user = supabase.auth.currentUser;

      // Set user as inactive and stop services
      await _userActivityService.setUserInactive();
      _appLifecycleObserver.setLoggedIn(false);
      _locationUpdater.stopUpdating();

      // Update driver status to offline
      if (user != null) {
        await supabase
            .from('drivers')
            .update({
          'is_available': false,
          'driver_status': 'offline',
          'last_online': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        })
            .eq('user_id', user.id);
      }

      // Sign out from Supabase
      await supabase.auth.signOut();

      print('Driver signed out successfully');
      _showUserFriendlyMessage('Signed out successfully');
    } catch (e) {
      print('Error signing out: $e');
      _showUserFriendlyMessage('Error occurred while signing out', isError: true);
      rethrow;
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'on_trip':
        return 'On Trip';
      case 'busy':
        return 'Busy';
      case 'break':
        return 'On Break';
      default:
        return 'Offline';
    }
  }

  void _showUserFriendlyMessage(String message, {bool isError = false}) {
    onMessage?.call(message, isError: isError);
  }

  bool get isLocationRunning => _locationUpdater.isRunning;
  bool get hasInternetConnection => _hasInternetConnection;

  Future<void> cleanup() async {
    print('Cleaning up driver service...');

    _cancelConnectionTimer();
    await _connectivitySubscription?.cancel();

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    _appLifecycleObserver.dispose();
    _locationUpdater.dispose();

    print('Driver service cleanup completed');
  }

  // Ride Request Methods

  // Fetch pending ride requests for the driver
  Future<List<Map<String, dynamic>>> getPendingRideRequests() async {
    try {
      print('Fetching pending ride requests...');

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Get all pending ride requests
      final requests = await supabase
          .from('ride_requests')
          .select('*, users!ride_requests_user_id_fkey(full_name, phone, profile_url)')
          .eq('status', 'pending')
          .order('created_at', ascending: false);

      print('Found ${requests.length} pending ride requests');
      return List<Map<String, dynamic>>.from(requests);
    } catch (e) {
      print('Error fetching pending ride requests: $e');
      _showUserFriendlyMessage('Failed to load ride requests', isError: true);
      return [];
    }
  }

  // Accept a ride request
  Future<bool> acceptRideRequest(String rideRequestId) async {
    try {
      print('Accepting ride request: $rideRequestId');
      onLoadingChanged?.call(true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update ride request status
      await supabase
          .from('ride_requests')
          .update({
            'status': 'accepted',
            'driver_id': user.id,
            'accepted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rideRequestId)
          .eq('status', 'pending');

      // Update driver status
      await supabase
          .from('drivers')
          .update({
            'driver_status': 'on_trip',
            'is_available': false,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);

      onStatusChanged?.call(true, _getStatusDisplay('on_trip'));
      _showUserFriendlyMessage('Ride request accepted successfully');
      return true;
    } catch (e) {
      print('Error accepting ride request: $e');
      _showUserFriendlyMessage('Failed to accept ride request', isError: true);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  // Deny a ride request
  Future<bool> denyRideRequest(String rideRequestId) async {
    try {
      print('Denying ride request: $rideRequestId');
      onLoadingChanged?.call(true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update ride request status
      await supabase
          .from('ride_requests')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
            'cancelled_by': user.id,
            'cancellation_reason': 'Denied by driver',
          })
          .eq('id', rideRequestId)
          .eq('status', 'pending');

      _showUserFriendlyMessage('Ride request denied');
      return true;
    } catch (e) {
      print('Error denying ride request: $e');
      _showUserFriendlyMessage('Failed to deny ride request', isError: true);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  // Start a ride
  Future<bool> startRide(String rideRequestId) async {
    try {
      print('Starting ride: $rideRequestId');
      onLoadingChanged?.call(true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update ride request status
      await supabase
          .from('ride_requests')
          .update({
            'status': 'in_progress',
            'started_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rideRequestId)
          .eq('status', 'accepted')
          .eq('driver_id', user.id);

      _showUserFriendlyMessage('Ride started successfully');
      return true;
    } catch (e) {
      print('Error starting ride: $e');
      _showUserFriendlyMessage('Failed to start ride', isError: true);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  // Complete a ride
  Future<bool> completeRide(String rideRequestId) async {
    try {
      print('Completing ride: $rideRequestId');
      onLoadingChanged?.call(true);

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Update ride request status
      await supabase
          .from('ride_requests')
          .update({
            'status': 'completed',
            'completed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rideRequestId)
          .eq('status', 'in_progress')
          .eq('driver_id', user.id);

      // Update driver status
      await supabase
          .from('drivers')
          .update({
            'driver_status': 'online',
            'is_available': true,
            'total_trips': supabase.rpc('increment', params: {'row_id': user.id, 'table_name': 'drivers', 'column_name': 'total_trips', 'amount': 1}),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('user_id', user.id);

      onStatusChanged?.call(true, _getStatusDisplay('online'));
      _showUserFriendlyMessage('Ride completed successfully');
      return true;
    } catch (e) {
      print('Error completing ride: $e');
      _showUserFriendlyMessage('Failed to complete ride', isError: true);
      return false;
    } finally {
      onLoadingChanged?.call(false);
    }
  }

  // Get driver's trip history
  Future<List<Map<String, dynamic>>> getDriverTripHistory({int limit = 0}) async {
    try {
      print('Fetching driver trip history...');

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      var query = supabase
          .from('ride_requests')
          .select('*, users!ride_requests_user_id_fkey(full_name, phone, profile_url)')
          .eq('driver_id', user.id)
          .eq('status', 'completed')
          .order('created_at', ascending: false);

      if (limit > 0) {
        query = query.limit(limit);
      }

      final trips = await query;

      print('Found ${trips.length} trips in history');
      return List<Map<String, dynamic>>.from(trips);
    } catch (e) {
      print('Error fetching trip history: $e');
      _showUserFriendlyMessage('Failed to load trip history', isError: true);
      return [];
    }
  }

  // Get active ride for driver
  Future<Map<String, dynamic>?> getActiveRide() async {
    try {
      print('Checking for active ride...');

      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      final activeRides = await supabase
          .from('ride_requests')
          .select('*, users!ride_requests_user_id_fkey(full_name, phone, profile_url)')
          .eq('driver_id', user.id)
          .or('status.eq.accepted,status.eq.in_progress')
          .order('created_at', ascending: false)
          .limit(1);

      if (activeRides.isEmpty) {
        print('No active ride found');
        return null;
      }

      print('Active ride found');
      return activeRides.first;
    } catch (e) {
      print('Error checking active ride: $e');
      return null;
    }
  }

  // Navigate to user location
  Future<bool> navigateToUser(double latitude, double longitude) async {
    try {
      final url = 'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving';
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      } else {
        _showUserFriendlyMessage('Could not launch navigation', isError: true);
        return false;
      }
    } catch (e) {
      print('Navigation error: $e');
      _showUserFriendlyMessage('Failed to open navigation', isError: true);
      return false;
    }
  }

  Future<Position?> getCurrentLocation() async { // Now 'Position' should be found
    try {
      print('Getting current location...');
      onLoadingChanged?.call(true);

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled(); // Geolocator should be found
      if (!serviceEnabled) {
        print('Location services are disabled');
        return null;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission(); // LocationPermission and Geolocator should be found
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('Location permissions are denied');
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('Location permissions are permanently denied');
        return null;
      }

      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high, // LocationAccuracy should be found
        timeLimit: const Duration(seconds: 15),
      );

      print('Current location: ${position.latitude}, ${position.longitude}');
      return position;
    } catch (e) {
      print('Error getting current location: $e');
      return null;
    } finally {
      onLoadingChanged?.call(false);
    }
  }
  // Get hotspot data
  // Get hotspot data - FIXED to show only riders
  // Replace the existing getHotspotData method in homebackend.dart with this:

  Future<List<Map<String, dynamic>>> getHotspotData() async {
    try {
      print('Getting hotspot data for currently active riders...');

      // Query user_locations table with JOIN to users table, filtering for riders only
      // This will get all currently active riders without time restriction
      final locations = await supabase
          .from('user_locations')
          .select('''
        latitude, 
        longitude, 
        last_updated,
        users!inner(role, is_active)
      ''')
          .eq('users.role', 'rider')
          .eq('users.is_active', true)
          .order('last_updated', ascending: false);

      print('Found ${locations.length} active rider locations');
      return List<Map<String, dynamic>>.from(locations);
    } catch (e) {
      print('Error getting hotspot data: $e');
      _showUserFriendlyMessage('Failed to load hotspot data', isError: true);
      return [];
    }
  }



}
