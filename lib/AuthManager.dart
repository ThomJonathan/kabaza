import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kabanza/routes.dart';
import 'package:kabanza/utils/service.dart';
import 'package:kabanza/utils/observer.dart';

class AppAuthManager {
  static String? _currentUserId;
  static Map<String, dynamic>? _currentUserData;

  // References to global services - these will be set from main.dart
  static UserActivityService? _userActivityService;
  static AppLifecycleObserver? _lifecycleObserver;
  static SupabaseClient? _supabase;

  // Initialize services references (call this from main.dart after services are created)
  static void initialize({
    required UserActivityService userActivityService,
    required AppLifecycleObserver lifecycleObserver,
    required SupabaseClient supabase,
  }) {
    _userActivityService = userActivityService;
    _lifecycleObserver = lifecycleObserver;
    _supabase = supabase;
  }

  // Set user data after successful login
  static void setUserData(Map<String, dynamic> userData) {
    _currentUserId = userData['id'];
    _currentUserData = userData;
  }

  // Get current user ID
  static String? getCurrentUserId() {
    return _currentUserId;
  }

  // Get current user data
  static Map<String, dynamic>? getCurrentUserData() {
    return _currentUserData;
  }

  // Get specific user field
  static String? getUserRole() {
    return _currentUserData?['role'];
  }

  static String? getUserName() {
    return _currentUserData?['name'];
  }

  static String? getUserEmail() {
    return _currentUserData?['email'];
  }

  static bool? getUserActiveStatus() {
    return _currentUserData?['is_active'];
  }

  // Check if user is logged in and we have their data
  static bool isUserDataAvailable() {
    return _currentUserId != null && _currentUserData != null;
  }

  static void onLoginSuccess() {
    _lifecycleObserver?.setLoggedIn(true);
    _userActivityService?.setUserActive();
  }

  static Future<void> onLogout(BuildContext context) async {
    try {
      _lifecycleObserver?.setLoggedIn(false);
      await _userActivityService?.setUserInactive();
      await _supabase?.auth.signOut();

      // Clear user data
      _currentUserId = null;
      _currentUserData = null;

      if (context.mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.login,
              (route) => false,
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Logout failed: ${e.toString()}')),
        );
      }
    }
  }

  static String getHomeRouteForUser(User user) {
    final userRole = user.userMetadata?['role'] as String? ?? 'rider';

    switch (userRole.toLowerCase()) {
      case 'driver':
        return AppRoutes.driverHome;
      case 'rider':
      default:
        return AppRoutes.riderHome;
    }
  }
}