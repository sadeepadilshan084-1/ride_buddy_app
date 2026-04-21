import 'package:supabase_flutter/supabase_flutter.dart';

class FuelPriceService {
  static final FuelPriceService _instance = FuelPriceService._internal();

  factory FuelPriceService() {
    return _instance;
  }

  FuelPriceService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // Fuel prices are now user-managed only - no API or defaults
  // Users must manually set their fuel prices

  /// Get current fuel prices for a user
  Future<Map<String, dynamic>?> getUserFuelPrices(String userId) async {
    try {
      final response = await _client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .single();

      print('✓ User preferences loaded: $response');

      // Handle case where columns might not exist and normalize types to double
      final petrolRaw =
          response['fuel_price_petrol'] ?? response['fuel_price'] ?? null;
      final dieselRaw = response['fuel_price_diesel'] ?? null;
      final lastUpdated = response['fuel_price_last_updated'];

      double? parseToDouble(dynamic v) {
        if (v == null) return null;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v);
        return null;
      }

      final petrolPrice = parseToDouble(petrolRaw);
      final dieselPrice = parseToDouble(dieselRaw);

      final result = {
        'fuel_price_petrol': petrolPrice,
        'fuel_price_diesel': dieselPrice,
        'fuel_price_last_updated': lastUpdated,
      };

      print('Processed fuel prices: $result');
      return result;
    } catch (e) {
      print('❌ Error fetching user fuel prices: $e');
      print('This might be because:');
      print(
        '1. The columns (fuel_price_petrol, fuel_price_diesel) do not exist in user_preferences table',
      );
      print('2. The user_preferences table does not exist');
      print('3. The user_id does not exist in user_preferences');
      print('Solution: Run the SQL migration in fuel_price_setup.sql');
      return null;
    }
  }

  /// Get fuel prices from dedicated fuel_prices table
  Future<List<Map<String, dynamic>>> getFuelPrices() async {
    try {
      final response = await _client.from('fuel_prices').select();
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching fuel prices: $e');
      return [];
    }
  }

  /// Get a specific fuel price by type and variant
  Future<double?> getFuelPrice(String fuelType, String variant) async {
    try {
      final normalizedFuelType = fuelType.toLowerCase().trim();
      final normalizedVariant = variant.toLowerCase().trim();

      final response = await _client
          .from('fuel_prices')
          .select('price, fuel_type, variant')
          .eq('fuel_type', normalizedFuelType)
          .eq('variant', normalizedVariant)
          .single();

      // back-compat fallback for old schema (no variant column)
      if (response == null) {
        final fallback = await _client
            .from('fuel_prices')
            .select('price')
            .eq('fuel_type', normalizedFuelType)
            .single();
        if (fallback != null && fallback['price'] != null) {
          return (fallback['price'] as num).toDouble();
        }
        return null;
      }

      final dynamic price = response['price'];
      return price != null ? (price as num).toDouble() : null;
    } catch (e) {
      print('Error fetching fuel price for $fuelType/$variant: $e');
      return null;
    }
  }

  /// Upsert a price for a fuel type and variant in fuel_prices
  Future<bool> upsertFuelPrice({
    required String fuelType,
    required String variant,
    required double price,
    required String source,
  }) async {
    final normalizedType = fuelType.toLowerCase().trim();
    final normalizedVariant = variant.toLowerCase().trim();

    try {
      final response = await _client.from('fuel_prices').upsert({
        'fuel_type': normalizedType,
        'variant': normalizedVariant,
        'price': price,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fuel_type,variant').select();

      if (response == null || (response is List && response.isEmpty)) {
        throw Exception('Fuel price upsert failed; no record returned');
      }

      // Also support older schema fallback item update for compatibility.
      // When variant is not found, we still keep the old fuel_type row updated.
      try {
        await _client.from('fuel_prices').update({
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('fuel_type', normalizedType).eq('variant', normalizedVariant);
      } catch (_) {
        // ignore since we've already performed upsert.
      }

      try {
        await _client.from('fuel_price_history').insert({
          'fuel_type': normalizedType,
          'variant': normalizedVariant,
          'price': price,
          'source': source,
          'updated_by': _client.auth.currentUser?.id,
          'recorded_at': DateTime.now().toIso8601String(),
        }).select();
      } catch (historyError) {
        print('Warning: failed to insert into fuel_price_history: $historyError');
      }

      return true;
    } catch (e, st) {
      print('Error upserting fuel price: $e');
      print('Stack trace: $st');
      return false;
    }
  }

  /// Update fuel price in user preferences and save to history (legacy fallback)
  Future<bool> updateFuelPrice({
    required String userId,
    required String fuelType, // 'petrol', 'diesel', 'super_petrol'
    required double price,
    required String source, // 'manual'
  }) async {
    try {
      // Update user_preferences (use .select() to get server response)
      try {
        if (fuelType == 'diesel') {
          final upsertRes = await _client.from('user_preferences').upsert({
            'user_id': userId,
            'fuel_price_diesel': price,
            'fuel_price_last_updated': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id').select();
          print('Upsert result (diesel): $upsertRes');
        } else {
          // petrol and super_petrol both update petrol price
          final upsertRes = await _client.from('user_preferences').upsert({
            'user_id': userId,
            'fuel_price_petrol': price,
            'fuel_price_last_updated': DateTime.now().toIso8601String(),
          }, onConflict: 'user_id').select();
          print('Upsert result (petrol): $upsertRes');
        }

        // Record in price history and log result
        final insertRes = await _client.from('fuel_price_history').insert({
          'fuel_type': fuelType,
          'price': price,
          'source': source,
          'updated_by': userId,
          'recorded_at': DateTime.now().toIso8601String(),
        }).select();
        print('Inserted price history: $insertRes');

        return true;
      } catch (e, st) {
        print('Error while writing to Supabase (updateFuelPrice): $e');
        print('Stack trace: $st');
        return false;
      }
    } catch (e) {
      print('Error updating fuel price: $e');
      return false;
    }
  }

  /// Get fuel price history for a user
  Future<List<Map<String, dynamic>>> getFuelPriceHistory({
    required String fuelType,
    int limit = 30,
  }) async {
    try {
      final response = await _client
          .from('fuel_price_history')
          .select()
          .eq('fuel_type', fuelType)
          .order('recorded_at', ascending: false)
          .limit(limit);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching fuel price history: $e');
      return [];
    }
  }
}
