import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:kabanza/AuthManager.dart';
import 'package:kabanza/routes.dart';
import 'Route.dart';
import 'bookridebackedService.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BookRidePage extends StatefulWidget {
  final String? apiKey;
  const BookRidePage({Key? key, this.apiKey}) : super(key: key);

  @override
  _BookRidePageState createState() => _BookRidePageState();
}

class _BookRidePageState extends State<BookRidePage> {
  final TextEditingController _destinationController = TextEditingController();
  final SupabaseClient supabase = Supabase.instance.client;
  late final RideService _rideService;

  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  LatLng? _destination;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _loading = false;
  bool _checkingDrivers = false;
  List<Map<String, dynamic>> _nearbyDrivers = [];

  @override
  void initState() {
    super.initState();
    _rideService = RideService(supabase);
    _verifyAuth();
    _getCurrentLocation();
  }

  void _verifyAuth() {
    if (!AppAuthManager.isUserDataAvailable()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
              (route) => false,
        );
      });
    }
  }

  void _navigateToProfile() {
    Navigator.pushNamed(context, '/profile');
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loading = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _markers.add(Marker(
          markerId: const MarkerId('current'),
          position: _currentLocation!,
          infoWindow: InfoWindow(title: AppAuthManager.getUserName() ?? 'You'),
        ));
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentLocation!, 14));

      // Check for nearby drivers after getting location
      await _checkNearbyDrivers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Location error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _checkNearbyDrivers() async {
    if (_currentLocation == null) return;

    setState(() => _checkingDrivers = true);
    try {
      final drivers = await _rideService.getNearbyDrivers(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
      );

      setState(() {
        _nearbyDrivers = drivers;
        _addDriverMarkers();
      });
    } catch (e) {
      print('Error checking nearby drivers: $e');
    } finally {
      setState(() => _checkingDrivers = false);
    }
  }

  void _addDriverMarkers() {
    // Remove existing driver markers
    _markers.removeWhere((marker) => marker.markerId.value.startsWith('driver_'));

    // Add new driver markers
    for (int i = 0; i < _nearbyDrivers.length; i++) {
      final driver = _nearbyDrivers[i];
      _markers.add(Marker(
        markerId: MarkerId('driver_$i'),
        position: LatLng(driver['latitude'], driver['longitude']),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title: '${driver['full_name']} (Driver)',
          snippet: '${driver['distance_km'].toStringAsFixed(1)} km away',
        ),
      ));
    }
  }

  Future<void> _searchDestination() async {
    if (_destinationController.text.isEmpty) return;

    setState(() => _loading = true);
    try {
      final locations = await locationFromAddress(_destinationController.text);
      if (locations.isNotEmpty) {
        setState(() {
          _destination = LatLng(locations.first.latitude, locations.first.longitude);
          _markers.removeWhere((marker) => marker.markerId.value == 'destination');
          _markers.add(Marker(
            markerId: const MarkerId('destination'),
            position: _destination!,
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            infoWindow: const InfoWindow(title: 'Destination'),
          ));
        });
        _calculateRoute();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _calculateRoute() async {
    if (_currentLocation == null || _destination == null) return;

    setState(() => _loading = true);
    try {
      final route = await RouteService(apiKey: widget.apiKey ?? '')
          .getRoute(origin: _currentLocation!, destination: _destination!);

      if (route != null) {
        setState(() {
          _polylines = {route.toPolyline()};
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngBounds(route.bounds, 50));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Route error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _bookRide() async {
    if (_destination == null || !AppAuthManager.isUserDataAvailable()) return;

    // Check if drivers are available
    if (_nearbyDrivers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No drivers available in your area')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await _rideService.createRideRequest(
        pickupLat: _currentLocation!.latitude,
        pickupLng: _currentLocation!.longitude,
        destLat: _destination!.latitude,
        destLng: _destination!.longitude,
      );

      if (response != null) {
        Navigator.pushNamed(context, AppRoutes.rideTracking, arguments: {
          'rideRequestId': response['id'],
          'pickup': _currentLocation!,
          'destination': _destination!,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create ride request')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Booking error: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Book Ride'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _navigateToProfile,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destinationController,
                        decoration: InputDecoration(
                          hintText: 'Enter destination',
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _searchDestination,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Driver availability indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _nearbyDrivers.isEmpty ? Colors.orange[100] : Colors.green[100],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _nearbyDrivers.isEmpty ? Colors.orange : Colors.green,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _nearbyDrivers.isEmpty ? Icons.warning_amber : Icons.check_circle,
                        color: _nearbyDrivers.isEmpty ? Colors.orange : Colors.green,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _checkingDrivers
                            ? 'Checking drivers...'
                            : _nearbyDrivers.isEmpty
                            ? 'No drivers nearby'
                            : '${_nearbyDrivers.length} driver(s) nearby',
                        style: TextStyle(
                          color: _nearbyDrivers.isEmpty ? Colors.orange[800] : Colors.green[800],
                          fontSize: 12,
                        ),
                      ),
                      if (_checkingDrivers) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _currentLocation == null
                ? const Center(child: CircularProgressIndicator())
                : GoogleMap(
              onMapCreated: (controller) => _mapController = controller,
              initialCameraPosition: CameraPosition(
                target: _currentLocation!,
                zoom: 14,
              ),
              markers: _markers,
              polylines: _polylines,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_nearbyDrivers.isNotEmpty && _destination != null) ...[
                  Text(
                    'Closest driver: ${_nearbyDrivers.first['distance_km'].toStringAsFixed(1)} km away',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _destination != null && _nearbyDrivers.isNotEmpty && !_loading
                        ? _bookRide
                        : null,
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text('Book Ride'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}