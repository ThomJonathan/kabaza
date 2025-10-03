import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LocationUpdater with WidgetsBindingObserver {
  static final LocationUpdater _instance = LocationUpdater._internal();
  factory LocationUpdater() => _instance;
  LocationUpdater._internal();

  Timer? _timer;
  bool _isRunning = false;
  StreamSubscription<AuthState>? _authSubscription;

  // Cache to avoid redundant geocoding
  Position? _lastPosition;
  String? _lastAddress;
  DateTime? _lastGeocodingTime;

  // Constants for efficiency
  static const int UPDATE_INTERVAL_SECONDS = 10;
  static const int GEOCODING_THROTTLE_SECONDS = 30; // Only geocode every 30s
  static const double MIN_DISTANCE_FOR_GEOCODING = 50.0; // meters

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

    // Update every 10 seconds for efficient real-time tracking
    _timer = Timer.periodic(Duration(seconds: UPDATE_INTERVAL_SECONDS), (timer) async {
      await _updateLocation();
    });

    print("Started location updates (every $UPDATE_INTERVAL_SECONDS seconds).");
  }

  Future<void> _updateLocation() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) {
        stopUpdating();
        return;
      }

      // Get position with shorter timeout for faster updates
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 8), // Shorter timeout for 10s interval
      );

      // Determine if we should perform geocoding
      String? address = _lastAddress; // Use cached address by default
      bool shouldGeocode = _shouldPerformGeocoding(position);

      if (shouldGeocode) {
        address = await _performGeocoding(position);
        _lastAddress = address;
        _lastGeocodingTime = DateTime.now();
      }

      _lastPosition = position;

      // Update database with upsert for efficiency
      await Supabase.instance.client.from('user_locations').upsert({
        'user_id': user.id,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'address': address,
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id'); // Specify conflict column for better performance

      print("Location updated: ${position.latitude}, ${position.longitude}");

    } catch (e) {
      print("Error updating location: $e");

      // If it's a timeout or location error, don't stop the service
      if (e.toString().contains('timeout') ||
          e.toString().contains('location') ||
          e.toString().contains('service')) {
        print("Location update failed, will retry in next cycle");
      }
    }
  }

  // Intelligently decide when to perform expensive geocoding
  bool _shouldPerformGeocoding(Position newPosition) {
    // Always geocode on first update
    if (_lastPosition == null || _lastGeocodingTime == null) {
      return true;
    }

    // Check time since last geocoding
    final timeSinceLastGeocoding = DateTime.now().difference(_lastGeocodingTime!);
    if (timeSinceLastGeocoding.inSeconds < GEOCODING_THROTTLE_SECONDS) {
      return false;
    }

    // Check distance moved
    final distance = Geolocator.distanceBetween(
      _lastPosition!.latitude,
      _lastPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    // Only geocode if moved significant distance
    return distance >= MIN_DISTANCE_FOR_GEOCODING;
  }

  // Perform geocoding with error handling
  Future<String?> _performGeocoding(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      ).timeout(Duration(seconds: 5)); // Timeout for geocoding

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
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

        return addressParts.join(', ');
      }
    } catch (e) {
      print("Geocoding failed: $e");
    }

    return null;
  }

  void stopUpdating() {
    _timer?.cancel();
    _timer = null;
    _isRunning = false;

    // Clear cache
    _lastPosition = null;
    _lastAddress = null;
    _lastGeocodingTime = null;

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
        print("App resumed - ensuring location updates");
        startIfNeeded();
        break;
      case AppLifecycleState.paused:
        print("App paused - location updates continue in background");
        // Continue running in background
        break;
      case AppLifecycleState.detached:
        print("App detached - stopping location updates");
        stopUpdating();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      // No action needed
        break;
    }
  }
}