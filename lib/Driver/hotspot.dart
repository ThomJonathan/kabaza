import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'backend/homebackend.dart';

class HotspotScreen extends StatefulWidget {
  const HotspotScreen({Key? key}) : super(key: key);

  @override
  State<HotspotScreen> createState() => _HotspotScreenState();
}

class _HotspotScreenState extends State<HotspotScreen> {
  final supabase = Supabase.instance.client;
  late DriverService _driverService;
  GoogleMapController? _mapController;
  Timer? _refreshTimer;

  // UI State
  bool _isLoading = true;
  String _errorMessage = '';

  // Map data
  final Map<String, HeatmapPoint> _heatmapPoints = {};
  final Set<Circle> _circles = {};
  HeatmapPoint? _highestDemandArea;

  // Default map position (will be updated based on driver's location)
  CameraPosition _initialCameraPosition = const CameraPosition(
    target: LatLng(0, 0),
    zoom: 14,
  );

  @override
  void initState() {
    super.initState();
    _driverService = DriverService(supabase);
    _initializeMap();

    // Auto-refresh every 30 seconds for real-time data
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) _loadHotspotData();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<String> _getAddressFromCoordinates(double latitude, double longitude) async {
    try {
      // This is a placeholder - you would typically use a geocoding service
      // For now, returning formatted coordinates
      return 'Lat: ${latitude.toStringAsFixed(4)}, Lng: ${longitude.toStringAsFixed(4)}';
    } catch (e) {
      return 'Location coordinates: ${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}';
    }
  }

  Future<void> _navigateToHighestDemandArea() async {
    if (_highestDemandArea == null) return;

    final success = await _driverService.navigateToUser(
      _highestDemandArea!.position.latitude,
      _highestDemandArea!.position.longitude,
    );

    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open navigation app'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _focusOnHighestDemandArea() {
    if (_highestDemandArea == null || _mapController == null) return;

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: _highestDemandArea!.position,
          zoom: 16,
        ),
      ),
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Focused on highest demand area (${_highestDemandArea!.count} users)',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _initializeMap() async {
    try {
      // Get driver's current location
      final driverLocation = await _driverService.getCurrentLocation();
      if (driverLocation != null) {
        setState(() {
          _initialCameraPosition = CameraPosition(
            target: LatLng(driverLocation.latitude, driverLocation.longitude),
            zoom: 14,
          );
        });
      }

      // Load hotspot data
      await _loadHotspotData();
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to initialize map: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHotspotData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      // Get hotspot data from the driver service (no time parameter needed)
      final hotspotData = await _driverService.getHotspotData();

      // Clear existing data
      _heatmapPoints.clear();
      _circles.clear();

      // Check if we have any data
      if (hotspotData.isEmpty) {
        setState(() {
          _errorMessage = 'No riders currently online in your area';
          _isLoading = false;
        });
        return;
      }

      // Process hotspot data
      for (final point in hotspotData) {
        final lat = point['latitude'] as double;
        final lng = point['longitude'] as double;
        final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

        if (_heatmapPoints.containsKey(key)) {
          _heatmapPoints[key]!.count++;
        } else {
          _heatmapPoints[key] = HeatmapPoint(
            position: LatLng(lat, lng),
            count: 1,
          );
        }
      }

      // Find the highest demand area
      _highestDemandArea = null;
      if (_heatmapPoints.isNotEmpty) {
        _highestDemandArea = _heatmapPoints.values
            .reduce((current, next) => current.count > next.count ? current : next);
      }

      // Create circles for heatmap visualization
      for (final point in _heatmapPoints.values) {
        final radius = 100.0 + (point.count * 20.0);
        final opacity = 0.3 + (point.count * 0.05 > 0.7 ? 0.7 : point.count * 0.05);

        _circles.add(
          Circle(
            circleId: CircleId('circle_${point.position.latitude}_${point.position.longitude}'),
            center: point.position,
            radius: radius,
            fillColor: Colors.red.withOpacity(opacity),
            strokeWidth: 0,
          ),
        );
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load hotspot data: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hotspot Map'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHotspotData,
            tooltip: 'Refresh hotspot data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadHotspotData,
              child: const Text('Try Again'),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Highest Demand Area Info
          if (_highestDemandArea != null) ...[
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.local_fire_department,
                          color: Colors.orange,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Highest Demand Area',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FutureBuilder<String>(
                    future: _getAddressFromCoordinates(
                      _highestDemandArea!.position.latitude,
                      _highestDemandArea!.position.longitude,
                    ),
                    builder: (context, snapshot) {
                      return Text(
                        'Location: ${snapshot.data ?? 'Loading address...'}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Demand Level: ${_highestDemandArea!.count} online rider${_highestDemandArea!.count > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _navigateToHighestDemandArea(),
                          icon: const Icon(Icons.navigation, size: 18),
                          label: const Text('Navigate Here'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () => _focusOnHighestDemandArea(),
                        icon: const Icon(Icons.center_focus_strong, size: 18),
                        label: const Text('Focus'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: GoogleMap(
              initialCameraPosition: _initialCameraPosition,
              circles: _circles,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (GoogleMapController controller) {
                _mapController = controller;
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Hotspot Legend',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'Live Data',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('Low demand'),
                    const SizedBox(width: 16),
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('High demand'),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Showing currently online riders',
                  style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Last updated: ${DateFormat('MMM d, h:mm a').format(DateTime.now())}',
                  style: const TextStyle(
                    fontStyle: FontStyle.italic,
                    color: Colors.grey,
                    fontSize: 12,
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

class HeatmapPoint {
  final LatLng position;
  int count;

  HeatmapPoint({
    required this.position,
    this.count = 1,
  });
}