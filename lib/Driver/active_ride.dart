import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'backend/homebackend.dart';

class DriverActiveRidePage extends StatefulWidget {
  final String? rideRequestId;

  const DriverActiveRidePage({Key? key, this.rideRequestId}) : super(key: key);

  @override
  State<DriverActiveRidePage> createState() => _DriverActiveRidePageState();
}

class _DriverActiveRidePageState extends State<DriverActiveRidePage> {
  final supabase = Supabase.instance.client;
  late DriverService _driverService;

  Map<String, dynamic>? _activeRide;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isProcessing = false;

  // Ride status tracking
  bool _isRideStarted = false;
  bool _isRideCompleted = false;

  @override
  void initState() {
    super.initState();
    _driverService = DriverService(supabase);
    _loadActiveRide();
  }

  Future<void> _loadActiveRide() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      Map<String, dynamic>? ride;

      // If a specific ride ID was provided, load that ride
      if (widget.rideRequestId != null) {
        final requests = await supabase
            .from('ride_requests')
            .select('*, users!ride_requests_user_id_fkey(full_name, phone, profile_url)')
            .eq('id', widget.rideRequestId!)
            .limit(1);

        if (requests.isNotEmpty) {
          ride = requests.first;
        }
      } else {
        // Otherwise, load the driver's active ride
        ride = await _driverService.getActiveRide();
      }

      if (ride != null) {
        _isRideStarted = ride['status'] == 'in_progress';
        _isRideCompleted = ride['status'] == 'completed';
      }

