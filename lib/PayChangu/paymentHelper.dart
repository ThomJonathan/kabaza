import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'paymentService.dart';
import 'Paymentscreen.dart';

/// Helper class for ride payments
class RidePaymentHelper {
  static final PayChanguService _paymentService = PayChanguService(
    PayChanguConfig(
      secretKey: 'sec-test-ImyPpPIQx87Rh1rOergg61qljCZHkgCg',
      publicKey: 'pub-test-QUbUBF2F34j5k0smsodB1JnKfnxVBuCz',
      isTestMode: true,
    ),
    Supabase.instance.client,
  );

  /// Launch payment screen for a ride
  static Future<void> launchRidePayment({
    required BuildContext context,
    required String rideId,
    required String userId,
    required String firstName,
    String? lastName,
    String? email,
    required double fareAmount,
    VoidCallback? onPaymentComplete,
    VoidCallback? onPaymentFailed,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => RidePaymentScreen(
          rideId: rideId,
          userId: userId,
          firstName: firstName,
          lastName: lastName,
          email: email,
          fareAmount: fareAmount,
          onPaymentComplete: onPaymentComplete,
          onPaymentFailed: onPaymentFailed,
        ),
      ),
    );
  }

  /// Check if a ride's payment is complete
  static Future<bool> isRidePaymentComplete(String rideId) async {
    try {
      final response = await Supabase.instance.client
          .from('ride_requests')
          .select('payment_status')
          .eq('id', rideId)
          .single();

      return response['payment_status'] == 'paid';
    } catch (e) {
      print('Error checking payment status: $e');
      return false;
    }
  }

  /// Get ride payment status
  static Future<String> getRidePaymentStatus(String rideId) async {
    try {
      final response = await Supabase.instance.client
          .from('ride_requests')
          .select('payment_status')
          .eq('id', rideId)
          .single();

      return response['payment_status'] ?? 'unknown';
    } catch (e) {
      print('Error getting payment status: $e');
      return 'unknown';
    }
  }

  /// Update ride payment status manually (for testing or admin purposes)
  static Future<bool> updateRidePaymentStatus({
    required String rideId,
    required String status, // 'paid', 'failed', 'pending'
    double? actualFare,
  }) async {
    try {
      final updates = <String, dynamic>{
        'payment_status': status,
      };

      if (actualFare != null) {
        updates['actual_fare'] = actualFare;
      }

      await Supabase.instance.client
          .from('ride_requests')
          .update(updates)
          .eq('id', rideId);

      return true;
    } catch (e) {
      print('Error updating payment status: $e');
      return false;
    }
  }
  /// Quick payment verification for a transaction reference
  static Future<String> quickVerifyPayment(String txRef) async {
    return await _paymentService.checkPaymentStatus(txRef);
  }

  /// Format currency for display
  static String formatCurrency(double amount, {String currency = 'MWK'}) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }


  /// Show payment confirmation dialog
  static Future<bool?> showPaymentConfirmationDialog({
    required BuildContext context,
    required double amount,
    required String rideId,
  }) async {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You are about to pay for your ride:'),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Ride ID:'),
                  Text(rideId.substring(0, 8) + '...'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Amount:'),
                  Text(
                    formatCurrency(amount),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'This will redirect you to PayChangu to complete the payment.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Pay Now'),
            ),
          ],
        );
      },
    );
  }


  /// Show payment status widget
  static Widget buildPaymentStatusWidget(String paymentStatus) {
    IconData icon;
    Color color;
    String text;

    switch (paymentStatus.toLowerCase()) {
      case 'paid':
        icon = Icons.check_circle;
        color = Colors.green;
        text = 'Paid';
        break;
      case 'failed':
        icon = Icons.error;
        color = Colors.red;
        text = 'Failed';
        break;
      case 'pending':
        icon = Icons.access_time;
        color = Colors.orange;
        text = 'Pending';
        break;
      default:
        icon = Icons.help;
        color = Colors.grey;
        text = 'Unknown';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Extension methods for ride payment
extension RidePaymentExtensions on Map<String, dynamic> {
  /// Check if this ride needs payment
  bool get needsPayment {
    final status = this['status'] as String?;
    final paymentStatus = this['payment_status'] as String?;

    return status == 'completed' &&
        (paymentStatus == null || paymentStatus == 'pending');
  }

  /// Get payment status color
  Color get paymentStatusColor {
    final paymentStatus = this['payment_status'] as String?;

    switch (paymentStatus?.toLowerCase()) {
      case 'paid':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  /// Check if payment is complete
  bool get isPaymentComplete {
    final paymentStatus = this['payment_status'] as String?;
    return paymentStatus == 'paid';
  }

  /// Get formatted fare amount
  String get formattedFare {
    final fare = this['actual_fare'] ?? this['estimated_fare'];
    if (fare == null) return 'N/A';

    double amount;
    if (fare is String) {
      amount = double.tryParse(fare) ?? 0.0;
    } else {
      amount = fare.toDouble();
    }

    return RidePaymentHelper.formatCurrency(amount);
  }
}

/// Payment status stream for real-time updates
class PaymentStatusStream {
  static Stream<Map<String, dynamic>> listenToRidePaymentStatus(String rideId) {
    return Supabase.instance.client
        .from('ride_requests')
        .stream(primaryKey: ['id'])
        .eq('id', rideId)
        .map((data) => data.isNotEmpty ? data.first : <String, dynamic>{});
  }
}