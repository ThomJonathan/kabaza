import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'paymentService.dart';

class RidePaymentScreen extends StatefulWidget {
  final String rideId;
  final String userId;
  final String firstName;
  final String? lastName;
  final String? email;
  final double fareAmount;
  final VoidCallback? onPaymentComplete;
  final VoidCallback? onPaymentFailed;

  const RidePaymentScreen({
    Key? key,
    required this.rideId,
    required this.userId,
    required this.firstName,
    this.lastName,
    this.email,
    required this.fareAmount,
    this.onPaymentComplete,
    this.onPaymentFailed,
  }) : super(key: key);

  @override
  State<RidePaymentScreen> createState() => _RidePaymentScreenState();
}

class _RidePaymentScreenState extends State<RidePaymentScreen> {
  late PayChanguService _paymentService;
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();

  String _selectedProvider = 'AIRTEL';
  bool _isLoading = false;
  bool _isProcessingPayment = false;
  String _status = '';
  String? _txRef;
  String? _paymentUrl;

  final List<Map<String, dynamic>> _providers = [
    {
      'value': 'AIRTEL',
      'name': 'Airtel Money',
      'icon': Icons.phone_android,
      'color': Colors.red,
    },
    {
      'value': 'TNM',
      'name': 'TNM Mpamba',
      'icon': Icons.phone_iphone,
      'color': Colors.blue,
    },
  ];

