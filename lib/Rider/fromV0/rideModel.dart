import 'dart:math' as math;

class RideModel {
  final String id;
  final String driverName;
  final String vehicleType;
  final String vehicleModel;
  final String plateNumber;
  final double rating;
  final int tripCount;
  final String estimatedArrival;
  final double fare;
  final String? driverPhoto;
  final double? driverLat;
  final double? driverLng;
  final String? driverId;
  final bool isAvailable;

  RideModel({
    required this.id,
    required this.driverName,
    required this.vehicleType,
    required this.vehicleModel,
    required this.plateNumber,
    required this.rating,
    required this.tripCount,
    required this.estimatedArrival,
    required this.fare,
    this.driverPhoto,
    this.driverLat,
    this.driverLng,
    this.driverId,
    this.isAvailable = true,
  });

  factory RideModel.fromJson(Map<String, dynamic> json) {
    return RideModel(
      id: json['id'],
      driverName: json['driver_name'],
      vehicleType: json['vehicle_type'],
      vehicleModel: json['vehicle_model'],
      plateNumber: json['plate_number'],
      rating: json['rating'].toDouble(),
      tripCount: json['trip_count'],
      estimatedArrival: json['estimated_arrival'],
      fare: json['fare'].toDouble(),
      driverPhoto: json['driver_photo'],
      driverLat: json['driver_lat']?.toDouble(),
      driverLng: json['driver_lng']?.toDouble(),
      driverId: json['driver_id'],
      isAvailable: json['is_available'] ?? true,
    );
  }

  double distanceFromLocation(double lat, double lng) {
    if (driverLat == null || driverLng == null) return double.infinity;

    const double earthRadius = 6371; // Earth's radius in kilometers
    double dLat = _degreesToRadians(driverLat! - lat);
    double dLon = _degreesToRadians(driverLng! - lng);

    double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(lat)) * math.cos(_degreesToRadians(driverLat!)) *
            math.sin(dLon / 2) * math.sin(dLon / 2);

    double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * (math.pi / 180);
  }
}