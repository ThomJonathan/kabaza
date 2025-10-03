import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class TokenBasedPasswordResetService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Send reset link via Supabase built-in method
  Future<Map<String, dynamic>> sendResetToken(String email) async {
    try {
      // Validate email format
      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email)) {
        return {'success': false, 'message': 'Please enter a valid email address'};
      }

      // Check if user exists in your users table
      final userResponse = await _supabase
          .from('users')
          .select('id, email, is_active')
          .eq('email', email.toLowerCase().trim())
          .maybeSingle();

      if (userResponse == null) {
        return {'success': false, 'message': 'No account found with this email address'};
      }

      // Send reset email using Supabase built-in method
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'yourapp://reset-password', // Set this to your app's deep link or web URL
      );

      return {
        'success': true,
        'message': 'Reset instructions sent to your email! Please check your inbox.',
      };
    } catch (error) {
      print('Error in sendResetToken: $error');
      return {'success': false, 'message': 'Failed to send reset email. Please try again later.'};
    }
  }

  // Add this method for code-based password reset
  Future<Map<String, dynamic>> resetPasswordWithToken({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    try {
      // Call your edge function endpoint
      final url = Uri.parse(
        // Replace with your deployed edge function URL
        'https://<your-project-ref>.functions.supabase.co/password-reset'
      );
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'update-password',
          'email': email,
          'token': token,
          'newPassword': newPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true, 'message': data['message'] ?? 'Password reset successful'};
      } else {
        return {'success': false, 'message': data['error'] ?? 'Failed to reset password'};
      }
    } catch (e) {
      return {'success': false, 'message': 'Failed to reset password. Please try again.'};
    }
  }
}