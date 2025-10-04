import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:kabanza/routes.dart';
import 'BottomNavBar.dart';
import 'homewidget.dart';
import 'backend/homebackend.dart';

class DriverHomePage extends StatefulWidget {
  const DriverHomePage({Key? key}) : super(key: key);

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  final supabase = Supabase.instance.client;
  late DriverService _driverService;

  // UI State
  Map<String, dynamic>? userProfile;
  Map<String, dynamic>? driverProfile;
  bool _isLoading = true;
  bool _isOnline = false;
  String _driverStatus = 'Offline';
  bool _isLocationLoading = false;

  // Ride data
  List<Map<String, dynamic>> _pendingRideRequests = [];
  List<Map<String, dynamic>> _recentTrips = [];
  Map<String, dynamic>? _activeRide;
  bool _isLoadingRideData = false;

  @override
  void initState() {
    super.initState();
    _initializeDriverService();
  }

  void _initializeDriverService() {
    _driverService = DriverService(supabase);

    // Set up callbacks
    _driverService.onStatusChanged = (isOnline, status) {
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
          _driverStatus = status;
        });
      }
    };

    _driverService.onMessage = (message, {bool isError = false}) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: isError ? Colors.red : (
                message.contains('online') || message.contains('updated') || message.contains('restored')
                    ? Colors.green
                    : Colors.grey
            ),
          ),
        );
      }
    };

    _driverService.onLoadingChanged = (isLoading) {
      if (mounted) {
        setState(() {
          _isLocationLoading = isLoading;
        });
      }
    };

    // Initialize the service and load profiles
    _initializeServices();
  }

  @override
  void dispose() {
    _driverService.cleanup();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    try {
      // Initialize driver service
      await _driverService.initialize();

      // Load profiles
      await _loadProfiles();

      // Load ride data
      await _loadRideData();

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadRideData() async {
    try {
      setState(() {
        _isLoadingRideData = true;
      });

      // Load data in parallel
      final pendingRequestsFuture = _driverService.getPendingRideRequests();
      final recentTripsFuture = _driverService.getDriverTripHistory(limit: 3);
      final activeRideFuture = _driverService.getActiveRide();

      final results = await Future.wait([
        pendingRequestsFuture,
        recentTripsFuture,
        activeRideFuture,
      ]);

      if (mounted) {
        setState(() {
          _pendingRideRequests = results[0] as List<Map<String, dynamic>>;
          _recentTrips = results[1] as List<Map<String, dynamic>>;
          _activeRide = results[2] as Map<String, dynamic>?;
          _isLoadingRideData = false;
        });
      }
    } catch (e) {
      print('Error loading ride data: $e');
      if (mounted) {
        setState(() {
          _isLoadingRideData = false;
        });
      }
    }
  }

  Future<void> _loadProfiles() async {
    try {
      // Load user and driver profiles
      final userProfileFuture = _driverService.loadUserProfile();
      final driverProfileFuture = _driverService.loadDriverProfile();

      final results = await Future.wait([userProfileFuture, driverProfileFuture]);

      final userProfileData = results[0] as Map<String, dynamic>?;
      final driverProfileData = results[1] as Map<String, dynamic>?;

      if (mounted) {
        setState(() {
          userProfile = userProfileData;
          driverProfile = driverProfileData;
          // Set initial status based on database
          _isOnline = driverProfileData?['driver_status'] == 'online';
          _driverStatus = _getStatusDisplay(driverProfileData?['driver_status'] ?? 'offline');
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getStatusDisplay(String status) {
    switch (status) {
      case 'online':
        return 'Online';
      case 'offline':
        return 'Offline';
      case 'on_trip':
        return 'On Trip';
      case 'busy':
        return 'Busy';
      case 'break':
        return 'On Break';
      default:
        return 'Offline';
    }
  }

  Future<void> _toggleOnlineStatus() async {
    final newStatus = await _driverService.toggleOnlineStatus(_isOnline);
    // Status update is handled by the callback, no need to setState here
  }

  Future<void> _forceLocationUpdate() async {
    await _driverService.forceLocationUpdate();
  }

  Future<void> _signOut() async {
    try {
      await _driverService.signOut();

      // Navigate to login screen
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (error) {
      // Error message is already shown by the service
    }
  }

  void _viewEarnings() {
    Navigator.pushNamed(context, '/driver-earnings');
  }

  void _viewTrips() {
    Navigator.pushNamed(context, '/driver-trips');
  }

  void _viewRideRequests() {
    Navigator.pushNamed(context, '/driver-ride-requests');
  }

  void _viewActiveRide() {
    Navigator.pushNamed(
      context, 
      '/driver-active-ride',
      arguments: _activeRide != null ? {'rideRequestId': _activeRide!['id']} : null,
    );
  }

  void _viewProfile() {
    Navigator.pushNamed(context, '/profile');
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'profile':
        _viewProfile();
        break;
      case 'vehicle':
        Navigator.pushNamed(context, '/vehicle-info');
        break;
      case 'settings':
        Navigator.pushNamed(context, AppRoutes.settings);
        break;
      case 'logout':
        _signOut();
        break;
    }
  }

  void _handleBottomNavTap(int index) {
    switch (index) {
      case 0:
        // Home tab
        // Already on home, do nothing or maybe refresh
        break;
      case 1:
        // Messages tab
        Navigator.pushNamed(context, AppRoutes.messages);
        break;
      case 2:
        // Trips tab
        _viewTrips();
        break;
      case 3:
        // Profile tab
        _viewProfile();
        break;
    }
  }

  Widget _buildConnectionStatusIndicator() {
    if (!_driverService.hasInternetConnection) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: Colors.red.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off, color: Colors.red.shade700, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'No internet connection. You will be set offline after 1 minute.',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading your driver dashboard...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: DriverHomeWidgets.buildDriverAppBar(
        userProfile: userProfile,
        isOnline: _isOnline,
        isLocationLoading: _isLocationLoading,
        isLocationRunning: _driverService.isLocationRunning,
        driverStatus: _driverStatus,
        onForceLocationUpdate: _forceLocationUpdate,
        onMenuSelected: _handleMenuSelection,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadRideData,
        backgroundColor: Colors.blue,
        child: _isLoadingRideData 
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              )
            : const Icon(Icons.refresh),
        tooltip: 'Refresh ride data',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection status indicator
            _buildConnectionStatusIndicator(),

            // Online/Offline Toggle
            DriverHomeWidgets.buildOnlineStatusToggle(
              isOnline: _isOnline,
              isLocationLoading: _isLocationLoading,
              onToggle: _toggleOnlineStatus,
            ),

            const SizedBox(height: 20),

            // Hotspot Card
            InkWell(
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.HotspotScreen);
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.local_fire_department,
                        color: Colors.orange,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Hotspot',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'View high demand areas',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: Colors.grey,
                      size: 24,
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Recent Trips
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Recent Trips',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      TextButton(
                        onPressed: _viewTrips,
                        child: const Text('View All'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _isLoadingRideData
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : _recentTrips.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'No trips found in your history',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          : Column(
                              children: _recentTrips.map((trip) {
                                final user = trip['users'] as Map<String, dynamic>;
                                final userName = user['full_name'] ?? 'Unknown User';
                                final pickupAddress = trip['pickup_address'] ?? 'Unknown pickup';
                                final destinationAddress = trip['destination_address'] ?? 'Unknown destination';
                                final route = '$pickupAddress to $destinationAddress';

                                final createdAt = DateTime.parse(trip['created_at']);
                                String timeString = DateFormat('h:mm a').format(createdAt);

                                if (trip['completed_at'] != null) {
                                  final completedAt = DateTime.parse(trip['completed_at']);
                                  timeString += ' - ${DateFormat('h:mm a').format(completedAt)}';
                                }

                                return Column(
                                  children: [
                                    DriverHomeWidgets.buildRecentTripItem(
                                      route,
                                      timeString,
                                      '★★★★★',
                                      Colors.green,
                                    ),
                                    if (_recentTrips.indexOf(trip) < _recentTrips.length - 1)
                                      const Divider(height: 24),
                                  ],
                                );
                              }).toList(),
                            ),
                ],
              ),
            ),

            // Pending Ride Requests
            if (_pendingRideRequests.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Ride Requests',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                '${_pendingRideRequests.length}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: _viewRideRequests,
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _viewRideRequests,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'VIEW ${_pendingRideRequests.length} PENDING REQUESTS',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Active Ride
            if (_activeRide != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Active Ride',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _activeRide!['status']?.toUpperCase() ?? 'ACTIVE',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _viewActiveRide,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'VIEW ACTIVE RIDE',
                        style: TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: DriverBottomNavigation(
        currentIndex: 0,
        onTap: _handleBottomNavTap,
      ),
    );
  }
}
