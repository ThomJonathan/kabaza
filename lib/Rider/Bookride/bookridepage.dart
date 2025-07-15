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
  Map<String, dynamic>? _selectedDriver;
  String _destinationAddress = '';
  String _pickupAddress = '';

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
      final currentLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentLocation = currentLatLng;
        _updateCurrentLocationMarker();
      });

      // Get pickup address
      await _getPickupAddress(currentLatLng);

      _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(currentLatLng, 14)
      );

      // Check for nearby drivers after getting location
      await _checkNearbyDrivers();
    } catch (e) {
      _showSnackBar('Location error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _getPickupAddress(LatLng location) async {
    try {
      final placemarks = await placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _pickupAddress = '${place.street}, ${place.locality}, ${place.country}';
        });
      }
    } catch (e) {
      print('Error getting pickup address: $e');
      setState(() {
        _pickupAddress = 'Current Location';
      });
    }
  }

  void _updateCurrentLocationMarker() {
    if (_currentLocation == null) return;

    _markers.removeWhere((marker) => marker.markerId.value == 'current');
    _markers.add(Marker(
      markerId: const MarkerId('current'),
      position: _currentLocation!,
      infoWindow: InfoWindow(
          title: AppAuthManager.getUserName() ?? 'You',
          snippet: 'Current Location'
      ),
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
    ));
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
        _selectedDriver = null; // Reset selection
      });

      _addDriverMarkers();
    } catch (e) {
      print('Error checking nearby drivers: $e');
      _showSnackBar('Error loading nearby drivers');
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
      final isSelected = _selectedDriver?['id'] == driver['id'];

      _markers.add(Marker(
        markerId: MarkerId('driver_${driver['id']}'),
        position: LatLng(driver['latitude'], driver['longitude']),
        icon: BitmapDescriptor.defaultMarkerWithHue(
            isSelected ? BitmapDescriptor.hueOrange : BitmapDescriptor.hueBlue
        ),
        infoWindow: InfoWindow(
          title: '${driver['full_name']} (Driver)',
          snippet: '${driver['distance_km'].toStringAsFixed(1)} km away - Tap to select',
        ),
        onTap: () => _selectDriver(driver),
      ));
    }
  }

  void _selectDriver(Map<String, dynamic> driver) {
    setState(() {
      _selectedDriver = driver;
    });
    _addDriverMarkers(); // Refresh markers to show selection
    _showSnackBar('Driver ${driver['full_name']} selected');
  }

  Future<void> _searchDestination() async {
    if (_destinationController.text.trim().isEmpty) {
      _showSnackBar('Please enter a destination');
      return;
    }

    setState(() => _loading = true);
    try {
      final locations = await locationFromAddress(_destinationController.text.trim());
      if (locations.isNotEmpty) {
        final destLatLng = LatLng(locations.first.latitude, locations.first.longitude);

        setState(() {
          _destination = destLatLng;
          _destinationAddress = _destinationController.text.trim();
        });

        _updateDestinationMarker();
        await _calculateRoute();
      } else {
        _showSnackBar('Destination not found');
      }
    } catch (e) {
      _showSnackBar('Search error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _updateDestinationMarker() {
    if (_destination == null) return;

    _markers.removeWhere((marker) => marker.markerId.value == 'destination');
    _markers.add(Marker(
      markerId: const MarkerId('destination'),
      position: _destination!,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
          title: 'Destination',
          snippet: _destinationAddress.isNotEmpty ? _destinationAddress : 'Your destination'
      ),
    ));
  }

  Future<void> _calculateRoute() async {
    if (_currentLocation == null || _destination == null) return;

    setState(() => _loading = true);
    try {
      // Check if API key is provided
      if (widget.apiKey == null || widget.apiKey!.isEmpty) {
        print('No Google Maps API key provided');
        _showSnackBar('Route calculation disabled: No API key');
        return;
      }

      final route = await RouteService(apiKey: widget.apiKey!)
          .getRoute(origin: _currentLocation!, destination: _destination!);

      if (route != null) {
        setState(() {
          _polylines = {
            Polyline(
              polylineId: const PolylineId('route'),
              points: route.polylinePoints,
              color: Colors.blue,
              width: 4,
            )
          };
        });

        // Animate camera to show both pickup and destination
        _mapController?.animateCamera(
            CameraUpdate.newLatLngBounds(route.bounds, 100)
        );

        print('Route calculated successfully');
      } else {
        print('Could not calculate route');
        _showSnackBar('Could not calculate route');
      }
    } catch (e) {
      print('Route calculation error: $e');
      _showSnackBar('Route calculation error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _bookRide() async {
    // Validation checks
    if (_destination == null) {
      _showSnackBar('Please select a destination');
      return;
    }

    if (!AppAuthManager.isUserDataAvailable()) {
      _showSnackBar('Please login to book a ride');
      return;
    }

    if (_nearbyDrivers.isEmpty) {
      _showSnackBar('No drivers available in your area. Please try again later.');
      return;
    }

    if (_selectedDriver == null) {
      _showSnackBar('Please select a driver');
      return;
    }

    setState(() => _loading = true);
    try {
      // Get addresses if not already set
      final addresses = await _rideService.getAddressesFromCoordinates(
        _currentLocation!.latitude,
        _currentLocation!.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );

      final response = await _rideService.createRideRequest(
        pickupLat: _currentLocation!.latitude,
        pickupLng: _currentLocation!.longitude,
        destLat: _destination!.latitude,
        destLng: _destination!.longitude,
        driverId: _selectedDriver!['id'], // Pass selected driver ID
        pickupAddress: _pickupAddress.isNotEmpty ? _pickupAddress : addresses['pickup'],
        destinationAddress: _destinationAddress.isNotEmpty ? _destinationAddress : addresses['destination'],
      );

      if (response != null) {
        _showSnackBar('Ride request created successfully!');

        // Navigate to ride tracking page
        Navigator.pushNamed(context, AppRoutes.rideTracking, arguments: {
          'rideRequestId': response['id'],
          'pickup': _currentLocation!,
          'destination': _destination!,
          'driver': _selectedDriver!,
        });
      } else {
        _showSnackBar('Failed to create ride request. Please try again.');
      }
    } catch (e) {
      print('Booking error: $e');
      _showSnackBar('Booking error: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showDriverBottomSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Select a Driver',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (_nearbyDrivers.isEmpty)
              const Text('No drivers available in your area')
            else
              ListView.builder(
                shrinkWrap: true,
                itemCount: _nearbyDrivers.length,
                itemBuilder: (context, index) {
                  final driver = _nearbyDrivers[index];
                  final isSelected = _selectedDriver?['id'] == driver['id'];

                  return Card(
                    color: isSelected ? Colors.blue[50] : null,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Text(driver['full_name'][0]),
                      ),
                      title: Text(driver['full_name']),
                      subtitle: Text(
                          '${driver['distance_km'].toStringAsFixed(1)} km away'
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.message),
                            onPressed: () => _messageDriver(driver),
                          ),
                          IconButton(
                            icon: Icon(
                              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: isSelected ? Colors.blue : null,
                            ),
                            onPressed: () {
                              _selectDriver(driver);
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                      onTap: () {
                        _selectDriver(driver);
                        Navigator.pop(context);
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  void _messageDriver(Map<String, dynamic> driver) {
    // Navigate to chat/message screen
    Navigator.pushNamed(context, '/chat', arguments: {
      'driverId': driver['id'],
      'driverName': driver['full_name'],
    });
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
          // Search and status section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Destination search
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _destinationController,
                        decoration: InputDecoration(
                          hintText: 'Enter destination',
                          prefixIcon: const Icon(Icons.location_on),
                          suffixIcon: IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: _searchDestination,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _searchDestination(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Driver status and selection
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _nearbyDrivers.isEmpty ? Colors.orange[100] : Colors.green[100],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _nearbyDrivers.isEmpty ? Colors.orange : Colors.green,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _nearbyDrivers.isEmpty ? Icons.warning_amber : Icons.check_circle,
                              color: _nearbyDrivers.isEmpty ? Colors.orange : Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _checkingDrivers
                                    ? 'Checking drivers...'
                                    : _nearbyDrivers.isEmpty
                                    ? 'No drivers nearby'
                                    : '${_nearbyDrivers.length} driver(s) available',
                                style: TextStyle(
                                  color: _nearbyDrivers.isEmpty ? Colors.orange[800] : Colors.green[800],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_nearbyDrivers.isNotEmpty)
                      ElevatedButton(
                        onPressed: _showDriverBottomSheet,
                        child: const Text('Select Driver'),
                      ),
                  ],
                ),

                // Selected driver info
                if (_selectedDriver != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person, color: Colors.blue),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Selected: ${_selectedDriver!['full_name']} (${_selectedDriver!['distance_km'].toStringAsFixed(1)} km)',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.message, color: Colors.blue),
                          onPressed: () => _messageDriver(_selectedDriver!),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Map section
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
              onTap: (LatLng position) {
                // Optional: Allow tap-to-set destination
              },
            ),
          ),

          // Book ride button
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _canBookRide() ? _bookRide : null,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: _canBookRide() ? Colors.blue : Colors.grey,
                ),
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                  _getBookButtonText(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _canBookRide() {
    return _destination != null &&
        _selectedDriver != null &&
        _nearbyDrivers.isNotEmpty &&
        !_loading;
  }

  String _getBookButtonText() {
    if (_destination == null) return 'Enter Destination';
    if (_nearbyDrivers.isEmpty) return 'No Drivers Available';
    if (_selectedDriver == null) return 'Select a Driver';
    return 'Book Ride';
  }
}