import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kabanza/AuthManager.dart';

class RideService {
  final SupabaseClient supabase;

  RideService(this.supabase);

  Future<Position?> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      return await Geolocator.getCurrentPosition();
    } catch (e) {
      print('Location error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getNearbyDrivers(double lat, double lng) async {
    try {
      // Get current user ID from AuthManager
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) {
        print('No user ID available');
        return [];
      }

      // First, update/insert the current user's location
      await _updateUserLocation(lat, lng);

      // Execute the nearby drivers query
      final response = await supabase.rpc('get_nearby_drivers_with_location', params: {
        'current_user_id': currentUserId,
      });

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Drivers error: $e');
      return [];
    }
  }

  // Helper method to update user location
  Future<void> _updateUserLocation(double lat, double lng) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) return;

      await supabase.from('user_locations').upsert({
        'user_id': currentUserId,
        'latitude': lat,
        'longitude': lng,
        'last_updated': DateTime.now().toIso8601String(),
        'is_sharing_location': true,
      });
    } catch (e) {
      print('Location update error: $e');
    }
  }

  // Alternative method using direct SQL query (if you prefer this approach)
  Future<List<Map<String, dynamic>>> getNearbyDriversDirectQuery(double lat, double lng) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) {
        print('No user ID available');
        return [];
      }

      // Update current user location first
      await _updateUserLocation(lat, lng);

      // Execute the query using PostgreSQL function
      final response = await supabase.rpc('execute_nearby_drivers_query', params: {
        'user_id_param': currentUserId,
      });

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Direct query error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createRideRequest({
    required double pickupLat,
    required double pickupLng,
    required double destLat,
    required double destLng,
  }) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      final userName = AppAuthManager.getUserName();
      final userEmail = AppAuthManager.getUserEmail();

      if (currentUserId == null) {
        print('No user ID available for ride request');
        return null;
      }

      final response = await supabase.from('ride_requests').insert({
        'user_id': currentUserId,
        'user_name': userName,
        'user_email': userEmail,
        'pickup_latitude': pickupLat,
        'pickup_longitude': pickupLng,
        'destination_latitude': destLat,
        'destination_longitude': destLng,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      }).select().single();

      return response;
    } catch (e) {
      print('Ride request error: $e');
      return null;
    }
  }

  // Method to check if drivers are available before booking
  Future<bool> areDriversAvailable(double lat, double lng) async {
    final drivers = await getNearbyDrivers(lat, lng);
    return drivers.isNotEmpty;
  }

  // Method to get the closest driver
  Future<Map<String, dynamic>?> getClosestDriver(double lat, double lng) async {
    final drivers = await getNearbyDrivers(lat, lng);
    if (drivers.isEmpty) return null;

    // Sort by distance and return the closest one
    drivers.sort((a, b) => (a['distance_km'] as double).compareTo(b['distance_km'] as double));
    return drivers.first;
  }
}