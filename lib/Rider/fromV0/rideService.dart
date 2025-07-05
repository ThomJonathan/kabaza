import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kabanza/Rider/fromV0/rideModel.dart';
import 'dart:math' as math;

class RideBookingService {
  final SupabaseClient _supabase;

  RideBookingService(this._supabase);

  // Fetch nearby drivers within specified radius
  Future<List<RideModel>> fetchNearbyDrivers({
    required LatLng userLocation,
    double radiusKm = 5.0,
  }) async {
    try {
      // Query active drivers with their locations
      final response = await _supabase
          .from('user_locations')
          .select('''
            *,
            users!inner(
              id,
              full_name,
              email,
              user_type,
              is_active,
              driver_info(
                vehicle_type,
                vehicle_model,
                plate_number,
                rating,
                trip_count,
                is_available
              )
            )
          ''')
          .eq('users.user_type', 'driver')
          .eq('users.is_active', true)
          .eq('users.driver_info.is_available', true)
          .gte('last_updated', DateTime.now().subtract(Duration(minutes: 10)).toIso8601String());

      List<RideModel> nearbyDrivers = [];

      for (var item in response) {
        double driverLat = item['latitude'].toDouble();
        double driverLng = item['longitude'].toDouble();

        // Calculate distance
        double distance = _calculateDistance(
          userLocation.latitude,
          userLocation.longitude,
          driverLat,
          driverLng,
        );

        // Only include drivers within radius
        if (distance <= radiusKm) {
          var driverInfo = item['users']['driver_info'];

          nearbyDrivers.add(RideModel(
            id: item['users']['id'],
            driverName: item['users']['full_name'] ?? 'Unknown Driver',
            vehicleType: driverInfo['vehicle_type'] ?? 'Unknown',
            vehicleModel: driverInfo['vehicle_model'] ?? 'Unknown',
            plateNumber: driverInfo['plate_number'] ?? 'N/A',
            rating: (driverInfo['rating'] ?? 4.5).toDouble(),
            tripCount: driverInfo['trip_count'] ?? 0,
            estimatedArrival: '${(distance * 2).round()} min', // Rough estimate
            fare: _calculateFare(distance),
            driverLat: driverLat,
            driverLng: driverLng,
            driverId: item['users']['id'],
            isAvailable: driverInfo['is_available'] ?? true,
          ));
        }
      }

      // Sort by distance (closest first)
      nearbyDrivers.sort((a, b) {
        double distanceA = a.distanceFromLocation(userLocation.latitude, userLocation.longitude);
        double distanceB = b.distanceFromLocation(userLocation.latitude, userLocation.longitude);
        return distanceA.compareTo(distanceB);
      });

      return nearbyDrivers;
    } catch (e) {
      print('Error fetching nearby drivers: $e');
      throw Exception('Failed to fetch nearby drivers: $e');
    }
  }

  // Book a ride with a specific driver
  Future<Map<String, dynamic>> bookRide({
    required String driverId,
    required LatLng pickupLocation,
    required LatLng destinationLocation,
    required String pickupAddress,
    required String destinationAddress,
    required double estimatedFare,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Get user ID from users table
      final userResponse = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .single();

      final userId = userResponse['id'];

      // Create ride booking
      final rideResponse = await _supabase
          .from('ride_bookings')
          .insert({
        'rider_id': userId,
        'driver_id': driverId,
        'pickup_latitude': pickupLocation.latitude,
        'pickup_longitude': pickupLocation.longitude,
        'pickup_address': pickupAddress,
        'destination_latitude': destinationLocation.latitude,
        'destination_longitude': destinationLocation.longitude,
        'destination_address': destinationAddress,
        'estimated_fare': estimatedFare,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      })
          .select()
          .single();

      // Send notification to driver (you can implement push notifications here)
      await _notifyDriver(driverId, rideResponse['id']);

      return {
        'success': true,
        'booking_id': rideResponse['id'],
        'message': 'Ride booked successfully! Driver will be notified.',
      };
    } catch (e) {
      print('Error booking ride: $e');
      return {
        'success': false,
        'message': 'Failed to book ride: $e',
      };
    }
  }

  // Send message to driver
  Future<bool> sendMessageToDriver({
    required String driverId,
    required String message,
    String? bookingId,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userResponse = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .single();

      final userId = userResponse['id'];

      Map<String, dynamic> messageData = {
        'sender_id': userId,
        'receiver_id': driverId,
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (bookingId != null) {
        messageData['booking_id'] = bookingId;
      }

      await _supabase.from('messages').insert(messageData);

      return true;
    } catch (e) {
      print('Error sending message: $e');
      return false;
    }
  }

  // Get messages between rider and driver
  Future<List<Map<String, dynamic>>> getMessages({
    required String driverId,
    String? bookingId,
  }) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userResponse = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .single();

      final userId = userResponse['id'];

      // Build the base query
      final baseQuery = _supabase
          .from('messages')
          .select('''
            *,
            sender:users!sender_id(full_name),
            receiver:users!receiver_id(full_name)
          ''')
          .or('sender_id.eq.$userId,receiver_id.eq.$userId')
          .or('sender_id.eq.$driverId,receiver_id.eq.$driverId');

      // Execute query with or without booking_id filter
      final response = bookingId != null
          ? await baseQuery.eq('booking_id', bookingId).order('created_at', ascending: true)
          : await baseQuery.order('created_at', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching messages: $e');
      return [];
    }
  }

  // Get ride booking details
  Future<Map<String, dynamic>?> getRideBooking(String bookingId) async {
    try {
      final response = await _supabase
          .from('ride_bookings')
          .select('''
            *,
            rider:users!rider_id(id, full_name, email),
            driver:users!driver_id(id, full_name, email, driver_info(*))
          ''')
          .eq('id', bookingId)
          .single();

      return response;
    } catch (e) {
      print('Error fetching ride booking: $e');
      return null;
    }
  }

  // Update ride status
  Future<bool> updateRideStatus(String bookingId, String status) async {
    try {
      await _supabase
          .from('ride_bookings')
          .update({'status': status, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', bookingId);

      return true;
    } catch (e) {
      print('Error updating ride status: $e');
      return false;
    }
  }

  // Cancel ride booking
  Future<bool> cancelRide(String bookingId, String reason) async {
    try {
      await _supabase
          .from('ride_bookings')
          .update({
        'status': 'cancelled',
        'cancellation_reason': reason,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', bookingId);

      return true;
    } catch (e) {
      print('Error cancelling ride: $e');
      return false;
    }
  }

  // Get user's ride history
  Future<List<Map<String, dynamic>>> getRideHistory({int limit = 20}) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final userResponse = await _supabase
          .from('users')
          .select('id')
          .eq('email', user.email!)
          .single();

      final userId = userResponse['id'];

      final response = await _supabase
          .from('ride_bookings')
          .select('''
            *,
            driver:users!driver_id(full_name, driver_info(vehicle_type, vehicle_model, plate_number))
          ''')
          .eq('rider_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching ride history: $e');
      return [];
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    double dLat = _degreesToRadians(lat2 - lat1);
    double dLon = _degreesToRadians(lon2 - lon1);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat1)) * math.cos(_degreesToRadians(lat2)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }

  double _calculateFare(double distanceKm) {
    const double baseFare = 5.0; // Base fare in your currency
    const double perKmRate = 2.5; // Rate per kilometer
    return baseFare + (distanceKm * perKmRate);
  }

  Future<void> _notifyDriver(String driverId, String bookingId) async {
    // Implement push notification or real-time notification here
    // For now, we'll just log it
    print('Notifying driver $driverId about booking $bookingId');
  }
}