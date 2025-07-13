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
      });

      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return _parseRouteResponse(json.decode(response.body));
      }
      return null;
    } catch (e) {
      print('Route error: $e');
      return null;
    }
  }

  RouteResult _parseRouteResponse(Map<String, dynamic> data) {
    if (data['status'] != 'OK') throw Exception('Directions API error');

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