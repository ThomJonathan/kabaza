// lib/payments/payment_utils.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/AuthManager.dart';
import 'paymentScreen.dart';

class PaymentUtils {
  static final supabase = Supabase.instance.client;

  /// Navigate to payment screen for ride payment
  static Future<void> payForRide({
    required BuildContext context,
    required String rideRequestId,
    required double amount,
  }) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          rideRequestId: rideRequestId,
          rideAmount: amount,
        ),
      ),
    );
  }

  /// Navigate to payment screen for wallet top-up
  static Future<void> topUpWallet({
    required BuildContext context,
  }) async {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const PaymentScreen(),
      ),
    );
  }

  /// Check if user has sufficient wallet balance
  static Future<bool> hasSufficientWalletBalance(double requiredAmount) async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return false;

      final user = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('id', userId)
          .single();

      final walletBalance = user['wallet_balance'] ?? 0.0;
      return walletBalance >= requiredAmount;
    } catch (e) {
      print('Error checking wallet balance: $e');
      return false;
    }
  }

  /// Pay for ride using wallet balance
  static Future<bool> payFromWallet({
    required String rideRequestId,
    required double amount,
  }) async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return false;

      // Check if user has sufficient balance
      if (!await hasSufficientWalletBalance(amount)) {
        return false;
      }

      // Start transaction
      final user = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('id', userId)
          .single();

      final currentBalance = user['wallet_balance'] ?? 0.0;
      final newBalance = currentBalance - amount;

      // Update wallet balance
      await supabase
          .from('users')
          .update({'wallet_balance': newBalance})
          .eq('id', userId);

      // Update ride request payment status
      await supabase
          .from('ride_requests')
          .update({
        'payment_status': 'paid',
        'payment_method': 'wallet',
        'actual_fare': amount,
      })
          .eq('id', rideRequestId);

      // Record payment in payments table
      await supabase.from('payments').insert({
        'user_id': userId,
        'ride_request_id': rideRequestId,
        'transaction_reference': 'wallet-${DateTime.now().millisecondsSinceEpoch}',
        'amount': amount,
        'currency': 'MWK',
        'payment_type': 'ride_payment',
        'status': 'completed',
        'payment_method': 'wallet',
        'created_at': DateTime.now().toIso8601String(),
      });

      return true;
    } catch (e) {
      print('Error paying from wallet: $e');
      return false;
    }
  }

  /// Get user's wallet balance
  static Future<double> getWalletBalance() async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return 0.0;

      final user = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('id', userId)
          .single();

      return (user['wallet_balance'] ?? 0.0).toDouble();
    } catch (e) {
      print('Error getting wallet balance: $e');
      return 0.0;
    }
  }

  /// Get user's payment history
  static Future<List<Map<String, dynamic>>> getPaymentHistory({int limit = 20}) async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) return [];

      final payments = await supabase
          .from('payments')
          .select('*, ride_requests(pickup_address, destination_address)')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(payments ?? []);
    } catch (e) {
      print('Error getting payment history: $e');
      return [];
    }
  }

  /// Show payment options dialog for ride
  static Future<void> showRidePaymentDialog({
    required BuildContext context,
    required String rideRequestId,
    required double amount,
    required VoidCallback onPaymentSuccess,
  }) async {
    final walletBalance = await getWalletBalance();
    final hasEnoughBalance = walletBalance >= amount;

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Choose Payment Method'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Amount to pay: MWK ${amount.toStringAsFixed(2)}'),
            const SizedBox(height: 16),

            // Wallet payment option
            ListTile(
              leading: const Icon(Icons.account_balance_wallet),
              title: const Text('Pay from Wallet'),
              subtitle: Text(
                hasEnoughBalance
                    ? 'Balance: MWK ${walletBalance.toStringAsFixed(2)}'
                    : 'Insufficient balance (MWK ${walletBalance.toStringAsFixed(2)})',
              ),
              enabled: hasEnoughBalance,
              onTap: hasEnoughBalance ? () async {
                Navigator.of(context).pop();

                // Show loading
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );

                final success = await payFromWallet(
                  rideRequestId: rideRequestId,
                  amount: amount,
                );

                Navigator.of(context).pop(); // Close loading

                if (success) {
                  onPaymentSuccess();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment successful!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Payment failed. Please try again.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              } : null,
            ),

            const Divider(),

            // PayChangu payment option
            ListTile(
              leading: const Icon(Icons.payment),
              title: const Text('Pay with PayChangu'),
              subtitle: const Text('Airtel Money, TNM Mpamba, Cards'),
              onTap: () {
                Navigator.of(context).pop();
                payForRide(
                  context: context,
                  rideRequestId: rideRequestId,
                  amount: amount,
                ).then((_) {
                  // Payment screen will handle success callback
                  onPaymentSuccess();
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Format currency amount
  static String formatCurrency(double amount, {String currency = 'MWK'}) {
    return '$currency ${amount.toStringAsFixed(2)}';
  }

  /// Get payment method display name
  static String getPaymentMethodDisplayName(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'wallet':
        return 'Wallet';
      case 'paychangu':
        return 'PayChangu';
      case 'airtel_money':
        return 'Airtel Money';
      case 'tnm_mpamba':
        return 'TNM Mpamba';
      case 'card':
        return 'Bank Card';
      default:
        return paymentMethod;
    }
  }

  /// Get payment status color
  static Color getPaymentStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'paid':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Get payment status icon
  static IconData getPaymentStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'paid':
        return Icons.check_circle;
      case 'pending':
        return Icons.access_time;
      case 'failed':
        return Icons.error;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help;
    }
  }
}