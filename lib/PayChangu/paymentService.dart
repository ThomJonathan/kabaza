import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class PayChanguConfig {
  final String secretKey;
  final String publicKey;
  final bool isTestMode;

  PayChanguConfig({
    required this.secretKey,
    required this.publicKey,
    this.isTestMode = true,
  });
}

enum PaymentStatus {
  pending,
  success,
  failed,
  cancelled
}

enum Currency {
  MWK,
  USD
}

class PaymentRequest {
  final String txRef;
  final String firstName;
  final String? lastName;
  final String? email;
  final Currency currency;
  final int amount;
  final String callbackUrl;
  final String returnUrl;

  PaymentRequest({
    required this.txRef,
    required this.firstName,
    this.lastName,
    this.email,
    required this.currency,
    required this.amount,
    required this.callbackUrl,
    required this.returnUrl,
  });

  Map<String, dynamic> toJson() {
    final json = {
      'tx_ref': txRef,
      'first_name': firstName,
      'currency': currency.toString().split('.').last,
      'amount': amount.toString(),
      'callback_url': callbackUrl,
      'return_url': returnUrl,
    };

    // Only add optional fields if they're not null or empty
    if (lastName != null && lastName!.isNotEmpty) {
      json['last_name'] = lastName!;
    }
    if (email != null && email!.isNotEmpty) {
      json['email'] = email!;
    }

    return json;
  }
}

class PaymentVerificationResponse {
  final String status;
  final String message;
  final VerificationData data;

  PaymentVerificationResponse({
    required this.status,
    required this.message,
    required this.data,
  });

  factory PaymentVerificationResponse.fromJson(Map<String, dynamic> json) {
    return PaymentVerificationResponse(
      status: json['status'] ?? 'unknown',
      message: json['message'] ?? '',
      data: VerificationData.fromJson(json['data'] ?? {}),
    );
  }
}

class VerificationData {
  final String status;
  final String txRef;
  final String currency;
  final int amount;
  final String createdAt;
  final String updatedAt;

