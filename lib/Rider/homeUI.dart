// rider_home_ui.dart
import 'package:flutter/material.dart';
import 'package:kabanza/utils/LocationUpdater.dart';

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
    required VoidCallback onRequestRide,
    required VoidCallback onRequestDelivery,
    required VoidCallback onViewRideHistory,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Quick Actions
          _buildQuickActionsSection(
            context: context,
            onRequestRide: onRequestRide,
            onRequestDelivery: onRequestDelivery,
          ),

          const SizedBox(height: 20),

          // Recent Activity
          _buildRecentTripsSection(
            context: context,
            onViewRideHistory: onViewRideHistory,
          ),

          const SizedBox(height: 20),

          // Quick Stats
          _buildQuickStatsSection(),
        ],
      ),
    );
  }

  static Widget _buildQuickActionsSection({
    required BuildContext context,
    required VoidCallback onRequestRide,
    required VoidCallback onRequestDelivery,
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
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.local_taxi,
                  title: 'Book Ride',
                  subtitle: 'Get a ride now',
                  color: Theme.of(context).primaryColor,
                  onTap: onRequestRide,  // This will use the updated _requestRide method
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.delivery_dining,
                  title: 'Delivery',
                  subtitle: 'Send packages',
                  color: Colors.orange,
                  onTap: onRequestDelivery,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _buildRecentTripsSection({
    required BuildContext context,
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
          _buildRecentTripItem(
            'Home to Office',
            'Jan 15, 2024',
            '\$12.50',
            Icons.work_outline,
          ),
          const Divider(height: 24),
          _buildRecentTripItem(
            'Mall to Restaurant',
            'Jan 14, 2024',
            '\$8.75',
            Icons.restaurant_outlined,
          ),
          const Divider(height: 24),
          _buildRecentTripItem(
            'Airport Transfer',
            'Jan 12, 2024',
            '\$25.00',
            Icons.flight_outlined,
          ),
        ],
      ),
    );
  }

  static Widget _buildQuickStatsSection() {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            'Total Trips',
            '24',
            Icons.directions_car_outlined,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            'Money Saved',
            '\$180',
            Icons.savings_outlined,
            Colors.green,
          ),
        ),
      ],
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildRecentTripItem(String route, String date, String amount, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: Colors.grey[600], size: 20),
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
              ),
              Text(
                date,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Text(
          amount,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  static Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}