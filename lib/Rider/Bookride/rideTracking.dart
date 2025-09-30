import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/AuthManager.dart';
import 'package:kabanza/routes.dart';

class RideTrackingPage extends StatefulWidget {
  final String rideRequestId;
  final LatLng pickup;
  final LatLng destination;

  const RideTrackingPage({
    Key? key,
    required this.rideRequestId,
    required this.pickup,
    required this.destination,
  }) : super(key: key);

  @override
  _RideTrackingPageState createState() => _RideTrackingPageState();
}

class _RideTrackingPageState extends State<RideTrackingPage> {
  final supabase = Supabase.instance.client;
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  String _status = 'pending';
  LatLng? _driverLocation;
  bool _isOwner = false;
  bool _isLoading = true;
  String? _driverId;
  RealtimeChannel? _locationChannel;

  @override
  void initState() {
    super.initState();
    _verifyOwnership();
  }

  @override
  void dispose() {
    if (_locationChannel != null) {
      supabase.removeChannel(_locationChannel!);
    }
    super.dispose();
  }

  Future<void> _verifyOwnership() async {
    if (!AppAuthManager.isUserDataAvailable()) {
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.login,
            (route) => false,
      );
      return;
    }

    try {
      final response = await supabase
          .from('ride_requests')
          .select('user_id, status, driver_id')
          .eq('id', widget.rideRequestId)
          .single();

      _isOwner = response['user_id'] == AppAuthManager.getCurrentUserId();
      _status = response['status'] ?? 'pending';
      _driverId = response['driver_id'];

      if (_isOwner) {
        _initTracking();
      } else {
        Navigator.pop(context);
      }
    } catch (e) {
      Navigator.pop(context);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _initTracking() {
    _addMarkers();
    _addPolyline();
    _subscribeToRideUpdates();
    if (_driverId != null) {
      _fetchInitialDriverLocation(_driverId!);
      _subscribeToLocationUpdates(_driverId!);
    }
  }

  void _addMarkers() {
    setState(() {
      _markers.addAll({
        Marker(
          markerId: const MarkerId('pickup'),
          position: widget.pickup,
          infoWindow: const InfoWindow(title: 'Pickup Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: widget.destination,
          infoWindow: const InfoWindow(title: 'Destination'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      });
    });
  }

  void _addPolyline() {
    setState(() {
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('route'),
          points: [widget.pickup, widget.destination],
          color: Colors.blue,
          width: 5,
        ),
      );
    });
  }

  void _subscribeToRideUpdates() {
    supabase.channel('ride_${widget.rideRequestId}').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'ride_requests',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'id',
        value: widget.rideRequestId,
      ),
      callback: (payload) {
        final newStatus = payload.newRecord?['status'];
        if (newStatus != null) {
          setState(() => _status = newStatus);
        }

        final newDriverId = payload.newRecord?['driver_id'];
        if (newDriverId != null && newDriverId != _driverId) {
          setState(() => _driverId = newDriverId);
          if (_locationChannel != null) {
            supabase.removeChannel(_locationChannel!);
          }
          _fetchInitialDriverLocation(newDriverId);
          _subscribeToLocationUpdates(newDriverId);
        }
      },
    ).subscribe();
  }

  Future<void> _fetchInitialDriverLocation(String driverId) async {
    try {
      final response = await supabase
          .from('user_locations')
          .select('latitude, longitude')
          .eq('user_id', driverId)
          .single();

      final driverLat = response['latitude'] as double?;
      final driverLng = response['longitude'] as double?;
      if (driverLat != null && driverLng != null) {
        _updateDriverLocation(LatLng(driverLat, driverLng));
      }
    } catch (e) {
      // Handle error, e.g., show snackbar if needed
    }
  }

  void _subscribeToLocationUpdates(String driverId) {
    _locationChannel = supabase.channel('location_$driverId').onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'user_locations',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: driverId,
      ),
      callback: (payload) {
        final driverLat = payload.newRecord?['latitude'] as double?;
        final driverLng = payload.newRecord?['longitude'] as double?;
        if (driverLat != null && driverLng != null) {
          _updateDriverLocation(LatLng(driverLat, driverLng));
        }
      },
    ).subscribe();
  }

  void _updateDriverLocation(LatLng location) {
    setState(() {
      _driverLocation = location;
      _markers.removeWhere((m) => m.markerId.value == 'driver');
      _markers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: location,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'Your Driver'),
        ),
      );
    });

    if (_mapController != null) {
      final double minLat = min(widget.pickup.latitude, min(widget.destination.latitude, location.latitude));
      final double maxLat = max(widget.pickup.latitude, max(widget.destination.latitude, location.latitude));
      final double minLng = min(widget.pickup.longitude, min(widget.destination.longitude, location.longitude));
      final double maxLng = max(widget.pickup.longitude, max(widget.destination.longitude, location.longitude));

      final LatLngBounds bounds = LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      );

      _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    }
  }

  Future<void> _cancelRide() async {
    try {
      await supabase.from('ride_requests').update({
        'status': 'cancelled',
        'cancelled_by': AppAuthManager.getCurrentUserId(),
        'cancelled_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.rideRequestId);

      Navigator.pop(context);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancellation failed: $e')),
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

    if (!_isOwner) {
      return const Scaffold(
        body: Center(child: Text('You do not have access to this ride.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Ride'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => AppAuthManager.onLogout(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: (controller) {
              _mapController = controller;
              _mapController?.animateCamera(
                CameraUpdate.newLatLngBounds(
                  LatLngBounds(
                    southwest: LatLng(
                      min(widget.pickup.latitude, widget.destination.latitude),
                      min(widget.pickup.longitude, widget.destination.longitude),
                    ),
                    northeast: LatLng(
                      max(widget.pickup.latitude, widget.destination.latitude),
                      max(widget.pickup.longitude, widget.destination.longitude),
                    ),
                  ),
                  50,
                ),
              );
            },
            initialCameraPosition: CameraPosition(
              target: widget.pickup,
              zoom: 14,
            ),
            markers: _markers,
            polylines: _polylines,
          ),
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Status: ${_status.toUpperCase()}'),
                    if (_driverLocation != null)
                      Text('Driver is ${_calculateDistance(widget.pickup, _driverLocation!).toStringAsFixed(1)} km away'),
                    if (_status == 'pending' || _status == 'accepted')
                      ElevatedButton(
                        onPressed: _cancelRide,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        child: const Text('Cancel Ride'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371; // km
    final double dLat = _degreesToRadians(end.latitude - start.latitude);
    final double dLng = _degreesToRadians(end.longitude - start.longitude);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(start.latitude)) * cos(_degreesToRadians(end.latitude)) *
            sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}