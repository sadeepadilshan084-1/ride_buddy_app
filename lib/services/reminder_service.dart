import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_models.dart';

class ReminderService {
  static final ReminderService _instance = ReminderService._internal();
  late final SupabaseClient _supabase;

  static const String remindersTable = 'reminders';
  static const String notificationLogsTable = 'notification_logs';

  factory ReminderService() {
    return _instance;
  }

  ReminderService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // CREATE REMINDER
  // ============================================

  /// Create a new reminder
  Future<ReminderModel> createReminder({
    required String userId,
    required ReminderType reminderType,
    required String title,
    required DateTime expiryDate,
    String? vehicleId,
    String? description,
    List<int> notificationDaysBefore = const [7, 1, 0],
    ReminderFrequency frequency = ReminderFrequency.yearly,
    String? reminderPhoneNumber,
  }) async {
    try {
      final now = DateTime.now();
      
      // Calculate next notification date
      DateTime? nextNotificationDate;
      
      for (final daysOffset in notificationDaysBefore) {
        final notificationDate = expiryDate.subtract(Duration(days: daysOffset));
        if (notificationDate.isAfter(now)) {
          nextNotificationDate = notificationDate;
          break;
        }
      }

      final response = await _supabase.from(remindersTable).insert({
        'user_id': userId,
        'vehicle_id': vehicleId,
        'reminder_type': reminderType.name,
        'title': title,
        'description': description,
        'expiry_date': expiryDate.toIso8601String().split('T')[0],
        'notification_days_before': notificationDaysBefore,
        'frequency': frequency.name,
        'reminder_phone_number': reminderPhoneNumber,
        'next_notification_date': nextNotificationDate?.toIso8601String().split('T')[0],
      }).select();

      if (response.isEmpty) throw Exception('Failed to create reminder');
      return ReminderModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error creating reminder: $e');
    }
  }

  // ============================================
  // READ REMINDERS
  // ============================================

  /// Get all reminders for a user
  Future<List<ReminderModel>> getUserReminders(String userId) async {
    try {
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('user_id', userId)
          .order('expiry_date', ascending: true);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching reminders: $e');
    }
  }

  /// Get reminders for a specific vehicle
  Future<List<ReminderModel>> getVehicleReminders(String vehicleId) async {
    try {
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('expiry_date', ascending: true);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching vehicle reminders: $e');
    }
  }

  /// Get upcoming reminders (active within next 30 days)
  Future<List<ReminderModel>> getUpcomingReminders(String userId) async {
    try {
      final thirtyDaysFromNow = DateTime.now().add(const Duration(days: 30));
      
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .lte('expiry_date', thirtyDaysFromNow.toIso8601String())
          .gt('expiry_date', DateTime.now().toIso8601String())
          .order('expiry_date', ascending: true);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching upcoming reminders: $e');
    }
  }

  /// Get expired reminders
  Future<List<ReminderModel>> getExpiredReminders(String userId) async {
    try {
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('user_id', userId)
          .eq('status', 'expired')
          .order('expiry_date', ascending: false);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching expired reminders: $e');
    }
  }

  /// Get a specific reminder by ID
  Future<ReminderModel?> getReminderById(String reminderId) async {
    try {
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('id', reminderId)
          .maybeSingle();

      return response != null ? ReminderModel.fromJson(response) : null;
    } catch (e) {
      throw Exception('Error fetching reminder: $e');
    }
  }

  // ============================================
  // UPDATE REMINDER
  // ============================================

  /// Update an existing reminder
  Future<ReminderModel> updateReminder(
    String reminderId, {
    String? title,
    String? description,
    DateTime? expiryDate,
    List<int>? notificationDaysBefore,
    ReminderFrequency? frequency,
    ReminderStatus? status,
    String? reminderPhoneNumber,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (title != null) updateData['title'] = title;
      if (description != null) updateData['description'] = description;
      if (expiryDate != null) {
        updateData['expiry_date'] = expiryDate.toIso8601String().split('T')[0];
        
        // Recalculate next notification date
        final now = DateTime.now();
        DateTime? nextNotificationDate;
        final days = notificationDaysBefore ?? [7, 1, 0];
        
        for (final daysOffset in days) {
          final notificationDate = expiryDate.subtract(Duration(days: daysOffset));
          if (notificationDate.isAfter(now)) {
            nextNotificationDate = notificationDate;
            break;
          }
        }
        
        updateData['next_notification_date'] = nextNotificationDate?.toIso8601String().split('T')[0];
      }
      if (notificationDaysBefore != null) updateData['notification_days_before'] = notificationDaysBefore;
      if (frequency != null) updateData['frequency'] = frequency.name;
      if (status != null) updateData['status'] = status.name;
      if (reminderPhoneNumber != null) updateData['reminder_phone_number'] = reminderPhoneNumber;
      
      updateData['updated_at'] = DateTime.now().toIso8601String();

      final response = await _supabase
          .from(remindersTable)
          .update(updateData)
          .eq('id', reminderId)
          .select();

      if (response.isEmpty) throw Exception('Failed to update reminder');
      return ReminderModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error updating reminder: $e');
    }
  }

