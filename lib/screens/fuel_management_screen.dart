import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/vehicle_service.dart';
import '../services/fuel_price_service_new.dart';
import 'add_vehicle_screen.dart';
import 'fuel_price_settings_screen.dart';

class FuelManagementScreen extends StatefulWidget {
  const FuelManagementScreen({Key? key}) : super(key: key);

  @override
  State<FuelManagementScreen> createState() => _FuelManagementScreenState();
}

class _FuelManagementScreenState extends State<FuelManagementScreen> {
  final VehicleService _vehicleService = VehicleService();
  final FuelPriceService _fuelPriceService = FuelPriceService();

  List<Vehicle> _vehicles = [];
  List<FuelPrice> _fuelPrices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _setupRealtimeSubscriptions();
  }

  void _setupRealtimeSubscriptions() {
    // Subscribe to vehicle changes
    Supabase.instance.client
        .channel('vehicles')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'vehicles',
          callback: (payload) {
            _loadVehicles();
          },
        )
        .subscribe();

    // Subscribe to fuel price changes
    Supabase.instance.client
        .channel('fuel_prices')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'fuel_prices',
          callback: (payload) {
            _loadFuelPrices();
          },
        )
        .subscribe();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    await Future.wait([
      _loadVehicles(),
      _loadFuelPrices(),
    ]);
    setState(() => _isLoading = false);
  }

  Future<void> _loadVehicles() async {
    try {
      final vehicles = await _vehicleService.getVehicles();
      setState(() => _vehicles = vehicles);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading vehicles: $e')),
      );
    }
  }

  Future<void> _loadFuelPrices() async {
    try {
      final fuelPrices = await _fuelPriceService.getFuelPrices();
      setState(() => _fuelPrices = fuelPrices);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading fuel prices: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Vehicle Fuel Management'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Vehicles', icon: Icon(Icons.directions_car)),
              Tab(text: 'Add Vehicle', icon: Icon(Icons.add)),
              Tab(text: 'Fuel Prices', icon: Icon(Icons.local_gas_station)),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _buildVehiclesList(),
                  AddVehicleScreen(onVehicleAdded: _loadVehicles),
                  FuelPriceSettingsScreen(fuelPrices: _fuelPrices, onPriceUpdated: _loadFuelPrices),
                ],
              ),
      ),
    );
  }

  Widget _buildVehiclesList() {
    if (_vehicles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.directions_car_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'No vehicles added yet',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tap the "Add Vehicle" tab to add your first vehicle',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _vehicles.length,
      itemBuilder: (context, index) {
        final vehicle = _vehicles[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Icon(
              _getVehicleIcon(vehicle.vehicleType ?? 'Car'),
              color: Theme.of(context).primaryColor,
            ),
            title: Text(vehicle.vehicleName),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Number: ${vehicle.vehicleNumber}'),
                Text('Type: ${vehicle.vehicleType ?? 'N/A'}'),
                Text('Fuel: ${vehicle.fuelType ?? 'N/A'}'),
                Text('Mileage: ${vehicle.currentMileage} km'),
              ],
            ),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete'),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') {
                  _editVehicle(vehicle);
                } else if (value == 'delete') {
                  _deleteVehicle(vehicle);
                }
              },
            ),
          ),
        );
      },
    );
  }

  IconData _getVehicleIcon(String vehicleType) {
    switch (vehicleType.toLowerCase()) {
      case 'car':
        return Icons.directions_car;
      case 'motorcycle':
      case 'bike':
        return Icons.motorcycle;
      case 'truck':
        return Icons.local_shipping;
      case 'van':
        return Icons.airport_shuttle;
      case 'bus':
        return Icons.directions_bus;
      default:
        return Icons.directions_car;
    }
  }

  void _editVehicle(Vehicle vehicle) {
    // Navigate to edit screen (can reuse AddVehicleScreen with initial data)
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddVehicleScreen(
          vehicle: vehicle,
          onVehicleAdded: _loadVehicles,
        ),
      ),
    );
  }

  void _deleteVehicle(Vehicle vehicle) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Vehicle'),
        content: Text('Are you sure you want to delete ${vehicle.vehicleName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _vehicleService.deleteVehicle(vehicle.id);
                _loadVehicles();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vehicle deleted successfully')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting vehicle: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}