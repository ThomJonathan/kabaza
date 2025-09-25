import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// PayChangu payment service for Airtel Money and TNM Mpamba
class PayChanguService {
  static const String _baseUrl = 'https://api.paychangu.com';
  final String _secretKey;
  final bool _isTestMode;

  PayChanguService({
    required String secretKey,
    bool isTestMode = true,
  }) : _secretKey = secretKey, _isTestMode = isTestMode;

  /// Initiate payment and get payment URL
  Future<String> initiatePayment({
    required String txRef,
    required String firstName,
    required String lastName,
    required String email,
    required int amount,
    required String callbackUrl,
    required String returnUrl,
    String currency = 'MWK',
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/payment'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'tx_ref': txRef,
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'currency': currency,
          'amount': amount.toString(),
          'callback_url': callbackUrl,
          'return_url': returnUrl,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['data']['checkout_url'] ?? data['data']['link'];
      } else {
        throw PayChanguException(
          'Payment initiation failed: ${response.statusCode}',
          response.body,
        );
      }
    } catch (e) {
      throw PayChanguException('Payment initiation failed', e.toString());
    }
  }

  /// Verify transaction status
  Future<PaymentVerificationResult> verifyTransaction(String txRef) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/verify-payment/$txRef'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Accept': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return PaymentVerificationResult.fromJson(jsonResponse);
      } else {
        throw PayChanguException(
          'Verification failed: ${response.statusCode}',
          response.body,
        );
      }
    } catch (e) {
      throw PayChanguException('Verification failed', e.toString());
    }
  }

  /// Validate payment details
  bool validatePayment({
    required PaymentVerificationResult verification,
    required String expectedTxRef,
    required int expectedAmount,
    String expectedCurrency = 'MWK',
  }) {
    final data = verification.data;
    return data['status'] == 'success' &&
        data['tx_ref'] == expectedTxRef &&
        data['currency'] == expectedCurrency &&
        (data['amount'] as int) >= expectedAmount;
  }
}

/// Payment verification result model
class PaymentVerificationResult {
  final String status;
  final String message;
  final Map<String, dynamic> data;

  PaymentVerificationResult({
    required this.status,
    required this.message,
    required this.data,
  });

  factory PaymentVerificationResult.fromJson(Map<String, dynamic> json) {
    return PaymentVerificationResult(
      status: json['status'] ?? '',
      message: json['message'] ?? '',
      data: json['data'] ?? {},
    );
  }
}

/// Custom exception for PayChangu errors
class PayChanguException implements Exception {
  final String message;
  final String? details;

  PayChanguException(this.message, [this.details]);

  @override
  String toString() => 'PayChanguException: $message${details != null ? '\nDetails: $details' : ''}';
}