      setState(() {
        _activeRide = ride;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load active ride: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _startRide() async {
    if (_activeRide == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      final success = await _driverService.startRide(_activeRide!['id']);

      if (success) {
        setState(() {
          _isRideStarted = true;
          _activeRide!['status'] = 'in_progress';
          _activeRide!['started_at'] = DateTime.now().toIso8601String();
        });
        _showSuccessSnackBar('Ride started successfully');
      } else {
        _showErrorSnackBar('Failed to start ride');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _completeRide() async {
    if (_activeRide == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      final success = await _driverService.completeRide(_activeRide!['id']);

      if (success) {
        setState(() {
          _isRideCompleted = true;
          _activeRide!['status'] = 'completed';
          _activeRide!['completed_at'] = DateTime.now().toIso8601String();
        });
        _showSuccessSnackBar('Ride completed successfully');
      } else {
        _showErrorSnackBar('Failed to complete ride');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _navigateToUser() async {
    if (_activeRide == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      final pickupLat = _activeRide!['pickup_latitude'] as double;
      final pickupLng = _activeRide!['pickup_longitude'] as double;

      final success = await _driverService.navigateToUser(pickupLat, pickupLng);

      if (!success) {
        _showErrorSnackBar('Failed to open navigation');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _navigateToDestination() async {
    if (_activeRide == null) return;

    try {
      setState(() {
        _isProcessing = true;
      });

      final destLat = _activeRide!['destination_latitude'] as double;
      final destLng = _activeRide!['destination_longitude'] as double;

      final success = await _driverService.navigateToUser(destLat, destLng);

      if (!success) {
        _showErrorSnackBar('Failed to open navigation');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Ride'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActiveRide,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadActiveRide,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_activeRide == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.directions_car_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No active ride found',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Go Back'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildRideStatusCard(),
          const SizedBox(height: 16),
          _buildRiderInfoCard(),
          const SizedBox(height: 16),
          _buildLocationCard(),
          const SizedBox(height: 16),
          _buildRideDetailsCard(),
          const SizedBox(height: 24),
          _buildActionButtons(),
        ],
      ),
    );
  }

  Widget _buildRideStatusCard() {
    final status = _activeRide!['status'] ?? 'unknown';
    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'accepted':
        statusText = 'Ride Accepted';
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle;
        break;
      case 'in_progress':
        statusText = 'Ride In Progress';
        statusColor = Colors.orange;
        statusIcon = Icons.directions_car;
        break;
      case 'completed':
        statusText = 'Ride Completed';
        statusColor = Colors.green;
        statusIcon = Icons.done_all;
        break;
      default:
        statusText = 'Unknown Status';
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [statusColor.withOpacity(0.7), statusColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(statusIcon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              statusText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRiderInfoCard() {
    final user = _activeRide!['users'] as Map<String, dynamic>;
    final userName = user['full_name'] ?? 'Unknown User';
    final userPhone = user['phone'] ?? 'No phone';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.blue.shade100,
              backgroundImage: user['profile_url'] != null 
                  ? NetworkImage(user['profile_url']) 
                  : null,
              child: user['profile_url'] == null 
                  ? Text(
                      userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                      style: const TextStyle(color: Colors.blue, fontSize: 20),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.blue, size: 26),
                  onPressed: () {
                    final riderUserId = _activeRide!['user_id'] as String?;
                    if (riderUserId != null) {
                      Navigator.of(context).pushNamed(
                        '/chat',
                        arguments: {
                          'otherUserId': riderUserId,
                          'otherUserName': userName,
                          'rideRequestId': _activeRide!['id'],
                        },
                      );
                    }
                  },
                  tooltip: 'Message Rider',
                ),

              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationCard() {
    final pickupAddress = _activeRide!['pickup_address'] ?? 'Unknown pickup';
    final destinationAddress = _activeRide!['destination_address'] ?? 'Unknown destination';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ride Route',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildLocationInfo(
              'Pickup',
              pickupAddress,
              Icons.location_on_outlined,
              Colors.green,
              _navigateToUser,
            ),
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: SizedBox(
                height: 30,
                child: VerticalDivider(
                  color: Colors.grey,
                  thickness: 1,
                  width: 20,
                ),
              ),
            ),
            _buildLocationInfo(
              'Destination',
              destinationAddress,
              Icons.location_on,
              Colors.red,
              _navigateToDestination,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRideDetailsCard() {
    final createdAt = DateTime.parse(_activeRide!['created_at']);
    final formattedDate = DateFormat('MMM d, yyyy').format(createdAt);
    final formattedTime = DateFormat('h:mm a').format(createdAt);

    final estimatedDistance = _activeRide!['estimated_distance'] ?? 'Unknown distance';
    final estimatedTime = _activeRide!['estimated_time'] ?? 'Unknown time';
    final estimatedFare = _activeRide!['estimated_fare'] ?? 'N/A';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ride Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem('Date', formattedDate, Icons.calendar_today),
                _buildDetailItem('Time', formattedTime, Icons.access_time),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildDetailItem('Distance', estimatedDistance, Icons.straighten),
                _buildDetailItem('Duration', estimatedTime, Icons.timelapse),
                _buildDetailItem('Fare', estimatedFare, Icons.attach_money),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_isRideCompleted) {
      return ElevatedButton(
        onPressed: () {
          Navigator.pop(context);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text('BACK TO HOME', style: TextStyle(fontSize: 16)),
      );
    }

    if (_isRideStarted) {
      return ElevatedButton(
        onPressed: _isProcessing ? null : _completeRide,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: _isProcessing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 2,
                ),
              )
            : const Text('COMPLETE RIDE', style: TextStyle(fontSize: 16)),
      );
    }

    return ElevatedButton(
      onPressed: _isProcessing ? null : _startRide,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: _isProcessing
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            )
          : const Text('START RIDE', style: TextStyle(fontSize: 16)),
    );
  }

  Widget _buildLocationInfo(
    String title,
    String address,
    IconData icon,
    Color color,
    VoidCallback onNavigate,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.navigation, color: Colors.blue),
          onPressed: onNavigate,
          tooltip: 'Navigate',
        ),
      ],
    );
  }

  Widget _buildDetailItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(
          title,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
