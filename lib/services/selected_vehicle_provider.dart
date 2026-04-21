import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'fuel_tracker_service.dart';

/// Service to manage persistent vehicle selection across the app
/// Stores the last selected vehicle and restores it on app startup
class SelectedVehicleProvider {
  static final SelectedVehicleProvider _instance = SelectedVehicleProvider._internal();
  
  late SharedPreferences _prefs;
  Vehicle? _selectedVehicle;
  
  // Storage keys
  static const String _selectedVehicleIdKey = 'selected_vehicle_id';
  static const String _selectedVehicleJsonKey = 'selected_vehicle_json';
  
  factory SelectedVehicleProvider() {
    return _instance;
  }
  
  SelectedVehicleProvider._internal();
  
  /// Initialize the provider with SharedPreferences
  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadSelectedVehicle();
  }
  
  /// Load the last selected vehicle from storage
  Future<void> _loadSelectedVehicle() async {
    try {
      final vehicleJson = _prefs.getString(_selectedVehicleJsonKey);
      if (vehicleJson != null && vehicleJson.isNotEmpty) {
        final json = jsonDecode(vehicleJson) as Map<String, dynamic>;
        _selectedVehicle = Vehicle.fromJson(json);
        print('✓ Loaded selected vehicle from storage: ${_selectedVehicle?.number}');
      }
    } catch (e) {
      print('⚠️ Error loading selected vehicle: $e');
      _selectedVehicle = null;
    }
  }
  
  /// Get the currently selected vehicle
  Vehicle? getSelectedVehicle() {
    return _selectedVehicle;
  }
  
  /// Set the selected vehicle and persist it
  Future<void> setSelectedVehicle(Vehicle? vehicle) async {
    try {
      _selectedVehicle = vehicle;
      
      if (vehicle != null) {
        // Store vehicle ID for quick reference
        await _prefs.setString(_selectedVehicleIdKey, vehicle.id ?? '');
        
        // Store full vehicle JSON for restoration
        final vehicleJson = jsonEncode(vehicle.toJson());
        await _prefs.setString(_selectedVehicleJsonKey, vehicleJson);
        
        print('✓ Selected vehicle persisted: ${vehicle.number}');
      } else {
        // Clear selection
        await _prefs.remove(_selectedVehicleIdKey);
        await _prefs.remove(_selectedVehicleJsonKey);
        print('✓ Selected vehicle cleared');
      }
    } catch (e) {
      print('❌ Error persisting selected vehicle: $e');
    }
  }
  
  /// Get the last selected vehicle ID
  String? getSelectedVehicleId() {
    return _prefs.getString(_selectedVehicleIdKey);
  }
  
  /// Check if a vehicle is currently selected
  bool hasSelectedVehicle() {
    return _selectedVehicle != null;
  }
  
  /// Clear the selected vehicle (useful on logout)
  Future<void> clearSelectedVehicle() async {
    try {
      await _prefs.remove(_selectedVehicleIdKey);
      await _prefs.remove(_selectedVehicleJsonKey);
      _selectedVehicle = null;
      print('✓ Selected vehicle cleared');
    } catch (e) {
      print('❌ Error clearing selected vehicle: $e');
    }
  }
  
  /// Validate if stored vehicle still exists in the system
  /// Returns the vehicle if it exists, null otherwise
  Future<Vehicle?> validateSelectedVehicle(List<Vehicle> availableVehicles) async {
    if (_selectedVehicle == null || _selectedVehicle!.id == null) {
      return null;
    }
    
    final exists = availableVehicles.any((v) => v.id == _selectedVehicle!.id);
    
    if (!exists) {
      print('⚠️ Selected vehicle no longer exists in user vehicles');
      await clearSelectedVehicle();
      return null;
    }
    
    return _selectedVehicle;
  }
}
