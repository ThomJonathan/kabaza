import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/LocationUpdater.dart';

class DriverService with WidgetsBindingObserver {
  final SupabaseClient supabase;
  final UserActivityService _userActivityService;
  final AppLifecycleObserver _appLifecycleObserver;
  final LocationUpdater _locationUpdater;
  final Connectivity _connectivity = Connectivity();

  Timer? _connectionTimer;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;
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
          (ConnectivityResult result) {
        _handleConnectivityChange(result);
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

  void _handleConnectivityChange(ConnectivityResult result) {
    final bool hasConnection = result != ConnectivityResult.none;

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
}