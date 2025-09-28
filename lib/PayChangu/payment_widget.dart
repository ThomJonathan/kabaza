import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'paychangu_service.dart';

/// Payment widget that handles the WebView checkout process
class PayChanguPaymentWidget extends StatefulWidget {
  final PayChanguService payChanguService;
  final String txRef;
  final String firstName;
  final String lastName;
  final String email;
  final int amount;
  final String callbackUrl;
  final String returnUrl;
  final Function(Map<String, dynamic>) onSuccess;
  final Function(String) onError;
  final Function() onCancel;
  final String currency;

  const PayChanguPaymentWidget({
    Key? key,
    required this.payChanguService,
    required this.txRef,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.amount,
    required this.callbackUrl,
    required this.returnUrl,
    required this.onSuccess,
    required this.onError,
    required this.onCancel,
    this.currency = 'MWK',
  }) : super(key: key);

  @override
  State<PayChanguPaymentWidget> createState() => _PayChanguPaymentWidgetState();
}

class _PayChanguPaymentWidgetState extends State<PayChanguPaymentWidget> {
  WebViewController? _controller;
  bool _isLoading = true;
  bool _hasError = false;
  String? _paymentUrl;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializePayment();
  }

  Future<void> _initializePayment() async {
    try {
      setState(() {
        _isLoading = true;
        _hasError = false;
      });

      final paymentUrl = await widget.payChanguService.initiatePayment(
        txRef: widget.txRef,
        firstName: widget.firstName,
        lastName: widget.lastName,
        email: widget.email,
        amount: widget.amount,
        callbackUrl: widget.callbackUrl,
        returnUrl: widget.returnUrl,
        currency: widget.currency,
      );

      if (!mounted) return;

      setState(() {
        _paymentUrl = paymentUrl;
      });

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36')
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            print('Navigation to: ${request.url}');
            _handleNavigation(request.url);
            return NavigationDecision.navigate;
          },
          onPageStarted: (String url) {
            print('Page started loading: $url');
          },
          onPageFinished: (String url) {
            print('Page finished loading: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            _handleNavigation(url);
          },
          onWebResourceError: (WebResourceError error) {
            print('Web resource error: ${error.description}');
            if (mounted) {
              setState(() {
                _hasError = true;
                _errorMessage = 'Failed to load payment page: ${error.description}';
                _isLoading = false;
              });
            }
          },
        ))
        ..loadRequest(Uri.parse(paymentUrl));

    } catch (e) {
      print('Error initializing payment: $e');
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _handleNavigation(String url) {
    print('Handling navigation: $url');

    // Check if payment was successful
    if (url.contains(widget.returnUrl) ||
        url.contains('success') ||
        url.contains('payment-success') ||
        url.toLowerCase().contains('successful')) {
      print('Payment success detected, verifying...');
      _verifyPayment();
    }
    // Check if payment was cancelled or failed
    else if (url.contains('cancel') ||
        url.contains('failed') ||
        url.contains('error') ||
        url.toLowerCase().contains('cancelled')) {
      print('Payment cancelled/failed detected');
      widget.onCancel();
    }
    // Additional check for PayChangu specific URLs
    else if (url.contains('paychangu.com') && url.contains('status')) {
      // Sometimes PayChangu includes status in URL parameters
      final uri = Uri.parse(url);
      final status = uri.queryParameters['status'];
      if (status == 'success' || status == 'successful') {
        _verifyPayment();
      } else if (status == 'failed' || status == 'cancelled') {
        widget.onCancel();
      }
    }
  }

  Future<void> _verifyPayment() async {
    if (!mounted) return;

    try {
      print('Verifying payment for txRef: ${widget.txRef}');

      // Show loading indicator during verification
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );

      // Wait a bit before verification to ensure payment is processed
      await Future.delayed(const Duration(seconds: 2));

      final verification = await widget.payChanguService.verifyTransaction(widget.txRef);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      print('Verification result: ${verification.data}');

      if (widget.payChanguService.validatePayment(
        verification: verification,
        expectedTxRef: widget.txRef,
        expectedAmount: widget.amount,
        expectedCurrency: widget.currency,
      )) {
        print('Payment validation successful');
        widget.onSuccess({
          'tx_ref': widget.txRef,
          'status': 'success',
          'amount': widget.amount,
          'currency': widget.currency,
          'verification': verification.data,
        });
      } else {
        print('Payment validation failed');
        widget.onError('Payment validation failed. Please contact support.');
      }
    } catch (e) {
      print('Payment verification error: $e');
      // Close loading dialog if still open
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
      }
      widget.onError('Payment verification failed: $e');
    }
  }

  void _retryPayment() {
    setState(() {
      _hasError = false;
      _errorMessage = null;
    });
    _initializePayment();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Complete Payment'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            widget.onCancel();
            Navigator.of(context).pop();
          },
        ),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_paymentUrl != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _retryPayment,
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: Stack(
        children: [
          // Error state
          if (_hasError)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Payment Error',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage ?? 'Something went wrong',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          onPressed: _retryPayment,
                          child: const Text('Retry'),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            widget.onCancel();
                            Navigator.of(context).pop();
                          },
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          // WebView
          else if (_paymentUrl != null && _controller != null)
            WebViewWidget(controller: _controller!)
          // Loading state
          else if (_isLoading)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Initializing payment...'),
                    SizedBox(height: 8),
                    Text(
                      'Please wait while we set up your payment',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

          // Loading overlay for page loading
          if (_isLoading && _paymentUrl != null)
            Container(
              color: Colors.white.withOpacity(0.8),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading payment page...'),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(
            top: BorderSide(color: Colors.grey[300]!),
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.blue),
                  const SizedBox(width: 8),
                  const Text(
                    'Secure Payment',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'MWK ${widget.amount}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Your payment is secured by PayChangu. Supported methods: Airtel Money, TNM Mpamba, Bank Cards',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}