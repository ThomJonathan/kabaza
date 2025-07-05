import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rideModel.dart';
import 'rideService.dart';
import 'package:kabanza/utils/LocationUpdater.dart';
import 'package:kabanza/utils/observer.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/messages.dart';
import 'dart:async';
import 'dart:math' as math;

class EnhancedBookRidePage extends StatefulWidget {
  const EnhancedBookRidePage({Key? key}) : super(key: key);

  @override
  State<EnhancedBookRidePage> createState() => _EnhancedBookRidePageState();
}

class _EnhancedBookRidePageState extends State<EnhancedBookRidePage>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  late final RideBookingService _rideService;
  final LocationUpdater _locationUpdater = LocationUpdater();

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
  List<RideModel> _availableRides = [];
  bool _isLoadingLocation = true;
  bool _isLoadingRides = false;
  bool _showRidesList = false;
  String? _estimatedDistance;
  String? _estimatedDuration;
  double? _estimatedFare;
  Timer? _driverUpdateTimer;

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
    _rideService = RideBookingService(_supabase);
    _initializeAnimations();
    _getCurrentLocation();
    _startDriverUpdates();
  }

  void _initializeAnimations() {
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
  }

  void _startDriverUpdates() {
    // Update nearby drivers every 30 seconds
    _driverUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_pickupLocation != null && _showRidesList) {
        _fetchNearbyDrivers();
      }
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      // Force location update to get current position
      await _locationUpdater.forceUpdate();

      // Get location from database (most recent)
      final user = _supabase.auth.currentUser;
      if (user != null) {
        final userResponse = await _supabase
            .from('users')
            .select('id')
            .eq('email', user.email!)
            .single();

        final locationResponse = await _supabase
            .from('user_locations')
            .select('latitude, longitude, address')
            .eq('user_id', userResponse['id'])
            .single();

        if (mounted) {
          setState(() {
            _currentLocation = LatLng(
              locationResponse['latitude'].toDouble(),
              locationResponse['longitude'].toDouble(),
            );
            _pickupLocation = _currentLocation;
            _isLoadingLocation = false;
          });

          _pickupController.text = locationResponse['address'] ?? 'Current Location';
          _updateMarkers();
        }
      }
    } catch (e) {
      print('Error getting current location: $e');
      if (mounted) {
        setState(() {
          _currentLocation = const LatLng(0.3476, 32.5825); // Kampala fallback
          _pickupLocation = _currentLocation;
          _isLoadingLocation = false;
        });
        _pickupController.text = "Kampala, Uganda (Default)";
        _updateMarkers();
        _showSnackBar('Using default location. Please enable location services.', Colors.orange);
      }
    }
  }

  Future<void> _searchLocation(String query, bool isDestination) async {
    if (query.isEmpty) return;

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
      _showSnackBar('Location not found: $query', Colors.red);
    }
  }

  void _updateMarkers() {
    Set<Marker> newMarkers = {};

    // Pickup marker
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

    // Destination marker
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

    // Driver markers
    for (RideModel ride in _availableRides) {
      if (ride.driverLat != null && ride.driverLng != null) {
        newMarkers.add(
          Marker(
            markerId: MarkerId('driver_${ride.id}'),
            position: LatLng(ride.driverLat!, ride.driverLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
            infoWindow: InfoWindow(
              title: ride.driverName,
              snippet: '${ride.vehicleModel} • ${ride.estimatedArrival}',
            ),
          ),
        );
      }
    }

    setState(() {
      _markers = newMarkers;
    });
  }

  Future<void> _calculateRoute() async {
    if (_pickupLocation == null || _destinationLocation == null) return;

    try {
      double distance = _calculateDistance(
        _pickupLocation!.latitude,
        _pickupLocation!.longitude,
        _destinationLocation!.latitude,
        _destinationLocation!.longitude,
      );

      List<LatLng> routePoints = [_pickupLocation!, _destinationLocation!];

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
        _estimatedDuration = '${(distance * 3).toInt()} min';
        _estimatedFare = 5.0 + (distance * 2.5); // Base fare + per km rate
      });

      await _fetchNearbyDrivers();
      _fitMarkersInView();
    } catch (e) {
      _showSnackBar('Error calculating route: $e', Colors.red);
    }
  }

  Future<void> _fetchNearbyDrivers() async {
    if (_pickupLocation == null) return;

    setState(() => _isLoadingRides = true);

    try {
      List<RideModel> drivers = await _rideService.fetchNearbyDrivers(
        userLocation: _pickupLocation!,
        radiusKm: 5.0,
      );

      setState(() {
        _availableRides = drivers;
        _isLoadingRides = false;
        _showRidesList = true;
      });

      _updateMarkers();
      _animationController.forward();
    } catch (e) {
      setState(() => _isLoadingRides = false);
      _showSnackBar('Error fetching nearby drivers: $e', Colors.red);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
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

  void _animateToLocation(LatLng location) {
    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(location, 15),
    );
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

  void _bookRide(RideModel ride) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Booking'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Driver: ${ride.driverName}'),
            Text('Vehicle: ${ride.vehicleModel}'),
            Text('Distance: ${ride.distanceFromLocation(_pickupLocation!.latitude, _pickupLocation!.longitude).toStringAsFixed(1)} km'),
            Text('Fare: UGX ${(ride.fare * 3700).toStringAsFixed(0)}'),
            Text('Estimated Arrival: ${ride.estimatedArrival}'),
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

  Future<void> _processBooking(RideModel ride) async {
    _showLoadingDialog('Booking your ride...');

    try {
      final result = await _rideService.bookRide(
        driverId: ride.driverId!,
        pickupLocation: _pickupLocation!,
        destinationLocation: _destinationLocation!,
        pickupAddress: _pickupController.text,
        destinationAddress: _destinationController.text,
        estimatedFare: ride.fare,
      );

      Navigator.pop(context); // Close loading dialog

      if (result['success']) {
        _showSnackBar(result['message'], Colors.green);
      } else {
        _showSnackBar(result['message'], Colors.red);
      }
    } catch (e) {
      Navigator.pop(context);
      _showSnackBar('Booking failed: $e', Colors.red);
    }
  }

  void _sendMessageToDriver(RideModel ride) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MessagesPage(
          driverId: ride.driverId!,
          driverName: ride.driverName,
          rideService: _rideService,
        ),
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _animationController.dispose();
    _driverUpdateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Book a Ride',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _fetchNearbyDrivers,
          ),
        ],
      ),
      body: _isLoadingLocation
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
                        Expanded(
                          child: Text(
                            '$_estimatedDistance • $_estimatedDuration • UGX ${((_estimatedFare ?? 0) * 3700).toStringAsFixed(0)}',
                            style: TextStyle(
                              color: Colors.blue[700],
                              fontWeight: FontWeight.w500,
                            ),
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
            child: AnimatedBuilder(
              animation: _slideAnimation,
              builder: (context, child) {
                return FractionallySizedBox(
                  heightFactor: _slideAnimation.value,
                  child: GoogleMap(
                    onMapCreated: (GoogleMapController controller) {
                      _mapController = controller;
                      controller.setMapStyle(_mapStyle);
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
                        Text(
                          'Available Drivers (${_availableRides.length})',
                          style: const TextStyle(
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
                    child: _availableRides.isEmpty
                        ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.car_rental, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'No drivers available nearby',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try expanding your search area',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    )
                        : ListView.builder(
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

  Widget _buildRideCard(RideModel ride) {
    double distance = ride.distanceFromLocation(
      _pickupLocation!.latitude,
      _pickupLocation!.longitude,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Theme.of(context).primaryColor,
                backgroundImage: ride.driverPhoto != null
                    ? NetworkImage(ride.driverPhoto!)
                    : null,
                child: ride.driverPhoto == null
                    ? Text(
                  ride.driverName[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ride.driverName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      '${ride.vehicleModel} • ${ride.plateNumber}',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          '${ride.rating} (${ride.tripCount} trips)',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green[100],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${distance.toStringAsFixed(1)}km away',
                            style: TextStyle(
                              color: Colors.green[700],
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                            ),
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
                    'UGX ${(ride.fare * 3700).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Colors.green,
                    ),
                  ),
                  Text(
                    'ETA: ${ride.estimatedArrival}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: () => _bookRide(ride),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Book Ride',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _sendMessageToDriver(ride),
                  icon: const Icon(Icons.message, size: 18),
                  label: const Text('Message'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}