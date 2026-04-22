import 'package:supabase_flutter/supabase_flutter.dart';

class FuelPriceService {
  static final FuelPriceService _instance = FuelPriceService._internal();

  factory FuelPriceService() {
    return _instance;
  }

  FuelPriceService._internal();

  final SupabaseClient _client = Supabase.instance.client;

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

      // Try getting with both fuel_type and variant
      final response = await _client
          .from('fuel_prices')
          .select('price')
          .eq('fuel_type', normalizedFuelType)
          .eq('variant', normalizedVariant)
          .maybeSingle();

      if (response != null && response['price'] != null) {
        return (response['price'] as num).toDouble();
      }

      // Fallback: Try getting by fuel_type only if variant is not found or for legacy support
      final fallbackResponse = await _client
          .from('fuel_prices')
          .select('price')
          .eq('fuel_type', normalizedFuelType)
          .maybeSingle();

      if (fallbackResponse != null && fallbackResponse['price'] != null) {
        return (fallbackResponse['price'] as num).toDouble();
      }

      return null;
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
      // Primary attempt: Upsert with variant
      final response = await _client.from('fuel_prices').upsert({
        'fuel_type': normalizedType,
        'variant': normalizedVariant,
        'price': price,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'fuel_type,variant').select();

      if (response.isEmpty) {
        // If upsert with variant failed (e.g. schema issue), try updating just fuel_type
        await _client.from('fuel_prices').upsert({
          'fuel_type': normalizedType,
          'price': price,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'fuel_type').select();
      }

      // Log to history
      try {
        await _client.from('fuel_price_history').insert({
          'fuel_type': normalizedType,
          'variant': normalizedVariant,
          'price': price,
          'source': source,
          'updated_by': _client.auth.currentUser?.id,
          'recorded_at': DateTime.now().toIso8601String(),
        });
      } catch (historyError) {
        print('Warning: failed to insert into fuel_price_history: $historyError');
      }

      return true;
    } catch (e) {
      print('Error upserting fuel price: $e');
      return false;
    }
  }

  /// Legacy support: Update fuel price in user preferences
  Future<bool> updateFuelPrice({
    required String userId,
    required String fuelType,
    required double price,
    required String source,
  }) async {
    try {
      final column = fuelType == 'diesel' ? 'fuel_price_diesel' : 'fuel_price_petrol';
      await _client.from('user_preferences').upsert({
        'user_id': userId,
        column: price,
        'fuel_price_last_updated': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');

      return true;
    } catch (e) {
      print('Error updating user preferences fuel price: $e');
      return false;
    }
  }
}
