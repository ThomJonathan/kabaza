// book_ride_page.dart - Fixed version
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:math' as math;

class BookRidePage extends StatefulWidget {
  const BookRidePage({Key? key}) : super(key: key);

  @override
  State<BookRidePage> createState() => _BookRidePageState();
}

class _BookRidePageState extends State<BookRidePage>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  // Controllers
  GoogleMapController? _mapController;
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();
  late AnimationController _animationController;
  late Animation<double> _slideAnimation;

  // State variables
  LatLng? _currentLocation;
  LatLng? _pickupLocation;
  LatLng? _destinationLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<Map<String, dynamic>> _availableRides = [];
  bool _isLoadingLocation = true;
  bool _isLoadingRides = false;
  bool _showRidesList = false;
  String? _estimatedDistance;
  String? _estimatedDuration;
  double? _estimatedFare;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isInitialized = false; // Add this flag

  // Map style
  static const String _mapStyle = '''
[
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{"visibility": "off"}]
  }
]
''';

  @override
  void initState() {
    super.initState();
    print('BookRidePage: initState called'); // Debug log
    _initializeAnimations();
    _getCurrentLocation();
  }

  void _initializeAnimations() {
    try {
      _animationController = AnimationController(
        duration: const Duration(milliseconds: 300),
        vsync: this,
      );
      _slideAnimation = Tween<double>(
        begin: 1.0,
        end: 0.6,
      ).animate(CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ));
      _isInitialized = true;
      print('BookRidePage: Animations initialized successfully');
    } catch (e) {
      print('BookRidePage: Animation initialization error: $e');
      // Don't set error state here, just log it
    }
  }

  Future<void> _getCurrentLocation() async {
    if (!mounted) return;

    print('BookRidePage: Getting current location...');

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        print('BookRidePage: Location services disabled');
        _setError('Location services are disabled. Please enable location services.');
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print('BookRidePage: Location permissions denied');
          _setError('Location permissions are denied. Please grant location permissions.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print('BookRidePage: Location permissions permanently denied');
        _setError('Location permissions are permanently denied. Please enable them in settings.');
        return;
      }

      print('BookRidePage: Getting position...');

      // Get current position with timeout
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15), // Increased timeout
      );

      print('BookRidePage: Position obtained: ${position.latitude}, ${position.longitude}');

      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _pickupLocation = _currentLocation;
          _isLoadingLocation = false;
          _hasError = false;
        });

        // Get address for current location
        await _updatePickupAddress();
        _updateMarkers();
        print('BookRidePage: Location setup completed');
      }
    } catch (e) {
      print('BookRidePage: Location error: $e');
      if (mounted) {
        // Provide fallback location (Kampala, Uganda)
        setState(() {
          _currentLocation = const LatLng(0.3476, 32.5825);
          _pickupLocation = _currentLocation;
          _isLoadingLocation = false;
          _hasError = false; // Don't show error, use fallback
        });

        _updateMarkers();
        _pickupController.text = "Kampala, Uganda (Default)";

        _showWarningSnackBar('Using default location. Please set your pickup location manually.');
      }
    }
  }

  void _setError(String message) {
    if (!mounted) return;

    print('BookRidePage: Setting error: $message');
    setState(() {
      _isLoadingLocation = false;
      _hasError = true;
      _errorMessage = message;
    });
    _showError(message);
  }

  void _showWarningSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _updatePickupAddress() async {
    if (_pickupLocation == null) return;

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
      );

      if (placemarks.isNotEmpty && mounted) {
        Placemark place = placemarks[0];
        String address = '${place.street ?? ''}, ${place.locality ?? ''}';
        _pickupController.text = address.trim().replaceAll(RegExp(r'^,\s*'), '');
      }
    } catch (e) {
      print('BookRidePage: Error getting pickup address: $e');
      // Don't show error for this, it's not critical
      if (mounted) {
        _pickupController.text = 'Current Location';
      }
    }
  }

  Future<void> _searchLocation(String query, bool isDestination) async {
    if (query.isEmpty || !mounted) return;

    try {
      List<Location> locations = await locationFromAddress(query);
      if (locations.isNotEmpty && mounted) {
        Location location = locations[0];
        LatLng newLocation = LatLng(location.latitude, location.longitude);

        setState(() {
          if (isDestination) {
            _destinationLocation = newLocation;
          } else {
            _pickupLocation = newLocation;
          }
        });

        _updateMarkers();
        if (_pickupLocation != null && _destinationLocation != null) {
          await _calculateRoute();
        }
        _animateToLocation(newLocation);
      }
    } catch (e) {
      print('BookRidePage: Location search error: $e');
      _showError('Location not found: $query');
    }
  }

  void _updateMarkers() {
    if (!mounted) return;

    Set<Marker> newMarkers = {};

    if (_pickupLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: _pickupLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Pickup Location'),
        ),
      );
    }

    if (_destinationLocation != null) {
      newMarkers.add(
        Marker(
          markerId: const MarkerId('destination'),
          position: _destinationLocation!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      );
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  Future<void> _calculateRoute() async {
    if (_pickupLocation == null || _destinationLocation == null || !mounted) return;

    try {
      // Calculate straight line distance for demo
      double distance = _calculateDistance(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );

      // Create simple polyline (in real app, use Google Directions API)
      List<LatLng> routePoints = [_pickupLocation!, _destinationLocation!];

      if (mounted) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: routePoints,
              color: Theme.of(context).primaryColor,
              width: 4,
            ),
          };

          _estimatedDistance = '${distance.toStringAsFixed(1)} km';
          _estimatedDuration = '${(distance * 3).toInt()} min'; // Rough estimate
          _estimatedFare = distance * 2.5; // Base fare calculation
        });

        await _fetchAvailableRides();
        _fitMarkersInView();
      }
    } catch (e) {
      print('BookRidePage: Route calculation error: $e');
      _showError('Error calculating route');
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  Future<void> _fetchAvailableRides() async {
    if (_pickupLocation == null || _destinationLocation == null || !mounted) return;

    setState(() => _isLoadingRides = true);

    try {
      // In a real app, this would fetch from your backend
      // For demo, we'll create mock data
      await Future.delayed(const Duration(seconds: 1));

      if (mounted) {
        List<Map<String, dynamic>> mockRides = [
          {
            'id': '1',
            'driver_name': 'John Mukisa',
            'vehicle_type': 'Sedan',
            'vehicle_model': 'Toyota Corolla',
            'plate_number': 'UAM 123A',
            'rating': 4.8,
            'trip_count': 234,
            'estimated_arrival': '3 min',
            'fare': _estimatedFare ?? 10.0,
            'driver_photo': null,
          },
          {
            'id': '2',
            'driver_name': 'Grace Namukasa',
            'vehicle_type': 'SUV',
            'vehicle_model': 'Honda CR-V',
            'plate_number': 'UAM 456B',
            'rating': 4.9,
            'trip_count': 189,
            'estimated_arrival': '5 min',
            'fare': (_estimatedFare ?? 10.0) * 1.2,
            'driver_photo': null,
          },
          {
            'id': '3',
            'driver_name': 'David Ssali',
            'vehicle_type': 'Economy',
            'vehicle_model': 'Nissan Note',
            'plate_number': 'UAM 789C',
            'rating': 4.7,
            'trip_count': 156,
            'estimated_arrival': '7 min',
            'fare': (_estimatedFare ?? 10.0) * 0.8,
            'driver_photo': null,
          },
        ];

        setState(() {
          _availableRides = mockRides;
          _isLoadingRides = false;
          _showRidesList = true;
        });

        if (_isInitialized) {
          _animationController.forward();
        }
      }
    } catch (e) {
      print('BookRidePage: Fetch rides error: $e');
      if (mounted) {
        setState(() => _isLoadingRides = false);
        _showError('Error fetching available rides: $e');
      }
    }
  }

  void _animateToLocation(LatLng location) {
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(location, 15),
      );
    }
  }

  void _fitMarkersInView() {
    if (_mapController != null && _pickupLocation != null && _destinationLocation != null) {
      LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(
          math.min(_pickupLocation!.latitude, _destinationLocation!.latitude),
          math.min(_pickupLocation!.longitude, _destinationLocation!.longitude),
        ),
        northeast: LatLng(
          math.max(_pickupLocation!.latitude, _destinationLocation!.latitude),
          math.max(_pickupLocation!.longitude, _destinationLocation!.longitude),
        ),
      );

      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 100));
    }
  }

  void _bookRide(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver: ${ride['driver_name']}'),
            Text('Vehicle: ${ride['vehicle_model']}'),
            Text('Fare: UGX ${((ride['fare'] as double) * 3700).toStringAsFixed(0)}'),
            Text('Estimated Arrival: ${ride['estimated_arrival']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _processBooking(ride);
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Future<void> _processBooking(Map<String, dynamic> ride) async {
    if (!mounted) return;

    try {
      // Show loading
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Booking your ride...'),
            ],
          ),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ride booked with ${ride['driver_name']}!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('BookRidePage: Booking error: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        _showError('Booking failed: $e');
      }
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _retryLocationFetch() {
    setState(() {
      _hasError = false;
      _isLoadingLocation = true;
    });
    _getCurrentLocation();
  }

  @override
  void dispose() {
    print('BookRidePage: dispose called');
    _pickupController.dispose();
    _destinationController.dispose();
    if (_isInitialized) {
      _animationController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print('BookRidePage: build called, hasError: $_hasError, isLoading: $_isLoadingLocation');

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () {
            print('BookRidePage: Back button pressed');
            Navigator.pop(context);
          },
        ),
        title: const Text(
          'Book a Ride',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _hasError
          ? _buildErrorWidget()
          : _isLoadingLocation
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting your location...'),
          ],
        ),
      )
          : Column(
        children: [
          // Location inputs
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              children: [
                _buildLocationInput(
                  controller: _pickupController,
                  hint: 'Pickup location',
                  icon: Icons.my_location,
                  iconColor: Colors.green,
                  onChanged: (value) => _searchLocation(value, false),
                ),
                const SizedBox(height: 12),
                _buildLocationInput(
                  controller: _destinationController,
                  hint: 'Where to?',
                  icon: Icons.location_on,
                  iconColor: Colors.red,
                  onChanged: (value) => _searchLocation(value, true),
                ),
                if (_estimatedDistance != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '$_estimatedDistance • $_estimatedDuration • UGX ${((_estimatedFare ?? 0) * 3700).toStringAsFixed(0)}',
                          style: TextStyle(
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Map
          Expanded(
            child: _isInitialized
                ? AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return FractionallySizedBox(
                  heightFactor: _slideAnimation.value,
                  child: GoogleMap(
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      try {
                        _mapController!.setMapStyle(_mapStyle);
                      } catch (e) {
                        print('BookRidePage: Map style error: $e');
                      }
                    },
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation ?? const LatLng(0.3476, 32.5825),
                      zoom: 14,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  ),
                );
              },
            )
                : GoogleMap(
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
                try {
                  _mapController!.setMapStyle(_mapStyle);
                } catch (e) {
                  print('BookRidePage: Map style error: $e');
                }
              },
              initialCameraPosition: CameraPosition(
                target: _currentLocation ?? const LatLng(0.3476, 32.5825),
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
            ),
          ),

          // Available rides list
          if (_showRidesList)
            Container(
              height: MediaQuery.of(context).size.height * 0.4,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 10,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Available Rides',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (_isLoadingRides)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _availableRides.length,
                      itemBuilder: (context, index) {
                        final ride = _availableRides[index];
                        return _buildRideCard(ride);
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _retryLocationFetch,
              child: const Text('Retry'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _currentLocation = const LatLng(0.3476, 32.5825);
                  _pickupLocation = _currentLocation;
                  _isLoadingLocation = false;
                  _hasError = false;
                });
                _updateMarkers();
                _pickupController.text = "Kampala, Uganda (Default)";
              },
              child: const Text('Use Default Location'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInput({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required Function(String) onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, color: iconColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).primaryColor,
                child: Text(
                  ride['driver_name'][0],
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride['driver_name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${ride['vehicle_model']} • ${ride['plate_number']}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${ride['rating']} (${ride['trip_count']} trips)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'UGX ${((ride['fare'] as double) * 3700).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    'Arrives in ${ride['estimated_arrival']}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => _bookRide(ride),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Book This Ride',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}