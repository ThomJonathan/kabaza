import 'package:flutter/material.dart';
import 'paychangu_service.dart';
import 'payment_widget.dart';

/// Example implementation of PayChangu payment in your app
class PaymentExampleScreen extends StatefulWidget {
  const PaymentExampleScreen({Key? key}) : super(key: key);

  @override
  State<PaymentExampleScreen> createState() => _PaymentExampleScreenState();
}

class _PaymentExampleScreenState extends State<PaymentExampleScreen> {
  // Initialize PayChangu service with your test credentials
  late final PayChanguService _payChanguService;

  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(text: '1000');
  final _emailController = TextEditingController(text: 'test@example.com');
  final _firstNameController = TextEditingController(text: 'John');
  final _lastNameController = TextEditingController(text: 'Doe');

  @override
  void initState() {
    super.initState();
    // Initialize with your test secret key
    _payChanguService = PayChanguService(
      secretKey: 'sec-test-ImyPpPIQx87Rh1rOergg61qljCZHkgCg',
      isTestMode: true,
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _emailController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  void _initiatePayment() {
    if (_formKey.currentState!.validate()) {
      final txRef = 'tx-${DateTime.now().millisecondsSinceEpoch}';

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PayChanguPaymentWidget(
            payChanguService: _payChanguService,
            txRef: txRef,
            firstName: _firstNameController.text.trim(),
            lastName: _lastNameController.text.trim(),
            email: _emailController.text.trim(),
            amount: int.parse(_amountController.text),
            callbackUrl: 'https://your-domain.com/callback',
            returnUrl: 'https://your-domain.com/return',
            currency: 'MWK',
            onSuccess: _handlePaymentSuccess,
            onError: _handlePaymentError,
            onCancel: _handlePaymentCancel,
          ),
        ),
      );
    }
  }

  void _handlePaymentSuccess(Map<String, dynamic> response) {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Successful'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Transaction Reference: ${response['tx_ref']}'),
            Text('Amount: MWK ${response['amount']}'),
            Text('Status: ${response['status']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handlePaymentError(String error) {
    Navigator.of(context).pop();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Failed'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _handlePaymentCancel() {
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Payment cancelled')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PayChangu Payment'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Payment Methods Available:',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPaymentMethodChip('Airtel Money', Colors.red),
                          _buildPaymentMethodChip('TNM Mpamba', Colors.blue),
                          _buildPaymentMethodChip('Cards', Colors.green),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(
                  labelText: 'First Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter first name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter last name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter email';
                  }
                  if (!value.contains('@')) {
                    return 'Please enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _amountController,
                decoration: const InputDecoration(
                  labelText: 'Amount (MWK)',
                  border: OutlineInputBorder(),
                  prefixText: 'MWK ',
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter amount';
                  }
                  final amount = int.tryParse(value);
                  if (amount == null || amount <= 0) {
                    return 'Please enter a valid amount';
                  }
                  if (amount < 100) {
                    return 'Minimum amount is MWK 100';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: _initiatePayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Pay Now'),
              ),

              const SizedBox(height: 16),
              const Text(
                'Note: This is a test environment. Use test credentials for payments.',
                style: TextStyle(color: Colors.grey, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentMethodChip(String label, Color color) {
    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
    );
  }
}

// How to use in your main app:
/*
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PayChangu Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: PaymentExampleScreen(),
    );
  }
}
*/