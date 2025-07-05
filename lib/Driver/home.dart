import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
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
        Navigator.pushNamed(context, '/settings');
        break;
      case 'logout':
        _signOut();
        break;
    }
  }

  void _handleBottomNavTap(int index) {
    switch (index) {
      case 1:
        _viewEarnings();
        break;
      case 2:
        _viewTrips();
        break;
      case 3:
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

            // Today's Stats
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
                  const Text(
                    'Today\'s Performance',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: DriverHomeWidgets.buildTodayStatCard(
                          'Trips',
                          driverProfile?['total_trips']?.toString() ?? '0',
                          Icons.route_outlined,
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DriverHomeWidgets.buildTodayStatCard(
                          'Online Hours',
                          '6h 30m', // You might want to calculate this
                          Icons.access_time_outlined,
                          Colors.orange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DriverHomeWidgets.buildTodayStatCard(
                          'Rating',
                          '${driverProfile?['average_rating']?.toString() ?? '0.0'}★',
                          Icons.star_outline,
                          Colors.amber,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DriverHomeWidgets.buildTodayStatCard(
                          'Reviews',
                          driverProfile?['total_reviews']?.toString() ?? '0',
                          Icons.rate_review_outlined,
                          Colors.purple,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  DriverHomeWidgets.buildRecentTripItem(
                    'Downtown to Airport',
                    '2:30 PM - 3:15 PM',
                    '4.9★',
                    Colors.green,
                  ),
                  const Divider(height: 24),
                  DriverHomeWidgets.buildRecentTripItem(
                    'Mall to Residential Area',
                    '1:45 PM - 2:10 PM',
                    '5.0★',
                    Colors.green,
                  ),
                  const Divider(height: 24),
                  DriverHomeWidgets.buildRecentTripItem(
                    'Office Complex to Hotel',
                    '12:20 PM - 12:50 PM',
                    '4.8★',
                    Colors.green,
                  ),
                ],
              ),
            ),
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