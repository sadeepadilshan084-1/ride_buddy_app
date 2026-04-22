import 'package:supabase_flutter/supabase_flutter.dart';

/// Service to manage service interval templates for common vehicles
class ServiceIntervalService {
  static final ServiceIntervalService _instance = ServiceIntervalService._internal();
  late final SupabaseClient _supabase;

  static const String templateTable = 'service_interval_templates';

  factory ServiceIntervalService() {
    return _instance;
  }

  ServiceIntervalService._internal() {
    _supabase = Supabase.instance.client;
  }

  // ============================================
  // GET SERVICE INTERVALS
  // ============================================

  /// Get service interval for a vehicle by make/model/fuelType
  Future<Map<String, dynamic>?> getServiceInterval({
    required String make,
    required String model,
    required String fuelType,
  }) async {
    try {
      final response = await _supabase
          .from(templateTable)
          .select()
          .eq('vehicle_make', make)
          .eq('vehicle_model', model)
          .eq('fuel_type', fuelType)
          .maybeSingle();

      return response;
    } catch (e) {
      print('Error fetching service interval: $e');
      return null;
    }
  }

  /// Get all templates for a make (for dropdown suggestions)
  Future<List<Map<String, dynamic>>> getTemplatesByMake(String make) async {
    try {
      final response = await _supabase
          .from(templateTable)
          .select()
          .eq('vehicle_make', make);

      return List<Map<String, dynamic>>.from(response ?? []);
    } catch (e) {
      print('Error fetching templates by make: $e');
      return [];
    }
  }

  /// Get all unique makes
  Future<List<String>> getAllMakes() async {
    try {
      final response = await _supabase
          .from(templateTable)
          .select('vehicle_make')
          .order('vehicle_make', ascending: true);

      final makes = <String>{};
      for (var item in response ?? []) {
        makes.add(item['vehicle_make'] as String);
      }
      return makes.toList();
    } catch (e) {
      print('Error fetching vehicle makes: $e');
      return [];
    }
  }

  /// Get models for a specific make
  Future<List<String>> getModelsForMake(String make) async {
    try {
      final response = await _supabase
          .from(templateTable)
          .select('vehicle_model')
          .eq('vehicle_make', make)
          .order('vehicle_model', ascending: true);

      final models = <String>{};
      for (var item in response ?? []) {
        models.add(item['vehicle_model'] as String);
      }
      return models.toList();
    } catch (e) {
      print('Error fetching vehicle models: $e');
      return [];
    }
  }

  /// Get fuel types for a specific make/model
  Future<List<String>> getFuelTypesForModel(String make, String model) async {
    try {
      final response = await _supabase
          .from(templateTable)
          .select('fuel_type')
          .eq('vehicle_make', make)
          .eq('vehicle_model', model)
          .order('fuel_type', ascending: true);

      final fuelTypes = <String>{};
      for (var item in response ?? []) {
        fuelTypes.add(item['fuel_type'] as String);
      }
      return fuelTypes.toList();
    } catch (e) {
      print('Error fetching fuel types: $e');
      return [];
    }
  }

  // ============================================
  // DEFAULT FALLBACK INTERVALS
  // ============================================

  /// Get default intervals if no template found
  /// Returns sensible defaults based on fuel type
  static Map<String, dynamic> getDefaultServiceInterval(String? fuelType) {
    // Different intervals for different fuel types
    switch (fuelType?.toLowerCase()) {
      case 'diesel':
        return {
          'service_interval_days': 210, // 7 months
          'service_interval_km': 7000,
          'warranty_years': 3,
        };
      case 'cng':
        return {
          'service_interval_days': 150, // 5 months
          'service_interval_km': 5000,
          'warranty_years': 3,
        };
      case 'electric':
        return {
          'service_interval_days': 365, // 1 year
          'service_interval_km': 20000, // Less frequent for electric
          'warranty_years': 5,
        };
      case 'hybrid':
        return {
          'service_interval_days': 180, // 6 months
          'service_interval_km': 8000,
          'warranty_years': 4,
        };
      case 'petrol':
      default:
        return {
          'service_interval_days': 180, // 6 months
          'service_interval_km': 5000,
          'warranty_years': 3,
        };
    }
  }

  // ============================================
  // SAMPLE DATA SEEDING
  // ============================================

  /// Seed initial service interval templates
  /// Call this once during app setup if database is empty
  Future<void> seedServiceIntervals() async {
    try {
      // Check if already seeded
      final existing = await _supabase
          .from(templateTable)
          .select('count', { Count.exact })
          .maybeSingle();

      if (existing?['count'] as int? ?? 0 > 0) {
        print('Service intervals already seeded');
        return;
      }

      // Sample data for popular Indian vehicles
      final data = [
        // Maruti Suzuki
        {'vehicle_make': 'Maruti Suzuki', 'vehicle_model': 'Swift', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Maruti Suzuki', 'vehicle_model': 'Swift', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Maruti Suzuki', 'vehicle_model': 'Baleno', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Maruti Suzuki', 'vehicle_model': 'Eeco', 'fuel_type': 'cng', 'service_interval_days': 150, 'service_interval_km': 5000, 'warranty_years': 3},

        // Hyundai
        {'vehicle_make': 'Hyundai', 'vehicle_model': 'i20', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 5},
        {'vehicle_make': 'Hyundai', 'vehicle_model': 'i20', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 5},
        {'vehicle_make': 'Hyundai', 'vehicle_model': 'Creta', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 5},
        {'vehicle_make': 'Hyundai', 'vehicle_model': 'Elantra', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 5},

        // Tata
        {'vehicle_make': 'Tata', 'vehicle_model': 'Nexon', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Tata', 'vehicle_model': 'Nexon', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Tata', 'vehicle_model': 'Tigor', 'fuel_type': 'cng', 'service_interval_days': 150, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Tata', 'vehicle_model': 'Harrier', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},

        // Honda
        {'vehicle_make': 'Honda', 'vehicle_model': 'City', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Honda', 'vehicle_model': 'City', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Honda', 'vehicle_model': 'Civic', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},

        // Toyota
        {'vehicle_make': 'Toyota', 'vehicle_model': 'Fortuner', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Toyota', 'vehicle_model': 'Innova', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Toyota', 'vehicle_model': 'Fortuner', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},

        // Mahindra
        {'vehicle_make': 'Mahindra', 'vehicle_model': 'XUV300', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
        {'vehicle_make': 'Mahindra', 'vehicle_model': 'XUV300', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},
        {'vehicle_make': 'Mahindra', 'vehicle_model': 'Bolero', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 3},

        // Kia
        {'vehicle_make': 'Kia', 'vehicle_model': 'Seltos', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 5},
        {'vehicle_make': 'Kia', 'vehicle_model': 'Seltos', 'fuel_type': 'diesel', 'service_interval_days': 210, 'service_interval_km': 7000, 'warranty_years': 5},

        // MG Motor
        {'vehicle_make': 'MG Motor', 'vehicle_model': 'ZS EV', 'fuel_type': 'electric', 'service_interval_days': 365, 'service_interval_km': 20000, 'warranty_years': 5},
        {'vehicle_make': 'MG Motor', 'vehicle_model': 'Hector', 'fuel_type': 'petrol', 'service_interval_days': 180, 'service_interval_km': 5000, 'warranty_years': 3},
      ];

      // Insert all at once
      await _supabase.from(templateTable).insert(data);
      print('Service intervals seeded successfully (${data.length} entries)');
    } catch (e) {
      print('Error seeding service intervals: $e');
    }
  }
}