  /// Mark reminder as completed
  Future<void> completeReminder(String reminderId) async {
    try {
      await updateReminder(reminderId, status: ReminderStatus.completed);
    } catch (e) {
      throw Exception('Error completing reminder: $e');
    }
  }

  /// Snooze a reminder (extend expiry date)
  Future<ReminderModel> snoozeReminder(String reminderId, int days) async {
    try {
      final reminder = await getReminderById(reminderId);
      if (reminder == null) throw Exception('Reminder not found');

      final newExpiryDate = reminder.expiryDate.add(Duration(days: days));
      return await updateReminder(reminderId, expiryDate: newExpiryDate);
    } catch (e) {
      throw Exception('Error snoozing reminder: $e');
    }
  }

  // ============================================
  // DELETE REMINDER
  // ============================================

  /// Delete a reminder
  Future<void> deleteReminder(String reminderId) async {
    try {
      await _supabase
          .from(remindersTable)
          .delete()
          .eq('id', reminderId);
    } catch (e) {
      throw Exception('Error deleting reminder: $e');
    }
  }

  // ============================================
  // NOTIFICATION MANAGEMENT
  // ============================================

  /// Log a notification
  Future<NotificationLogModel> logNotification({
    required String userId,
    required String reminderId,
    required NotificationType notificationType,
    required String title,
    required String message,
    int? daysBeforeExpiry,
    bool isDelivered = false,
    DeliveryStatus deliveryStatus = DeliveryStatus.pending,
    String? errorMessage,
  }) async {
    try {
      final response = await _supabase.from(notificationLogsTable).insert({
        'user_id': userId,
        'reminder_id': reminderId,
        'notification_type': notificationType.name,
        'title': title,
        'message': message,
        'days_before_expiry': daysBeforeExpiry,
        'is_delivered': isDelivered,
        'delivery_status': deliveryStatus.name,
        'error_message': errorMessage,
      }).select();

      if (response.isEmpty) throw Exception('Failed to log notification');
      return NotificationLogModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error logging notification: $e');
    }
  }

  /// Get notification logs for a user
  Future<List<NotificationLogModel>> getUserNotificationLogs(String userId) async {
    try {
      final response = await _supabase
          .from(notificationLogsTable)
          .select()
          .eq('user_id', userId)
          .order('sent_at', ascending: false);

      return (response as List)
          .map((n) => NotificationLogModel.fromJson(n))
          .toList();
    } catch (e) {
      throw Exception('Error fetching notification logs: $e');
    }
  }

