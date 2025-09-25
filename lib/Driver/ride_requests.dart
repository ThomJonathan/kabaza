import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'backend/homebackend.dart';

class DriverRideRequestsPage extends StatefulWidget {
  const DriverRideRequestsPage({Key? key}) : super(key: key);

  @override
  State<DriverRideRequestsPage> createState() => _DriverRideRequestsPageState();
}

class _DriverRideRequestsPageState extends State<DriverRideRequestsPage> {
  final supabase = Supabase.instance.client;
  late DriverService _driverService;
  
  List<Map<String, dynamic>> _rideRequests = [];
  bool _isLoading = true;
  String _errorMessage = '';
  Map<String, bool> _processingRequests = {};

  @override
  void initState() {
    super.initState();
    _driverService = DriverService(supabase);
    _loadRideRequests();
  }

  Future<void> _loadRideRequests() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      final requests = await _driverService.getPendingRideRequests();
      
      setState(() {
        _rideRequests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load ride requests: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptRideRequest(String requestId) async {
    try {
      setState(() {
        _processingRequests[requestId] = true;
      });

      final success = await _driverService.acceptRideRequest(requestId);
      
      if (success) {
        // Remove the request from the list
        setState(() {
          _rideRequests.removeWhere((request) => request['id'] == requestId);
        });
        
        // Navigate to active ride page or show details
        _showSuccessDialog('Ride request accepted successfully!');
      } else {
        _showErrorSnackBar('Failed to accept ride request');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _processingRequests[requestId] = false;
      });
    }
  }

  Future<void> _denyRideRequest(String requestId) async {
    try {
      setState(() {
        _processingRequests[requestId] = true;
      });

      final success = await _driverService.denyRideRequest(requestId);
      
      if (success) {
        // Remove the request from the list
        setState(() {
          _rideRequests.removeWhere((request) => request['id'] == requestId);
        });
      } else {
        _showErrorSnackBar('Failed to deny ride request');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() {
        _processingRequests[requestId] = false;
      });
    }
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Success'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pop(); // Return to previous screen
            },
            child: const Text('OK'),
          ),
        ],
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
        title: const Text('Ride Requests'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRideRequests,
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
              onPressed: _loadRideRequests,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_rideRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.notifications_off_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            const Text(
              'No pending ride requests',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pull down to refresh',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadRideRequests,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRideRequests,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _rideRequests.length,
        itemBuilder: (context, index) {
          final request = _rideRequests[index];
          return _buildRequestCard(request);
        },
      ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final user = request['users'] as Map<String, dynamic>;
    final userName = user['full_name'] ?? 'Unknown User';
    final userPhone = user['phone'] ?? 'No phone';
    final requestId = request['id'];
    final createdAt = DateTime.parse(request['created_at']);
    final formattedTime = DateFormat('h:mm a').format(createdAt);
    
    final pickupAddress = request['pickup_address'] ?? 'Unknown pickup';
    final destinationAddress = request['destination_address'] ?? 'Unknown destination';
    final estimatedDistance = request['estimated_distance'] ?? 'Unknown distance';
    final estimatedTime = request['estimated_time'] ?? 'Unknown time';
    final estimatedFare = request['estimated_fare'] ?? 'N/A';
    
    final isProcessing = _processingRequests[requestId] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.shade100,
                  backgroundImage: user['profile_url'] != null 
                      ? NetworkImage(user['profile_url']) 
                      : null,
                  child: user['profile_url'] == null 
                      ? Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.blue),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        userName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Requested at $formattedTime',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.phone, color: Colors.blue),
                  onPressed: () {
                    // Implement phone call functionality
                  },
                  tooltip: 'Call $userPhone',
                ),
              ],
            ),
            const Divider(height: 24),
            _buildLocationInfo(
              'Pickup',
              pickupAddress,
              Icons.location_on_outlined,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildLocationInfo(
              'Destination',
              destinationAddress,
              Icons.location_on,
              Colors.red,
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildInfoItem('Distance', estimatedDistance, Icons.straighten),
                _buildInfoItem('Time', estimatedTime, Icons.access_time),
                _buildInfoItem('Fare', estimatedFare, Icons.attach_money),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _denyRideRequest(requestId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      elevation: 0,
                    ),
                    child: isProcessing 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(strokeWidth: 2)
                          )
                        : const Text('DENY'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: isProcessing ? null : () => _acceptRideRequest(requestId),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: isProcessing 
                        ? const SizedBox(
                            width: 20, 
                            height: 20, 
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              strokeWidth: 2,
                            )
                          )
                        : const Text('ACCEPT'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationInfo(
    String title,
    String address,
    IconData icon,
    Color color,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
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
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoItem(String title, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
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