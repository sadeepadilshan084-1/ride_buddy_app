import 'package:supabase_flutter/supabase_flutter.dart';

class FuelPrice {
  final String id;
  final String fuelType;
  final double price;
  final DateTime updatedAt;

  FuelPrice({
    required this.id,
    required this.fuelType,
    required this.price,
    required this.updatedAt,
  });

  factory FuelPrice.fromJson(Map<String, dynamic> json) {
    return FuelPrice(
      id: json['id'],
      fuelType: json['fuel_type'],
      price: (json['price'] as num).toDouble(),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'fuel_type': fuelType,
      'price': price,
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class FuelPriceService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<FuelPrice>> getFuelPrices() async {
    final response = await _supabase
        .from('fuel_prices')
        .select()
        .order('fuel_type');

    return response.map((json) => FuelPrice.fromJson(json)).toList();
  }

  Future<FuelPrice> updateFuelPrice(String fuelType, double newPrice) async {
    final response = await _supabase
        .from('fuel_prices')
        .update({'price': newPrice})
        .eq('fuel_type', fuelType)
        .select()
        .single();

    return FuelPrice.fromJson(response);
  }

  Future<FuelPrice> addFuelPrice(String fuelType, double price) async {
    final response = await _supabase
        .from('fuel_prices')
        .insert({
          'fuel_type': fuelType,
          'price': price,
        })
        .select()
        .single();

    return FuelPrice.fromJson(response);
  }

  // Get fuel price by type
  Future<double?> getFuelPrice(String fuelType) async {
    final response = await _supabase
        .from('fuel_prices')
        .select('price')
        .eq('fuel_type', fuelType)
        .single();

    return (response['price'] as num?)?.toDouble();
  }
}