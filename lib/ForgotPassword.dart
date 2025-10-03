import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:kabanza/config/supabaseConfig.dart';

class TokenBasedPasswordResetService {
  final SupabaseClient _supabase = Supabase.instance.client;
  static const String _edgeFunctionUrl =
      'https://xagaehyzcnobvvmaykvt.supabase.co/functions/v1/password-reset';

  // Send 6-digit code via custom Edge Function
  Future<Map<String, dynamic>> sendResetToken(String email) async {
    try {
      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        return {'success': false, 'message': 'Please enter a valid email address'};
      }

      // Call Edge Function to send 6-digit code
      final url = Uri.parse(_edgeFunctionUrl);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}', // Add this line
        },
        body: jsonEncode({
          'action': 'send-code',
          'email': email.toLowerCase().trim(),
        }),
      ).timeout(const Duration(seconds: 30));

      print('Reset code response: ${response.statusCode} ${response.body}'); // Debug

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': 'A 6-digit code has been sent to your email!',
        };
      } else {
        // Improved error reporting
        String errorMsg = data['error'] ?? data['message'] ?? 'Failed to send reset code';
        return {
          'success': false,
          'message': errorMsg,
        };
      }
    } catch (error) {
      print('Error in sendResetToken: $error');
      return {
        'success': false,
        'message': 'Failed to send reset code. Please try again later.',
      };
    }
  }

  // Reset password with 6-digit code
  Future<Map<String, dynamic>> resetPasswordWithToken({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    try {
      final url = Uri.parse(_edgeFunctionUrl);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'apikey': SupabaseConfig.supabaseAnonKey,
          'Authorization': 'Bearer ${SupabaseConfig.supabaseAnonKey}', // Add this line
        },
        body: jsonEncode({
          'action': 'update-password',
          'email': email.toLowerCase().trim(),
          'token': token,
          'newPassword': newPassword,
        }),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Password reset successful'
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? 'Failed to reset password'
        };
      }
    } catch (e) {
      print('Error in resetPasswordWithToken: $e');
      return {
        'success': false,
        'message': 'Failed to reset password. Please try again.'
      };
    }
  }
}