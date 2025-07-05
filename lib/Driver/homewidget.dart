import 'package:flutter/material.dart';

class DriverHomeWidgets {
  static Widget buildTodayStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  static Widget buildQuickActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
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
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget buildRecentTripItem(
      String route,
      String time,
      String rating,
      Color ratingColor,
      ) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.directions_car, color: Colors.blue),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                ),
              ),
              Text(
                time,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
        Text(
          rating,
          style: TextStyle(
            fontSize: 14,
            color: ratingColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  static Widget buildOnlineStatusToggle({
    required bool isOnline,
    required bool isLocationLoading,
    required VoidCallback onToggle,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isOnline
              ? [Colors.green[400]!, Colors.green[600]!]
              : [Colors.grey[400]!, Colors.grey[600]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (isOnline ? Colors.green : Colors.grey).withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.radio_button_checked : Icons.radio_button_off,
            color: Colors.white,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isOnline ? 'You\'re Online' : 'You\'re Offline',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  isOnline
                      ? 'Ready to accept ride requests'
                      : 'Tap to be available for booking',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isOnline,
            onChanged: (value) => onToggle(),
            activeColor: Colors.white,
            activeTrackColor: Colors.white30,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: Colors.white30,
          ),
        ],
      ),
    );
  }

  static AppBar buildDriverAppBar({
    required Map<String, dynamic>? userProfile,
    required bool isOnline,
    required bool isLocationLoading,
    required bool isLocationRunning,
    required String driverStatus,
    required VoidCallback onForceLocationUpdate,
    required Function(String) onMenuSelected,
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
                'Hi, ${userProfile?['full_name']?.split(' ')[0] ?? 'Driver'}!',
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
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? Colors.green : Colors.grey,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                driverStatus,
                style: TextStyle(
                  fontSize: 14,
                  color: isOnline ? Colors.green : Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (isLocationRunning) ...[
                const SizedBox(width: 8),
                const Icon(Icons.location_on, size: 14, color: Colors.green),
              ],
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isLocationRunning
                ? Icons.location_on_outlined
                : Icons.location_off_outlined,
            color: isLocationRunning ? Colors.green : Colors.red,
          ),
          onPressed: onForceLocationUpdate,
          tooltip: isLocationRunning
              ? 'Location sharing active'
              : 'Location sharing inactive',
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
            backgroundColor: Colors.blue, // You might want to pass theme color
            child: Text(
              userProfile?['full_name']?[0]?.toUpperCase() ?? 'D',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          onSelected: onMenuSelected,
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
              value: 'vehicle',
              child: Row(
                children: [
                  Icon(Icons.directions_car_outlined),
                  SizedBox(width: 8),
                  Text('Vehicle Info'),
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
}