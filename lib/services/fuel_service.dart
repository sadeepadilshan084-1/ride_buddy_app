import 'package:supabase_flutter/supabase_flutter.dart';
import 'backend_models.dart';

class FuelService {
  static final FuelService _instance = FuelService._internal();
  late final SupabaseClient _supabase;

  static const String fuelRefillTable = 'fuel_refills';
  static const String vehicleServiceDetailsTable = 'vehicle_service_details';

  factory FuelService() {
    return _instance;
  }

  FuelService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // CREATE FUEL REFILL
  // ============================================

  /// Create a new fuel refill entry
  Future<FuelRefillModel> createFuelRefill({
    required String vehicleId,
    required String userId,
    required DateTime refillDate,
    required double mileage,
    required double amount,
    required double cost,
    String? fuelType,
    double? pricePerLiter,
    String? fillingStation,
    String? notes,
  }) async {
    try {
      // Calculate price per liter if not provided
      final ppLiter = pricePerLiter ?? (cost / amount);
      
      final response = await _supabase.from(fuelRefillTable).insert({
        'vehicle_id': vehicleId,
        'user_id': userId,
        'refill_date': refillDate.toIso8601String().split('T')[0],
        'mileage': mileage,
        'amount': amount,
        'cost': cost,
        'fuel_type': fuelType,
        'price_per_liter': ppLiter,
        'filling_station': fillingStation,
        'notes': notes,
      }).select();

      if (response.isEmpty) throw Exception('Failed to create fuel refill');
      
      final refill = FuelRefillModel.fromJson(response.first);
      
      // Update vehicle service details with latest mileage
      await _updateVehicleServiceMileage(vehicleId, mileage);
      
      return refill;
    } catch (e) {
      throw Exception('Error creating fuel refill: $e');
    }
  }

  // ============================================
  // READ FUEL REFILLS
  // ============================================

