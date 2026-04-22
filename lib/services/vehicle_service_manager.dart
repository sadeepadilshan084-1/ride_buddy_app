import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_models.dart';

class VehicleServiceManager {
  static final VehicleServiceManager _instance = VehicleServiceManager._internal();
  late final SupabaseClient _supabase;

  static const String vehicleServiceDetailsTable = 'vehicle_service_details';
  static const String serviceHistoryTable = 'service_history';

  factory VehicleServiceManager() {
    return _instance;
  }

  VehicleServiceManager._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // SERVICE DETAILS MANAGEMENT
  // ============================================

  /// Create or initialize service details for a vehicle
  Future<VehicleServiceDetailsModel> initializeServiceDetails({
    required String vehicleId,
    DateTime? lastServiceDate,
    double? lastServiceMileage,
    int serviceIntervalDays = 365,
    double serviceIntervalKm = 10000,
    String? serviceCenterName,
    String? serviceCenterPhone,
    String? serviceCenterLocation,
    DateTime? warrantyExpiryDate,
  }) async {
    try {
      // Calculate next service values
      final nextServiceDate = lastServiceDate != null
          ? lastServiceDate.add(Duration(days: serviceIntervalDays))
          : null;
      final nextServiceMileage = lastServiceMileage != null
          ? lastServiceMileage + serviceIntervalKm
          : null;

      final response = await _supabase
          .from(vehicleServiceDetailsTable)
          .insert({
            'vehicle_id': vehicleId,
            'last_service_date': lastServiceDate?.toIso8601String().split('T')[0],
            'last_service_mileage': lastServiceMileage,
            'next_service_mileage': nextServiceMileage,
            'service_interval_days': serviceIntervalDays,
            'service_interval_km': serviceIntervalKm,
            'service_center_name': serviceCenterName,
            'service_center_phone': serviceCenterPhone,
            'service_center_location': serviceCenterLocation,
            'warranty_expiry_date': warrantyExpiryDate?.toIso8601String().split('T')[0],
          })
          .select();

      if (response.isEmpty) throw Exception('Failed to initialize service details');
      return VehicleServiceDetailsModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error initializing service details: $e');
    }
  }

