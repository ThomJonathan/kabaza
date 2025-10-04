import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';

class UserDeletionService {
  final SupabaseClient supabase;

  UserDeletionService(this.supabase);

  /// Delete current user's account
  Future<bool> deleteMyAccount(BuildContext context) async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      // Get user role first
      final userRole = await _getUserRole(user.id);

      // Show confirmation dialog with role-specific info
      final confirmed = await _showDeleteConfirmation(context, userRole);
      if (!confirmed) return false;

      // Show loading
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      // Get current session token
      final session = supabase.auth.currentSession;
      if (session == null) throw Exception('No active session');

      // Call edge function to delete account
      final response = await supabase.functions.invoke(
        'delete-account',
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );

      // Close loading dialog
      if (context.mounted) Navigator.pop(context);

      if (response.status == 200 && response.data['success'] == true) {
        // Sign out locally (already deleted from auth.users)
        await supabase.auth.signOut();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }

        return true;
      } else {
        throw Exception(response.data['error'] ?? 'Failed to delete account');
      }

    } catch (e) {
      print('❌ Error deleting account: $e');

      if (context.mounted) {
        // Close loading dialog if still open
        Navigator.of(context, rootNavigator: true).pop();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }

      return false;
    }
  }

  /// Get user role
  Future<String> _getUserRole(String userId) async {
    try {
      final response = await supabase
          .from('users')
          .select('role')
          .eq('id', userId)
          .single();

      return response['role'] ?? 'rider';
    } catch (e) {
      print('Error getting user role: $e');
      return 'rider'; // Default to rider
    }
  }

  /// Show confirmation dialog with role-specific information
  Future<bool> _showDeleteConfirmation(BuildContext context, String role) async {
    // Build role-specific message
    String whatWillBeDeleted = 'be aware that your account and all associated data will be permanently removed.';

    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Account'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to delete your account?',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                '⚠️ This action cannot be undone!',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'What will be deleted:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(whatWillBeDeleted),


            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete Account'),
          ),
        ],
      ),
    ) ?? false;
  }

  /// Admin function to delete any user (for admin panel)
  Future<bool> deleteUserAsAdmin(String userId) async {
    try {
      // Step 1: Delete from database
      final response = await supabase.rpc(
        'delete_user_account',
        params: {'p_user_id': userId},
      );

      if (response['success'] != true) {
        throw Exception(response['error'] ?? 'Failed to delete user data');
      }

      print('✅ Deleted ${response['user_role']} account data from database');

      // Step 2: Delete from auth.users
      // Note: This requires admin privileges
      await supabase.auth.admin.deleteUser(userId);

      print('✅ User $userId deleted successfully');
      return true;

    } catch (e) {
      print('❌ Error deleting user: $e');
      return false;
    }
  }
}