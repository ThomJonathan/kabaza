import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';  // Add this import
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationUpdater with WidgetsBindingObserver {
  static final LocationUpdater _instance = LocationUpdater._internal();
  factory LocationUpdater() => _instance;
  LocationUpdater._internal();

  Timer? _timer;
  bool _isRunning = false;
  StreamSubscription<AuthState>? _authSubscription;

  void initialize() {
    WidgetsBinding.instance.addObserver(this);

    // Listen to auth state changes
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;

      if (event == AuthChangeEvent.signedIn) {
        startIfNeeded();
      } else if (event == AuthChangeEvent.signedOut) {
        stopUpdating();
      }
    });

    // Start if user is already logged in
    startIfNeeded();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authSubscription?.cancel();
    stopUpdating();
  }

  // Public method that can be called from outside
  Future<void> startIfNeeded() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && !_isRunning) {
      try {
        // Check location permissions before starting
        if (await _checkLocationPermissions()) {
          _startTimer();
        } else {
          throw Exception('Location permissions not granted');
        }
      } catch (e) {
        print("Error starting location updates: $e");
        rethrow;
      }
    }
  }

  Future<bool> _checkLocationPermissions() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Check if location services are enabled
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled.');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied');
      return false;
    }

    return true;
  }

  void _startTimer() {
    _isRunning = true;

    // Update immediately when starting
    _updateLocation();

    // Then update every minute
    _timer = Timer.periodic(Duration(minutes: 1), (timer) async {
      await _updateLocation();
    });

    print("Started location updates.");
  }

  Future<void> _updateLocation() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        stopUpdating();
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 30),
      );

      // Perform reverse geocoding to get address
      String? address;
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
            position.latitude,
            position.longitude
        );

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          // Build address string from available components
          List<String> addressParts = [];

          if (place.street != null && place.street!.isNotEmpty) {
            addressParts.add(place.street!);
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            addressParts.add(place.locality!);
          }
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
            addressParts.add(place.administrativeArea!);
          }
          if (place.country != null && place.country!.isNotEmpty) {
            addressParts.add(place.country!);
          }

          address = addressParts.join(', ');
        }
      } catch (geocodingError) {
        print("Geocoding failed: $geocodingError");
        // Continue without address if geocoding fails
      }

      // Use upsert to handle duplicates automatically
      await Supabase.instance.client.from('user_locations').upsert({
        'user_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'address': address, // This was missing!
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      });

      print("Location updated for user ${user.id} at ${DateTime.now()}");
      if (address != null) {
        print("Address: $address");
      }

    } catch (e) {
      print("Error updating location: $e");

      // If it's a timeout or location error, don't stop the service
      // It will try again in the next cycle
      if (e.toString().contains('timeout') || e.toString().contains('location')) {
        print("Location update failed, will retry in next cycle");
      }
    }
  }

  void stopUpdating() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;
    print("Stopped location updates.");
  }

  // Force an immediate location update (useful for testing or manual triggers)
  Future<void> forceUpdate() async {
    if (_isRunning) {
      await _updateLocation();
    } else {
      print("Location updater is not running. Cannot force update.");
    }
  }

  // Get current status
  bool get isRunning => _isRunning;

  // Called when app state changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        startIfNeeded();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      // Don't stop on paused/inactive - keep running in background
      // Only stop on detached (app completely closed)
        if (state == AppLifecycleState.detached) {
          stopUpdating();
        }
        break;
      case AppLifecycleState.hidden:
      // Handle the new hidden state for modern Flutter versions
        break;
    }
  }
}