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

      print('Nearby drivers response: $response'); // Debug log
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

  // Alternative method using direct coordinates
  Future<List<Map<String, dynamic>>> getNearbyDriversByCoordinates(double lat, double lng) async {
    try {
      final response = await supabase.rpc('get_nearby_drivers_by_coordinates', params: {
        'user_lat': lat,
        'user_lng': lng,
        'radius_km': 5.0,
      });

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Direct coordinate query error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> createRideRequest({
    required double pickupLat,
    required double pickupLng,
    required double destLat,
    required double destLng,
    String? driverId,
    String? pickupAddress,
    String? destinationAddress,
    String? specialInstructions,
  }) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      final userName = AppAuthManager.getUserName();
      final userEmail = AppAuthManager.getUserEmail();

      if (currentUserId == null) {
        print('No user ID available for ride request');
        return null;
      }

      // Validate driver exists if driverId is provided
      if (driverId != null) {
        final driverCheck = await supabase
            .from('users')
            .select('id, role')
            .eq('id', driverId)
            .eq('role', 'driver')
            .maybeSingle();

        if (driverCheck == null) {
          print('Invalid driver ID: $driverId');
          return null;
        }
      }

      // Calculate estimated distance and duration
      final estimatedDistance = _calculateDistance(pickupLat, pickupLng, destLat, destLng);
      final estimatedDuration = (estimatedDistance * 2).round(); // Rough estimate: 2 minutes per km

      final rideData = {
        'user_id': currentUserId,
        'driver_id': driverId,
        'pickup_latitude': pickupLat,
        'pickup_longitude': pickupLng,
        'pickup_address': pickupAddress ?? 'Unknown pickup location',
        'destination_latitude': destLat,
        'destination_longitude': destLng,
        'destination_address': destinationAddress ?? 'Unknown destination',
        'estimated_distance': '${estimatedDistance.toStringAsFixed(1)} km',
        'estimated_time': '${estimatedDuration} minutes',
        'estimated_fare': _calculateFare(estimatedDistance),
        'status': 'pending',
        'special_instructions': specialInstructions,
        'created_at': DateTime.now().toIso8601String(),
      };

      print('Creating ride request: $rideData'); // Debug log

      final response = await supabase
          .from('ride_requests')
          .insert(rideData)
          .select()
          .single();

      print('Ride request created: $response'); // Debug log

      // If a specific driver is selected, notify them
      if (driverId != null) {
        await _notifyDriver(driverId, response['id']);
      }

      return response;
    } catch (e) {
      print('Ride request error: $e');
      print('Error details: ${e.toString()}');
      return null;
    }
  }

  // Helper method to calculate distance between two points
  double _calculateDistance(double lat1, double lng1, double lat2, double lng2) {
    return Geolocator.distanceBetween(lat1, lng1, lat2, lng2) / 1000; // Convert to km
  }

  // Helper method to calculate fare based on distance
  String _calculateFare(double distanceKm) {
    const double basePrice = 2.0; // Base fare
    const double pricePerKm = 1.5; // Price per kilometer
    final fare = basePrice + (distanceKm * pricePerKm);
    return 'MK ${fare.toStringAsFixed(2)}';
  }

  // Helper method to notify selected driver
  Future<void> _notifyDriver(String driverId, String rideRequestId) async {
    try {
      // Create a database notification
      await supabase.from('notifications').insert({
        'user_id': driverId,
        'type': 'ride_request',
        'title': 'New Ride Request',
        'message': 'You have a new ride request',
        'data': {'ride_request_id': rideRequestId},
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      print('Driver notification error: $e');
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

  // Method to cancel a ride request
  Future<bool> cancelRideRequest(String rideRequestId, String reason) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) return false;

      await supabase.from('ride_requests').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancellation_reason': reason,
      }).eq('id', rideRequestId).eq('user_id', currentUserId);

      return true;
    } catch (e) {
      print('Cancel ride error: $e');
      return false;
    }
  }

  // Method to get ride request details
  Future<Map<String, dynamic>?> getRideRequestDetails(String rideRequestId) async {
    try {
      final response = await supabase
          .from('ride_requests')
          .select('*, users!ride_requests_driver_id_fkey(full_name, phone)')
          .eq('id', rideRequestId)
          .single();

      return response;
    } catch (e) {
      print('Get ride details error: $e');
      return null;
    }
  }

  // Method to get user's ride history
  Future<List<Map<String, dynamic>>> getUserRideHistory() async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) return [];

      final response = await supabase
          .from('ride_requests')
          .select('*')
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Get ride history error: $e');
      return [];
    }
  }

  // Method to get pickup and destination addresses from coordinates
  Future<Map<String, String>> getAddressesFromCoordinates(
      double pickupLat,
      double pickupLng,
      double destLat,
      double destLng
      ) async {
    try {
      // You can use a geocoding service here
      // For now, return formatted coordinates
      return {
        'pickup': 'Pickup: ${pickupLat.toStringAsFixed(4)}, ${pickupLng.toStringAsFixed(4)}',
        'destination': 'Destination: ${destLat.toStringAsFixed(4)}, ${destLng.toStringAsFixed(4)}',
      };
    } catch (e) {
      print('Address lookup error: $e');
      return {
        'pickup': 'Unknown pickup location',
        'destination': 'Unknown destination',
      };
    }
  }
}
