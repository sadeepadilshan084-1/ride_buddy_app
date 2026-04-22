import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../services/supabase_service.dart';
import '../services/fuel_price_service.dart';
import '../services/fuel_tracker_service.dart';
import '../services/selected_vehicle_provider.dart';
import '../google_api_config.dart';

class TripCostCalculatorPage extends StatefulWidget {
  const TripCostCalculatorPage({Key? key}) : super(key: key);

  @override
  State<TripCostCalculatorPage> createState() => _TripCostCalculatorPageState();
}

class _TripCostCalculatorPageState extends State<TripCostCalculatorPage> {
  GoogleMapController? _mapController;
  LatLng? _currentLocation;
  LatLng? _destinationLocation;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  bool _isLoading = false;
  String _distance = '';
  String _duration = '';
  double _fuelEfficiency = 0.0; // Will be fetched automatically
  double _fuelPrice = 0.0; // Will be fetched automatically
  double _estimatedFuel = 0.0;
  double _estimatedCost = 0.0;
  String _currentLocationAddress = 'Getting location...';

  // Vehicle selection state
  Vehicle? _selectedVehicle;
  List<Vehicle> _availableVehicles = [];
  String _currentFuelType = 'Unknown'; // Current fuel type of selected vehicle
  bool _isLoadingVehicles = false;

  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _currentLocationController = TextEditingController();
  final TextEditingController _fuelEfficiencyController = TextEditingController(text: '15.0');
  final TextEditingController _fuelPriceController = TextEditingController(text: '300.0');

  final SupabaseService _supabaseService = SupabaseService();
  final FuelTrackerService _fuelTrackerService = FuelTrackerService();
  final FuelPriceService _fuelPriceService = FuelPriceService();
  final SelectedVehicleProvider _selectedVehicleProvider = SelectedVehicleProvider();

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _destinationController.dispose();
    _currentLocationController.dispose();
    _fuelEfficiencyController.dispose();
    _fuelPriceController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    // Initialize the vehicle provider first
    await _selectedVehicleProvider.initialize();

