import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/AuthManager.dart';
import 'package:intl/intl.dart';
import 'package:kabanza/PayChangu/paymentHelper.dart';
import 'dart:io';

class RiderHistoryPage extends StatefulWidget {
  const RiderHistoryPage({Key? key}) : super(key: key);

  @override
  State<RiderHistoryPage> createState() => _RiderHistoryPageState();
}

class _RiderHistoryPageState extends State<RiderHistoryPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rides = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRideHistory();
  }

  Future<void> _loadRideHistory() async {
    setState(() => _isLoading = true);
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) {
        setState(() {
          _rides = [];
          _isLoading = false;
        });
        return;
      }

      final response = await supabase
          .from('ride_requests')
          .select('''
            *,
            driver:driver_id(full_name, phone)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      setState(() {
        _rides = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _rides = [];
        _isLoading = false;
      });
      String msg = 'Failed to load ride history.';
      if (e is SocketException || e.toString().contains('SocketException')) {
        msg = 'No internet connection. Please check your network.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    }
  }

  Widget _buildStatusChip(String status) {
    Color color;
    String text;
    switch (status) {
      case 'completed':
        color = Colors.green;
        text = 'Completed';
        break;
      case 'cancelled':
        color = Colors.red;
        text = 'Cancelled';
        break;
      case 'in_progress':
        color = Colors.blue;
        text = 'In Progress';
        break;
      case 'accepted':
        color = Colors.orange;
        text = 'Accepted';
        break;
      default:
        color = Colors.grey;
        text = status;
    }
    return Chip(
      label: Text(text, style: TextStyle(color: Colors.white)),
      backgroundColor: color,
    );
  }

  Widget _buildRideCard(Map<String, dynamic> ride) {
    final driver = ride['driver'];
    final driverName = driver != null && driver['full_name'] != null
        ? driver['full_name']
        : 'Not assigned';
    final driverPhone = driver != null && driver['phone'] != null
        ? driver['phone']
        : '-';

    final status = ride['status'] ?? '';
    final paymentStatus = ride['payment_status'] ?? 'pending';
    final paymentMethod = ride['payment_method'] ?? '-';
    final actualFare = ride['actual_fare'];
    final estimatedFare = ride['estimated_fare'];
    final fare = actualFare != null
        ? double.tryParse(actualFare.toString()) ?? 0.0
        : (estimatedFare != null
            ? double.tryParse(estimatedFare.toString().replaceAll(RegExp(r'[^\d.]'), '')) ?? 0.0
            : null);

    final createdAt = ride['created_at'] != null
        ? DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(ride['created_at']))
        : '-';

    final pickup = ride['pickup_address'] ?? 'Unknown pickup';
    final destination = ride['destination_address'] ?? 'Unknown destination';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Route
            Row(
              children: [
                const Icon(Icons.location_on, color: Colors.blue, size: 18),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    '$pickup → $destination',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Date and status
            Row(
              children: [
                const Icon(Icons.calendar_today, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(createdAt, style: const TextStyle(color: Colors.grey)),
                const Spacer(),
                _buildStatusChip(status),
              ],
            ),
            const SizedBox(height: 8),
            // Driver info
            Row(
              children: [
                const Icon(Icons.person, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text('Driver: $driverName', style: const TextStyle(fontSize: 14)),
                if (driverPhone != '-') ...[
                  const SizedBox(width: 8),
                  Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                  Text(' $driverPhone', style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            // Payment info
            Row(
              children: [
                const Icon(Icons.payment, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Payment: ',
                  style: const TextStyle(fontSize: 14),
                ),
                RidePaymentHelper.buildPaymentStatusWidget(paymentStatus),
                if (status == 'completed' && fare != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Amount: MWK ${fare.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                      fontSize: 14,
                    ),
                  ),
                  if (paymentMethod != '-' && paymentMethod.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      'via $paymentMethod',
                      style: const TextStyle(fontSize: 13, color: Colors.blue),
                    ),
                  ],
                ],
              ],
            ),
            // Special instructions
            if (ride['special_instructions'] != null &&
                (ride['special_instructions'] as String).trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.orange),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        ride['special_instructions'],
                        style: const TextStyle(fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
            // Cancellation reason
            if (status == 'cancelled' && ride['cancellation_reason'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Row(
                  children: [
                    const Icon(Icons.cancel, size: 16, color: Colors.red),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Reason: ${ride['cancellation_reason']}',
                        style: const TextStyle(fontSize: 13, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? const Center(
                  child: Text(
                    'No trips found.',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadRideHistory,
                  child: ListView.builder(
                    itemCount: _rides.length,
                    itemBuilder: (context, index) {
                      final ride = _rides[index];
                      return _buildRideCard(ride);
                    },
                  ),
                ),
    );
  }
}
