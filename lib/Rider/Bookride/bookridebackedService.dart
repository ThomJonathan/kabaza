import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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

      // First, update the current user's location with address
      await _updateUserLocation(lat, lng);

      print('Calling get_nearby_drivers_with_location for user: $currentUserId');

      // Execute the nearby drivers query
      final response = await supabase.rpc('get_nearby_drivers_with_location', params: {
        'current_user_id': currentUserId,
      });

      print('Nearby drivers response: $response');

      // Validate response
      if (response == null) {
        print('Null response from database function');
        return [];
      }

      final drivers = List<Map<String, dynamic>>.from(response);
      print('Found ${drivers.length} online and available drivers');

      return drivers;
    } catch (e) {
      print('Error getting nearby drivers: $e');
      print('Stack trace: ${StackTrace.current}');
      return [];
    }
  }

  // Helper method to update user location with address
  Future<void> _updateUserLocation(double lat, double lng) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) return;

      // Get address from coordinates
      String? address;
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(lat, lng)
            .timeout(Duration(seconds: 5));

        if (placemarks.isNotEmpty) {
          Placemark place = placemarks[0];
          List<String> addressParts = [];

          if (place.street != null && place.street!.isNotEmpty) {
            addressParts.add(place.street!);
          }
          if (place.locality != null && place.locality!.isNotEmpty) {
            addressParts.add(place.locality!);
          }
          if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
            addressParts.add(place.administrativeArea!);
          }
          if (place.country != null && place.country!.isNotEmpty) {
            addressParts.add(place.country!);
          }

          address = addressParts.join(', ');
        }
      } catch (e) {
        print('Geocoding failed for rider location: $e');
      }

      // Update with address included
      await supabase.from('user_locations').upsert({
        'user_id': currentUserId,
        'latitude': lat,
        'longitude': lng,
        'address': address,
        'last_updated': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id');

      print('Rider location updated with address: $address');
    } catch (e) {
      print('Location update error: $e');
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

      if (currentUserId == null) {
        print('No user ID available for ride request');
        return null;
      }

      // Validate driver exists and is available
      if (driverId != null) {
        final driverCheck = await supabase
            .from('drivers')
            .select('user_id, driver_status, is_available')
            .eq('user_id', driverId)
            .eq('driver_status', 'online')
            .eq('is_available', true)
            .maybeSingle();

        if (driverCheck == null) {
          print('Driver is not available or not online: $driverId');
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
        'created_at': DateTime.now().toUtc().toIso8601String(),
      };

      print('Creating ride request: $rideData');

      final response = await supabase
          .from('ride_requests')
          .insert(rideData)
          .select()
          .single();

      print('Ride request created successfully: ${response['id']}');

      // Notify the selected driver
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
    const double basePrice = 500.0; // Base fare
    const double pricePerKm = 500; // Price per kilometer
    final fare = basePrice + (distanceKm * pricePerKm);
    return 'MK ${fare.toStringAsFixed(2)}';
  }

  // Helper method to notify selected driver
  Future<void> _notifyDriver(String driverId, String rideRequestId) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': driverId,
        'type': 'ride_request',
        'title': 'New Ride Request',
        'message': 'You have a new ride request',
        'data': {'ride_request_id': rideRequestId},
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      print('Driver notified: $driverId');
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

    // Already sorted by distance in SQL function
    return drivers.first;
  }

  // Method to cancel a ride request
  Future<bool> cancelRideRequest(String rideRequestId, String reason) async {
    try {
      final currentUserId = AppAuthManager.getCurrentUserId();
      if (currentUserId == null) return false;

      await supabase.from('ride_requests').update({
        'status': 'cancelled',
        'cancelled_at': DateTime.now().toUtc().toIso8601String(),
        'cancelled_by': currentUserId,
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
          .select('*, drivers!ride_requests_driver_id_fkey(*, users!drivers_user_id_fkey(full_name, phone, profile_url))')
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
          .select('*, drivers!ride_requests_driver_id_fkey(*, users!drivers_user_id_fkey(full_name, phone))')
          .eq('user_id', currentUserId)
          .order('created_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Get ride history error: $e');
      return [];
    }
  }

  // Method to get addresses from coordinates using geocoding
  Future<Map<String, String>> getAddressesFromCoordinates(
      double pickupLat,
      double pickupLng,
      double destLat,
      double destLng
      ) async {
    try {
      // Get pickup address
      String pickupAddress = 'Unknown pickup location';
      try {
        List<Placemark> pickupPlacemarks = await placemarkFromCoordinates(
            pickupLat,
            pickupLng
        ).timeout(Duration(seconds: 5));

        if (pickupPlacemarks.isNotEmpty) {
          final place = pickupPlacemarks.first;
          pickupAddress = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}'.trim();
        }
      } catch (e) {
        print('Pickup geocoding error: $e');
      }

      // Get destination address
      String destAddress = 'Unknown destination';
      try {
        List<Placemark> destPlacemarks = await placemarkFromCoordinates(
            destLat,
            destLng
        ).timeout(Duration(seconds: 5));

        if (destPlacemarks.isNotEmpty) {
          final place = destPlacemarks.first;
          destAddress = '${place.street ?? ''}, ${place.locality ?? ''}, ${place.country ?? ''}'.trim();
        }
      } catch (e) {
        print('Destination geocoding error: $e');
      }

      return {
        'pickup': pickupAddress,
        'destination': destAddress,
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