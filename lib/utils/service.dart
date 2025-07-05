// lib/services/user_activity_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class UserActivityService {
  final SupabaseClient _supabase;

  UserActivityService(this._supabase);

  // Update user activity status in the database
  Future<void> updateUserActivity(bool isActive) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      await _supabase
          .from('users')
          .update({'is_active': isActive, 'updated_at': DateTime.now().toIso8601String()})
          .eq('email', user.email!);
    } catch (e) {
      print('Error updating user activity: $e');
      rethrow;
    }
  }

  // Called when user logs in or app comes to foreground
  Future<void> setUserActive() async {
    await updateUserActivity(true);
  }

  // Called when user logs out or app goes to background
  Future<void> setUserInactive() async {
    await updateUserActivity(false);
  }
}