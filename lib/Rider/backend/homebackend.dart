// rider_home_backend.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/LocationUpdater.dart';

class RiderHomeBackend {
  final SupabaseClient supabase;
  final UserActivityService userActivityService;
  final AppLifecycleObserver appLifecycleObserver;
  final LocationUpdater locationUpdater;
  final Function(Map<String, dynamic>) onUserProfileLoaded;
  final Function(bool) onLoadingStateChanged;
  final Function(bool) onLocationLoadingStateChanged;
  final Function(String) onShowErrorSnackBar;
  final Function(String) onShowSuccessSnackBar;
  final BuildContext context;

  RiderHomeBackend({
    required this.supabase,
    required this.userActivityService,
    required this.appLifecycleObserver,
    required this.locationUpdater,
    required this.onUserProfileLoaded,
    required this.onLoadingStateChanged,
    required this.onLocationLoadingStateChanged,
    required this.onShowErrorSnackBar,
    required this.onShowSuccessSnackBar,
    required this.context,
  });

  Future<void> initializeApp() async {
    try {
      // Initialize observers and services
      appLifecycleObserver.initialize();
      locationUpdater.initialize();

      // Load user profile first
      await loadUserProfile();

      // Then initialize location services
      await initializeLocationServices();
    } catch (e) {
      print('Error during app initialization: $e');
      onLoadingStateChanged(false);
      onShowErrorSnackBar('Error initializing app: $e');
    }
  }

  Future<void> initializeLocationServices() async {
    try {
      onLocationLoadingStateChanged(true);

      // Set user as active
      await userActivityService.setUserActive();
      appLifecycleObserver.setLoggedIn(true);

      // Start location updates using the new service
      if (!locationUpdater.isRunning) {
        await locationUpdater.startIfNeeded();
      } else {
        // If already running, just force an update to get current location
        await forceLocationUpdate();
      }
    } catch (e) {
      print('Error initializing location services: $e');
      onShowErrorSnackBar('Error starting location services');

      // Fallback to manual location update if service fails
      await getCurrentLocationAndUpdateFallback();
    } finally {
      onLocationLoadingStateChanged(false);
    }
  }

  Future<void> loadUserProfile() async {
    try {
      final user = supabase.auth.currentUser;
      if (user != null) {
        final profile = await supabase
            .from('users')
            .select()
            .eq('email', user.email!)
            .single();

        onUserProfileLoaded(profile);
      }
    } catch (error) {
      onLoadingStateChanged(false);
      onShowErrorSnackBar('Error loading profile: $error');
    }
  }

  Future<void> forceLocationUpdate() async {
    onLocationLoadingStateChanged(true);
    try {
      await locationUpdater.forceUpdate();
      onShowSuccessSnackBar('Location updated successfully');
    } catch (e) {
      print('Force update failed, trying fallback: $e');
      await getCurrentLocationAndUpdateFallback();
    } finally {
      onLocationLoadingStateChanged(false);
    }
  }

  Future<void> getCurrentLocationAndUpdateFallback() async {
    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showLocationPermissionDialog('Location services are disabled. Please enable them in settings.');
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showLocationPermissionDialog('Location permissions are denied. Please grant permission to continue.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showLocationPermissionDialog('Location permissions are permanently denied. Please enable them in app settings.');
        return;
      }

      // Get current position with fallback strategy
      Position? position;

      try {
        // First try with high accuracy but longer timeout
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 15),
        );
      } catch (e) {
        print('High accuracy failed, trying medium accuracy: $e');
        try {
          // Fallback to medium accuracy with shorter timeout
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          );
        } catch (e2) {
          print('Medium accuracy failed, trying last known position: $e2');
          // Last resort: try to get last known position
          position = await Geolocator.getLastKnownPosition();
          if (position == null) {
            throw Exception('Unable to get location: GPS timeout and no cached location available');
          }
        }
      }

      // Get address from coordinates (optional)
      String? address;
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        ).timeout(const Duration(seconds: 5));

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          address = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}';
        }
      } catch (e) {
        print('Error getting address: $e');
        // Continue without address if geocoding fails
      }

      // Update location in database
      await updateUserLocation(
        position.latitude,
        position.longitude,
        address,
      );
    } catch (error) {
      print('Error getting location: $error');

      // Show more specific error messages based on the error type
      String errorMessage;
      if (error.toString().contains('TimeoutException')) {
        errorMessage = 'Location request timed out. Please make sure you\'re in an area with good GPS signal and try again.';
      } else if (error.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Location permission denied. Please enable location access in settings.';
      } else if (error.toString().contains('GPS')) {
        errorMessage = 'GPS is not available. Please enable location services and try again.';
      } else {
        errorMessage = 'Unable to get your location. Please try again later.';
      }

      _showLocationErrorDialog(errorMessage);
    }
  }

  Future<void> updateUserLocation(double latitude, double longitude, String? address) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Get user ID from the users table
      final userResponse = await supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .single();

      final userId = userResponse['id'];

      // Check if user location already exists
      final existingLocation = await supabase
          .from('user_locations')
          .select('user_id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existingLocation != null) {
        // Update existing location record
        await supabase
            .from('user_locations')
            .update({
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'last_updated': DateTime.now().toIso8601String(),
        })
            .eq('user_id', userId);

        print('Location updated for existing user');
      } else {
        // Insert new location record for new user
        await supabase.from('user_locations').insert({
          'user_id': userId,
          'latitude': latitude,
          'longitude': longitude,
          'address': address,
          'is_sharing_location': true,
          'last_updated': DateTime.now().toIso8601String(),
        });

        print('Location inserted for new user');
      }
    } catch (error) {
      print('Error updating location: $error');
      onShowErrorSnackBar('Error updating location: $error');
    }
  }

  Future<void> signOut() async {
    try {
      // Set user as inactive and stop location updates
      await userActivityService.setUserInactive();
      appLifecycleObserver.setLoggedIn(false);
      locationUpdater.stopUpdating();

      // Sign out from Supabase
      await supabase.auth.signOut();
    } catch (error) {
      onShowErrorSnackBar('Error signing out: $error');
    }
  }

  void _showLocationPermissionDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Permission'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            if (message.contains('app settings'))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openAppSettings();
                },
                child: const Text('Open App Settings'),
              ),
            if (message.contains('Location services'))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openLocationSettings();
                },
                child: const Text('Open Location Settings'),
              ),
          ],
        );
      },
    );
  }

  void _showLocationErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Location Error'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message),
              const SizedBox(height: 16),
              const Text(
                'Tips to improve location accuracy:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text('• Make sure you\'re outdoors or near a window'),
              const Text('• Enable high accuracy mode in location settings'),
              const Text('• Restart the app if location services were just enabled'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                forceLocationUpdate();
              },
              child: const Text('Retry'),
            ),
            if (message.contains('settings'))
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  Geolocator.openLocationSettings();
                },
                child: const Text('Open Settings'),
              ),
          ],
        );
      },
    );
  }

  void dispose() {
    appLifecycleObserver.dispose();
    locationUpdater.dispose();
  }
}