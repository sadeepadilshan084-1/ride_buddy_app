import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_models.dart';
import 'reminder_service.dart';
import 'vehicle_service_manager.dart';
import 'notification_service.dart';

class DashboardAnalyticsService {
  static final DashboardAnalyticsService _instance = DashboardAnalyticsService._internal();
  late final SupabaseClient _supabase;
  final ReminderService _reminderService = ReminderService();
  final VehicleServiceManager _serviceManager = VehicleServiceManager();
  final NotificationService _notificationService = NotificationService();

  factory DashboardAnalyticsService() {
    return _instance;
  }

  DashboardAnalyticsService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // DASHBOARD SUMMARY
  // ============================================

  /// Get comprehensive dashboard summary
  Future<Map<String, dynamic>> getDashboardSummary(String userId) async {
    try {
      final vehicles = await _getUserVehicles(userId);
      final reminderStats = await _reminderService.getReminderStats(userId);
      final notificationStats = await _notificationService.getNotificationStats(userId);
      final upcomingReminders = await _reminderService.getUpcomingReminders(userId);

      // Get service status for all vehicles
      final serviceStatuses = <Map<String, dynamic>>[];
      for (final vehicle in vehicles) {
        try {
          final isServiceDue =
              await _serviceManager.isServiceDue(vehicle.id, vehicle.currentMileage);
          final serviceAnalytics = await _serviceManager.getServiceAnalytics(vehicle.id);

          serviceStatuses.add({
            'vehicle_id': vehicle.id,
            'vehicle_number': vehicle.vehicleNumber,
            'is_service_due': isServiceDue['is_due'],
            'service_urgency': isServiceDue['urgency'],
            'km_until_service': isServiceDue['km_remaining'],
            'days_until_service': isServiceDue['days_remaining'],
            'last_service_date': serviceAnalytics['last_service_date'],
          });
        } catch (e) {
          print('Error getting service status for vehicle: $e');
        }
      }

      return {
        'user_id': userId,
        'total_vehicles': vehicles.length,
        'active_vehicles': vehicles.where((v) => v.isActive).length,
        'reminders': reminderStats,
        'notifications': notificationStats,
        'upcoming_reminders': upcomingReminders
            .take(5)
            .map((r) => {
                  'id': r.id,
                  'title': r.title,
                  'expiry_date': r.expiryDate,
                  'days_remaining': r.daysUntilExpiry,
                  'priority': r.isUrgent
                      ? 'urgent'
                      : r.isUpcoming
                          ? 'upcoming'
                          : 'normal',
                  'type': r.reminderType.name,
                })
            .toList(),
        'service_status': serviceStatuses,
        'critical_items': _getCriticalItems(upcomingReminders, serviceStatuses),
        'last_updated': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      throw Exception('Error getting dashboard summary: $e');
    }
  }

  /// Get vehicle summary
  Future<Map<String, dynamic>> getVehicleSummary(
    String userId,
    String vehicleId,
  ) async {
    try {
      final vehicle = await _getVehicleById(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final reminders = await _reminderService.getVehicleReminders(vehicleId);
      final serviceAnalytics = await _serviceManager.getServiceAnalytics(vehicleId);
      final isServiceDue = await _serviceManager.isServiceDue(
        vehicleId,
        vehicle.currentMileage,
      );
      final recentServices = await _serviceManager.getRecentServices(vehicleId);

      return {
        'vehicle_id': vehicleId,
        'vehicle_number': vehicle.vehicleNumber,
        'brand': vehicle.brand,
        'model': vehicle.model,
        'vehicle_type': vehicle.vehicleType,
        'current_mileage': vehicle.currentMileage,
        'fuel_type': vehicle.fuelType,
        'reminders': {
          'active': reminders.where((r) => r.status == ReminderStatus.active).length,
          'expired': reminders.where((r) => r.status == ReminderStatus.expired).length,
          'upcoming': reminders.where((r) => r.isUpcoming).length,
          'upcoming_list': reminders
              .where((r) => r.isUpcoming || r.isUrgent)
              .map((r) => {
                    'id': r.id,
                    'title': r.title,
                    'type': r.reminderType.name,
                    'expiry_date': r.expiryDate,
                    'days_remaining': r.daysUntilExpiry,
                  })
              .toList(),
        },
        'service': {
          'is_due': isServiceDue['is_due'],
          'urgency': isServiceDue['urgency'],
          'km_remaining': isServiceDue['km_remaining'],
          'days_remaining': isServiceDue['days_remaining'],
          'last_service_date': serviceAnalytics['last_service_date'],
          'recent_services': recentServices
              .take(3)
              .map((s) => {
                    'service_date': s.serviceDate,
                    'service_type': s.serviceType.name,
                    'cost': s.serviceCost,
                    'center': s.serviceCenter,
                  })
              .toList(),
        },
      };
    } catch (e) {
      throw Exception('Error getting vehicle summary: $e');
    }
  }

  // ============================================
  // ANALYTICS & STATISTICS
  // ============================================

  /// Get reminder frequency statistics
  Future<Map<String, dynamic>> getReminderFrequencyStats(String userId) async {
    try {
      final reminders = await _reminderService.getUserReminders(userId);

      final byType = <String, int>{};
      final byStatus = <String, int>{};

      for (final reminder in reminders) {
        // By type
        final typeKey = reminder.reminderType.name;
        byType[typeKey] = (byType[typeKey] ?? 0) + 1;

        // By status
        final statusKey = reminder.status.name;
        byStatus[statusKey] = (byStatus[statusKey] ?? 0) + 1;
      }

      return {
        'by_type': byType,
        'by_status': byStatus,
        'total': reminders.length,
      };
    } catch (e) {
      throw Exception('Error getting reminder frequency stats: $e');
    }
  }

  /// Get service cost analysis
  Future<Map<String, dynamic>> getServiceCostAnalysis(String userId) async {
    try {
      final vehicles = await _getUserVehicles(userId);
      double totalCost = 0;
      double avgCostPerVehicle = 0;

      final vehicleCosts = <Map<String, dynamic>>[];

      for (final vehicle in vehicles) {
        try {
          final costStats = await _serviceManager.getServiceCostStats(vehicle.id);
          final cost = costStats['total_cost'] as double? ?? 0;
          totalCost += cost;

          vehicleCosts.add({
            'vehicle_number': vehicle.vehicleNumber,
            'total_cost': cost,
            'average_cost': costStats['average_cost'],
            'total_services': costStats['total_services'],
          });
        } catch (e) {
          print('Error getting costs for vehicle: $e');
        }
      }

      if (vehicleCosts.isNotEmpty) {
        avgCostPerVehicle = totalCost / vehicleCosts.length;
      }

      return {
        'total_cost': totalCost,
        'average_cost_per_vehicle': avgCostPerVehicle,
        'vehicles': vehicleCosts,
        'cost_breakdown': _calculateMonthlyTrend(vehicleCosts),
      };
    } catch (e) {
      throw Exception('Error getting service cost analysis: $e');
    }
  }

  /// Get vehicle health status
  Future<Map<String, dynamic>> getVehicleHealthStatus(String vehicleId) async {
    try {
      final vehicle = await _getVehicleById(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final serviceDue = await _serviceManager.isServiceDue(
        vehicleId,
        vehicle.currentMileage,
      );
      final reminders = await _reminderService.getVehicleReminders(vehicleId);

      int healthScore = 100;

      // Reduce score based on overdue service
      if (serviceDue['is_due'] == true) {
        healthScore -= serviceDue['urgency'] == 'critical' ? 40 : 20;
      }

      // Reduce score based on expired reminders
      final expiredCount = reminders.where((r) => r.isExpired).length;
      healthScore -= (expiredCount * 5).clamp(0, 30);

      // Reduce score based on urgent reminders
      final urgentCount = reminders.where((r) => r.isUrgent && !r.isExpired).length;
      healthScore -= (urgentCount * 3).clamp(0, 20);

      healthScore = healthScore.clamp(0, 100);

      return {
        'vehicle_id': vehicleId,
        'health_score': healthScore,
        'status': healthScore >= 80
            ? 'good'
            : healthScore >= 60
                ? 'fair'
                : 'poor',
        'issues': [
          if (serviceDue['is_due'] == true)
            {'type': 'service_due', 'urgency': serviceDue['urgency']},
          if (expiredCount > 0) {'type': 'expired_reminders', 'count': expiredCount},
          if (urgentCount > 0) {'type': 'urgent_reminders', 'count': urgentCount},
        ],
      };
    } catch (e) {
      throw Exception('Error getting vehicle health: $e');
    }
  }

  // ============================================
  // HELPER FUNCTIONS
  // ============================================

  /// Get critical items that need immediate attention
  List<Map<String, dynamic>> _getCriticalItems(
    List<ReminderModel> upcomingReminders,
    List<Map<String, dynamic>> serviceStatuses,
  ) {
    final critical = <Map<String, dynamic>>[];

    // Add urgent reminders
    for (final reminder in upcomingReminders) {
      if (reminder.isUrgent || reminder.isExpired) {
        critical.add({
          'type': 'reminder',
          'title': reminder.title,
          'urgency': reminder.isExpired ? 'critical' : 'urgent',
          'days_remaining': reminder.daysUntilExpiry,
        });
      }
    }

    // Add overdue services
    for (final service in serviceStatuses) {
      if (service['service_urgency'] == 'critical') {
        critical.add({
          'type': 'service',
          'vehicle': service['vehicle_number'],
          'urgency': 'critical',
          'km_remaining': service['km_until_service'],
        });
      }
    }

    return critical;
  }

  /// Calculate monthly trend (placeholder for future analysis)
  Map<String, dynamic> _calculateMonthlyTrend(
    List<Map<String, dynamic>> vehicleCosts,
  ) {
    // This would integrate with actual monthly data from database
    return {
      'trend': 'stable',
      'variance': 0,
    };
  }

  /// Get user vehicles
  Future<List<VehicleModel>> _getUserVehicles(String userId) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .eq('is_active', true);

      return (response as List)
          .map((v) => VehicleModel.fromJson(v))
          .toList();
    } catch (e) {
      throw Exception('Error fetching vehicles: $e');
    }
  }

  /// Get vehicle by ID
  Future<VehicleModel?> _getVehicleById(String vehicleId) async {
    try {
      final response = await _supabase
          .from('vehicles')
          .select()
          .eq('id', vehicleId)
          .maybeSingle();

      return response != null ? VehicleModel.fromJson(response) : null;
    } catch (e) {
      throw Exception('Error fetching vehicle: $e');
    }
  }
}

// ============================================
// VEHICLE MODEL (from existing code)
// ============================================

class VehicleModel {
  final String id;
  final String userId;
  final String vehicleType;
  final String brand;
  final String model;
  final String vehicleNumber;
  final double currentMileage;
  final int? yearOfManufacture;
  final String? fuelType;
  final double? tankCapacity;
  final double previousMileage;
  final double fuelRemaining;
  final double totalDistanceAccumulated;
  final double totalFuelAddedAccumulated;
  final double? firstAvg;
  final double? previousAvg;
  final double? currentAvg;
  final String? ownerName;
  final String? ownerPhone;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  VehicleModel({
    required this.id,
    required this.userId,
    required this.vehicleType,
    required this.brand,
    required this.model,
    required this.vehicleNumber,
    this.currentMileage = 0,
    this.yearOfManufacture,
    this.fuelType,
    this.tankCapacity,
    this.previousMileage = 0,
    this.fuelRemaining = 0,
    this.totalDistanceAccumulated = 0,
    this.totalFuelAddedAccumulated = 0,
    this.firstAvg,
    this.previousAvg,
    this.currentAvg,
    this.ownerName,
    this.ownerPhone,
    this.isActive = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleModel.fromJson(Map<String, dynamic> json) {
    return VehicleModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vehicleType: json['vehicle_type'] as String,
      brand: json['brand'] as String? ?? 'Unknown',
      model: json['model'] as String? ?? 'Unknown',
      vehicleNumber: json['vehicle_number'] as String,
      currentMileage: (json['current_mileage'] as num?)?.toDouble() ?? 0,
      yearOfManufacture: json['year_of_manufacture'] as int?,
      fuelType: json['fuel_type'] as String?,
      tankCapacity: json['tank_capacity'] != null
          ? (json['tank_capacity'] as num).toDouble()
          : null,
      previousMileage: (json['previous_mileage'] as num?)?.toDouble() ?? 0,
      fuelRemaining: (json['fuel_remaining'] as num?)?.toDouble() ?? 0,
      totalDistanceAccumulated:
          (json['total_distance_accumulated'] as num?)?.toDouble() ?? 0,
      totalFuelAddedAccumulated:
          (json['total_fuel_added_accumulated'] as num?)?.toDouble() ?? 0,
      firstAvg: json['first_avg'] != null
          ? (json['first_avg'] as num).toDouble()
          : null,
      previousAvg: json['previous_avg'] != null
          ? (json['previous_avg'] as num).toDouble()
          : null,
      currentAvg: json['current_avg'] != null
          ? (json['current_avg'] as num).toDouble()
          : null,
      ownerName: json['owner_name'] as String?,
      ownerPhone: json['owner_phone'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'vehicle_type': vehicleType,
        'brand': brand,
        'model': model,
        'vehicle_number': vehicleNumber,
        'current_mileage': currentMileage,
        'year_of_manufacture': yearOfManufacture,
        'fuel_type': fuelType,
        'tank_capacity': tankCapacity,
        'previous_mileage': previousMileage,
        'fuel_remaining': fuelRemaining,
        'total_distance_accumulated': totalDistanceAccumulated,
        'total_fuel_added_accumulated': totalFuelAddedAccumulated,
        'first_avg': firstAvg,
        'previous_avg': previousAvg,
        'current_avg': currentAvg,
        'owner_name': ownerName,
        'owner_phone': ownerPhone,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}
