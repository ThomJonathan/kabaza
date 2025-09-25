import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:google_polyline_algorithm/google_polyline_algorithm.dart';

class RouteService {
  static const String _baseUrl = 'https://maps.googleapis.com/maps/api/directions/json';
  final String apiKey;

  RouteService({required this.apiKey});

  Future<RouteResult?> getRoute({
    required LatLng origin,
    required LatLng destination,
  }) async {
    try {
      final url = Uri.parse(_baseUrl).replace(queryParameters: {
        'origin': '${origin.latitude},${origin.longitude}',
        'destination': '${destination.latitude},${destination.longitude}',
        'key': apiKey,
        'mode': 'driving', // Explicitly set mode
        'avoid': '', // Remove any restrictions that might cause issues
      });

      print('Making request to: $url'); // Debug log

      final response = await http.get(url).timeout(const Duration(seconds: 15));

      print('Response status: ${response.statusCode}'); // Debug log
      print('Response body: ${response.body}'); // Debug log

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseRouteResponse(data);
      } else {
        print('HTTP Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Route error: $e');
      return null;
    }
  }

  RouteResult _parseRouteResponse(Map<String, dynamic> data) {
    print('API Response Status: ${data['status']}'); // Debug log

    // Handle different API response statuses
    switch (data['status']) {
      case 'OK':
        break;
      case 'NOT_FOUND':
        throw Exception('No route found between the specified locations');
      case 'ZERO_RESULTS':
        throw Exception('No route could be found between the origin and destination');
      case 'MAX_WAYPOINTS_EXCEEDED':
        throw Exception('Too many waypoints provided');
      case 'MAX_ROUTE_LENGTH_EXCEEDED':
        throw Exception('Route is too long');
      case 'INVALID_REQUEST':
        throw Exception('Invalid request. Check your parameters.');
      case 'OVER_DAILY_LIMIT':
        throw Exception('API daily limit exceeded');
      case 'OVER_QUERY_LIMIT':
        throw Exception('API query limit exceeded');
      case 'REQUEST_DENIED':
        throw Exception('Request denied. Check your API key and permissions.');
      case 'UNKNOWN_ERROR':
        throw Exception('Unknown error occurred');
      default:
        throw Exception('API Error: ${data['status']} - ${data['error_message'] ?? 'Unknown error'}');
    }

    if (data['routes'] == null || (data['routes'] as List).isEmpty) {
      throw Exception('No routes returned from API');
    }

    final route = data['routes'][0];
    final leg = route['legs'][0];

    return RouteResult(
      polylinePoints: _decodePolyline(route['overview_polyline']['points']),
      distanceText: leg['distance']['text'],
      distanceValue: leg['distance']['value'],
      durationText: leg['duration']['text'],
      durationValue: leg['duration']['value'],
      bounds: _parseBounds(route['bounds']),
    );
  }

  List<LatLng> _decodePolyline(String polyline) {
    return decodePolyline(polyline)
        .map((point) => LatLng(point[0].toDouble(), point[1].toDouble()))
        .toList();
  }

  LatLngBounds _parseBounds(Map<String, dynamic> bounds) {
    return LatLngBounds(
      northeast: LatLng(bounds['northeast']['lat'], bounds['northeast']['lng']),
      southwest: LatLng(bounds['southwest']['lat'], bounds['southwest']['lng']),
    );
  }
}

class RouteResult {
  final List<LatLng> polylinePoints;
  final String distanceText;
  final int distanceValue;
  final String durationText;
  final int durationValue;
  final LatLngBounds bounds;

  RouteResult({
    required this.polylinePoints,
    required this.distanceText,
    required this.distanceValue,
    required this.durationText,
    required this.durationValue,
    required this.bounds,
  });

  Polyline toPolyline({String polylineId = 'route', Color color = Colors.blue}) {
    return Polyline(
      polylineId: PolylineId(polylineId),
      points: polylinePoints,
      color: color,
      width: 5,
    );
  }
}