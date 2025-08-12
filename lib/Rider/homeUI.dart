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
    required VoidCallback onRequestDelivery,
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _buildCurrentRideSection(
                key: ValueKey(currentRideRequest!['id']),
                context: context,
                currentRideRequest: currentRideRequest,
                isUpdatingRideStatus: isUpdatingRideStatus,
                onMarkRideCompleted: onMarkRideCompleted,
                onCancelRide: onCancelRide,
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Quick Actions (only show if no current ride)
          if (currentRideRequest == null) ...[
            _buildQuickActionsSection(
              context: context,
              onRequestRide: onRequestRide,
              onRequestDelivery: onRequestDelivery,
            ),
            const SizedBox(height: 20),
          ],

          // Recent Trips Section
          _buildRecentTripsSection(
            context: context,
            recentTrips: recentTrips,
            onViewRideHistory: onViewRideHistory,
          ),

          const SizedBox(height: 20),

          // Quick Stats
          _buildQuickStatsSection(recentTrips: recentTrips),
        ],
      ),
    );
  }

  static Widget _buildCurrentRideSection({
    Key? key,
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
    String statusTitle;
    String statusSubtitle;

    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.hourglass_empty;
        statusTitle = 'Finding Driver';
        statusSubtitle = 'Looking for available drivers nearby...';
        break;
      case 'accepted':
        statusColor = Colors.blue;
        statusIcon = Icons.check_circle_outline;
        statusTitle = 'Driver Assigned';
        statusSubtitle = 'Your driver is on the way to pick you up';
        break;
      case 'in_progress':
        statusColor = Colors.green;
        statusIcon = Icons.directions_car;
        statusTitle = 'Ride in Progress';
        statusSubtitle = 'You are currently on your way';
        break;
      case 'declined':
        statusColor = Colors.red;
        statusIcon = Icons.cancel_outlined;
        statusTitle = 'Finding New Driver';
        statusSubtitle = 'Previous driver declined, finding another...';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.info_outline;
        statusTitle = 'Ride Status';
        statusSubtitle = 'Status unknown';
    }

    return Container(
      key: key,
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
          // Header with animated status
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    statusIcon,
                    key: ValueKey(statusIcon),
                    color: statusColor,
                    size: 24,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        statusTitle,
                        key: ValueKey(statusTitle),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: Text(
                        statusSubtitle,
                        key: ValueKey(statusSubtitle),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    status.toUpperCase(),
                    key: ValueKey(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Real-time loading indicator for pending/declined status
          if (status == 'pending' || status == 'declined') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status == 'pending'
                          ? 'Searching for nearby drivers...'
                          : 'Finding another driver...',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[700],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Driver Information (only show when driver is assigned)
          if (driverData != null && (status == 'accepted' || status == 'in_progress')) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.blue,
                        child: Text(
                          driverData['full_name']?[0]?.toUpperCase() ?? 'D',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverData['full_name'] ?? 'Unknown Driver',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Your Driver',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.call, color: Colors.blue),
                        onPressed: () {
                          // Call driver functionality
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
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
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                        : const Icon(Icons.check_circle),
                    label: const Text('Mark as Completed'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              if (status == 'pending' || status == 'accepted' || status == 'declined') ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isUpdatingRideStatus ? null : onCancelRide,
                    icon: isUpdatingRideStatus
                        ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    )
                        : const Icon(Icons.cancel),
                    label: const Text('Cancel Ride'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
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
    required VoidCallback onRequestDelivery,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.directions_car,
                title: 'Request Ride',
                subtitle: 'Get a ride to your destination',
                color: Colors.blue,
                onTap: onRequestRide,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildActionCard(
                icon: Icons.local_shipping,
                title: 'Delivery',
                subtitle: 'Send or receive packages',
                color: Colors.orange,
                onTap: onRequestDelivery,
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildRecentTripsSection({
    required BuildContext context,
    required List<Map<String, dynamic>> recentTrips,
    required VoidCallback onViewRideHistory,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Recent Trips',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            if (recentTrips.isNotEmpty)
              TextButton(
                onPressed: onViewRideHistory,
                child: const Text('View All'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (recentTrips.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.history,
                  size: 48,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No recent trips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your completed trips will appear here',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          )
        else
          ...recentTrips.take(3).map((trip) => _buildTripCard(trip)),
      ],
    );
  }

  static Widget _buildTripCard(Map<String, dynamic> trip) {
    final pickupAddress = trip['pickup_address'] as String?;
    final destinationAddress = trip['destination_address'] as String?;
    final completedAt = trip['completed_at'] as String?;
    final estimatedDistance = trip['estimated_distance'] as String?;
    final driverData = trip['driver'] as Map<String, dynamic>?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Trip Completed',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (completedAt != null)
                Text(
                  _formatDateTime(completedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            icon: Icons.my_location_outlined,
            label: 'From',
            value: pickupAddress ?? 'Unknown location',
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            icon: Icons.location_on_outlined,
            label: 'To',
            value: destinationAddress ?? 'Unknown destination',
          ),
          if (estimatedDistance != null || driverData != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                if (estimatedDistance != null) ...[
                  Icon(
                    Icons.straighten_outlined,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    estimatedDistance,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
                if (estimatedDistance != null && driverData != null) ...[
                  const SizedBox(width: 16),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(width: 16),
                ],
                if (driverData != null) ...[
                  Icon(
                    Icons.person_outline,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    driverData['full_name'] ?? 'Unknown driver',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Widget _buildQuickStatsSection({
    required List<Map<String, dynamic>> recentTrips,
  }) {
    if (recentTrips.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Stats',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  icon: Icons.directions_car,
                  label: 'Total Trips',
                  value: recentTrips.length.toString(),
                  color: Colors.blue,
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey[200],
              ),
              Expanded(
                child: _buildStatItem(
                  icon: Icons.access_time,
                  label: 'This Month',
                  value: _getThisMonthTrips(recentTrips).toString(),
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(
          icon,
          color: color,
          size: 24,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
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
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[600],
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[800],
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _formatDateTime(String dateTimeString) {
    try {
      final dateTime = DateTime.parse(dateTimeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays == 0) {
        return DateFormat('HH:mm').format(dateTime);
      } else if (difference.inDays == 1) {
        return 'Yesterday ${DateFormat('HH:mm').format(dateTime)}';
      } else if (difference.inDays < 7) {
        return DateFormat('EEE HH:mm').format(dateTime);
      } else {
        return DateFormat('MMM dd, HH:mm').format(dateTime);
      }
    } catch (e) {
      return 'Invalid date';
    }
  }

  static int _getThisMonthTrips(List<Map<String, dynamic>> trips) {
    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month, 1);
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    return trips.where((trip) {
      final completedAt = trip['completed_at'] as String?;
      if (completedAt == null) return false;

      try {
        final dateTime = DateTime.parse(completedAt);
        return dateTime.isAfter(thisMonth) && dateTime.isBefore(nextMonth);
      } catch (e) {
        return false;
      }
    }).length;
  }
}