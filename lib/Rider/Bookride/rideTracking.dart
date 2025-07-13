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

  @override
  void initState() {
    super.initState();
    _verifyOwnership();
    _initTracking();
  }

  Future<void> _verifyOwnership() async {
    if (!AppAuthManager.isUserDataAvailable()) {
      Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.login,
              (route) => false
      );
      return;
    }

    try {
      final response = await supabase
          .from('ride_requests')
          .select('user_id')
          .eq('id', widget.rideRequestId)
          .single();

      setState(() {
        _isOwner = response['user_id'] == AppAuthManager.getCurrentUserId();
      });

      if (!_isOwner) {
        Navigator.pop(context);
      }
    } catch (e) {
      Navigator.pop(context);
    }
  }

  void _initTracking() {
    _addMarkers();
    _subscribeToUpdates();
  }

  void _addMarkers() {
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
  }

  void _subscribeToUpdates() {
    supabase.channel('ride_${widget.rideRequestId}')
        .onPostgresChanges(
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

        final driverLat = payload.newRecord?['driver_latitude'];
        final driverLng = payload.newRecord?['driver_longitude'];
        if (driverLat != null && driverLng != null) {
          _updateDriverLocation(LatLng(driverLat, driverLng));
        }
      },
    )
        .subscribe();
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

  double _calculateDistance(LatLng a, LatLng b) {
    return ((a.latitude - b.latitude).abs() + (a.longitude - b.longitude).abs()) * 111;
  }
}