  @override
  void initState() {
    super.initState();
    _initializePaymentService();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _initializePaymentService() {
    final config = PayChanguConfig(
      secretKey: 'sec-test-ImyPpPIQx87Rh1rOergg61qljCZHkgCg',
      publicKey: 'pub-test-QUbUBF2F34j5k0smsodB1JnKfnxVBuCz',
      isTestMode: true,
    );

    _paymentService = PayChanguService(config, Supabase.instance.client);
  }

  Future<void> _initiatePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _status = 'Initializing payment...';
    });

    try {
      // FIX: Do not multiply by 100, send the actual amount as shown in the app
      final amountInTambala = widget.fareAmount.round();

      // Generate email if not provided
      final paymentEmail = widget.email ?? '${widget.userId}@quickride.app';

      final result = await _paymentService.initiateRidePayment(
        rideId: widget.rideId,
        userId: widget.userId,
        firstName: widget.firstName,
        lastName: widget.lastName ?? '',
        email: paymentEmail,
        amount: amountInTambala,
        paymentMethod: _selectedProvider,
      );

      if (result['success']) {
        setState(() {
          _txRef = result['tx_ref'];
          _paymentUrl = result['payment_url'];
          _status = 'Payment initialized successfully!';
          _isLoading = false;
        });

        // Show confirmation then launch payment
        await Future.delayed(const Duration(milliseconds: 500));
        await _launchPayment();
      } else {
        throw Exception('Payment initialization failed');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _status = 'Failed to initialize payment';
      });

      _showErrorDialog('Payment Initialization Failed', e.toString());
    }
  }

  Future<void> _launchPayment() async {
    if (_paymentUrl == null) return;

    try {
      final uri = Uri.parse(_paymentUrl!);

      setState(() {
        _isProcessingPayment = true;
        _status = 'Opening payment page...';
      });

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (launched) {
        // Wait a moment before starting to poll
        await Future.delayed(const Duration(seconds: 2));

        // Start polling for payment status
        if (mounted) {
          _startPaymentPolling();
        }
      } else {
        throw Exception('Could not launch payment URL');
      }
    } catch (e) {
      setState(() {
        _status = 'Error launching payment';
        _isProcessingPayment = false;
      });

      _showErrorDialog('Launch Error', e.toString());
    }
  }

  void _startPaymentPolling() async {
    if (_txRef == null) return;

    setState(() {
      _status = 'Please complete payment in your browser...\nChecking status automatically...';
    });

    try {
      // FIX: Use MWK as expectedAmount, not MWK * 100
      final expectedAmount = widget.fareAmount.round();

      final success = await _paymentService.pollAndUpdateRidePayment(
        rideId: widget.rideId,
        txRef: _txRef!,
        expectedAmount: expectedAmount,
        maxAttempts: 36, // Poll for 6 minutes
      );

      if (!mounted) return;

      if (success) {
        setState(() {
          _status = 'Payment successful!';
          _isProcessingPayment = false;
        });

        _showSuccessDialog();
      } else {
        setState(() {
          _status = 'Payment failed or was cancelled';
          _isProcessingPayment = false;
        });

        _showErrorDialog(
          'Payment Failed',
          'Your payment was not completed. Please try again.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _status = 'Payment verification failed';
        _isProcessingPayment = false;
      });

      _showErrorDialog('Verification Failed', e.toString());
    }
  }

  Future<void> _checkPaymentStatus() async {
    if (_txRef == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Checking payment status...';
    });

    try {
      final status = await _paymentService.checkPaymentStatus(_txRef!);

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _status = 'Payment status: $status';
      });

      if (status == 'success') {
        _showSuccessDialog();
      } else if (status == 'failed' || status == 'cancelled') {
        _showErrorDialog('Payment Failed', 'Your payment was not completed.');
      } else if (status == 'pending') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment is still pending. Please wait...'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _status = 'Error checking status';
      });

      _showErrorDialog('Status Check Failed', e.toString());
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Column(
            children: const [
              Icon(Icons.check_circle, color: Colors.green, size: 64),
              SizedBox(height: 16),
              Text('Payment Successful!', textAlign: TextAlign.center),
            ],
          ),
          content: Text(
            'Your payment of MWK ${widget.fareAmount.toStringAsFixed(2)} has been processed successfully.\n\nThank you for using QuickRide!',
            textAlign: TextAlign.center,
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(); // Close dialog
                Navigator.of(context).pop(true); // Return with success
                widget.onPaymentComplete?.call();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.error, color: Colors.red),
              const SizedBox(width: 8),
              Expanded(child: Text(title)),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                if (_txRef == null) {
                  Navigator.of(context).pop(false);
                  widget.onPaymentFailed?.call();
                }
              },
              child: const Text('Close'),
            ),
            if (_txRef == null)
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _initiatePayment();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Retry'),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isProcessingPayment) {
          final shouldPop = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Cancel Payment?'),
              content: const Text(
                'Payment is in progress. Are you sure you want to leave?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Stay'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Leave'),
                ),
              ],
            ),
          );
          return shouldPop ?? false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pay for Ride'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Payment Amount Card
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        Text(
                          'Amount to Pay',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'MWK ${widget.fareAmount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ride ID: ${widget.rideId.substring(0, 8)}...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Payment form (only show if payment not initiated)
                if (_txRef == null) ...[
                  const Text(
                    'Select Payment Provider',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Provider selection
                  ..._providers.map((provider) {
                    final isSelected = _selectedProvider == provider['value'];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedProvider = provider['value'];
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? provider['color'].withOpacity(0.1)
                                : Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? provider['color']
                                  : Colors.grey[300]!,
                              width: 2,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: provider['color'],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  provider['icon'],
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  provider['name'],
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: isSelected
                                        ? provider['color']
                                        : Colors.black87,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(
                                  Icons.check_circle,
                                  color: provider['color'],
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 24),

                  // Phone number input
                  const Text(
                    'Enter Phone Number',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 12),

                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    decoration: InputDecoration(
                      hintText: '0888123456',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your phone number';
                      }
                      if (value.length < 9) {
                        return 'Please enter a valid phone number';
                      }
                      return null;
                    },
                  ),

                  const SizedBox(height: 32),

                  // Pay button
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _initiatePayment,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Icon(Icons.payment),
                    label: Text(
                      _isLoading ? 'Processing...' : 'Pay Now',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ] else ...[
                  // Payment processing status
                  Card(
                    color: _status.contains('successful')
                        ? Colors.green.shade50
                        : _status.contains('failed')
                        ? Colors.red.shade50
                        : Colors.blue.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          Icon(
                            _status.contains('successful')
                                ? Icons.check_circle
                                : _status.contains('failed')
                                ? Icons.error
                                : Icons.info,
                            size: 48,
                            color: _status.contains('successful')
                                ? Colors.green
                                : _status.contains('failed')
                                ? Colors.red
                                : Colors.blue,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: _status.contains('successful')
                                  ? Colors.green.shade700
                                  : _status.contains('failed')
                                  ? Colors.red.shade700
                                  : Colors.blue.shade700,
                            ),
                          ),
                          if (_isProcessingPayment) ...[
                            const SizedBox(height: 20),
                            const LinearProgressIndicator(),
                          ],
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Check status button
                  OutlinedButton.icon(
                    onPressed: _isProcessingPayment ? null : _checkPaymentStatus,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check Payment Status'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // Info text
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'You will be redirected to complete payment. Please return to this app after payment.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

