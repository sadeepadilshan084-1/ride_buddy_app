import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_models.dart';

class DatabaseMigrationService {
  static final DatabaseMigrationService _instance = DatabaseMigrationService._internal();
  late final SupabaseClient _supabase;

  factory DatabaseMigrationService() {
    return _instance;
  }

  DatabaseMigrationService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // USER INITIALIZATION
  // ============================================

  /// Initialize user profile after auth signup
  Future<UserModel> initializeUserProfile({
    required String userId,
    required String email,
    String? fullName,
    String? phone,
    String? fcmToken,
  }) async {
    try {
      final response = await _supabase.from('users').insert({
        'auth_id': userId,
        'email': email,
        'full_name': fullName ?? 'User',
        'phone': phone,
        'fcm_token': fcmToken,
        'notification_enabled': true,
      }).select();

      if (response.isEmpty) throw Exception('Failed to create user');
      return UserModel.fromJson(response.first);
    } catch (e) {
      // User might already exist
      try {
        final existingResponse = await _supabase
            .from('users')
            .select()
            .eq('auth_id', userId)
            .single();
        return UserModel.fromJson(existingResponse);
      } catch (e) {
        throw Exception('Error initializing user: $e');
      }
    }
  }

  // ============================================
  // DEFAULT DATA INITIALIZATION
  // ============================================

  /// Initialize default reminder templates for a user
  Future<void> initializeDefaultReminders(String userId) async {
    try {
      final defaultReminders = [
        {
          'user_id': userId,
          'reminder_type': 'license',
          'title': 'Driving License Renewal',
          'description': 'Time to renew your driving license',
          'expiry_date': DateTime.now().add(const Duration(days: 365)),
          'notification_days_before': [30, 7, 1],
          'frequency': 'yearly',
          'status': 'active',
        },
        {
          'user_id': userId,
          'reminder_type': 'insurance',
          'title': 'Vehicle Insurance Renewal',
          'description': 'Don\'t forget to renew your vehicle insurance',
          'expiry_date': DateTime.now().add(const Duration(days: 330)),
          'notification_days_before': [30, 7, 1],
          'frequency': 'yearly',
          'status': 'active',
        },
      ];

      for (final reminder in defaultReminders) {
        try {
          await _supabase.from('reminders').insert(reminder);
        } catch (e) {
          print('Error inserting default reminder: $e');
        }
      }
    } catch (e) {
      print('Error initializing default reminders: $e');
    }
  }

  // ============================================
  // EMERGENCY CONTACTS INITIAL SETUP
  // ============================================

  /// Initialize emergency contacts
  Future<void> initializeEmergencyContacts(
    String userId,
    List<Map<String, String>> contacts,
  ) async {
    try {
      for (int i = 0; i < contacts.length; i++) {
        final contact = contacts[i];
        await _supabase.from('emergency_contacts').insert({
          'user_id': userId,
          'contact_name': contact['name'],
          'phone_number': contact['phone'],
          'relationship': contact['relationship'],
          'is_primary': i == 0,
        });
      }
    } catch (e) {
      throw Exception('Error initializing emergency contacts: $e');
    }
  }

  // ============================================
  // VEHICLE INITIALIZATION
  // ============================================

  /// Initialize vehicle with default service settings
  Future<void> initializeVehicleServiceDetails(
    String vehicleId, {
    DateTime? lastServiceDate,
    double? lastServiceMileage,
    int serviceIntervalDays = 365,
    double serviceIntervalKm = 10000,
  }) async {
    try {
      final today = DateTime.now();
      final nextServiceDate = lastServiceDate != null
          ? lastServiceDate.add(Duration(days: serviceIntervalDays))
          : today.add(Duration(days: serviceIntervalDays));

      final nextServiceMileage = lastServiceMileage != null
          ? lastServiceMileage + serviceIntervalKm
          : serviceIntervalKm;

      await _supabase.from('vehicle_service_details').insert({
        'vehicle_id': vehicleId,
        'last_service_date': lastServiceDate?.toIso8601String().split('T')[0],
        'last_service_mileage': lastServiceMileage,
        'next_service_mileage': nextServiceMileage,
        'service_interval_days': serviceIntervalDays,
        'service_interval_km': serviceIntervalKm,
      });
    } catch (e) {
      print('Error initializing vehicle service details: $e');
    }
  }

  // ============================================
  // BULK OPERATIONS
  // ============================================

