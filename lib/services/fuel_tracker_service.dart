import 'package:supabase_flutter/supabase_flutter.dart';
import 'fuel_price_service.dart';

// Constants
const double DEFAULT_AVG_KM_PER_LITER = 10.0;
const int AVERAGE_DECIMAL_PLACES = 1;

class Vehicle {
  final String? id;
  final String number;
  final String model;
  final String vehicleType;
  final String fuelType;
  final String fuelVariant;
  final double tankCapacity;
  final double previousMileage;
  final double? firstAvg;
  final double? previousAvg;
  final double? currentAvg;
  final double fuelRemaining;
  final double totalDistanceAccumulated;
  final double totalFuelAddedAccumulated;
  final String owner;
  final DateTime createdAt;
  final DateTime updatedAt;

  Vehicle({
    this.id,
    required this.number,
    required this.model,
    required this.vehicleType,
    required this.fuelType,
    required this.fuelVariant,
    this.tankCapacity = 30.0,
    this.previousMileage = 0.0,
    this.firstAvg,
    this.previousAvg,
    this.currentAvg,
    this.fuelRemaining = 0.0,
    this.totalDistanceAccumulated = 0.0,
    this.totalFuelAddedAccumulated = 0.0,
    required this.owner,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'number': number,
    'model': model,
    'vehicle_type': vehicleType,
    'fuel_type': fuelType,
    'fuel_variant': fuelVariant,
    'tank_capacity': tankCapacity,
    'previous_mileage': previousMileage,
    'first_avg': firstAvg,
    'previous_avg': previousAvg,
    'current_avg': currentAvg,
    'fuel_remaining': fuelRemaining,
    'total_distance_accumulated': totalDistanceAccumulated,
    'total_fuel_added_accumulated': totalFuelAddedAccumulated,
    'owner': owner,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    try {
      return Vehicle(
        id: json['id'] as String?,
        number: json['number'] as String? ?? 'UNKNOWN',
        model: json['model'] as String? ?? 'UNKNOWN',
        vehicleType: json['vehicle_type'] as String? ?? 'Unknown',
        fuelType: json['fuel_type'] as String? ?? 'Unknown',
        fuelVariant: (() {
          final rawVariant = (json['fuel_variant'] as String?)?.trim().toLowerCase();
          if (rawVariant != null && rawVariant.isNotEmpty) return rawVariant;
          // fallback from fuel type
          final fuelType = (json['fuel_type'] as String?)?.trim().toLowerCase();
          if (fuelType == 'diesel') return 'auto';
          if (fuelType == 'super_petrol') return '95';
          return '92';
        })(),
        tankCapacity: (json['tank_capacity'] as num?)?.toDouble() ?? 30.0,
        previousMileage: (json['previous_mileage'] as num?)?.toDouble() ?? 0.0,
        firstAvg: json['first_avg'] != null
            ? (json['first_avg'] as num).toDouble()
            : null,
        previousAvg: json['previous_avg'] != null
            ? (json['previous_avg'] as num).toDouble()
            : null,
        currentAvg: json['current_avg'] != null
            ? (json['current_avg'] as num).toDouble()
            : null,
        fuelRemaining: (json['fuel_remaining'] as num?)?.toDouble() ?? 0.0,
        totalDistanceAccumulated:
        (json['total_distance_accumulated'] as num?)?.toDouble() ?? 0.0,
        totalFuelAddedAccumulated:
        (json['total_fuel_added_accumulated'] as num?)?.toDouble() ?? 0.0,
        owner: json['owner'] as String? ?? 'Unknown',
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        updatedAt: json['updated_at'] != null
            ? DateTime.parse(json['updated_at'] as String)
            : DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to parse Vehicle: $e');
    }
  }

  Vehicle copyWith({
    String? id,
    String? number,
    String? model,
    String? vehicleType,
    String? fuelType,
    String? fuelVariant,
    double? tankCapacity,
    double? previousMileage,
    double? firstAvg,
    double? previousAvg,
    double? currentAvg,
    double? fuelRemaining,
    double? totalDistanceAccumulated,
    double? totalFuelAddedAccumulated,
    String? owner,
    DateTime? updatedAt,
  }) => Vehicle(
    id: id ?? this.id,
    number: number ?? this.number,
    model: model ?? this.model,
    vehicleType: vehicleType ?? this.vehicleType,
    fuelType: fuelType ?? this.fuelType,
    fuelVariant: fuelVariant ?? this.fuelVariant,
    tankCapacity: tankCapacity ?? this.tankCapacity,
    previousMileage: previousMileage ?? this.previousMileage,
    firstAvg: firstAvg ?? this.firstAvg,
    previousAvg: previousAvg ?? this.previousAvg,
    currentAvg: currentAvg ?? this.currentAvg,
    fuelRemaining: fuelRemaining ?? this.fuelRemaining,
    totalDistanceAccumulated:
    totalDistanceAccumulated ?? this.totalDistanceAccumulated,
    totalFuelAddedAccumulated:
    totalFuelAddedAccumulated ?? this.totalFuelAddedAccumulated,
    owner: owner ?? this.owner,
    createdAt: createdAt,
    updatedAt: updatedAt ?? DateTime.now(),
  );

  /// Equality operator - compare vehicles by ID
  @override
  bool operator ==(dynamic other) =>
      identical(this, other) ||
          other is Vehicle &&
              runtimeType == other.runtimeType &&
              id == other.id;

  /// Hash code for Vehicle
  @override
  int get hashCode => id.hashCode;
}

class RefillRecord {
  final String? id;
  final String vehicleId;
  final double mileage;
  final double fuelAdded;
  final bool tankFull;
  final double fuelCost;
  final double pricePerLitre;
  final DateTime createdAt;

  RefillRecord({
    this.id,
    required this.vehicleId,
    required this.mileage,
    required this.fuelAdded,
    required this.tankFull,
    required this.fuelCost,
    this.pricePerLitre = 100.0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'mileage': mileage,
    'fuel_added': fuelAdded,
    'tank_full': tankFull,
    'fuel_cost': fuelCost,
    'price_per_litre': pricePerLitre,
    'created_at': createdAt.toIso8601String(),
  };

  factory RefillRecord.fromJson(Map<String, dynamic> json) {
    try {
      return RefillRecord(
        id: json['id'] as String?,
        vehicleId: json['vehicle_id'] as String? ?? '',
        mileage: (json['mileage'] as num?)?.toDouble() ?? 0.0,
        fuelAdded: (json['fuel_added'] as num?)?.toDouble() ?? 0.0,
        tankFull: json['tank_full'] as bool? ?? false,
        fuelCost: (json['fuel_cost'] as num?)?.toDouble() ?? 0.0,
        pricePerLitre: (json['price_per_litre'] as num?)?.toDouble() ?? 100.0,
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
      );
    } catch (e) {
      throw Exception('Failed to parse RefillRecord: $e');
    }
  }
}

class RefillResult {
  final RefillRecord refillRecord;
  final bool averageCalculated;
  final double? calculatedAvg;

  RefillResult({
    required this.refillRecord,
    required this.averageCalculated,
    this.calculatedAvg,
  });
}

class FuelTrackerService {
  late final SupabaseClient _supabase;
  static const String vehiclesTable = 'vehicles';
  static const String refillsTable = 'refill_records';
  static const double pricePerLitre = 100.0;

  FuelTrackerService() {
    _supabase = Supabase.instance.client;
  }

  // ===== VEHICLE OPERATIONS =====

  /// Create a new vehicle in database
  Future<Vehicle> createVehicle({
    required String number,
    required String model,
    required String vehicleType,
    required String fuelType,
    required String fuelVariant,
    required double tankCapacity,
    required String owner,
    double previousMileage = 0.0,
    String? mobile,
  }) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      // Normalize fuel type to lowercase
      final normalizedFuelType = fuelType.toLowerCase();

      final normalizedFuelVariant = fuelVariant.toLowerCase();
      final Map<String, dynamic> vehiclePayload = {
        'user_id': currentUserId,
        'number': number,
        'model': model,
        'vehicle_type': vehicleType,
        'fuel_type': normalizedFuelType,
        'fuel_variant': normalizedFuelVariant,
        'tank_capacity': tankCapacity,
        'previous_mileage': previousMileage,
        'fuel_remaining': 0.0,
        'total_distance_accumulated': 0.0,
        'total_fuel_added_accumulated': 0.0,
        'owner': owner,
        'mobile': mobile ?? '', // Required field, default to empty string
      };

      final response = await _supabase.from(vehiclesTable).insert(vehiclePayload).select();
      if (response.isEmpty) throw Exception('Failed to create vehicle');
      return Vehicle.fromJson(response.first);
    } catch (e) {
      throw Exception('Error creating vehicle: $e');
    }
  }

  /// Normalize vehicle type to match database constraints
  String _normalizeVehicleType(String vehicleType) {
    final type = vehicleType.toLowerCase();
    if (type.contains('bike') || type.contains('motorcycle')) return 'bike';
    if (type.contains('van') || type.contains('bus') || type.contains('truck') || type.contains('lorry')) return 'truck';
    return 'car'; // default
  }

  /// Get a vehicle by ID
  Future<Vehicle?> getVehicle(String vehicleId) async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from(vehiclesTable)
          .select()
          .eq('id', vehicleId)
          .eq('user_id', currentUserId)
          .single();

      return Vehicle.fromJson(response);
    } on PostgrestException catch (e) {
      if (e.code == 'PGRST116') return null; // Not found
      throw Exception('Error loading vehicle: $e');
    } catch (e) {
      throw Exception('Error loading vehicle: $e');
    }
  }

  /// Get all vehicles for current user
  Future<List<Vehicle>> getVehicles() async {
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) throw Exception('User not authenticated');

      final response = await _supabase
          .from(vehiclesTable)
          .select()
          .eq('user_id', currentUserId);
      return (response as List).map((v) => Vehicle.fromJson(v)).toList();
    } catch (e) {
      throw Exception('Error loading vehicles: $e');
    }
  }

  /// Get the active price configured for a vehicle's fuel type and variant
  Future<double?> getFuelPriceForVehicle(Vehicle vehicle) async {
    final service = FuelPriceService();
    return await service.getFuelPrice(vehicle.fuelType, vehicle.fuelVariant);
  }

  /// Update vehicle
  Future<Vehicle> updateVehicle(Vehicle vehicle) async {
    try {
      if (vehicle.id == null) throw Exception('Vehicle ID is required');

      // Only update fields that should change, exclude system fields
      final updateData = {
        'number': vehicle.number,
        'model': vehicle.model,
        'vehicle_type': vehicle.vehicleType,
        'fuel_type': vehicle.fuelType,
        'fuel_variant': vehicle.fuelVariant,
        'tank_capacity': vehicle.tankCapacity,
        'previous_mileage': vehicle.previousMileage,
        'first_avg': vehicle.firstAvg,
        'previous_avg': vehicle.previousAvg,
        'current_avg': vehicle.currentAvg,
        'fuel_remaining': vehicle.fuelRemaining,
        'total_distance_accumulated': vehicle.totalDistanceAccumulated,
        'total_fuel_added_accumulated': vehicle.totalFuelAddedAccumulated,
        'owner': vehicle.owner,
        'updated_at': DateTime.now().toIso8601String(),
      };

      final response = await _supabase
          .from(vehiclesTable)
          .update(updateData)
          .eq('id', vehicle.id!)
          .select();

      if (response.isEmpty) throw Exception('Failed to update vehicle');
      return Vehicle.fromJson(response.first);
    } catch (e) {
      throw Exception('Error updating vehicle: $e');
    }
  }

  /// Returns true when the vehicle average is backed by at least two full tank refills.
  bool hasValidAverage(Vehicle vehicle, List<RefillRecord> refills) {
    if (vehicle.currentAvg == null || vehicle.currentAvg! <= 0) {
      return false;
    }

    final fullTankCount = refills.where((refill) => refill.tankFull).length;
    return fullTankCount >= 2;
  }

  /// Returns the average to use for fuel consumption calculations.
  double getAverageForConsumption(Vehicle vehicle, List<RefillRecord> refills) {
    return hasValidAverage(vehicle, refills)
        ? vehicle.currentAvg!
        : DEFAULT_AVG_KM_PER_LITER;
  }

  /// Returns the validated average or null when there is not yet enough full tank history.
  double? getValidatedAverage(Vehicle vehicle, List<RefillRecord> refills) {
    return hasValidAverage(vehicle, refills) ? vehicle.currentAvg : null;
  }

  // ===== REFILL OPERATIONS =====

  /// Get all refills for a vehicle
  Future<List<RefillRecord>> getRefills(String vehicleId) async {
    try {
      final response = await _supabase
          .from(refillsTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: false);

      return (response as List).map((r) => RefillRecord.fromJson(r)).toList();
    } catch (e) {
      throw Exception('Error loading refills: $e');
    }
  }

  /// Add a new refill record
  Future<RefillResult> addRefill({
    required String vehicleId,
    required double currentMileage,
    required double fuelCost,
    required bool isManualFull,
    double fuelPrice = 300.0,
  }) async {
    try {
      // Load current vehicle state
      final vehicle = await getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final refills = await getRefills(vehicleId);

      // Calculate fuel added using the provided fuel price
      double fuelAdded = fuelCost / fuelPrice;

      // Validate fuel price and fuel added
      if (fuelPrice <= 0) {
        throw Exception('Fuel price must be greater than 0');
      }
      if (fuelAdded <= 0) {
        throw Exception('Fuel added must be greater than 0');
      }

      // Validate mileage
      if (currentMileage <= vehicle.previousMileage) {
        throw Exception(
          'Current mileage ($currentMileage) must be greater than previous mileage (${vehicle.previousMileage})',
        );
      }

      // Calculate distance from the last recorded mileage
      double distance = currentMileage - vehicle.previousMileage;

      // Consume fuel from the previous segment using a validated average.
      double avgForCalc = getAverageForConsumption(vehicle, refills);
      double fuelConsumed = distance / avgForCalc;
      double newFuelRemaining = vehicle.fuelRemaining - fuelConsumed;
      if (newFuelRemaining < 0) newFuelRemaining = 0;

      // Determine if this refill should be treated as a full tank entry.
      // The tank is full if user marked it full or the added liters cover the remaining capacity.
      double remainingCapacity = vehicle.tankCapacity - newFuelRemaining;
      if (remainingCapacity < 0) remainingCapacity = 0;
      bool isFull = isManualFull || (fuelAdded >= remainingCapacity);
      final previousFullRefills = refills
          .where((r) => r.tankFull && r.mileage < currentMileage);
      RefillRecord? lastFullRefill;
      if (previousFullRefills.isNotEmpty) {
        lastFullRefill = previousFullRefills.reduce(
              (a, b) => a.mileage > b.mileage ? a : b,
        );
      }

      double actualFuelAddedToTank = isFull ? remainingCapacity : fuelAdded;
      if (actualFuelAddedToTank < 0) actualFuelAddedToTank = 0;

      double finalFuelRemaining = newFuelRemaining + fuelAdded;
      double? newFirstAvg = vehicle.firstAvg;
      double? newPreviousAvg = vehicle.previousAvg;
      double? newCurrentAvg = vehicle.currentAvg;
      double newTotalDistance = vehicle.totalDistanceAccumulated + distance;
      double newTotalFuel = vehicle.totalFuelAddedAccumulated + fuelAdded;
      bool averageWasCalculated = false;

      // If the stored average is not supported by enough full tank history,
      // clear it so stale values are not reused or shown.
      if (!hasValidAverage(vehicle, refills)) {
        newFirstAvg = null;
        newPreviousAvg = null;
        newCurrentAvg = null;
      }

      if (isFull) {
        // FULL REFILL LOGIC
        if (lastFullRefill != null) {
          // STEP 4 & 5: SMART VALIDATION OR FIRST CALCULATION
          double distanceSinceLastFull = currentMileage - lastFullRefill.mileage;
          if (distanceSinceLastFull <= 0) {
            throw Exception(
              'Current mileage ($currentMileage) must be greater than last full tank mileage (${lastFullRefill.mileage})',
            );
          }

          bool shouldCalculateAverage = false;
          double newAvg = 0.0;

          if (actualFuelAddedToTank > 0) {
            // Calculate a fresh average from the last full fill cycle.
            shouldCalculateAverage = true;
            newAvg = distanceSinceLastFull / actualFuelAddedToTank;
          }

          if (shouldCalculateAverage) {
            newAvg = double.parse(newAvg.toStringAsFixed(1));

            // Update averages
            newFirstAvg ??= newAvg;
            newPreviousAvg = newCurrentAvg;
            newCurrentAvg = newAvg;
            averageWasCalculated = true;
          }
        }

        // ELSE: First full refill - do NOT calculate average yet (just a starting point)

        // STEP 6: AFTER FULL REFILL
        finalFuelRemaining = vehicle.tankCapacity;
      } else {
        // STEP 2: PARTIAL REFILL LOGIC
        // DO NOT change any averages
        if (finalFuelRemaining > vehicle.tankCapacity) {
          finalFuelRemaining = vehicle.tankCapacity;
        }
      }

      // STEP 7: SAFETY RULES
      if (finalFuelRemaining < 0) finalFuelRemaining = 0;
      if (finalFuelRemaining > vehicle.tankCapacity) finalFuelRemaining = vehicle.tankCapacity;

      // Update vehicle in database
      final updatedVehicle = vehicle.copyWith(
        previousMileage: currentMileage,
        fuelRemaining: finalFuelRemaining,
        totalDistanceAccumulated: newTotalDistance,
        totalFuelAddedAccumulated: newTotalFuel,
        firstAvg: newFirstAvg,
        previousAvg: newPreviousAvg,
        currentAvg: newCurrentAvg,
      );

      await updateVehicle(updatedVehicle);

      // Create refill record
      final response = await _supabase.from(refillsTable).insert({
        'vehicle_id': vehicleId,
        'mileage': currentMileage,
        'fuel_added': fuelAdded,
        'tank_full': isFull,
        'fuel_cost': fuelCost,
        'price_per_litre': fuelPrice,
      }).select();

      if (response.isEmpty) throw Exception('Failed to save refill');
      final savedRefill = RefillRecord.fromJson(response.first);
      return RefillResult(
        refillRecord: savedRefill,
        averageCalculated: averageWasCalculated,
        calculatedAvg: averageWasCalculated ? newCurrentAvg : null,
      );
    } catch (e) {
      throw Exception('Error adding refill: $e');
    }
  }

  /// Estimate remaining fuel at given mileage
  Future<double> estimateRemainingFuel(
      String vehicleId,
      double currentMileage,
      ) async {
    try {
      final vehicle = await getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final refills = await getRefills(vehicleId);
      if (refills.isEmpty) {
        // No refill history - return tank capacity
        return vehicle.tankCapacity;
      }

      // Find the MOST RECENT FULL TANK refill by mileage (highest mileage with tankFull=true)
      RefillRecord? lastFullRefill;
      double maxMileage = -1;

      for (final refill in refills) {
        if (refill.tankFull && refill.mileage <= currentMileage) {
          if (refill.mileage > maxMileage) {
            maxMileage = refill.mileage;
            lastFullRefill = refill;
          }
        }
      }

      if (lastFullRefill == null) {
        // No full tank recorded yet - return stored fuelRemaining
        return vehicle.fuelRemaining;
      }

      // Get all refills AFTER the last full tank (including partial refills)
      final refillsAfterLastFull = refills
          .where((r) => r.mileage > lastFullRefill!.mileage)
          .toList();

      // Start with full tank
      double currentFuel = vehicle.tankCapacity;

      // Subtract fuel consumed from driving
      double distanceSinceFullTank = currentMileage - lastFullRefill.mileage;
      if (distanceSinceFullTank < 0) {
        // Current mileage is before last full refill (shouldn't happen)
        return vehicle.fuelRemaining;
      }

      double avgForCalc = getAverageForConsumption(vehicle, refills);
      double fuelConsumed = distanceSinceFullTank / avgForCalc;
      currentFuel -= fuelConsumed;

      // Add back any partial refills after the last full tank
      for (final refill in refillsAfterLastFull) {
        if (!refill.tankFull) {
          // This is a partial refill - add the fuel
          currentFuel += refill.fuelAdded;
        }
      }

      // Make sure result is within valid range
      if (currentFuel < 0) currentFuel = 0;
      if (currentFuel > vehicle.tankCapacity) {
        currentFuel = vehicle.tankCapacity;
      }

      return currentFuel;
    } catch (e) {
      throw Exception('Error estimating fuel: $e');
    }
  }

  /// Get fuel statistics for a vehicle
  Future<Map<String, dynamic>> getFuelStatistics(String vehicleId) async {
    try {
      final vehicle = await getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final refills = await getRefills(vehicleId);

      double totalFuelSpent = refills.fold(0, (sum, r) => sum + r.fuelCost);
      double totalFuelAdded = refills.fold(0, (sum, r) => sum + r.fuelAdded);
      int fullTanks = refills.where((r) => r.tankFull).length;
      final validAverage = getValidatedAverage(vehicle, refills);

      return {
        'total_fuel_spent': totalFuelSpent,
        'total_fuel_added': totalFuelAdded,
        'full_tanks': fullTanks,
        'refill_count': refills.length,
        'current_fuel': vehicle.fuelRemaining,
        'average_km_per_liter': validAverage ?? 'N/A',
        'first_average': vehicle.firstAvg ?? 'N/A',
        'previous_average': vehicle.previousAvg ?? 'N/A',
      };
    } catch (e) {
      throw Exception('Error getting statistics: $e');
    }
  }

  /// Delete a vehicle
  Future<void> deleteVehicle(String vehicleId) async {
    try {
      // Delete refills first
      await _supabase.from(refillsTable).delete().eq('vehicle_id', vehicleId);

      // Delete vehicle
      await _supabase.from(vehiclesTable).delete().eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error deleting vehicle: $e');
    }
  }

  /// Edit an existing refill record with mileage validation
  /// Mileage must maintain chronological order: older refills have lower mileage, newer have higher
  Future<RefillResult> editRefill({
    required String refillId,
    required String vehicleId,
    required double currentMileage,
    required double fuelCost,
    required bool isManualFull,
    double fuelPrice = 300.0,
  }) async {
    try {
      // Get the refill to edit
      final existingRefill = await _supabase
          .from(refillsTable)
          .select()
          .eq('id', refillId)
          .single();

      if (existingRefill == null) throw Exception('Refill not found');

      final createdAtExisting = existingRefill['created_at'];

      // Load all refills to validate mileage order
      final allRefills = await getRefills(vehicleId);

      // Find this refill in the list to determine its position in time
      final thisRefillIndex = allRefills.indexWhere((r) => r.id == refillId);
      if (thisRefillIndex == -1) throw Exception('Refill not found in vehicle history');

      // Validate mileage is strictly increasing with chronological order
      // All refills BEFORE this one (newer) must have HIGHER mileage
      // All refills AFTER this one (older) must have LOWER mileage

      for (int i = 0; i < thisRefillIndex; i++) {
        // These are newer refills (earlier in the list since sorted by created_at DESC)
        if (currentMileage >= allRefills[i].mileage) {
          throw Exception(
            'Mileage ${currentMileage.toStringAsFixed(1)}km cannot be >= newer refill mileage ${allRefills[i].mileage.toStringAsFixed(1)}km',
          );
        }
      }

      for (int i = thisRefillIndex + 1; i < allRefills.length; i++) {
        // These are older refills (later in the list since sorted by created_at DESC)
        if (currentMileage <= allRefills[i].mileage) {
          throw Exception(
            'Mileage ${currentMileage.toStringAsFixed(1)}km must be > older refill mileage ${allRefills[i].mileage.toStringAsFixed(1)}km',
          );
        }
      }

      // Load current vehicle state
      final vehicle = await getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      // Calculate fuel added using the new cost and provided fuel price
      double fuelAdded = fuelCost / fuelPrice;

      // Validate fuel price and fuel added
      if (fuelPrice <= 0) {
        throw Exception('Fuel price must be greater than 0');
      }
      if (fuelAdded <= 0) {
        throw Exception('Fuel added must be greater than 0');
      }

      // Initialize average variables
      double? newFirstAvg = vehicle.firstAvg;
      double? newPreviousAvg = vehicle.previousAvg;
      double? newCurrentAvg = vehicle.currentAvg;
      bool averageWasCalculated = false;

      // Determine if this refill should be treated as a full tank entry
      bool isFull = isManualFull;

      // If the stored average is not supported by enough full tank history,
      // clear it so stale values are not reused or shown.
      if (!hasValidAverage(vehicle, allRefills)) {
        newFirstAvg = null;
        newPreviousAvg = null;
        newCurrentAvg = null;
      }

      // If marking as full tank, recalculate average
      if (isFull) {
        // Find previous full refills (older ones with lower mileage)
        final previousFullRefills = allRefills
            .where((r) => r.tankFull && r.mileage < currentMileage && r.id != refillId);

        RefillRecord? lastFullRefill;
        if (previousFullRefills.isNotEmpty) {
          lastFullRefill = previousFullRefills.reduce(
                (a, b) => a.mileage > b.mileage ? a : b,
          );
        }

        if (lastFullRefill != null) {
          double distanceSinceLastFull = currentMileage - lastFullRefill.mileage;

          if (distanceSinceLastFull > 0 && lastFullRefill.fuelAdded > 0) {
            double newAverage = distanceSinceLastFull / lastFullRefill.fuelAdded;

            if (vehicle.firstAvg == null) {
              newFirstAvg = newAverage;
              newPreviousAvg = newAverage;
              newCurrentAvg = newAverage;
            } else {
              newPreviousAvg = vehicle.currentAvg ?? vehicle.firstAvg;
              newCurrentAvg = newAverage;
            }
            averageWasCalculated = true;
          }
        }
      }

      // Update the refill record
      final updatePayload = {
        'mileage': currentMileage,
        'fuel_cost': fuelCost,
        'fuel_added': fuelAdded,
        'tank_full': isFull,
        'price_per_litre': fuelPrice,
      };

      await _supabase
          .from(refillsTable)
          .update(updatePayload)
          .eq('id', refillId);

      // Update vehicle averages
      final vehicleUpdatePayload = {
        'first_avg': newFirstAvg,
        'previous_avg': newPreviousAvg,
        'current_avg': newCurrentAvg,
      };

      await _supabase
          .from(vehiclesTable)
          .update(vehicleUpdatePayload)
          .eq('id', vehicleId);

      return RefillResult(
        refillRecord: RefillRecord(
          id: refillId,
          vehicleId: vehicleId,
          mileage: currentMileage,
          fuelCost: fuelCost,
          fuelAdded: fuelAdded,
          tankFull: isFull,
          pricePerLitre: fuelPrice,
          createdAt: DateTime.parse(createdAtExisting),
        ),
        averageCalculated: averageWasCalculated,
      );
    } catch (e) {
      throw Exception('Error editing refill: $e');
    }
  }

  /// Delete a refill record
  Future<void> deleteRefill(String refillId, String vehicleId) async {
    try {
      // Get the refill to delete
      final refillToDelete = await _supabase
          .from(refillsTable)
          .select()
          .eq('id', refillId)
          .single();

      if (refillToDelete == null) throw Exception('Refill not found');

      // Delete the refill
      await _supabase.from(refillsTable).delete().eq('id', refillId);

      // Recalculate vehicle averages after deletion
      final vehicle = await getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final refills = await getRefills(vehicleId);

      // Recalculate totals and averages
      double newTotalDistance = 0;
      double newTotalFuel = 0;
      double? newFirstAvg;
      double? newPreviousAvg;
      double? newCurrentAvg;

      if (refills.isNotEmpty) {
        // Recalculate totals
        for (final refill in refills) {
          newTotalFuel += refill.fuelAdded;
        }

        // Find full tank refills for average calculation
        final fullRefills = refills.where((r) => r.tankFull).toList();
        if (fullRefills.length >= 2) {
          fullRefills.sort((a, b) => a.mileage.compareTo(b.mileage));

          // Calculate averages from consecutive full refills
          double totalDistance = 0;
          double totalFuel = 0;
          int validSegments = 0;

          for (int i = 1; i < fullRefills.length; i++) {
            double distance = fullRefills[i].mileage - fullRefills[i - 1].mileage;
            double fuel = fullRefills[i - 1].fuelAdded;

            if (distance > 0 && fuel > 0) {
              totalDistance += distance;
              totalFuel += fuel;
              validSegments++;
            }
          }

          if (validSegments > 0) {
            double average = totalDistance / totalFuel;
            newCurrentAvg = average;
            newPreviousAvg = average;
            if (vehicle.firstAvg == null) {
              newFirstAvg = average;
            } else {
              newFirstAvg = vehicle.firstAvg;
            }
          }
        }
      }

      // Update vehicle
      final vehicleUpdatePayload = {
        'total_distance_accumulated': newTotalDistance,
        'total_fuel_added_accumulated': newTotalFuel,
        'first_avg': newFirstAvg,
        'previous_avg': newPreviousAvg,
        'current_avg': newCurrentAvg,
        'updated_at': DateTime.now().toIso8601String(),
      };

      await _supabase
          .from(vehiclesTable)
          .update(vehicleUpdatePayload)
          .eq('id', vehicleId);
    } catch (e) {
      throw Exception('Error deleting refill: $e');
    }
  }
}
