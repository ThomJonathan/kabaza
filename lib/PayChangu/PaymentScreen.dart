// lib/payments/payment_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/AuthManager.dart';
import 'paychangu_service.dart';
import 'payment_widget.dart';

class PaymentScreen extends StatefulWidget {
  final String? rideRequestId; // For ride payments
  final double? rideAmount; // For ride payments

  const PaymentScreen({
    Key? key,
    this.rideRequestId,
    this.rideAmount,
  }) : super(key: key);

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  final supabase = Supabase.instance.client;
  late final PayChanguService _payChanguService;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();

  // User data
  Map<String, dynamic>? userProfile;
  List<Map<String, dynamic>> paymentHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializePaymentService();
    _loadUserData();

    // Set ride amount if provided
    if (widget.rideAmount != null) {
      _amountController.text = widget.rideAmount!.toStringAsFixed(0);
    }
  }

  void _initializePaymentService() {
    _payChanguService = PayChanguService(
      secretKey: 'sec-test-ImyPpPIQx87Rh1rOergg61qljCZHkgCg', // Replace with your actual key
      isTestMode: true, // Change to false for production
    );
  }

  Future<void> _loadUserData() async {
    try {
      final userId = AppAuthManager.getCurrentUserId();
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Load user profile from users table
      final profileResponse = await supabase
          .from('users')
          .select('*')
          .eq('id', userId)
          .single();

      // Load payment history
      final historyResponse = await supabase
          .from('payments')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(10);

      setState(() {
        userProfile = profileResponse;
        paymentHistory = List<Map<String, dynamic>>.from(historyResponse ?? []);
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _makePayment(PaymentType paymentType) {
    if (!_formKey.currentState!.validate()) return;

    final amount = int.parse(_amountController.text);
    final txRef = 'kabanza-${paymentType.name}-${DateTime.now().millisecondsSinceEpoch}';

    // Extract names from full_name
    final fullName = userProfile?['full_name'] ?? 'User Name';
    final nameParts = fullName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : 'User';
    final lastName = nameParts.length > 1 ? nameParts.skip(1).join(' ') : 'Name';

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PayChanguPaymentWidget(
          payChanguService: _payChanguService,
          txRef: txRef,
          firstName: firstName,
          lastName: lastName,
          email: userProfile?['email'] ?? 'user@example.com',
          amount: amount,
          callbackUrl: 'https://yourapp.com/callback', // Replace with your URL
          returnUrl: 'https://yourapp.com/return',     // Replace with your URL
          currency: 'MWK',
          onSuccess: (response) => _handlePaymentSuccess(response, paymentType),
          onError: _handlePaymentError,
          onCancel: _handlePaymentCancel,
        ),
      ),
    );
  }

  Future<void> _handlePaymentSuccess(Map<String, dynamic> response, PaymentType paymentType) async {
    Navigator.of(context).pop(); // Close payment screen

    try {
      // Save payment to your database
      await _savePaymentToDatabase(response, paymentType);

      // Show success dialog
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment Successful'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Payment Type: ${paymentType.displayName}'),
              Text('Amount: MWK ${response['amount']}'),
              Text('Transaction: ${response['tx_ref']}'),
              Text('Status: ${response['status']}'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _processPostPayment(paymentType, response);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      _showErrorSnackBar('Payment successful but failed to save: $e');
    }
  }

  Future<void> _savePaymentToDatabase(Map<String, dynamic> response, PaymentType paymentType) async {
    final userId = AppAuthManager.getCurrentUserId();
    if (userId == null) return;

    await supabase.from('payments').insert({
      'user_id': userId,
      'ride_request_id': paymentType == PaymentType.ridePayment ? widget.rideRequestId : null,
      'transaction_reference': response['tx_ref'],
      'amount': response['amount'],
      'currency': response['currency'],
      'payment_type': paymentType.name,
      'status': 'completed',
      'payment_method': 'paychangu',
      'verification_data': response['verification'],
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  void _processPostPayment(PaymentType paymentType, Map<String, dynamic> response) {
    switch (paymentType) {
      case PaymentType.walletTopup:
        _updateWalletBalance(response['amount']);
        break;
      case PaymentType.ridePayment:
        _processRidePayment(response);
        break;
      case PaymentType.subscription:
        _processSubscription(response);
        break;
    }
  }

  Future<void> _updateWalletBalance(int amount) async {
    final userId = AppAuthManager.getCurrentUserId();
    if (userId == null) return;

    try {
      // Update user wallet balance directly in users table
      final currentUser = await supabase
          .from('users')
          .select('wallet_balance')
          .eq('id', userId)
          .single();

      final currentBalance = currentUser['wallet_balance'] ?? 0;
      final newBalance = currentBalance + amount;

      await supabase
          .from('users')
          .update({'wallet_balance': newBalance})
          .eq('id', userId);

      _showSuccessSnackBar('Wallet topped up successfully!');
      _loadUserData(); // Refresh data
    } catch (e) {
      _showErrorSnackBar('Failed to update wallet: $e');
    }
  }

  Future<void> _processRidePayment(Map<String, dynamic> response) async {
    if (widget.rideRequestId == null) {
      _showErrorSnackBar('No ride request found');
      return;
    }

    try {
      // Update ride request payment status
      await supabase
          .from('ride_requests')
          .update({
        'payment_status': 'paid',
        'payment_method': 'paychangu',
        'actual_fare': response['amount'],
      })
          .eq('id', widget.rideRequestId!);

      _showSuccessSnackBar('Ride payment processed successfully!');

      // Navigate back to previous screen
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to update ride payment: $e');
    }
  }

  Future<void> _processSubscription(Map<String, dynamic> response) async {
    final userId = AppAuthManager.getCurrentUserId();
    if (userId == null) return;

    try {
      // Update user subscription status - you might need to create a subscriptions table
      await supabase.from('user_subscriptions').upsert({
        'user_id': userId,
        'status': 'active',
        'plan_type': 'premium',
        'started_at': DateTime.now().toIso8601String(),
        'expires_at': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
        'payment_reference': response['tx_ref'],
      });

      _showSuccessSnackBar('Subscription activated successfully!');
    } catch (e) {
      _showErrorSnackBar('Failed to activate subscription: $e');
    }
  }

  void _handlePaymentError(String error) {
    Navigator.of(context).pop();
    _showErrorSnackBar('Payment failed: $error');
  }

  void _handlePaymentCancel() {
    Navigator.of(context).pop();
    _showInfoSnackBar('Payment cancelled');
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showInfoSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.blue),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Payments'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wallet Balance Section
            _buildWalletSection(),
            const SizedBox(height: 20),

            // Payment Methods Info
            _buildPaymentMethodsInfo(),
            const SizedBox(height: 20),

            // Payment Options
            _buildPaymentOptionsSection(),
            const SizedBox(height: 20),

            // Recent Payments
            _buildRecentPaymentsSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSection() {
    final walletBalance = userProfile?['wallet_balance'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue, Colors.blue.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Wallet Balance',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'MWK ${walletBalance.toString()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodsInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          const Text(
            'Supported Payment Methods',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildPaymentMethodChip('Airtel Money', Colors.red),
              _buildPaymentMethodChip('TNM Mpamba', Colors.blue),
              _buildPaymentMethodChip('Bank Cards', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildPaymentOptionsSection() {
    return Container(
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
            'Payment Options',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),

          // Amount input
          Form(
            key: _formKey,
            child: TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount (MWK)',
                border: OutlineInputBorder(),
                prefixText: 'MWK ',
                hintText: 'Enter amount to pay',
              ),
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Enter amount';
                final amount = int.tryParse(value!);
                if (amount == null || amount <= 0) return 'Enter valid amount';
                if (amount < 100) return 'Minimum amount is MWK 100';
                return null;
              },
            ),
          ),

          const SizedBox(height: 20),

          // Payment Type Buttons
          if (widget.rideRequestId != null) ...[
            _buildPaymentTypeButton(
              'Pay for Ride',
              'Complete payment for your ride',
              Icons.local_taxi,
              Colors.blue,
                  () => _makePayment(PaymentType.ridePayment),
            ),
            const SizedBox(height: 12),
          ],

          _buildPaymentTypeButton(
            'Top Up Wallet',
            'Add money to your wallet',
            Icons.account_balance_wallet,
            Colors.green,
                () => _makePayment(PaymentType.walletTopup),
          ),
          const SizedBox(height: 12),

          if (widget.rideRequestId == null) ...[
            _buildPaymentTypeButton(
              'Subscription',
              'Upgrade your account',
              Icons.star,
              Colors.orange,
                  () => _makePayment(PaymentType.subscription),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPaymentTypeButton(
      String title,
      String subtitle,
      IconData icon,
      Color color,
      VoidCallback onTap,
      ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentPaymentsSection() {
    return Container(
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
            'Recent Payments',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          if (paymentHistory.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No payments yet',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...paymentHistory.map((payment) => _buildPaymentHistoryItem(payment)),
        ],
      ),
    );
  }

  Widget _buildPaymentHistoryItem(Map<String, dynamic> payment) {
    final amount = payment['amount'];
    final paymentType = payment['payment_type'] ?? 'unknown';
    final createdAt = payment['created_at'];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  PaymentType.values
                      .firstWhere((type) => type.name == paymentType, orElse: () => PaymentType.walletTopup)
                      .displayName,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                if (createdAt != null)
                  Text(
                    _formatDateTime(createdAt),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
              ],
            ),
          ),
          Text(
            'MWK $amount',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return 'Invalid date';
    }
  }
}

enum PaymentType {
  walletTopup('wallet_topup', 'Wallet Top-up'),
  ridePayment('ride_payment', 'Ride Payment'),
  subscription('subscription', 'Subscription');

  const PaymentType(this.name, this.displayName);
  final String name;
  final String displayName;
}