  /// Backup user data
  Future<Map<String, dynamic>> backupUserData(String userId) async {
    try {
      final reminders = await _supabase
          .from('reminders')
          .select()
          .eq('user_id', userId);

      final vehicles = await _supabase
          .from('vehicles')
          .select()
          .eq('user_id', userId);

      final services = await _supabase
          .from('service_history')
          .select('*')
          .inFilter('vehicle_id', (vehicles as List).map((v) => v['id']));

      final notifications = await _supabase
          .from('notification_logs')
          .select()
          .eq('user_id', userId);

      return {
        'user_id': userId,
        'backup_date': DateTime.now().toIso8601String(),
        'reminders': reminders,
        'vehicles': vehicles,
        'service_history': services,
        'notifications': notifications,
      };
    } catch (e) {
      throw Exception('Error backing up user data: $e');
    }
  }

  /// Clean up old notification logs (older than 90 days)
  Future<int> cleanupOldNotificationLogs(String userId, {int daysToKeep = 90}) async {
    try {
      final cutoffDate = DateTime.now()
          .subtract(Duration(days: daysToKeep))
          .toIso8601String()
          .split('T')[0];

      final response = await _supabase
          .from('notification_logs')
          .delete()
          .eq('user_id', userId)
          .lt('sent_at', cutoffDate);

      return response;
    } catch (e) {
      throw Exception('Error cleaning up notification logs: $e');
    }
  }

  /// Archive completed reminders
  Future<void> archiveCompletedReminders(String userId) async {
    try {
      await _supabase
          .from('reminders')
          .update({'status': 'archived'})
          .eq('user_id', userId)
          .eq('status', 'completed');
    } catch (e) {
      throw Exception('Error archiving reminders: $e');
    }
  }

  /// Export user data as JSON
  Future<String> exportUserDataAsJSON(String userId) async {
    try {
      final backup = await backupUserData(userId);
      // In production, convert to JSON string
      return backup.toString();
    } catch (e) {
      throw Exception('Error exporting data: $e');
    }
  }

  // ============================================
  // VALIDATION & HEALTH CHECK
  // ============================================

  /// Check database connection
  Future<bool> checkDatabaseConnection() async {
    try {
      final response = await _supabase.from('users').select().limit(1);
      return true;
    } catch (e) {
      print('Database connection error: $e');
      return false;
    }
  }

  /// Validate user data integrity
  Future<Map<String, dynamic>> validateUserIntegrity(String userId) async {
    try {
      final issues = <String>[];

      // Check if user exists
      final userData = await _supabase
          .from('users')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (userData == null) {
        issues.add('User profile not found');
        return {
          'is_valid': false,
          'issues': issues,
        };
      }

      // Check if user has at least one vehicle
      final vehicles = await _supabase
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .limit(1);

      if (vehicles.isEmpty) {
        issues.add('No vehicles found for user');
      }

      // Check for orphaned reminders (reminders without valid vehicles)
      if (vehicles.isNotEmpty) {
        final orphanedReminders = await _supabase
            .from('reminders')
            .select()
            .eq('user_id', userId)
            .notInFilter(
              'vehicle_id',
              (vehicles as List).map((v) => v['id']).toList(),
            );

        if (orphanedReminders.isNotEmpty) {
          issues.add(
            'Found ${orphanedReminders.length} orphaned reminders',
          );
        }
      }

      return {
        'is_valid': issues.isEmpty,
        'issues': issues,
        'last_checked': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error validating user integrity: $e');
    }
  }

  // ============================================
  // DATA STATISTICS
  // ============================================

  /// Get database statistics
  Future<Map<String, dynamic>> getDatabaseStatistics() async {
    try {
      final users = await _supabase.from('users').select().count(CountOption.exact);
      final vehicles = await _supabase.from('vehicles').select().count(CountOption.exact);
      final reminders = await _supabase.from('reminders').select().count(CountOption.exact);
      final serviceHistory = await _supabase
          .from('service_history')
          .select()
          .count(CountOption.exact);
      final notifications = await _supabase
          .from('notification_logs')
          .select()
          .count(CountOption.exact);

      return {
        'total_users': users.count,
        'total_vehicles': vehicles.count,
        'total_reminders': reminders.count,
        'total_service_records': serviceHistory.count,
        'total_notifications': notifications.count,
        'last_updated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error getting database statistics: $e');
    }
  }

  /// Get user statistics
  Future<Map<String, dynamic>> getUserStatistics(String userId) async {
    try {
      final reminders = await _supabase
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .count(CountOption.exact);

      final vehicles = await _supabase
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .count(CountOption.exact);

      final notifications = await _supabase
          .from('notification_logs')
          .select()
          .eq('user_id', userId)
          .count(CountOption.exact);

      return {
        'total_reminders': reminders.count,
        'total_vehicles': vehicles.count,
        'total_notifications': notifications.count,
      };
    } catch (e) {
      throw Exception('Error getting user statistics: $e');
    }
  }
}