  /// Get all fuel refills for a vehicle
  Future<List<FuelRefillModel>> getVehicleFuelRefills(String vehicleId) async {
    try {
      final response = await _supabase
          .from(fuelRefillTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('refill_date', ascending: false);

      return (response as List)
          .map((r) => FuelRefillModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching fuel refills: $e');
    }
  }

  /// Get fuel refills for a user across all vehicles
  Future<List<FuelRefillModel>> getUserFuelRefills(String userId) async {
    try {
      final response = await _supabase
          .from(fuelRefillTable)
          .select()
          .eq('user_id', userId)
          .order('refill_date', ascending: false);

      return (response as List)
          .map((r) => FuelRefillModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching user fuel refills: $e');
    }
  }

  /// Get latest fuel refill for a vehicle
  Future<FuelRefillModel?> getLatestFuelRefill(String vehicleId) async {
    try {
      final response = await _supabase
          .from(fuelRefillTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('refill_date', ascending: false)
          .limit(1)
          .maybeSingle();

      return response != null ? FuelRefillModel.fromJson(response) : null;
    } catch (e) {
      throw Exception('Error fetching latest fuel refill: $e');
    }
  }

  /// Get fuel refills within a date range
  Future<List<FuelRefillModel>> getFuelRefillsByDateRange(
    String vehicleId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final response = await _supabase
          .from(fuelRefillTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .gte('refill_date', startDate.toIso8601String().split('T')[0])
          .lte('refill_date', endDate.toIso8601String().split('T')[0])
          .order('refill_date', ascending: false);

      return (response as List)
          .map((r) => FuelRefillModel.fromJson(r))
          .toList();
    } catch (e) {
      throw Exception('Error fetching fuel refills by date range: $e');
    }
  }

  // ============================================
  // UPDATE FUEL REFILL
  // ============================================

  /// Update a fuel refill entry
  Future<FuelRefillModel> updateFuelRefill(
    String refillId, {
    DateTime? refillDate,
    double? mileage,
    double? amount,
    double? cost,
    String? fuelType,
    double? pricePerLiter,
    String? fillingStation,
    String? notes,
  }) async {
    try {
      final updateData = <String, dynamic>{};
      
      if (refillDate != null) updateData['refill_date'] = refillDate.toIso8601String().split('T')[0];
      if (mileage != null) updateData['mileage'] = mileage;
      if (amount != null) updateData['amount'] = amount;
      if (cost != null) updateData['cost'] = cost;
      if (fuelType != null) updateData['fuel_type'] = fuelType;
      if (pricePerLiter != null) updateData['price_per_liter'] = pricePerLiter;
      if (fillingStation != null) updateData['filling_station'] = fillingStation;
      if (notes != null) updateData['notes'] = notes;
      
      updateData['updated_at'] = DateTime.now().toIso8601String();

      final response = await _supabase
          .from(fuelRefillTable)
          .update(updateData)
          .eq('id', refillId)
          .select();

      if (response.isEmpty) throw Exception('Failed to update fuel refill');
      return FuelRefillModel.fromJson(response.first);
    } catch (e) {
      throw Exception('Error updating fuel refill: $e');
    }
  }

  // ============================================
  // DELETE FUEL REFILL
  // ============================================

  /// Delete a fuel refill entry
  Future<void> deleteFuelRefill(String refillId) async {
    try {
      await _supabase
          .from(fuelRefillTable)
          .delete()
          .eq('id', refillId);
    } catch (e) {
      throw Exception('Error deleting fuel refill: $e');
    }
  }

  // ============================================
  // FUEL ANALYTICS
  // ============================================

  /// Get fuel economy statistics for a vehicle
  Future<Map<String, dynamic>> getFuelEconomyStats(String vehicleId) async {
    try {
      final refills = await getVehicleFuelRefills(vehicleId);
      
      if (refills.isEmpty) {
        return {
          'totalRefills': 0,
          'totalLiters': 0,
          'totalCost': 0,
          'averageFuelEconomy': 0,
          'averagePricePerLiter': 0,
          'lastRefillDate': null,
          'lastMileage': 0,
        };
      }

      double totalLiters = 0;
      double totalCost = 0;
      double totalKms = 0;
      double? firstMileage;
      double? lastMileage;

      for (int i = 0; i < refills.length; i++) {
        totalLiters += refills[i].amount;
        totalCost += refills[i].cost;
        lastMileage = refills[i].mileage;
        
        if (i < refills.length - 1) {
          final kmDiff = refills[i].mileage - refills[i + 1].mileage;
          if (kmDiff > 0) totalKms += kmDiff;
        }
        
        if (i == refills.length - 1) firstMileage = refills[i].mileage;
      }

      final avgFuelEconomy = totalKms > 0 ? totalKms / totalLiters : 0;
      final avgPricePerLiter = totalLiters > 0 ? totalCost / totalLiters : 0;

      return {
        'totalRefills': refills.length,
        'totalLiters': totalLiters,
        'totalCost': totalCost,
        'totalKms': totalKms,
        'averageFuelEconomy': avgFuelEconomy,
        'averagePricePerLiter': avgPricePerLiter,
        'lastRefillDate': refills.isNotEmpty ? refills.first.refillDate : null,
        'lastMileage': lastMileage ?? 0,
        'currentMileage': lastMileage ?? 0,
      };
    } catch (e) {
      throw Exception('Error getting fuel economy stats: $e');
    }
  }

  // ============================================
  // SERVICE CALCULATION
  // ============================================

  /// Calculate if service is due based on time interval
  Future<ServiceReminderStatusModel> calculateServiceStatus(
    String vehicleId,
    int serviceIntervalDays,
  ) async {
    try {
      // Get latest fuel refill
      final latestRefill = await getLatestFuelRefill(vehicleId);
      final lastRefillMileage = latestRefill?.mileage.toString() ?? '0';

      // Get service details
      final serviceDetails = await _getVehicleServiceDetails(vehicleId);
      
      if (serviceDetails == null) {
        return ServiceReminderStatusModel(
          vehicleId: vehicleId,
          lastRefillMileage: lastRefillMileage,
          nextServiceDate: DateTime.now().add(Duration(days: serviceIntervalDays)),
          nextServiceMileage: null,
          isOverdueByTime: false,
          isOverdueByMileage: false,
          status: 'on-schedule',
          details: {},
        );
      }

      // Calculate next service date
      final nextServiceDate = serviceDetails.lastServiceDate != null
          ? serviceDetails.lastServiceDate!.add(Duration(days: serviceIntervalDays))
          : DateTime.now().add(Duration(days: serviceIntervalDays));

      // Check if overdue
      final isOverdue = DateTime.now().isAfter(nextServiceDate);
      final daysOverdue = DateTime.now().difference(nextServiceDate).inDays;

      // Determine status
      String status = 'on-schedule';
      if (isOverdue) {
        status = daysOverdue > 7 ? 'overdue' : 'due-soon';
      } else if (DateTime.now().difference(nextServiceDate).inDays > -7) {
        status = 'due-soon';
      }

      return ServiceReminderStatusModel(
        vehicleId: vehicleId,
        lastRefillMileage: lastRefillMileage,
        nextServiceDate: nextServiceDate,
        nextServiceMileage: serviceDetails.nextServiceMileage,
        isOverdueByTime: isOverdue,
        isOverdueByMileage: false,
        status: status,
        details: {
          'lastServiceDate': serviceDetails.lastServiceDate?.toIso8601String(),
          'daysOverdue': isOverdue ? daysOverdue : 0,
          'serviceCenter': serviceDetails.serviceCenterName,
        },
      );
    } catch (e) {
      throw Exception('Error calculating service status: $e');
    }
  }

  // ============================================
  // PRIVATE HELPER METHODS
  // ============================================

  /// Update vehicle service details with latest mileage
  Future<void> _updateVehicleServiceMileage(
    String vehicleId,
    double mileage,
  ) async {
    try {
      await _supabase
          .from(vehicleServiceDetailsTable)
          .update({
            'last_recorded_mileage': mileage,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('vehicle_id', vehicleId);
    } catch (e) {
      // Log but don't fail - this is just tracking
      print('Warning: Could not update vehicle mileage: $e');
    }
  }

  /// Get vehicle service details
  Future<VehicleServiceDetailsModel?> _getVehicleServiceDetails(
    String vehicleId,
  ) async {
    try {
      final response = await _supabase
          .from(vehicleServiceDetailsTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .maybeSingle();

      return response != null ? VehicleServiceDetailsModel.fromJson(response) : null;
    } catch (e) {
      return null;
    }
  }
}