  /// Get service details for a vehicle
  Future<VehicleServiceDetailsModel?> getServiceDetails(String vehicleId) async {
    try {
      final response = await _supabase
          .from(vehicleServiceDetailsTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .maybeSingle();

      return response != null
          ? VehicleServiceDetailsModel.fromJson(response)
          : null;
    } catch (e) {
      throw Exception('Error fetching service details: $e');
    }
  }

  /// Update service details
  Future<VehicleServiceDetailsModel> updateServiceDetails(
    String vehicleId, {
    DateTime? lastServiceDate,
    double? lastServiceMileage,
    double? nextServiceMileage,
    int? serviceIntervalDays,
    double? serviceIntervalKm,
    String? serviceCenterName,
    String? serviceCenterPhone,
    String? serviceCenterLocation,
    DateTime? warrantyExpiryDate,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (lastServiceDate != null) {
        updateData['last_service_date'] = lastServiceDate.toIso8601String().split('T')[0];
      }
      if (lastServiceMileage != null) {
        updateData['last_service_mileage'] = lastServiceMileage;
      }
      if (nextServiceMileage != null) {
        updateData['next_service_mileage'] = nextServiceMileage;
      }
      if (serviceIntervalDays != null) {
        updateData['service_interval_days'] = serviceIntervalDays;
      }
      if (serviceIntervalKm != null) {
        updateData['service_interval_km'] = serviceIntervalKm;
      }
      if (serviceCenterName != null) {
        updateData['service_center_name'] = serviceCenterName;
      }
      if (serviceCenterPhone != null) {
        updateData['service_center_phone'] = serviceCenterPhone;
      }
      if (serviceCenterLocation != null) {
        updateData['service_center_location'] = serviceCenterLocation;
      }
      if (warrantyExpiryDate != null) {
        updateData['warranty_expiry_date'] = warrantyExpiryDate.toIso8601String().split('T')[0];
      }

      updateData['updated_at'] = DateTime.now().toIso8601String();

      final response = await _supabase
          .from(vehicleServiceDetailsTable)
          .update(updateData)
          .eq('vehicle_id', vehicleId)
          .select();

      if (response.isEmpty) throw Exception('Failed to update service details');
      return VehicleServiceDetailsModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error updating service details: $e');
    }
  }

  // ============================================
  // SERVICE HISTORY MANAGEMENT
  // ============================================

  /// Add service history record
  Future<ServiceHistoryModel> addServiceRecord({
    required String vehicleId,
    required ServiceType serviceType,
    required DateTime serviceDate,
    double? serviceMileage,
    double? serviceCost,
    String? serviceCenter,
    String? description,
    String? technicianName,
    DateTime? nextServiceDate,
    double? nextServiceMileage,
    String? partsReplaced,
  }) async {
    try {
      final response = await _supabase
          .from(serviceHistoryTable)
          .insert({
            'vehicle_id': vehicleId,
            'service_type': serviceType.name,
            'service_date': serviceDate.toIso8601String().split('T')[0],
            'service_mileage': serviceMileage,
            'service_cost': serviceCost,
            'service_center': serviceCenter,
            'description': description,
            'technician_name': technicianName,
            'next_service_date': nextServiceDate?.toIso8601String().split('T')[0],
            'next_service_mileage': nextServiceMileage,
            'parts_replaced': partsReplaced,
          })
          .select();

      if (response.isEmpty) throw Exception('Failed to add service record');

      // Update vehicle service details
      if (serviceMileage != null) {
        final nextServiceMile = nextServiceMileage ??
            (serviceMileage + 10000); // Default 10000 km interval

        await updateServiceDetails(
          vehicleId,
          lastServiceDate: serviceDate,
          lastServiceMileage: serviceMileage,
          nextServiceMileage: nextServiceMile,
        );
      }

      return ServiceHistoryModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error adding service record: $e');
    }
  }

  /// Get service history for a vehicle
  Future<List<ServiceHistoryModel>> getServiceHistory(String vehicleId) async {
    try {
      final response = await _supabase
          .from(serviceHistoryTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('service_date', ascending: false);

      return (response as List)
          .map((s) => ServiceHistoryModel.fromJson(s))
          .toList();
    } catch (e) {
      throw Exception('Error fetching service history: $e');
    }
  }

  /// Get recent service records (last N services)
  Future<List<ServiceHistoryModel>> getRecentServices(
    String vehicleId, {
    int limit = 5,
  }) async {
    try {
      final response = await _supabase
          .from(serviceHistoryTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('service_date', ascending: false)
          .limit(limit);

      return (response as List)
          .map((s) => ServiceHistoryModel.fromJson(s))
          .toList();
    } catch (e) {
      throw Exception('Error fetching recent services: $e');
    }
  }

  /// Get service cost statistics
  Future<Map<String, dynamic>> getServiceCostStats(String vehicleId) async {
    try {
      final history = await getServiceHistory(vehicleId);

      double totalCost = 0;
      double avgCost = 0;
      double maxCost = 0;
      double minCost = double.infinity;

      for (final service in history) {
        if (service.serviceCost != null && service.serviceCost! > 0) {
          totalCost += service.serviceCost!;
          maxCost = maxCost > service.serviceCost! ? maxCost : service.serviceCost!;
          minCost = minCost < service.serviceCost! ? minCost : service.serviceCost!;
        }
      }

      if (history.isNotEmpty) {
        avgCost = totalCost / history.length;
      }

      return {
        'total_cost': totalCost,
        'average_cost': avgCost,
        'max_cost': maxCost == 0 ? 0 : maxCost,
        'min_cost': minCost == double.infinity ? 0 : minCost,
        'total_services': history.length,
      };
    } catch (e) {
      throw Exception('Error getting service cost stats: $e');
    }
  }

  /// Update service record
  Future<ServiceHistoryModel> updateServiceRecord(
    String serviceId, {
    ServiceType? serviceType,
    DateTime? serviceDate,
    double? serviceMileage,
    double? serviceCost,
    String? serviceCenter,
    String? description,
    String? technicianName,
    DateTime? nextServiceDate,
    double? nextServiceMileage,
    String? partsReplaced,
  }) async {
    try {
      final updateData = <String, dynamic>{};

      if (serviceType != null) updateData['service_type'] = serviceType.name;
      if (serviceDate != null) {
        updateData['service_date'] = serviceDate.toIso8601String().split('T')[0];
      }
      if (serviceMileage != null) updateData['service_mileage'] = serviceMileage;
      if (serviceCost != null) updateData['service_cost'] = serviceCost;
      if (serviceCenter != null) updateData['service_center'] = serviceCenter;
      if (description != null) updateData['description'] = description;
      if (technicianName != null) updateData['technician_name'] = technicianName;
      if (nextServiceDate != null) {
        updateData['next_service_date'] = nextServiceDate.toIso8601String().split('T')[0];
      }
      if (nextServiceMileage != null) {
        updateData['next_service_mileage'] = nextServiceMileage;
      }
      if (partsReplaced != null) updateData['parts_replaced'] = partsReplaced;

      updateData['updated_at'] = DateTime.now().toIso8601String();

      final response = await _supabase
          .from(serviceHistoryTable)
          .update(updateData)
          .eq('id', serviceId)
          .select();

      if (response.isEmpty) throw Exception('Failed to update service record');
      return ServiceHistoryModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error updating service record: $e');
    }
  }

  /// Delete service record
  Future<void> deleteServiceRecord(String serviceId) async {
    try {
      await _supabase
          .from(serviceHistoryTable)
          .delete()
          .eq('id', serviceId);
    } catch (e) {
      throw Exception('Error deleting service record: $e');
    }
  }

  // ============================================
  // SERVICE ANALYTICS & PREDICTIONS
  // ============================================

  /// Get service analytics for a vehicle
  Future<Map<String, dynamic>> getServiceAnalytics(String vehicleId) async {
    try {
      final serviceDetails = await getServiceDetails(vehicleId);
      final costStats = await getServiceCostStats(vehicleId);
      final history = await getServiceHistory(vehicleId);

      // Calculate average service interval based on history
      double avgDaysInterval = serviceDetails?.serviceIntervalDays.toDouble() ?? 365;
      double avgKmInterval = serviceDetails?.serviceIntervalKm ?? 10000;

      if (history.length > 1) {
        final intervals = <int>[];
        for (int i = 0; i < history.length - 1; i++) {
          final daysDiff = history[i].serviceDate
              .difference(history[i + 1].serviceDate)
              .inDays
              .abs();
          intervals.add(daysDiff);
        }
        avgDaysInterval = intervals.isEmpty
            ? avgDaysInterval
            : intervals.reduce((a, b) => a + b) / intervals.length;
      }

      return {
        'last_service_date': serviceDetails?.lastServiceDate,
        'last_service_mileage': serviceDetails?.lastServiceMileage,
        'next_service_mileage': serviceDetails?.nextServiceMileage,
        'days_since_last_service':
            serviceDetails?.lastServiceDate != null
                ? DateTime.now().difference(serviceDetails!.lastServiceDate!).inDays
                : null,
        'average_days_interval': avgDaysInterval,
        'average_km_interval': avgKmInterval,
        'cost_stats': costStats,
        'total_services': history.length,
        'warranty_expiry': serviceDetails?.warrantyExpiryDate,
      };
    } catch (e) {
      throw Exception('Error getting service analytics: $e');
    }
  }

  /// Check if service is due (based on mileage or days)
  Future<Map<String, dynamic>> isServiceDue(
    String vehicleId,
    double currentMileage,
  ) async {
    try {
      final serviceDetails = await getServiceDetails(vehicleId);
      if (serviceDetails == null) {
        throw Exception('Service details not found for vehicle');
      }

      final kmRemaining = serviceDetails.nextServiceMileage != null
          ? (serviceDetails.nextServiceMileage! - currentMileage).toInt()
          : null;

      final daysRemaining = serviceDetails.lastServiceDate != null
          ? (serviceDetails.lastServiceDate!
                  .add(Duration(days: serviceDetails.serviceIntervalDays))
                  .difference(DateTime.now())
                  .inDays)
          : null;

      final isKmOverdue = kmRemaining != null && kmRemaining <= 0;
      final isDaysOverdue = daysRemaining != null && daysRemaining <= 0;
      final isOverdue = isKmOverdue || isDaysOverdue;

      return {
        'is_due': isOverdue,
        'is_km_overdue': isKmOverdue,
        'is_days_overdue': isDaysOverdue,
        'km_remaining': kmRemaining,
        'days_remaining': daysRemaining,
        'urgency': isOverdue
            ? 'critical'
            : kmRemaining != null && kmRemaining <= 1000 || daysRemaining != null && daysRemaining <= 7
                ? 'high'
                : 'normal',
      };
    } catch (e) {
      throw Exception('Error checking service due: $e');
    }
  }

  /// Get service statistics for all vehicles of a user
  Future<Map<String, dynamic>> getUserServiceStats(
    List<String> vehicleIds,
  ) async {
    try {
      int totalServices = 0;
      double totalCost = 0;
      int overdueCount = 0;
      int upcomingCount = 0;

      for (final vehicleId in vehicleIds) {
        try {
          final costStats = await getServiceCostStats(vehicleId);
          totalServices += costStats['total_services'] as int? ?? 0;
          totalCost += costStats['total_cost'] as double? ?? 0;
        } catch (e) {
          print('Error getting stats for vehicle $vehicleId: $e');
        }
      }

      return {
        'total_services': totalServices,
        'total_cost': totalCost,
        'average_cost_per_service': totalServices > 0 ? totalCost / totalServices : 0,
      };
    } catch (e) {
      throw Exception('Error getting user service stats: $e');
    }
  }
}
