import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'backend_models.dart';
import 'reminder_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  late final SupabaseClient _supabase;
  final ReminderService _reminderService = ReminderService();

  factory NotificationService() {
    return _instance;
  }

  NotificationService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // LOCAL NOTIFICATIONS & ALARMS SETUP (DISABLED)
  // ============================================

  /// Initialize local notifications plugin (Stub)
  Future<void> initializeLocalNotifications() async {
    print('Local notifications disabled');
  }

  // ============================================
  // SEND NOTIFICATIONS
  // ============================================

  /// Send test notification (Stub)
  Future<void> sendTestNotification({
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    print('Test notification (disabled): $title - $body');
  }

  // ============================================
  // LOCAL NOTIFICATION SCHEDULING (DISABLED)
  // ============================================

  /// Schedule a local reminder notification (Stub)
  Future<void> scheduleLocalReminderNotification({
    required int notificationId,
    required String title,
    required String description,
    required DateTime scheduledDate,
    String? sound = 'default',
    String? payload,
  }) async {
    print('Local reminder notification disabled: "$title"');
  }

  /// Schedule multiple advance notifications (Stub)
  Future<void> scheduleAdvanceReminders({
    required int reminderId,
    required String reminderTitle,
    required String reminderDescription,
    required DateTime expiryDate,
    List<int> daysBeforeList = const [30, 7, 1, 0],
  }) async {
    print('Advance reminders disabled for: $reminderTitle');
  }

  /// Schedule a daily recurring notification (Stub)
  Future<void> scheduleDailyNotification({
    required int notificationId,
    required String title,
    required String description,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    print('Daily notification disabled');
  }

  /// Show an immediate alarm notification (Stub)
  Future<void> showLocalAlarmNotification({
    required int notificationId,
    required String title,
    required String description,
    String? payload,
  }) async {
    print('Alarm notification disabled: $title');
  }

  /// Cancel a scheduled notification (Stub)
  Future<void> cancelNotification(int notificationId) async {
    print('Cancel notification (noop): $notificationId');
  }

  /// Cancel all scheduled notifications (Stub)
  Future<void> cancelAllNotifications() async {
    print('Cancel all notifications (noop)');
  }

  /// Get all pending notifications (Stub)
  Future<List<dynamic>> getPendingNotifications() async {
    return [];
  }

  /// Schedule notification for reminder (Stub)
  Future<void> scheduleReminderNotification({
    required String reminderId,
    required String userId,
    required String reminderTitle,
    required int daysBeforeExpiry,
    required DateTime expiryDate,
    String? reminderPhoneNumber,
    bool useLocalNotification = true,
  }) async {
    print('Reminder notification disabled for: $reminderTitle');
  }

  /// Send immediate reminder notification
  Future<void> sendImmediateReminderNotification({
    required String reminderId,
    required String userId,
    required String reminderTitle,
    required int daysBeforeExpiry,
    String? reminderType,
  }) async {
    try {
      String messageBody = '';
      if (daysBeforeExpiry > 0) {
        messageBody = '$reminderTitle expires in $daysBeforeExpiry days';
      } else if (daysBeforeExpiry == 0) {
        messageBody = '$reminderTitle expires today!';
      } else {
        messageBody = '$reminderTitle has expired';
      }

      // Log the notification to database even if push/local is disabled
      await _reminderService.logNotification(
        userId: userId,
        reminderId: reminderId,
        notificationType: NotificationType.push,
        title: 'Reminder: $reminderTitle',
        message: messageBody,
        daysBeforeExpiry: daysBeforeExpiry,
        isDelivered: true,
        deliveryStatus: DeliveryStatus.sent,
      );

      print('Notification logged: $messageBody');
    } catch (e) {
      print('Error logging immediate notification: $e');
      rethrow;
    }
  }

  // ============================================
  // SERVICE NOTIFICATION
  // ============================================

  /// Send service due notification
  Future<void> sendServiceDueNotification({
    required String userId,
    required String vehicleNumber,
    required double? kmRemaining,
    required int? daysRemaining,
    required String urgency,
  }) async {
    try {
      String title = 'Service Due for $vehicleNumber';
      String body = '';

      if (urgency == 'critical') {
        title = '⚠️ URGENT: Service Overdue for $vehicleNumber';
        body = 'Your vehicle service is overdue!';
      } else if (urgency == 'high') {
        title = '🔔 Service Due Soon for $vehicleNumber';
        if (kmRemaining != null) {
          body = 'Service due in ${kmRemaining.toStringAsFixed(0)} km';
        } else if (daysRemaining != null) {
          body = 'Service due in $daysRemaining days';
        }
      } else {
        if (kmRemaining != null) {
          body = 'Service scheduled in ${kmRemaining.toStringAsFixed(0)} km';
        } else if (daysRemaining != null) {
          body = 'Service scheduled in $daysRemaining days';
        }
      }

      // Log notification
      await _reminderService.logNotification(
        userId: userId,
        reminderId: vehicleNumber, // Using vehicle number as reference
        notificationType: NotificationType.push,
        title: title,
        message: body,
        isDelivered: true,
        deliveryStatus: DeliveryStatus.sent,
      );

      print('Service notification logged: $title - $body');
    } catch (e) {
      throw Exception('Error logging service notification: $e');
    }
  }

  // ============================================
  // BATCH NOTIFICATION PROCESSING
  // ============================================

  /// Process all pending reminders and log notifications
  Future<void> processPendingReminders(String userId) async {
    try {
      final reminders = await _reminderService.getUserReminders(userId);

      for (final reminder in reminders) {
        if (reminder.status != ReminderStatus.active) continue;

        final now = DateTime.now();
        final daysUntilExpiry = reminder.expiryDate.difference(now).inDays;

        // Check if any notifications are due
        for (final daysOffset in reminder.notificationDaysBefore) {
          if (daysUntilExpiry == daysOffset) {
            await sendImmediateReminderNotification(
              reminderId: reminder.id,
              userId: userId,
              reminderTitle: reminder.title,
              daysBeforeExpiry: daysOffset,
              reminderType: reminder.reminderType.name,
            );
          }
        }
      }
    } catch (e) {
      throw Exception('Error processing pending reminders: $e');
    }
  }

  /// Get unread notification count
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final response = await _supabase
          .from('notification_logs')
          .select()
          .eq('user_id', userId)
          .isFilter('read_at', true)
          .count(CountOption.exact);

      return response.count;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // ============================================
  // NOTIFICATION PREFERENCES
  // ============================================

  /// Update user notification preferences
  Future<void> updateNotificationPreferences(
    String userId, {
    required bool enabled,
  }) async {
    try {
      await _supabase.from('users').update({
        'notification_enabled': enabled,
      }).eq('id', userId);
    } catch (e) {
      throw Exception('Error updating notification preferences: $e');
    }
  }

  /// Subscribe to reminder type notifications (Stub)
  Future<void> subscribeToReminderType(String reminderType) async {
    print('Subscribe to topic disabled');
  }

  /// Unsubscribe from reminder type notifications (Stub)
  Future<void> unsubscribeFromReminderType(String reminderType) async {
    print('Unsubscribe from topic disabled');
  }

  // ============================================
  // NOTIFICATION ANALYTICS
  // ============================================

  /// Get notification statistics for a user
  Future<Map<String, dynamic>> getNotificationStats(String userId) async {
    try {
      final response = await _supabase
          .from('notification_logs')
          .select()
          .eq('user_id', userId);

      if (response.isEmpty) {
        return {
          'total': 0,
          'sent': 0,
          'delivered': 0,
          'failed': 0,
          'unread': 0,
        };
      }

      final logs = response as List<dynamic>;
      final sent = logs.where((l) => l['delivery_status'] == 'sent').length;
      final delivered = logs.where((l) => l['is_delivered'] == true).length;
      final failed = logs.where((l) => l['delivery_status'] == 'failed').length;
      final unread = logs.where((l) => l['read_at'] == null).length;

      return {
        'total': logs.length,
        'sent': sent,
        'delivered': delivered,
        'failed': failed,
        'unread': unread,
        'delivery_rate': logs.isEmpty ? 0 : (delivered / logs.length * 100).toStringAsFixed(2),
      };
    } catch (e) {
      throw Exception('Error getting notification stats: $e');
    }
  }
}
