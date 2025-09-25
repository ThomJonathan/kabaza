import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:math';

class TokenBasedPasswordResetService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Generate a 6-digit reset token
  String _generateResetToken() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }

  // Send reset token via email
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


      final token = _generateResetToken();
      final expiresAt = DateTime.now().add(const Duration(minutes: 15));

      // Store token in database
      try {
        await _supabase.from('password_reset_tokens').upsert({
          'email': email.toLowerCase().trim(),
          'token': token,
          'expires_at': expiresAt.toIso8601String(),
          'used': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (functionError) {
        print('Edge function error: $functionError');
        return {'success': false, 'message': 'Failed to send reset email. Please try again later.'};
      }

      // Send email via Edge Function
      try {
        final response = await _supabase.functions.invoke(
          'password-reset',
          body: {
            'action': 'send-reset-token',
            'email': email.toLowerCase().trim(),
            'token': token,
          },
        );

        if (response.status == 200) {
          final data = response.data;
          if (data['success'] == true) {
            return {
              'success': true,
              'message': 'Reset code sent to your email address!',
              // Remove in production:
              'debug_token': token, // For testing purposes only
            };
          } else {
            return {'success': false, 'message': data['error'] ?? 'Failed to send reset email'};
          }
        } else {
          throw Exception('HTTP ${response.status}');
        }
      } catch (functionError) {
        print('Edge function error: $functionError');

        // Fallback: Try Supabase built-in password reset
        try {
          await _supabase.auth.resetPasswordForEmail(
            email,
            redirectTo: 'yourapp://reset-password',
          );

          return {
            'success': true,
            'message': 'Reset instructions sent to your email! Please check your inbox.',
            'fallback': true,
          };
        } catch (fallbackError) {
          print('Fallback error: $fallbackError');
          return {'success': false, 'message': 'Failed to send reset email. Please try again later.'};
        }
      }
    } catch (error) {
      print('Error in sendResetToken: $error');
      return {'success': false, 'message': 'An unexpected error occurred. Please try again.'};
    }
  }

  // Verify token and update password
  Future<Map<String, dynamic>> resetPasswordWithToken({
    required String email,
    required String token,
    required String newPassword,
  }) async {
    try {
      // Validate inputs
      if (email.isEmpty || token.isEmpty || newPassword.isEmpty) {
        return {'success': false, 'message': 'All fields are required'};
      }

      if (newPassword.length < 8) {
        return {'success': false, 'message': 'Password must be at least 8 characters long'};
      }

      if (token.length != 6 || !RegExp(r'^\d{6}$').hasMatch(token)) {
        return {'success': false, 'message': 'Please enter a valid 6-digit code'};
      }

      // Verify token exists and is valid
      final tokenRecord = await _supabase
          .from('password_reset_tokens')
          .select('*')
          .eq('email', email.toLowerCase().trim())
          .eq('token', token.trim())
          .eq('used', false)
          .maybeSingle();

      if (tokenRecord == null) {
        return {'success': false, 'message': 'Invalid reset code. Please check and try again.'};
      }

      // Check if token is expired
      final expiresAt = DateTime.parse(tokenRecord['expires_at']);
      if (DateTime.now().isAfter(expiresAt)) {
        // Clean up expired token
        await _supabase
            .from('password_reset_tokens')
            .delete()
            .eq('id', tokenRecord['id']);

        return {'success': false, 'message': 'Reset code has expired. Please request a new one.'};
      }

      // Update password using Edge Function
      try {
        final response = await _supabase.functions.invoke(
          'password-reset',
          body: {
            'action': 'update-password',
            'email': email.toLowerCase().trim(),
            'newPassword': newPassword,
          },
        );

        if (response.status == 200) {
          final data = response.data;
          if (data['success'] == true) {
            // Mark token as used
            await _supabase
                .from('password_reset_tokens')
                .update({
              'used': true,
              'used_at': DateTime.now().toIso8601String()
            })
                .eq('id', tokenRecord['id']);

            // Clean up other tokens for this email
            await _cleanupUserTokens(email.toLowerCase().trim(), tokenRecord['id']);

            return {'success': true, 'message': 'Password updated successfully!'};
          } else {
            return {'success': false, 'message': data['error'] ?? 'Failed to update password'};
          }
        } else {
          throw Exception('HTTP ${response.status}');
        }
      } catch (functionError) {
        print('Password update error: $functionError');
        return {'success': false, 'message': 'Failed to update password. Please try again.'};
      }

    } catch (error) {
      print('Error in resetPasswordWithToken: $error');
      return {'success': false, 'message': 'An unexpected error occurred. Please try again.'};
    }
  }

  // Helper method to clean up user tokens
  Future<void> _cleanupUserTokens(String email, String currentTokenId) async {
    try {
      await _supabase
          .from('password_reset_tokens')
          .delete()
          .eq('email', email)
          .neq('id', currentTokenId);
    } catch (error) {
      print('Error cleaning up tokens: $error');
    }
  }

  // Clean up expired tokens (call this periodically)
  Future<void> cleanupExpiredTokens() async {
    try {
      await _supabase
          .from('password_reset_tokens')
          .delete()
          .lt('expires_at', DateTime.now().toIso8601String());
      print('Expired tokens cleaned up');
    } catch (error) {
      print('Error cleaning up expired tokens: $error');
    }
  }

  // Check if user has pending reset tokens
  Future<bool> hasValidToken(String email) async {
    try {
      final result = await _supabase
          .from('password_reset_tokens')
          .select('expires_at')
          .eq('email', email.toLowerCase().trim())
          .eq('used', false)
          .gt('expires_at', DateTime.now().toIso8601String())
          .maybeSingle();

      return result != null;
    } catch (error) {
      print('Error checking valid token: $error');
      return false;
    }
  }
}