  VerificationData({
    required this.status,
    required this.txRef,
    required this.currency,
    required this.amount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VerificationData.fromJson(Map<String, dynamic> json) {
    return VerificationData(
      status: json['status'] ?? 'pending',
      txRef: json['tx_ref'] ?? '',
      currency: json['currency'] ?? 'MWK',
      amount: _parseAmount(json['amount']),
      createdAt: json['created_at'] ?? '',
      updatedAt: json['updated_at'] ?? '',
    );
  }

  static int _parseAmount(dynamic amount) {
    if (amount == null) return 0;
    if (amount is int) return amount;
    if (amount is double) return amount.round();
    if (amount is String) {
      return int.tryParse(amount) ?? 0;
    }
    return 0;
  }
}

class PayChanguException implements Exception {
  final String message;
  final String? details;

  PayChanguException(this.message, [this.details]);

  @override
  String toString() => 'PayChanguException: $message${details != null ? '\nDetails: $details' : ''}';
}

class PayChanguService {
  static const String _baseUrl = 'https://api.paychangu.com';
  final PayChanguConfig _config;
  final SupabaseClient _supabase;

  PayChanguService(this._config, this._supabase);

  /// Initiates a payment transaction for a ride
  Future<Map<String, dynamic>> initiateRidePayment({
    required String rideId,
    required String userId,
    required String firstName,
    String? lastName,
    String? email,
    required int amount, // Amount in MWK (not cents)
    Currency currency = Currency.MWK,
    String paymentMethod = 'paychangu',
  }) async {
    try {
      // Generate unique transaction reference
      final txRef = 'ride_${rideId}_${DateTime.now().millisecondsSinceEpoch}';

      // Ensure email is properly formatted or use default
      final paymentEmail = (email != null && email.isNotEmpty)
          ? email
          : '${userId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')}@quickride.app';

      final request = PaymentRequest(
        txRef: txRef,
        firstName: firstName,
        lastName: lastName,
        email: paymentEmail,
        currency: currency,
        amount: amount, // FIX: Pass the actual amount, not multiplied by 100
        callbackUrl: 'https://quickride.app/callback',
        returnUrl: 'https://quickride.app/return',
      );

      print('Initiating payment with data: ${request.toJson()}');

      final response = await http.post(
        Uri.parse('$_baseUrl/payment'),
        headers: {
          'Authorization': 'Bearer ${_config.secretKey}',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(request.toJson()),
      );

      print('Payment API Response Status: ${response.statusCode}');
      print('Payment API Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);

        // Check if the response indicates success
        if (responseData['status'] == 'success' || responseData['data'] != null) {
          // ✅ FIXED: Use the paymentMethod parameter instead of hardcoded 'paychangu'
          await _supabase.from('ride_requests').update({
            'payment_status': 'pending',
            'payment_method': paymentMethod, // Use the parameter here
          }).eq('id', rideId);

          // Extract payment URL from response
          final paymentUrl = responseData['data']?['checkout_url'] // <-- Use checkout_url
              ?? responseData['data']?['authorization_url']
              ?? responseData['data']?['payment_url']
              ?? responseData['payment_url'];

          if (paymentUrl == null) {
            throw PayChanguException('Payment URL not found in response');
          }

          return {
            'success': true,
            'tx_ref': txRef,
            'payment_url': paymentUrl,
            'reference': responseData['data']?['reference'] ?? txRef,
          };
        } else {
          throw PayChanguException(
            'Payment initiation failed: ${responseData['message'] ?? 'Unknown error'}',
            response.body,
          );
        }
      } else {
        throw PayChanguException(
          'Payment initiation failed with status: ${response.statusCode}',
          response.body,
        );
      }
    } catch (e) {
      print('Payment initiation error: $e');
      if (e is PayChanguException) rethrow;
      throw PayChanguException('Payment initiation failed', e.toString());
    }

  }

  /// Verifies a transaction using the transaction reference
  Future<PaymentVerificationResponse> verifyTransaction(String txRef) async {
    try {
      print('Verifying transaction: $txRef');

      final response = await http.get(
        Uri.parse('$_baseUrl/verify-payment/$txRef'),
        headers: {
          'Authorization': 'Bearer ${_config.secretKey}',
          'Accept': 'application/json',
        },
      );

      print('Verification Response Status: ${response.statusCode}');
      print('Verification Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        return PaymentVerificationResponse.fromJson(jsonResponse);
      } else if (response.statusCode == 404) {
        // Transaction not found yet - might still be pending
        return PaymentVerificationResponse(
          status: 'pending',
          message: 'Transaction not found',
          data: VerificationData(
            status: 'pending',
            txRef: txRef,
            currency: 'MWK',
            amount: 0,
            createdAt: DateTime.now().toIso8601String(),
            updatedAt: DateTime.now().toIso8601String(),
          ),
        );
      } else {
        throw PayChanguException(
          'Transaction verification failed with status: ${response.statusCode}',
          response.body,
        );
      }
    } catch (e) {
      print('Verification error: $e');
      if (e is PayChanguException) rethrow;
      throw PayChanguException('Transaction verification failed', e.toString());
    }
  }

  /// Polls transaction status and updates ride payment status
  Future<bool> pollAndUpdateRidePayment({
    required String rideId,
    required String txRef,
    required int expectedAmount,
    int maxAttempts = 36, // Poll for 6 minutes (36 attempts * 10 seconds)
  }) async {
    int attempts = 0;
    print('Starting payment polling for ride: $rideId, txRef: $txRef');

    while (attempts < maxAttempts) {
      try {
        print('Poll attempt ${attempts + 1}/$maxAttempts');

        final verification = await verifyTransaction(txRef);
        print('Verification status: ${verification.data.status}');

        if (verification.data.status == 'success' ||
            verification.data.status == 'successful' ||
            verification.data.status == 'completed') {

          // Validate payment amount (allow exact or higher amount)
          if (verification.data.amount >= expectedAmount) {
            // Update ride payment status to paid
            await _supabase.from('ride_requests').update({
              'payment_status': 'paid',
              'actual_fare': (verification.data.amount / 100).toDouble(),
            }).eq('id', rideId);

            print('Payment successful! Updated ride status.');
            return true; // Payment successful
          } else {
            // Amount mismatch - mark as failed
            print('Payment amount mismatch. Expected: $expectedAmount, Got: ${verification.data.amount}');

            await _supabase.from('ride_requests').update({
              'payment_status': 'failed',
            }).eq('id', rideId);

            throw PayChanguException('Payment amount mismatch. Expected ${expectedAmount / 100} MWK but received ${verification.data.amount / 100} MWK');
          }
        } else if (verification.data.status == 'failed' ||
            verification.data.status == 'cancelled' ||
            verification.data.status == 'canceled') {
          // Payment failed or cancelled
          print('Payment failed or cancelled');

          await _supabase.from('ride_requests').update({
            'payment_status': 'failed',
          }).eq('id', rideId);

          return false;
        }

        // If status is still pending, continue polling
        print('Payment still pending, waiting...');
        attempts++;

        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 10));
        }

      } catch (e) {
        print('Error during payment verification attempt ${attempts + 1}: $e');

        // If it's a critical error (not just pending), don't keep retrying
        if (e is PayChanguException && e.message.contains('amount mismatch')) {
          rethrow;
        }

        attempts++;
        if (attempts < maxAttempts) {
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    // Timeout reached - mark as failed
    print('Payment verification timeout reached');

    await _supabase.from('ride_requests').update({
      'payment_status': 'failed',
    }).eq('id', rideId);

    throw PayChanguException('Payment verification timeout. Please check your payment status manually.');
  }

  /// Quick verification without polling - for immediate checks
  Future<String> checkPaymentStatus(String txRef) async {
    try {
      final verification = await verifyTransaction(txRef);
      return verification.data.status;
    } catch (e) {
      print('Error checking payment status: $e');
      return 'unknown';
    }
  }

  /// Validates payment details
  bool validatePayment(
      PaymentVerificationResponse verification, {
        required String expectedTxRef,
        required String expectedCurrency,
        required int expectedAmount,
      }) {
    final data = verification.data;

    return (data.status == 'success' || data.status == 'successful') &&
        data.txRef == expectedTxRef &&
        data.currency == expectedCurrency &&
        data.amount >= expectedAmount;
  }

  /// Manual payment verification for admin/testing
  Future<Map<String, dynamic>> manualVerifyPayment({
    required String rideId,
    required String txRef,
  }) async {
    try {
      final verification = await verifyTransaction(txRef);

      return {
        'success': true,
        'status': verification.data.status,
        'amount': verification.data.amount,
        'currency': verification.data.currency,
        'tx_ref': verification.data.txRef,
        'created_at': verification.data.createdAt,
        'updated_at': verification.data.updatedAt,
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Check if PayChangu API is accessible
  Future<bool> healthCheck() async {
    try {
      final response = await http.get(
        Uri.parse(_baseUrl),
        headers: {
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      return response.statusCode == 200 || response.statusCode == 404;
    } catch (e) {
      print('Health check failed: $e');
      return false;
    }
  }
}