  /// Get notification logs for a specific reminder
  Future<List<NotificationLogModel>> getReminderNotificationLogs(String reminderId) async {
    try {
      final response = await _supabase
          .from(notificationLogsTable)
          .select()
          .eq('reminder_id', reminderId)
          .order('sent_at', ascending: false);

      return (response as List)
          .map((n) => NotificationLogModel.fromJson(n))
          .toList();
    } catch (e) {
      throw Exception('Error fetching reminder notification logs: $e');
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationLogId) async {
    try {
      await _supabase
          .from(notificationLogsTable)
          .update({
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('id', notificationLogId);
    } catch (e) {
      throw Exception('Error marking notification as read: $e');
    }
  }

  /// Update notification delivery status
  Future<void> updateNotificationStatus(
    String notificationLogId, {
    required DeliveryStatus status,
    String? errorMessage,
  }) async {
    try {
      await _supabase
          .from(notificationLogsTable)
          .update({
            'delivery_status': status.name,
            'is_delivered': status == DeliveryStatus.sent,
            'error_message': errorMessage,
          })
          .eq('id', notificationLogId);
    } catch (e) {
      throw Exception('Error updating notification status: $e');
    }
  }

  // ============================================
  // DASHBOARD ANALYTICS
  // ============================================

  /// Get reminder statistics for a user
  Future<Map<String, dynamic>> getReminderStats(String userId) async {
    try {
      final reminders = await getUserReminders(userId);
      
      final active = reminders.where((r) => r.status == ReminderStatus.active).length;
      final expired = reminders.where((r) => r.status == ReminderStatus.expired).length;
      final completed = reminders.where((r) => r.status == ReminderStatus.completed).length;
      final upcoming = reminders.where((r) => r.isUpcoming).length;
      final urgent = reminders.where((r) => r.isUrgent).length;

      return {
        'total': reminders.length,
        'active': active,
        'expired': expired,
        'completed': completed,
        'upcoming': upcoming,
        'urgent': urgent,
        'by_type': {
          'license': reminders.where((r) => r.reminderType == ReminderType.license).length,
          'insurance': reminders.where((r) => r.reminderType == ReminderType.insurance).length,
          'service': reminders.where((r) => r.reminderType == ReminderType.service).length,
          'inspection': reminders.where((r) => r.reminderType == ReminderType.inspection).length,
          'pollution_check': reminders.where((r) => r.reminderType == ReminderType.pollutionCheck).length,
        }
      };
    } catch (e) {
      throw Exception('Error getting reminder stats: $e');
    }
  }

  // ============================================
  // SERVICE REMINDERS
  // ============================================

  /// Get service reminders for a vehicle (specific to service type)
  Future<List<ReminderModel>> getServiceReminders(String vehicleId) async {
    try {
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .eq('reminder_type', 'service')
          .order('expiry_date', ascending: true);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching service reminders: $e');
    }
  }

  /// Get service reminders due soon (within next 30 days)
  Future<List<ReminderModel>> getServiceRemindersDueSoon(String vehicleId) async {
    try {
      final thirtyDaysFromNow = DateTime.now().add(const Duration(days: 30));
      
      final response = await _supabase
          .from(remindersTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .eq('reminder_type', 'service')
          .eq('status', 'active')
          .lte('expiry_date', thirtyDaysFromNow.toIso8601String())
          .gt('expiry_date', DateTime.now().toIso8601String())
          .order('expiry_date', ascending: true);

      return (response as List)
          .map((r) => ReminderModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching due soon service reminders: $e');
    }
  }

  /// Create service reminder with mileage-based notification
  Future<ReminderModel> createServiceReminder({
    required String userId,
    required String vehicleId,
    required String serviceType,
    required DateTime reminderDate,
    required int mileageThreshold,
    int reminderBeforeKm = 250,
    String? notes,
  }) async {
    try {
      // Convert km threshold to days offset for notifications
      // Assuming average 50km/day, 250km = 5 days
      final daysOffset = (reminderBeforeKm / 50).toInt().clamp(1, 30);
      
      final notificationDaysBefore = [daysOffset, 1, 0];

      final response = await _supabase.from(remindersTable).insert({
        'user_id': userId,
        'vehicle_id': vehicleId,
        'reminder_type': 'service',
        'title': serviceType,
        'description': 'Service due at $mileageThreshold km${notes != null ? ' - $notes' : ''}',
        'expiry_date': reminderDate.toIso8601String().split('T')[0],
        'notification_days_before': notificationDaysBefore,
        'frequency': 'yearly',
        'status': 'active',
      }).select();

      if (response.isEmpty) throw Exception('Failed to create service reminder');
      return ReminderModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error creating service reminder: $e');
    }
  }

  /// Check mileage-based service reminders
  Future<Map<String, dynamic>> checkMileageBasedReminders(
    String vehicleId,
    double currentMileage,
  ) async {
    try {
      final serviceReminders = await getServiceReminders(vehicleId);
      
      final dueReminders = <ReminderModel>[];
      final upcomingReminders = <ReminderModel>[];

      for (final reminder in serviceReminders) {
        if (reminder.status != ReminderStatus.active) continue;

        // Extract mileage from description (format: "Service at XXXX km")
        final mileageRegex = RegExp(r'(\d+)\s*km');
        final match = mileageRegex.firstMatch(reminder.description ?? '');
        
        if (match != null) {
          final serviceMileage = int.parse(match.group(1)!);
          final remainingKm = serviceMileage - currentMileage.toInt();

          if (remainingKm <= 0) {
            dueReminders.add(reminder);
          } else if (remainingKm <= 500) {
            upcomingReminders.add(reminder);
          }
        }
      }

      return {
        'due': dueReminders,
        'upcoming': upcomingReminders,
        'dueCount': dueReminders.length,
        'upcomingCount': upcomingReminders.length,
      };
    } catch (e) {
      print('Error checking mileage-based reminders: $e');
      return {
        'due': [],
        'upcoming': [],
        'dueCount': 0,
        'upcomingCount': 0,
      };
    }
  }
}

