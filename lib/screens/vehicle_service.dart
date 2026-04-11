import 'package:supabase_flutter/supabase_flutter.dart';

class Vehicle {
  final String id;
  final String userId;
  final String vehicleName;
  final String vehicleNumber;
  final String? vehicleType;
  final double currentMileage;
  final double tankCapacity;
  final String? fuelType;
  final DateTime createdAt;
  final DateTime updatedAt;

  Vehicle({
    required this.id,
    required this.userId,
    required this.vehicleName,
    required this.vehicleNumber,
    this.vehicleType,
    required this.currentMileage,
    required this.tankCapacity,
    this.fuelType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    // Handle fuel type compatibility between different vehicle creation methods
    String? fuelType = json['fuel_type'];
    final fuelVariant = json['fuel_variant'];

    // If fuel_type is in lowercase format (from FuelTrackerService), combine with fuel_variant
    if (fuelType != null && fuelVariant != null && fuelVariant.isNotEmpty) {
      if (fuelType.toLowerCase() == 'petrol' && fuelVariant == '92') {
        fuelType = 'Petrol 92';
      } else if (fuelType.toLowerCase() == 'petrol' && fuelVariant == '95') {
        fuelType = 'Petrol 95';
      } else if (fuelType.toLowerCase() == 'diesel' && fuelVariant == 'auto') {
        fuelType = 'Auto Diesel';
      } else if (fuelType.toLowerCase() == 'diesel' && fuelVariant == 'super') {
        fuelType = 'Super Diesel';
      }
    }

    return Vehicle(
      id: json['id'],
      userId: json['user_id'],
      vehicleName: json['vehicle_name'] ?? json['model'] ?? 'Unknown', // Handle different field names
      vehicleNumber: json['vehicle_number'] ?? json['number'] ?? 'Unknown',
      vehicleType: json['vehicle_type'],
      currentMileage: (json['current_mileage'] as num?)?.toDouble() ?? (json['previous_mileage'] as num?)?.toDouble() ?? 0.0,
      tankCapacity: (json['tank_capacity'] as num?)?.toDouble() ?? 30.0,
      fuelType: fuelType,
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'vehicle_name': vehicleName,
      'vehicle_number': vehicleNumber,
      'vehicle_type': vehicleType,
      'current_mileage': currentMileage,
      'tank_capacity': tankCapacity,
      'fuel_type': fuelType,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class VehicleService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Vehicle>> getVehicles() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final response = await _supabase
        .from('vehicles')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return response.map((json) => Vehicle.fromJson(json)).toList();
  }

  Future<Vehicle> addVehicle({
    required String vehicleName,
    required String vehicleNumber,
    required String vehicleType,
    required double currentMileage,
    required double tankCapacity,
    required String fuelType,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    // Split fuel type for compatibility with FuelTrackerService
    String fuelTypeLower = '';
    String fuelVariant = '';

    if (fuelType == 'Petrol 92') {
      fuelTypeLower = 'petrol';
      fuelVariant = '92';
    } else if (fuelType == 'Petrol 95') {
      fuelTypeLower = 'petrol';
      fuelVariant = '95';
    } else if (fuelType == 'Auto Diesel') {
      fuelTypeLower = 'diesel';
      fuelVariant = 'auto';
    } else if (fuelType == 'Super Diesel') {
      fuelTypeLower = 'diesel';
      fuelVariant = 'super';
    }

    final response = await _supabase
        .from('vehicles')
        .insert({
          'user_id': userId,
          'vehicle_name': vehicleName,
          'vehicle_number': vehicleNumber,
          'vehicle_type': vehicleType,
          'current_mileage': currentMileage,
          'fuel_type': fuelType, // Combined format for VehicleService
          'fuel_variant': fuelVariant, // Separate format for FuelTrackerService
          'tank_capacity': tankCapacity,
          'previous_mileage': currentMileage,
          'fuel_remaining': tankCapacity,
          'total_distance_accumulated': 0.0,
          'total_fuel_added_accumulated': 0.0,
          'owner': '', // Default empty
        })
        .select()
        .single();

    return Vehicle.fromJson(response);
  }

  Future<void> updateVehicle(String vehicleId, {
    String? vehicleName,
    String? vehicleNumber,
    String? vehicleType,
    double? currentMileage,
    double? tankCapacity,
    String? fuelType,
  }) async {
    final updates = <String, dynamic>{};
    if (vehicleName != null) updates['vehicle_name'] = vehicleName;
    if (vehicleNumber != null) updates['vehicle_number'] = vehicleNumber;
    if (vehicleType != null) updates['vehicle_type'] = vehicleType;
    if (currentMileage != null) updates['current_mileage'] = currentMileage;
    if (tankCapacity != null) updates['tank_capacity'] = tankCapacity;
    if (fuelType != null) {
      updates['fuel_type'] = fuelType;
      // Also update fuel_variant for compatibility
      if (fuelType == 'Petrol 92') {
        updates['fuel_variant'] = '92';
      } else if (fuelType == 'Petrol 95') {
        updates['fuel_variant'] = '95';
      } else if (fuelType == 'Auto Diesel') {
        updates['fuel_variant'] = 'auto';
      } else if (fuelType == 'Super Diesel') {
        updates['fuel_variant'] = 'super';
      }
    }

    await _supabase
        .from('vehicles')
        .update(updates)
        .eq('id', vehicleId);
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _supabase
        .from('vehicles')
        .delete()
        .eq('id', vehicleId);
  }
}