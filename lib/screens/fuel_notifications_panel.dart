import 'package:flutter/material.dart';
import '../services/advanced_fuel_tracker_service.dart';

class FuelNotificationsPanel extends StatefulWidget {
  final String vehicleId;
  final Function onRefresh;

  const FuelNotificationsPanel({
    Key? key,
    required this.vehicleId,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<FuelNotificationsPanel> createState() => _FuelNotificationsPanelState();
}

class _FuelNotificationsPanelState extends State<FuelNotificationsPanel> {
  late AdvancedFuelTrackerService _service;
  List<NotificationEvent> _notifications = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _service = AdvancedFuelTrackerService();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() => _isLoading = true);
    try {
      final notifications = await _service.getUnreadNotifications(
        widget.vehicleId,
      );
      setState(() {
        _notifications = notifications;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading notifications: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _markAsRead(NotificationEvent notification) async {
    try {
      await _service.markNotificationAsRead(notification.id);
      setState(() {
        _notifications.removeWhere((n) => n.id == notification.id);
      });
    } catch (e) {
      print('Error marking as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_notifications.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'No notifications',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: _notifications.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final notification = _notifications[index];
        return _buildNotificationCard(notification);
      },
    );
  }

  Widget _buildNotificationCard(NotificationEvent notification) {
    IconData icon;
    Color color;

    switch (notification.type) {
      case 'low_fuel':
        icon = Icons.local_gas_station;
        color = Colors.red;
        break;
      case 'service_due':
        icon = Icons.construction;
        color = Colors.orange;
        break;
      case 'price_spike':
        icon = Icons.trending_up;
        color = Colors.amber;
        break;
      default:
        icon = Icons.notifications;
        color = Colors.blue;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.message,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatTime(notification.createdAt),
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _markAsRead(notification),
              icon: const Icon(Icons.clear, size: 20),
              color: Colors.grey,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }
}
