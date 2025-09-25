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
  late WebViewController _controller;
  bool _isLoading = true;
  String? _paymentUrl;

  @override
  void initState() {
    super.initState();
    _initializePayment();
  }

  Future<void> _initializePayment() async {
    try {
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

      setState(() {
        _paymentUrl = paymentUrl;
      });

      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onNavigationRequest: (NavigationRequest request) {
            _handleNavigation(request.url);
            return NavigationDecision.navigate;
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
            _handleNavigation(url);
          },
        ))
        ..loadRequest(Uri.parse(paymentUrl));

    } catch (e) {
      widget.onError(e.toString());
    }
  }

  void _handleNavigation(String url) {
    // Check if payment was successful
    if (url.contains(widget.returnUrl) || url.contains('success')) {
      _verifyPayment();
    } else if (url.contains('cancel') || url.contains('failed')) {
      widget.onCancel();
    }
  }

  Future<void> _verifyPayment() async {
    try {
      final verification = await widget.payChanguService.verifyTransaction(widget.txRef);

      if (widget.payChanguService.validatePayment(
        verification: verification,
        expectedTxRef: widget.txRef,
        expectedAmount: widget.amount,
        expectedCurrency: widget.currency,
      )) {
        widget.onSuccess({
          'tx_ref': widget.txRef,
          'status': 'success',
          'amount': widget.amount,
          'currency': widget.currency,
          'verification': verification.data,
        });
      } else {
        widget.onError('Payment validation failed');
      }
    } catch (e) {
      widget.onError('Payment verification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PayChangu Payment'),
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
      ),
      body: Stack(
        children: [
          if (_paymentUrl != null)
            WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading payment page...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}