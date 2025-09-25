// rider_home_ui.dart
import 'package:flutter/material.dart';
import 'package:kabanza/utils/LocationUpdater.dart';
import 'package:intl/intl.dart';

class RiderHomeUI {
  static AppBar buildAppBar({
    required BuildContext context,
    required Map<String, dynamic>? userProfile,
    required bool isLocationLoading,
    required LocationUpdater locationUpdater,
    required VoidCallback onForceLocationUpdate,
    required VoidCallback onProfileSelected,
    required VoidCallback onSettingsSelected,
    required VoidCallback onLogoutSelected,
  }) {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Hello, ${userProfile?['full_name']?.split(' ')[0] ?? 'Rider'}!',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              if (isLocationLoading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const Text(
            'Where are you going today?',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            locationUpdater.isRunning
                ? Icons.location_on_outlined
                : Icons.location_off_outlined,
            color: locationUpdater.isRunning ? Colors.green : Colors.red,
          ),
          onPressed: onForceLocationUpdate,
          tooltip: locationUpdater.isRunning
              ? 'Location sharing active - Tap to update'
              : 'Location sharing inactive - Tap to start',
        ),
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          onPressed: () {
            // Navigate to notifications
          },
        ),
        PopupMenuButton<String>(
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: Theme.of(context).primaryColor,
            child: Text(
              userProfile?['full_name']?[0]?.toUpperCase() ?? 'R',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          onSelected: (value) {
            switch (value) {
              case 'profile':
                onProfileSelected();
                break;
              case 'settings':
                onSettingsSelected();
                break;
              case 'logout':
                onLogoutSelected();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'profile',
              child: Row(
                children: [
                  Icon(Icons.person_outline),
                  SizedBox(width: 8),
                  Text('Profile'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'settings',
              child: Row(
                children: [
                  Icon(Icons.settings_outlined),
                  SizedBox(width: 8),
                  Text('Settings'),
                ],
              ),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Logout', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget buildBody({
    required BuildContext context,
    required Map<String, dynamic>? currentRideRequest,
    required List<Map<String, dynamic>> recentTrips,
    required bool isUpdatingRideStatus,
    required VoidCallback onRequestRide,
    required VoidCallback onViewRideHistory,
    required VoidCallback onMarkRideCompleted,
    required VoidCallback onCancelRide,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current Ride Request Section
          if (currentRideRequest != null) ...[
            _buildCurrentRideSection(
              context: context,
              currentRideRequest: currentRideRequest,
              isUpdatingRideStatus: isUpdatingRideStatus,
              onMarkRideCompleted: onMarkRideCompleted,
              onCancelRide: onCancelRide,
            ),
            const SizedBox(height: 20),
          ],

          // Quick Actions (only show if no current ride)
          if (currentRideRequest == null) ...[
            _buildQuickActionsSection(
              context: context,
              onRequestRide: onRequestRide,
            ),
            const SizedBox(height: 20),
          ],

          // Recent Trips Section
          _buildRecentTripsSection(
            context: context,
            recentTrips: recentTrips,
            onViewRideHistory: onViewRideHistory,
          ),
        ],
      ),
    );
  }

  static Widget _buildCurrentRideSection({
    required BuildContext context,
    required Map<String, dynamic> currentRideRequest,
    required bool isUpdatingRideStatus,
    required VoidCallback onMarkRideCompleted,
    required VoidCallback onCancelRide,
  }) {
    final status = currentRideRequest['status'] as String;
    final driverData = currentRideRequest['driver'] as Map<String, dynamic>?;
    final createdAt = currentRideRequest['created_at'] as String?;
    final estimatedDistance = currentRideRequest['estimated_distance'] as String?;
    final pickupAddress = currentRideRequest['pickup_address'] as String?;
    final destinationAddress = currentRideRequest['destination_address'] as String?;

    Color statusColor;
    IconData statusIcon;

    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        break;
      case 'accepted':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle_outline;
        break;
      case 'in_progress':
        statusColor = Colors.green;
        statusIcon = Icons.directions_car;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info_outline;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.1),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 24),
              const SizedBox(width: 8),
              Text(
                'Current Ride',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Driver Information (Phone number removed for security)
          if (driverData != null) ...[
            _buildInfoRow(
              icon: Icons.person_outline,
              label: 'Driver',
              value: driverData['full_name'] ?? 'Unknown Driver',
            ),
            const SizedBox(height: 12),
          ],

          // Trip Details
          _buildInfoRow(
            icon: Icons.my_location_outlined,
            label: 'Pickup Location',
            value: pickupAddress ?? 'Location not available',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'Destination',
            value: destinationAddress ?? 'Destination not available',
          ),
          const SizedBox(height: 8),
          if (estimatedDistance != null) ...[
            _buildInfoRow(
              icon: Icons.straighten_outlined,
              label: 'Distance',
              value: estimatedDistance,
            ),
            const SizedBox(height: 8),
          ],
          if (createdAt != null) ...[
            _buildInfoRow(
              icon: Icons.schedule_outlined,
              label: 'Requested At',
              value: _formatDateTime(createdAt),
            ),
            const SizedBox(height: 16),
          ],

          // Action Buttons
          Row(
            children: [
              if (status == 'in_progress') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isUpdatingRideStatus ? null : onMarkRideCompleted,
                    icon: isUpdatingRideStatus
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.check_circle),
                    label: const Text('Mark as Completed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              if (status == 'pending' || status == 'accepted') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: isUpdatingRideStatus ? null : onCancelRide,
                    icon: isUpdatingRideStatus
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                        : const Icon(Icons.cancel),
                    label: const Text('Cancel Ride'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildQuickActionsSection({
    required BuildContext context,
    required VoidCallback onRequestRide,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: _buildQuickActionCard(
              icon: Icons.local_taxi,
              title: 'Book Ride',
              subtitle: 'Get a ride now',
              color: Theme.of(context).primaryColor,
              onTap: onRequestRide,
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildRecentTripsSection({
    required BuildContext context,
    required List<Map<String, dynamic>> recentTrips,
    required VoidCallback onViewRideHistory,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Recent Trips',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              TextButton(
                onPressed: onViewRideHistory,
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (recentTrips.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'No recent trips yet',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ...recentTrips.take(3).map((trip) {
              final index = recentTrips.indexOf(trip);
              return Column(
                children: [
                  if (index > 0) const Divider(height: 24),
                  _buildRecentTripItem(trip),
                ],
              );
            }).toList(),
        ],
      ),
    );
  }

  static Widget _buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildRecentTripItem(Map<String, dynamic> trip) {
    final pickupAddress = trip['pickup_address'] as String?;
    final destinationAddress = trip['destination_address'] as String?;
    final completedAt = trip['completed_at'] as String?;
    final actualFare = trip['actual_fare'];
    final driverData = trip['driver'] as Map<String, dynamic>?;

    String route = 'Unknown Route';
    if (pickupAddress != null && destinationAddress != null) {
      route = '${_truncateAddress(pickupAddress)} → ${_truncateAddress(destinationAddress)}';
    }

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                completedAt != null ? _formatDateTime(completedAt) : 'Unknown date',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              if (driverData != null)
                Text(
                  'Driver: ${driverData['full_name'] ?? 'Unknown'}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        Text(
          actualFare != null ? 'MK ${actualFare.toString()}' : 'N/A',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  static Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid date';
    }
  }

  static String _truncateAddress(String address) {
    if (address.length > 20) {
      return '${address.substring(0, 20)}...';
    }
    return address;
  }
}