    // Load vehicles and use persisted selection
    await _loadAvailableVehicles();
    await Future.wait([
      _getCurrentLocation(),
      if (_selectedVehicle != null) _loadFuelData(_selectedVehicle!),
    ]);
  }

  /// Load all available vehicles for the current user
  Future<void> _loadAvailableVehicles() async {
    if (!mounted) return;

    setState(() => _isLoadingVehicles = true);
    try {
      final vehicles = await _fuelTrackerService.getVehicles();

      if (!mounted) return;

      // Try to restore the previously selected vehicle, preferring server-side active selection
      Vehicle? vehicleToSelect;
      final activeVehicle = await _fuelTrackerService.getActiveVehicle();
      if (activeVehicle != null) {
        final activeMatch = vehicles.where((v) => v.id == activeVehicle.id);
        if (activeMatch.isNotEmpty) {
          vehicleToSelect = activeMatch.first;
          print('✓ Restored server-selected vehicle in trip calculator: ${vehicleToSelect.number}');
        }
      }

      if (vehicleToSelect == null && vehicles.isNotEmpty) {
        // First, check if there's a persisted selection and validate it
        final persistedVehicle = await _selectedVehicleProvider.validateSelectedVehicle(vehicles);

        if (persistedVehicle != null) {
          vehicleToSelect = persistedVehicle;
          print('✓ Restored persisted vehicle in trip calculator: ${vehicleToSelect.number}');
        } else {
          // Fallback to first vehicle if no valid persistence
          vehicleToSelect = vehicles.first;
          print('⚠️ No valid persisted vehicle in trip calculator, using first: ${vehicleToSelect.number}');
        }
      }

      setState(() {
        _availableVehicles = vehicles;
        _selectedVehicle = vehicleToSelect;
        if (_selectedVehicle != null) {
          _currentFuelType = _selectedVehicle!.fuelType;
        }
      });
    } catch (e) {
      _showError('Error loading vehicles: $e');
      if (mounted) setState(() => _isLoadingVehicles = false);
    }
  }

  /// Handle vehicle selection change
  Future<void> _onVehicleChanged(Vehicle? newVehicle) async {
    if (newVehicle == null) return;

    // Prevent redundant reloads if the same vehicle is selected
    if (_selectedVehicle?.id == newVehicle.id) {
      print('⚠️ Same vehicle already selected, skipping reload');
      return;
    }

    print('🚗 Vehicle changed: ${_selectedVehicle?.number} → ${newVehicle.number}');

    // Update selected vehicle
    setState(() {
      _selectedVehicle = newVehicle;
      _currentFuelType = newVehicle.fuelType;
    });

    // Persist and sync the selected vehicle
    if (newVehicle.id != null) {
      await _fuelTrackerService.setActiveVehicle(newVehicle.id!);
    }
    await _selectedVehicleProvider.setSelectedVehicle(newVehicle);

    print('📦 Fetching fuel data for: ${newVehicle.number}');

    // Immediately reload fuel data for the newly selected vehicle
    await _loadFuelData(newVehicle);

    print('✅ Fuel data reload complete for: ${newVehicle.number}');
  }

  Future<void> _loadFuelData(Vehicle vehicle) async {
    try {
      if (vehicle.id == null) {
        _showError('Vehicle ID not available');
        return;
      }

      // Validate fuel type and variant
      if (vehicle.fuelType.isEmpty || vehicle.fuelVariant.isEmpty) {
        _showError('Vehicle fuel type or variant not configured');
        return;
      }

      // IMPORTANT: Reset fuel data before fetching new data to avoid stale values
      setState(() {
        _fuelPrice = 0.0;
        _fuelPriceController.text = '';
        _fuelEfficiency = 0.0;
        _fuelEfficiencyController.text = '';
      });

      // Load fuel efficiency from the selected vehicle only when it is backed by valid full-tank history
      final refills = await _fuelTrackerService.getRefills(vehicle.id!);
      final validAverage = _fuelTrackerService.getValidatedAverage(vehicle, refills);
      if (validAverage != null && validAverage > 0) {
        setState(() {
          _fuelEfficiency = validAverage;
          _fuelEfficiencyController.text = _fuelEfficiency.toStringAsFixed(1);
        });
      } else {
        // Use a default value
        setState(() {
          _fuelEfficiency = 15.0;
          _fuelEfficiencyController.text = '15.0';
        });
        _showError('Vehicle fuel efficiency not available. Using default 15 km/L');
      }

      // CRITICAL: Load fuel price from fuel price table using vehicle's fuel type + variant
      // This must match the fuel type and variant configured in the vehicle's fuel_type and fuel_variant fields
      final fuelTypeNormalized = vehicle.fuelType.toLowerCase().trim();
      final variantNormalized = vehicle.fuelVariant.toLowerCase().trim();

      print('🔍 Fetching fuel price for: fuelType=$fuelTypeNormalized, variant=$variantNormalized');

      final variantPrice = await _fuelPriceService.getFuelPrice(
        fuelTypeNormalized,
        variantNormalized,
      );

      print('💰 Fetched price result: $variantPrice');

      if (variantPrice != null && variantPrice > 0) {
        print('✅ Using fuel prices table price: $variantPrice');
        setState(() {
          _fuelPrice = variantPrice;
          _fuelPriceController.text = _fuelPrice.toStringAsFixed(2);
        });
      } else {
        print('⚠️ No price found in fuel_prices table for $fuelTypeNormalized $variantNormalized');
        setState(() {
          _fuelPrice = 0.0;
          _fuelPriceController.text = '0.00';
        });
        _showError('Fuel price not set for ${vehicle.fuelType} ${vehicle.fuelVariant}. Please set the fuel price in the fuel price settings.');
      }

      // Update fuel type display
      setState(() {
        _currentFuelType = vehicle.fuelType;
      });

      print('✅ Fuel data loaded successfully for vehicle: ${vehicle.number}');

      // Re-calculate trip cost if distance is already set
      if (_distance.isNotEmpty) {
        _calculateTripCost();
      }
    } catch (e) {
      print('❌ Error in _loadFuelData: $e');
      _showError('Failed to load fuel data: $e');
    }
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _isLoading = true);

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showError('Location permission denied');
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final location = LatLng(position.latitude, position.longitude);
      await _updateCurrentLocation(location);
    } catch (e) {
      _showError('Failed to get current location: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateCurrentLocation(LatLng location) async {
    setState(() {
      _currentLocation = location;
      _currentLocationAddress = '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
      _currentLocationController.text = _currentLocationAddress;

      // Update marker
      _markers.removeWhere((marker) => marker.markerId.value == 'current');
      _markers.add(
        Marker(
          markerId: const MarkerId('current'),
          position: _currentLocation!,
          infoWindow: const InfoWindow(title: 'Your Location'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ),
      );
    });

    _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(_currentLocation!, 15),
    );

    // Try to get address from coordinates
    try {
      final address = await _getAddressFromLatLng(location);
      if (address.isNotEmpty) {
        setState(() {
          _currentLocationAddress = address;
          _currentLocationController.text = address;
        });
      }
    } catch (e) {
      // Keep coordinates if address fetch fails
    }
  }

  Future<String> _getAddressFromLatLng(LatLng location) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json?'
        'latlng=${location.latitude},${location.longitude}&'
        'key=$googleMapsApiKey',
      );

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          return data['results'][0]['formatted_address'];
        }
      }
    } catch (e) {
      print('Error getting address: $e');
    }
    return '';
  }

  Future<void> _getDirections() async {
    if (_currentLocation == null || _destinationLocation == null) return;

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/directions/json?'
        'origin=${_currentLocation!.latitude},${_currentLocation!.longitude}&'
        'destination=${_destinationLocation!.latitude},${_destinationLocation!.longitude}&'
        'key=$googleMapsApiKey',
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          final route = data['routes'][0];
          final leg = route['legs'][0];

          setState(() {
            _distance = leg['distance']['text'];
            _duration = leg['duration']['text'];
          });

          // Decode polyline
          final points = _decodePolyline(route['overview_polyline']['points']);
          setState(() {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('route'),
                points: points,
                color: Colors.blue,
                width: 5,
              ),
            );
          });

          // Fit camera to show entire route
          if (points.isNotEmpty) {
            LatLngBounds bounds = _getLatLngBounds(points);
            _mapController?.animateCamera(
              CameraUpdate.newLatLngBounds(bounds, 50),
            );
          }

          _calculateTripCost();
        } else {
          _showError('Failed to get directions: ${data['status']}');
        }
      } else {
        _showError('Failed to get directions');
      }
    } catch (e) {
      _showError('Error getting directions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      points.add(LatLng(lat / 1E5, lng / 1E5));
    }
    return points;
  }

  LatLngBounds _getLatLngBounds(List<LatLng> points) {
    double minLat = points[0].latitude;
    double maxLat = points[0].latitude;
    double minLng = points[0].longitude;
    double maxLng = points[0].longitude;

    for (LatLng point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    return LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
  }

  void _calculateTripCost() {
    if (_distance.isEmpty) return;

    // Extract numeric value from distance string (e.g., "15.2 km" -> 15.2)
    final distanceMatch = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(_distance);
    if (distanceMatch != null) {
      final distanceKm = double.parse(distanceMatch.group(1)!);

      // Use system data (fuel efficiency and price from vehicle profile)
      // Do not override with user input
      setState(() {
        _estimatedFuel = distanceKm / _fuelEfficiency;
        _estimatedCost = _estimatedFuel * _fuelPrice;
      });
    }
  }

  bool _isLocationInSriLanka(LatLng location) {
    // Sri Lanka geographical bounds (approximate)
    const double minLat = 5.9161;
    const double maxLat = 9.8356;
    const double minLng = 79.6524;
    const double maxLng = 81.8790;

    return location.latitude >= minLat &&
           location.latitude <= maxLat &&
           location.longitude >= minLng &&
           location.longitude <= maxLng;
  }

  void _onCurrentLocationSelected(Prediction place) {
    if (place.lat != null && place.lng != null) {
      final lat = double.tryParse(place.lat!);
      final lng = double.tryParse(place.lng!);
      if (lat != null && lng != null) {
        final location = LatLng(lat, lng);

        // Validate that location is in Sri Lanka
        if (!_isLocationInSriLanka(location)) {
          _showError('Please select a location within Sri Lanka only.');
          return;
        }

        _updateCurrentLocation(location);
        setState(() {
          _currentLocationController.text = place.description ?? '';
          _currentLocationAddress = place.description ?? '';
        });
      }
    }
  }

  void _onPlaceSelected(Prediction place) {
    if (place.lat != null && place.lng != null) {
      final lat = double.tryParse(place.lat!);
      final lng = double.tryParse(place.lng!);
      if (lat != null && lng != null) {
        final location = LatLng(lat, lng);

        // Validate that location is in Sri Lanka
        if (!_isLocationInSriLanka(location)) {
          _showError('Please select a destination within Sri Lanka only.');
          return;
        }

        setState(() {
          _destinationLocation = location;
          _destinationController.text = place.description ?? '';

          // Clear previous destination marker
          _markers.removeWhere((marker) => marker.markerId.value == 'destination');

          // Add destination marker
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: _destinationLocation!,
              infoWindow: InfoWindow(title: place.description ?? 'Destination'),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            ),
          );
        });

        _getDirections();
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Trip Cost Calculator',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          // Map
          Container(
            height: 400,
            child: _currentLocation != null
                ? GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _currentLocation!,
                      zoom: 15,
                    ),
                    markers: _markers,
                    polylines: _polylines,
                    onMapCreated: (controller) => _mapController = controller,
                    myLocationEnabled: true,
                    myLocationButtonEnabled: true,
                    // Restrict map to Sri Lanka boundaries
                    cameraTargetBounds: CameraTargetBounds(
                      LatLngBounds(
                        southwest: const LatLng(5.9161, 79.6524), // Southwest Sri Lanka
                        northeast: const LatLng(9.8356, 81.8790), // Northeast Sri Lanka
                      ),
                    ),
                    minMaxZoomPreference: const MinMaxZoomPreference(7, 18),
                  )
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
          ),

          // Loading overlay
          if (_isLoading)
            Container(
              height: 400,
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),

          // Bottom sheet content
          SingleChildScrollView(
            child: Container(
              margin: const EdgeInsets.only(top: 350),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Current Location
                    const Text(
                      'Current Location',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GooglePlaceAutoCompleteTextField(
                      textEditingController: _currentLocationController,
                      googleAPIKey: googlePlacesApiKey,
                      inputDecoration: InputDecoration(
                        hintText: 'Search current location in Sri Lanka...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.my_location),
                          onPressed: _getCurrentLocation,
                        ),
                      ),
                      debounceTime: 800,
                      countries: const ['lk'], // Restrict to Sri Lanka only
                      isLatLngRequired: true,
                      getPlaceDetailWithLatLng: _onCurrentLocationSelected,
                      itemClick: _onCurrentLocationSelected,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '🔒 Search restricted to Sri Lanka only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Destination
                    const Text(
                      'Destination',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GooglePlaceAutoCompleteTextField(
                      textEditingController: _destinationController,
                      googleAPIKey: googlePlacesApiKey,
                      inputDecoration: InputDecoration(
                        hintText: 'Search destination in Sri Lanka...',
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: const Icon(Icons.search),
                      ),
                      debounceTime: 800,
                      countries: const ['lk'], // Restrict to Sri Lanka only
                      isLatLngRequired: true,
                      getPlaceDetailWithLatLng: _onPlaceSelected,
                      itemClick: _onPlaceSelected,
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '🔒 Search restricted to Sri Lanka only',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Vehicle Selection Dropdown
                    const Text(
                      'Select Vehicle',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _isLoadingVehicles
                        ? const Center(child: CircularProgressIndicator())
                        : _availableVehicles.isEmpty
                            ? const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Text('No vehicles available. Please add a vehicle first.'),
                              )
                            : DropdownButtonFormField<Vehicle>(
                                value: _selectedVehicle,
                                decoration: const InputDecoration(
                                  labelText: 'Vehicle',
                                  border: OutlineInputBorder(),
                                  hintText: 'Select a vehicle',
                                ),
                                items: _availableVehicles
                                    .map((vehicle) => DropdownMenuItem(
                                          value: vehicle,
                                          child: Text(
                                            '${vehicle.number} - ${vehicle.model} (${vehicle.fuelType})',
                                          ),
                                        ))
                                    .toList(),
                                onChanged: _onVehicleChanged,
                                isExpanded: true,
                              ),
                    const SizedBox(height: 8),

                    // Display fuel type for selected vehicle
                    if (_selectedVehicle != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.local_gas_station,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Fuel Type',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue.shade700,
                                  ),
                                ),
                                Text(
                                  '${_currentFuelType.toUpperCase()} (${_selectedVehicle!.fuelVariant})',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Vehicle Settings
                    const Text(
                      'Vehicle Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _fuelEfficiencyController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Fuel Efficiency (km/L)',
                              border: OutlineInputBorder(),
                              hintText: 'Loaded from vehicle profile',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _fuelPriceController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Fuel Price (LKR/L)',
                              border: OutlineInputBorder(),
                              hintText: 'Loaded from system',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Results
                    if (_distance.isNotEmpty) ...[
                      const Text(
                        'Trip Details',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Distance:'),
                                Text(
                                  _distance,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Duration:'),
                                Text(
                                  _duration,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Estimated Fuel:'),
                                Text(
                                  '${_estimatedFuel.toStringAsFixed(2)} L',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Estimated Cost:'),
                                Text(
                                  'LKR ${_estimatedCost.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green.shade700,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () => _saveTrip(),
                          icon: const Icon(Icons.save),
                          label: const Text('Save Trip'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Future<void> _saveTrip() async {
    if (_destinationController.text.isEmpty || _distance.isEmpty) {
      _showError('Please complete the trip calculation first');
      return;
    }

    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId != null) {
        final success = await _supabaseService.addTripRecord(
          userId: userId,
          tripType: 'one_way',
          fromLocation: 'Current Location',
          toLocation: _destinationController.text,
          cost: 'LKR ${_estimatedCost.toStringAsFixed(2)}',
          consumption: '${_estimatedFuel.toStringAsFixed(2)} L',
          duration: _duration,
        );

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Trip saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          _showError('Failed to save trip');
        }
      }
    } catch (e) {
      _showError('Error saving trip: $e');
    }
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/home'),
            child: _buildNavItem(Icons.home, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/petrol-station'),
            child: _buildNavItem(Icons.location_on, true),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/media'),
            child: _buildNavItem(Icons.videocam, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/stats'),
            child: _buildNavItem(Icons.bar_chart, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: _buildNavItem(Icons.person, false),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: isActive ? Colors.white : Colors.grey),
    );
  }
}
