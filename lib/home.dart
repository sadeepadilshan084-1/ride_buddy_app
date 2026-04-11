import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'l10n/app_localizations.dart';
import 'package:ride_buddy/services/fuel_tracker_service.dart' as fts;
import 'package:ride_buddy/services/advanced_fuel_tracker_service.dart' as afts;
import 'package:ride_buddy/services/fuel_price_service.dart';
import 'package:ride_buddy/services/selected_vehicle_provider.dart';
import 'package:ride_buddy/services/reminder_service.dart';
import 'package:ride_buddy/services/supabase_service.dart';
import 'package:ride_buddy/services/media_storage_service.dart';
import 'package:ride_buddy/services/backend_models.dart';
import 'package:ride_buddy/services/location_service.dart';
import 'package:ride_buddy/services/weather_service.dart';
import 'package:ride_buddy/screens/fuel_analytics_dashboard.dart';
import 'package:ride_buddy/screens/fuel_notifications_panel.dart';
import 'package:ride_buddy/screens/reminder_screen.dart';

// Import Vehicle and RefillRecord from service
typedef Vehicle = fts.Vehicle;
typedef RefillRecord = fts.RefillRecord;

class FuelEntry {
  final String type;
  final String date;
  final String amount;

  FuelEntry({required this.type, required this.date, required this.amount});
}

class ChatMessage {
  final String text;
  final bool fromUser;

  ChatMessage(this.text, {this.fromUser = true});
}

class HomeScreen extends StatefulWidget {
  final String userName;

  const HomeScreen({Key? key, this.userName = 'User'}) : super(key: key);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Vehicle> vehicles = [];
  Vehicle? selectedVehicle;
  List<RefillRecord> refills = [];
  List<ChatMessage> chatLog = [];
  Map<String, double> _vehicleFuelPriceMap = {};

  RealtimeChannel? _fuelPriceChannel;

  late fts.FuelTrackerService fuelService;
  late afts.AdvancedFuelTrackerService advancedFuelService;
  late SelectedVehicleProvider _selectedVehicleProvider;
  late ReminderService _reminderService;
  late SupabaseService _supabaseService;

  bool _isWeatherLoading = false;
  String? _weatherError;
  WeatherData? _currentWeather;
  WeatherAlert? _currentWeatherAlert;
  Timer? _weatherTimer;

  bool _isQrUploading = false;
  String? _qrError;

  // Today's tasks state
  List<ReminderModel> _todayTasks = [];
  bool _hasTodayTasks = false;

  // Service reminder state
  DateTime? _nextServiceDate;
  double? _nextServiceKm;
  bool _hasServiceApproaching = false;

  final TextEditingController _mileageController = TextEditingController();
  final TextEditingController _fuelCostController = TextEditingController();

  // fuel capacity calculation state
  bool tankFull = false;
  double currentFuelPrice = 0.0; // Store current fuel price, 0.0 means not set

  bool get _hasValidFuelAverage {
    if (selectedVehicle == null || selectedVehicle!.currentAvg == null || selectedVehicle!.currentAvg! <= 0) {
      return false;
    }
    final fullTankCount = refills.where((refill) => refill.tankFull).length;
    return fullTankCount >= 2;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fuelService = fts.FuelTrackerService();
    advancedFuelService = afts.AdvancedFuelTrackerService();
    _selectedVehicleProvider = SelectedVehicleProvider();
    _reminderService = ReminderService();
    _supabaseService = SupabaseService();
    _initializeAuthListener();
    _initializeApp();
  }

  void _initializeAuthListener() {
    // Listen for auth state changes
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final session = event.session;
      if (session == null && mounted) {
        // Session expired or user logged out, redirect to login
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  Future<void> _initializeApp() async {
    // Initialize the vehicle provider first
    await _selectedVehicleProvider.initialize();
    _bindFuelPriceRealtime();
    await _refreshData();
    _initializeWeatherMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_fuelPriceChannel != null) {
      Supabase.instance.client.removeChannel(_fuelPriceChannel!);
      _fuelPriceChannel = null;
    }
    _weatherTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await loadVehicles();
    // Load refills if vehicle is selected after loadVehicles
    if (selectedVehicle != null) {
      await loadRefills();
    }
    await _loadFuelPriceMap();
    await _refreshCurrentFuelPrice();
    await _loadTodayTasks();
    await _loadNextServiceReminder();
  }

  void _initializeWeatherMonitoring() {
    _fetchWeatherAlert();
    _weatherTimer?.cancel();
    _weatherTimer = Timer.periodic(
      const Duration(minutes: 15),
      (_) => _fetchWeatherAlert(),
    );
  }

  Future<void> _fetchWeatherAlert() async {
    if (!mounted) return;

    setState(() {
      _isWeatherLoading = true;
      _weatherError = null;
    });

    try {
      final position = await LocationService().getCurrentPosition();
      final weather = await WeatherService().fetchCurrentWeather(
        position.latitude,
        position.longitude,
      );
      final alert = getWeatherAlert(weather);

      if (!mounted) return;
      setState(() {
        _currentWeather = weather;
        _currentWeatherAlert = alert;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _weatherError = error.toString();
        _currentWeather = null;
        _currentWeatherAlert = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isWeatherLoading = false;
        });
      }
    }
  }

  Widget _buildWeatherAlertCard() {
    if (_isWeatherLoading) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Row(
          children: const [
            CircularProgressIndicator(strokeWidth: 2),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Fetching live weather for safe driving...',
                style: TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    if (_weatherError != null) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.red.shade100),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade700),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Unable to load weather alert. $_weatherError',
                style: TextStyle(color: Colors.red.shade900, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    if (_currentWeather == null || _currentWeatherAlert == null) {
      return const SizedBox.shrink();
    }

    final alert = _currentWeatherAlert!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: alert.color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: alert.color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: alert.color.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(alert.icon, color: alert.color, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: alert.color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      weatherCodeToStatus(_currentWeather!.weathercode),
                      style: TextStyle(
                        fontSize: 12,
                        color: alert.color.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            alert.message,
            style: TextStyle(
              fontSize: 11,
              color: alert.color,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildWeatherDetail('Temp', '${_currentWeather!.temperature.toStringAsFixed(1)}°C'),
              _buildWeatherDetail('Wind', '${_currentWeather!.windspeed.toStringAsFixed(1)} km/h'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWeatherDetail(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVehicleQrCard() {
    final qrUrl = selectedVehicle?.qrUrl;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.green.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade900.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vehicle QR Code',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Colors.green.shade900,
            ),
          ),
          const SizedBox(height: 8),
          if (_qrError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                _qrError!,
                style: TextStyle(color: Colors.red.shade800, fontSize: 12),
              ),
            ),
          if (_isQrUploading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: const [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Expanded(child: Text('Uploading QR code...')),
                ],
              ),
            ),
          if (qrUrl == null || qrUrl.isEmpty) ...[
            const Text(
              'No QR code has been uploaded for this vehicle yet.',
              style: TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isQrUploading ? null : _pickVehicleQrImage,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload QR'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF038124),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ] else ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                MediaStorageService().getPublicQrUrl(qrUrl),
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 160,
                  color: Colors.green.shade100,
                  child: Center(
                    child: Text(
                      'Unable to preview QR image',
                      style: TextStyle(color: Colors.green.shade900),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _viewVehicleQr,
                    child: const Text('View QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF038124),
                      side: BorderSide(color: Colors.green.shade300),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _replaceVehicleQr,
                    child: const Text('Replace QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF038124),
                      side: BorderSide(color: Colors.green.shade300),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _deleteVehicleQr,
                    child: const Text('Delete QR'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                      side: BorderSide(color: Colors.red.shade200),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickVehicleQrImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (image == null) return;
      await _uploadVehicleQr(File(image.path));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrError = 'Failed to select QR image. Please try again.';
      });
    }
  }

  Future<void> _uploadVehicleQr(File file) async {
    if (selectedVehicle == null) return;
    setState(() {
      _isQrUploading = true;
      _qrError = null;
    });

    final oldQrUrl = selectedVehicle!.qrUrl;
    try {
      final qrUrl = await MediaStorageService().uploadVehicleQrFile(
        file: file,
        vehicleId: selectedVehicle!.id!,
      );

      final updatedVehicle = selectedVehicle!.copyWith(qrUrl: qrUrl);
      final savedVehicle = await fuelService.updateVehicle(updatedVehicle);
      await _selectedVehicleProvider.setSelectedVehicle(savedVehicle);

      if (!mounted) return;
      setState(() {
        selectedVehicle = savedVehicle;
      });

      if (oldQrUrl != null && oldQrUrl.isNotEmpty) {
        await MediaStorageService().deleteFileFromUrl(oldQrUrl);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code uploaded successfully.'),
            backgroundColor: Color(0xFF038124),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrError = 'Unable to upload QR code. Please try again. ${e.toString()}';
      });
      // Also log the underlying exception for debugging
      print('QR upload failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isQrUploading = false;
        });
      }
    }
  }

  Future<void> _replaceVehicleQr() async {
    await _pickVehicleQrImage();
  }

  Future<void> _deleteVehicleQr() async {
    if (selectedVehicle == null || selectedVehicle!.qrUrl == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete QR Code'),
        content: const Text('Are you sure you want to delete the saved QR code for this vehicle?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isQrUploading = true;
      _qrError = null;
    });

    final qrUrl = selectedVehicle!.qrUrl!;
    try {
      final updatedVehicle = selectedVehicle!.copyWith(qrUrl: null);
      final savedVehicle = await fuelService.updateVehicle(updatedVehicle);
      await _selectedVehicleProvider.setSelectedVehicle(savedVehicle);

      if (!mounted) return;
      setState(() {
        selectedVehicle = savedVehicle;
      });

      await MediaStorageService().deleteVehicleQrFile(qrUrl);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR code deleted successfully.'),
            backgroundColor: Color(0xFF038124),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _qrError = 'Unable to delete QR code. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isQrUploading = false;
        });
      }
    }
  }

  void _viewVehicleQr() {
    if (selectedVehicle?.qrUrl == null) return;

    // Convert file path to public URL for displaying
    final qrUrl = MediaStorageService().getPublicQrUrl(selectedVehicle!.qrUrl!);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        contentPadding: EdgeInsets.zero,
        content: AspectRatio(
          aspectRatio: 1,
          child: Image.network(
            qrUrl,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.grey.shade200,
              child: const Center(
                child: Text('Unable to load QR image'),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _bindFuelPriceRealtime() async {
    try {
      _fuelPriceChannel = Supabase.instance.client
          .channel('public:fuel_prices')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'fuel_prices',
            callback: (payload) {
              // ignore: avoid_print
              print('Realtime fuel_prices event: $payload');
              _onFuelPricesChanged();
            },
          )
          .subscribe();
    } catch (e) {
      // ignore: avoid_print
      print('Error setting up fuel_prices realtime listener: $e');
    }
  }

  Future<void> _onFuelPricesChanged() async {
    await _loadFuelPriceMap();
    await _refreshCurrentFuelPrice();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshCurrentFuelPrice() async {
    if (selectedVehicle == null) return;

    final key = '${selectedVehicle!.fuelType.toLowerCase()}_${selectedVehicle!.fuelVariant.toLowerCase()}';
    final mappedPrice = _vehicleFuelPriceMap[key];

    if (mappedPrice != null && mappedPrice > 0) {
      if (mounted) {
        setState(() {
          currentFuelPrice = mappedPrice;
        });
      }
      return;
    }

    try {
      final price = await FuelPriceService().getFuelPrice(
        selectedVehicle!.fuelType,
        selectedVehicle!.fuelVariant,
      );

      if (mounted) {
        setState(() {
          if (price != null && price > 0) {
            currentFuelPrice = price;
            _vehicleFuelPriceMap[key] = price;
          } else {
            currentFuelPrice = 0.0;
            // Keep explicit missing price state to avoid showing stale values
            _vehicleFuelPriceMap[key] = 0.0;
          }
        });
      }
    } catch (e) {
      print('Error refreshing current fuel price: $e');
      if (mounted) {
        setState(() {
          currentFuelPrice = 0.0;
          _vehicleFuelPriceMap[key] = 0.0;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // refresh data on resume and avoid stale price cache
      _refreshData();
    }
  }

  Future<void> _loadTodayTasks() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null || selectedVehicle?.id == null) {
        if (mounted) {
          setState(() {
            _todayTasks = [];
            _hasTodayTasks = false;
          });
        }
        return;
      }

      final today = DateTime.now();
      final vehicleId = selectedVehicle!.id!;
      final reminders = await _reminderService.getUserReminders(userId);

      final todayTasks = reminders.where((reminder) {
        return reminder.vehicleId == vehicleId &&
            reminder.expiryDate.year == today.year &&
            reminder.expiryDate.month == today.month &&
            reminder.expiryDate.day == today.day &&
            reminder.status == ReminderStatus.active;
      }).toList();

      if (mounted) {
        setState(() {
          _todayTasks = todayTasks;
          _hasTodayTasks = todayTasks.isNotEmpty;
        });
      }
    } catch (e) {
      print('Error loading today tasks: $e');
    }
  }

  Future<void> _loadNextServiceReminder() async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null || selectedVehicle?.id == null) {
        if (mounted) {
          setState(() {
            _nextServiceDate = null;
            _nextServiceKm = null;
            _hasServiceApproaching = false;
          });
        }
        return;
      }

      final vehicleId = selectedVehicle!.id!;

      final response = await _supabaseService.supabase
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .eq('vehicle_id', vehicleId)
          .eq('reminder_type', 'service')
          .eq('status', 'active')
          .order('expiry_date', ascending: true)
          .limit(1)
          .maybeSingle();

      if (response != null) {
        final parsedDate = response['expiry_date'] != null
            ? DateTime.tryParse(response['expiry_date'] as String)
            : null;

        // Check if service is approaching (within 500 km)
        final currentMileage = selectedVehicle?.previousMileage ?? 0;
        double? nextServiceKm = response['service_km'] != null 
            ? (response['service_km'] as num).toDouble()
            : null;

        bool serviceApproaching = false;
        if (nextServiceKm != null && nextServiceKm > 0) {
          final kmLeft = nextServiceKm - currentMileage;
          serviceApproaching = kmLeft > 0 && kmLeft <= 500;
        }

        if (mounted) {
          setState(() {
            _nextServiceDate = parsedDate;
            _nextServiceKm = nextServiceKm;
            _hasServiceApproaching = serviceApproaching;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _nextServiceDate = null;
            _nextServiceKm = null;
            _hasServiceApproaching = false;
          });
        }
      }
    } catch (e) {
      print('Error loading next service reminder: $e');
      if (mounted) {
        setState(() {
          _nextServiceDate = null;
          _nextServiceKm = null;
          _hasServiceApproaching = false;
        });
      }
    }
  }

  double? _getFuelPriceForVehicle(Vehicle? vehicle) {
    if (vehicle == null) return null;
    final key = '${vehicle.fuelType.toLowerCase()}_${vehicle.fuelVariant.toLowerCase()}';
    return _vehicleFuelPriceMap[key];
  }

  double _calculateCurrentFuelCost() {
    final distanceKm = double.tryParse(_mileageController.text) ?? 0.0;
    final fuelPrice = _getFuelPriceForVehicle(selectedVehicle) ?? currentFuelPrice;
    if (fuelPrice <= 0) return 0.0;

    double efficiencyKmPerLiter = 10.0;
    if (_hasValidFuelAverage) {
      efficiencyKmPerLiter = selectedVehicle!.currentAvg!;
    }

    final litersNeeded = efficiencyKmPerLiter > 0 ? distanceKm / efficiencyKmPerLiter : 0.0;
    return litersNeeded * fuelPrice;
  }

  Future<void> _loadFuelPriceMap() async {
    try {
      final prices = await FuelPriceService().getFuelPrices();
      final map = <String, double>{};
      for (final item in prices) {
        final fuelType = (item['fuel_type'] as String?)?.toLowerCase();
        final variant = (item['variant'] as String?)?.toLowerCase();
        final price = (item['price'] as num?)?.toDouble();
        if (fuelType != null && variant != null && price != null) {
          final key = '${fuelType}_$variant';
          map[key] = price;
        }
      }
      if (mounted) {
        setState(() {
          _vehicleFuelPriceMap = map;
        });
      }
    } catch (e) {
      print('Error loading fuel price map: $e');
    }
  }

  Future<void> loadVehicles() async {
    try {
      final loadedVehicles = await fuelService.getVehicles();
      
      // Try to restore the previously selected vehicle from server-side active selection
      Vehicle? vehicleToSelect;
      final activeVehicle = await fuelService.getActiveVehicle();
      if (activeVehicle != null) {
        final matchingVehicles = loadedVehicles.where((v) => v.id == activeVehicle.id);
        if (matchingVehicles.isNotEmpty) {
          vehicleToSelect = matchingVehicles.first;
          print('✓ Restored server-selected vehicle: ${vehicleToSelect.number}');
        }
      }
      
      if (vehicleToSelect == null && loadedVehicles.isNotEmpty) {
        // First, check if there's a persisted selection and validate it
        final persistedVehicle = await _selectedVehicleProvider.validateSelectedVehicle(loadedVehicles);
        
        if (persistedVehicle != null) {
          vehicleToSelect = persistedVehicle;
          print('✓ Restored persisted vehicle: ${vehicleToSelect.number}');
        } else {
          // Fallback to first vehicle if no valid persistence
          vehicleToSelect = loadedVehicles.first;
          print('⚠️ No valid persisted vehicle, using first: ${vehicleToSelect.number}');
        }
      }
      
      setState(() {
        vehicles = loadedVehicles;
        selectedVehicle = vehicleToSelect;
      });
      
      // Persist and sync the selected vehicle
      if (vehicleToSelect != null) {
        await _selectedVehicleProvider.setSelectedVehicle(vehicleToSelect);
        if (vehicleToSelect.id != null) {
          await fuelService.setActiveVehicle(vehicleToSelect.id!);
        }
      }
      
      await _loadFuelPriceMap();
    } catch (e) {
      print('Error loading vehicles: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading vehicles: $e')));
      }
    }
  }

  Future<void> loadRefills() async {
    if (selectedVehicle?.id == null) return;
    try {
      final loadedRefills = await fuelService.getRefills(selectedVehicle!.id!);
      setState(() {
        refills = loadedRefills;
      });
      // Auto-fill mileage when refills are loaded
      _autoFillMileage();
    } catch (e) {
      print('Error loading refills: $e');
    }
  }

  String _getCombinedFuelType(String fuelType, String fuelVariant) {
    if (fuelType.toLowerCase() == 'petrol' && fuelVariant == '92') {
      return 'Petrol 92';
    } else if (fuelType.toLowerCase() == 'petrol' && fuelVariant == '95') {
      return 'Petrol 95';
    } else if (fuelType.toLowerCase() == 'diesel' && fuelVariant == 'auto') {
      return 'Auto Diesel';
    } else if (fuelType.toLowerCase() == 'diesel' && fuelVariant == 'super') {
      return 'Super Diesel';
    }
    // Default fallback
    return 'Petrol 92';
  }

  String _formatFuelDisplay(String fuelType, String fuelVariant) {
    final normalized = fuelType.toLowerCase().trim();
    if (normalized.contains('petrol')) return 'Petrol';
    if (normalized.contains('diesel')) return 'Diesel';
    if (normalized.contains('cng')) return 'CNG';
    if (normalized.contains('electric')) return 'Electric';
    if (fuelType.isNotEmpty) {
      return '${fuelType[0].toUpperCase()}${fuelType.substring(1)}';
    }
    return 'Fuel';
  }

  void _autoFillMileage() {
    if (selectedVehicle != null && selectedVehicle!.previousMileage > 0) {
      _mileageController.text = selectedVehicle!.previousMileage.toStringAsFixed(2);
    }
  }

  Future<void> addNewVehicle({
    required String number,
    required String model,
    required String vehicleType,
    required String fuelType,
    required String fuelVariant,
    required double tankCapacity,
    required String owner,
    required double previousMileage,
  }) async {
    try {
      // Split combined fuel type (e.g., "Petrol 92" -> fuelType: "petrol", fuelVariant: "92")
      String actualFuelType;
      String actualFuelVariant;

      if (fuelType.contains(' ')) {
        final parts = fuelType.split(' ');
        actualFuelType = parts[0].toLowerCase();
        actualFuelVariant = parts[1].toLowerCase();
      } else {
        // Fallback for old format
        actualFuelType = fuelType.toLowerCase();
        actualFuelVariant = fuelVariant.toLowerCase();
      }

      final newVehicle = await fuelService.createVehicle(
        number: number,
        model: model,
        vehicleType: vehicleType,
        fuelType: actualFuelType,
        fuelVariant: actualFuelVariant,
        tankCapacity: tankCapacity,
        owner: owner,
        previousMileage: previousMileage,
      );

      setState(() {
        vehicles.add(newVehicle);
        selectedVehicle = newVehicle;
      });

      // Persist the newly selected vehicle
      await fuelService.setActiveVehicle(newVehicle.id!);
      await _selectedVehicleProvider.setSelectedVehicle(newVehicle);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vehicle added successfully')),
        );
      }

      await loadRefills();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error adding vehicle: $e')));
      }
    }
  }

  Future<void> saveRefill() async {
    if (selectedVehicle?.id == null) return;

    final mileageText = _mileageController.text;
    final costText = _fuelCostController.text;

    if (mileageText.isEmpty || costText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter both mileage and fuel cost"),
        ),
      );
      return;
    }

    final mileage = double.tryParse(mileageText);
    final cost = double.tryParse(costText);

    if (mileage == null || cost == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid input values")));
      return;
    }

    try {
      final vehicleKey = '${selectedVehicle!.fuelType.toLowerCase()}_${selectedVehicle!.fuelVariant.toLowerCase()}';
      final selectedPrice = _vehicleFuelPriceMap[vehicleKey] ?? 0.0;

      if (selectedPrice == 0.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fuel price not set for this vehicle type. Please set the fuel price first.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      // Use dynamic fuel price from central price table
      print(
        'Saving refill with fuel price: $selectedPrice LKR, cost: $cost, liters: ${cost / selectedPrice}',
      );

      final refillResult = await fuelService.addRefill(
        vehicleId: selectedVehicle!.id!,
        currentMileage: mileage,
        fuelCost: cost,
        isManualFull: tankFull,
        fuelPrice: selectedPrice,
      );

      _mileageController.clear();
      _fuelCostController.clear();
      setState(() {
        tankFull = false;
      });

      // Reload vehicles to get updated currentAvg and previousAvg
      final updatedVehicles = await fuelService.getVehicles();
      setState(() {
        vehicles = updatedVehicles;
        // Update selectedVehicle with the latest data
        if (selectedVehicle != null) {
          selectedVehicle = vehicles.firstWhere(
            (v) => v.id == selectedVehicle!.id,
            orElse: () =>
                vehicles.isNotEmpty ? vehicles.first : selectedVehicle!,
          );
        }
      });

      await loadRefills();

      if (mounted) {
        final message = refillResult.averageCalculated
            ? "Full refill recorded. Average updated."
            : "Partial refill recorded. Average not updated.";
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving refill: $e')));
      }
    }
  }

  Future<void> _editLastRefill(RefillRecord refill) async {
    if (refill.id == null) return;

    final mileageController = TextEditingController(text: refill.mileage.toString());
    final costController = TextEditingController(text: refill.fuelCost.toString());
    bool tankFull = refill.tankFull;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Text('Edit Refill Entry'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: mileageController,
                    decoration: const InputDecoration(
                      labelText: 'Current Mileage (km)',
                      hintText: 'Must be in chronological order',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(
                      labelText: 'Fuel Cost (LKR)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Tank Full'),
                    value: tankFull,
                    onChanged: (value) => setState(() {
                      tankFull = value ?? false;
                    }),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && selectedVehicle?.id != null) {
      final mileageText = mileageController.text;
      final costText = costController.text;

      if (mileageText.isEmpty || costText.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter both mileage and fuel cost")),
        );
        return;
      }

      final mileage = double.tryParse(mileageText);
      final cost = double.tryParse(costText);

      if (mileage == null || cost == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid input values")),
        );
        return;
      }

      try {
        final vehicleKey = '${selectedVehicle!.fuelType.toLowerCase()}_${selectedVehicle!.fuelVariant.toLowerCase()}';
        final selectedPrice = _vehicleFuelPriceMap[vehicleKey] ?? 0.0;

        if (selectedPrice == 0.0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Fuel price not set for this vehicle type. Please set the fuel price first.'),
              backgroundColor: Colors.orange,
            ),
          );
          return;
        }

        final editResult = await fuelService.editRefill(
          refillId: refill.id!,
          vehicleId: selectedVehicle!.id!,
          currentMileage: mileage,
          fuelCost: cost,
          isManualFull: tankFull,
          fuelPrice: selectedPrice,
        );

        // Reload vehicles to get updated currentAvg and previousAvg
        final updatedVehicles = await fuelService.getVehicles();
        setState(() {
          vehicles = updatedVehicles;
          // Update selectedVehicle with the latest data
          if (selectedVehicle != null) {
            selectedVehicle = vehicles.firstWhere(
              (v) => v.id == selectedVehicle!.id,
              orElse: () => vehicles.isNotEmpty ? vehicles.first : selectedVehicle!,
            );
          }
        });

        await loadRefills();

        if (mounted) {
          final message = editResult.averageCalculated
              ? "Refill updated. Average recalculated."
              : "Refill updated. Average not changed.";
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating refill: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteLastRefill(RefillRecord refill) async {
    if (refill.id == null) return; // Cannot delete refill without ID

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Delete Last Refill'),
        content: const Text(
          'Are you sure you want to delete this refill? This will recalculate the fuel averages.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && selectedVehicle?.id != null) {
      try {
        await fuelService.deleteRefill(refill.id!, selectedVehicle!.id!);

        // Reload vehicles to get updated averages
        final updatedVehicles = await fuelService.getVehicles();
        setState(() {
          vehicles = updatedVehicles;
          // Update selectedVehicle with the latest data
          if (selectedVehicle != null) {
            selectedVehicle = vehicles.firstWhere(
              (v) => v.id == selectedVehicle!.id,
              orElse: () => vehicles.isNotEmpty ? vehicles.first : selectedVehicle!,
            );
          }
        });

        await loadRefills();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Refill deleted and averages recalculated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting refill: $e')),
          );
        }
      }
    }
  }

  Future<void> checkEstimatedFuel(double currentMileage) async {
    if (selectedVehicle?.id == null) return;

    try {
      final estimatedFuel = await fuelService.estimateRemainingFuel(
        selectedVehicle!.id!,
        currentMileage,
      );

      print('Estimated fuel at $currentMileage km: $estimatedFuel L');
      // Show in dialog or UI
    } catch (e) {
      print('Error estimating fuel: $e');
    }
  }

  Future<void> getFuelStats() async {
    if (selectedVehicle?.id == null) return;

    try {
      final stats = await fuelService.getFuelStatistics(selectedVehicle!.id!);
      print('Fuel Statistics: $stats');
      // Display stats in UI
    } catch (e) {
      print('Error getting stats: $e');
    }
  }

  void _showSelectVehicleDialog() {
    Vehicle? tempSelectedVehicle = selectedVehicle;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(
                    Icons.directions_car,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Text(AppLocalizations.of(context)!.selectVehicle),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vehicles.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Icon(
                              Icons.directions_car,
                              size: 48,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No vehicles added yet',
                              style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: vehicles.length,
                          separatorBuilder: (context, index) => const Divider(),
                          itemBuilder: (context, index) {
                            final v = vehicles[index];
                            final isSelected = tempSelectedVehicle?.id == v.id;
                            return Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Theme.of(
                                        context,
                                      ).colorScheme.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                leading: Icon(
                                  Icons.directions_car,
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.secondary,
                                ),
                                title: Text(
                                  v.number,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : null,
                                  ),
                                ),
                                subtitle: Text(
                                  '${v.model} • ${_formatFuelDisplay(v.fuelType, v.fuelVariant)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                trailing: isSelected
                                    ? Icon(
                                        Icons.check_circle,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary,
                                        size: 24,
                                      )
                                    : null,
                                onTap: () {
                                  setStateDialog(() {
                                    tempSelectedVehicle = v;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    if (vehicles.isNotEmpty) const SizedBox(height: 12),
                    // Delete button - shown only when a vehicle is selected
                    if (tempSelectedVehicle != null)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _showDeleteVehicleConfirmation(
                              tempSelectedVehicle!,
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete Selected Vehicle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red.shade700,
                            side: BorderSide(color: Colors.red.shade200),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _showAddVehicleDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: Text(AppLocalizations.of(context)!.addVehicle),
                  ),
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: tempSelectedVehicle == null
                        ? null
                        : () {
                            Navigator.pop(context);
                            _showEditVehicleDialog(tempSelectedVehicle!);
                          },
                    icon: const Icon(Icons.edit),
                    label: const Text('Edit Vehicle'),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLocalizations.of(context)!.cancel),
                  ),
                ),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: tempSelectedVehicle == null
                        ? null
                        : () async {
                            setState(() {
                              selectedVehicle = tempSelectedVehicle;
                            });
                            // Persist and sync the selected vehicle
                            if (selectedVehicle?.id != null) {
                              await fuelService.setActiveVehicle(selectedVehicle!.id!);
                            }
                            await _selectedVehicleProvider.setSelectedVehicle(selectedVehicle);
                            await _loadFuelPriceMap();
                            await _refreshCurrentFuelPrice();
                            await loadRefills();
                            await _loadTodayTasks();
                            await _loadNextServiceReminder();
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.check),
                    label: const Text('Select'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showDeleteVehicleConfirmation(Vehicle vehicle) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: Icon(
            Icons.warning_rounded,
            color: Colors.red.shade600,
            size: 48,
          ),
          title: const Text('Delete Vehicle?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Are you sure you want to delete ${vehicle.number}?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  'This action cannot be undone. All refill records for this vehicle will also be deleted.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.red.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await fuelService.deleteVehicle(vehicle.id!);

                    setState(() {
                      vehicles.removeWhere((v) => v.id == vehicle.id);
                      if (selectedVehicle?.id == vehicle.id) {
                        selectedVehicle = vehicles.isNotEmpty
                            ? vehicles.first
                            : null;
                      }
                    });

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${vehicle.number} deleted successfully'),
                          backgroundColor: const Color(0xFF038124),
                        ),
                      );
                      loadRefills();
                    }
                  } catch (e) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error deleting vehicle: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.delete),
                label: const Text('Delete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddVehicleDialog() {
    final numberCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    final mileageCtrl = TextEditingController();
    final tankCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();
    String vehicleType = 'Car';
    String fuelType = 'petrol';
    String fuelVariant = '92';

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.addNewVehicle),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Vehicle Number
                    TextField(
                      controller: numberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number',
                        hintText: 'e.g., ABC 1234',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.directions_car),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vehicle Model
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model',
                        hintText: 'e.g., Honda Civic',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.build),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vehicle Type Dropdown
                    DropdownButtonFormField<String>(
                      initialValue: vehicleType,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Car', child: Text('Car')),
                        DropdownMenuItem(value: 'Bike', child: Text('Bike')),
                        DropdownMenuItem(value: 'Truck', child: Text('Truck')),
                        DropdownMenuItem(value: 'Van', child: Text('Van')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() {
                            vehicleType = value;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Fuel Type Dropdown
                    DropdownButtonFormField<String>(
                      value: _getCombinedFuelType(fuelType, fuelVariant),
                      decoration: const InputDecoration(
                        labelText: 'Fuel Type',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Petrol 92', child: Text('Petrol 92')),
                        DropdownMenuItem(value: 'Petrol 95', child: Text('Petrol 95')),
                        DropdownMenuItem(value: 'Auto Diesel', child: Text('Auto Diesel')),
                        DropdownMenuItem(value: 'Super Diesel', child: Text('Super Diesel')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() {
                            if (value == 'Petrol 92') {
                              fuelType = 'petrol';
                              fuelVariant = '92';
                            } else if (value == 'Petrol 95') {
                              fuelType = 'petrol';
                              fuelVariant = '95';
                            } else if (value == 'Auto Diesel') {
                              fuelType = 'diesel';
                              fuelVariant = 'auto';
                            } else if (value == 'Super Diesel') {
                              fuelType = 'diesel';
                              fuelVariant = 'super';
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    // Current Mileage
                    TextField(
                      controller: mileageCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Current Mileage (km)',
                        hintText: 'e.g., 50000',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.speed),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tank Capacity
                    TextField(
                      controller: tankCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tank Capacity (liters)',
                        hintText: 'e.g., 50',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_gas_station),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Owner Name
                    TextField(
                      controller: ownerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Owner Name',
                        hintText: 'Your name',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.cancel),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (numberCtrl.text.isEmpty || modelCtrl.text.isEmpty || mileageCtrl.text.isEmpty || tankCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all required fields'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    final tankCapacity = double.tryParse(tankCtrl.text);
                    final previousMileage = double.tryParse(mileageCtrl.text);
                    if (tankCapacity == null || tankCapacity <= 0 || previousMileage == null || previousMileage < 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter valid mileage and tank capacity values'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    try {
                      await addNewVehicle(
                        number: numberCtrl.text.trim(),
                        model: modelCtrl.text.trim(),
                        vehicleType: vehicleType,
                        fuelType: fuelType,
                        fuelVariant: fuelVariant,
                        tankCapacity: tankCapacity,
                        owner: ownerCtrl.text.trim(),
                        previousMileage: previousMileage,
                      );

                      // Reload data
                      await loadVehicles();
                      await _loadFuelPriceMap();
                      await _refreshCurrentFuelPrice();

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'âœ“ ${numberCtrl.text} added successfully',
                            ),
                            backgroundColor: const Color(0xFF038124),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: Text(AppLocalizations.of(context)!.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditVehicleDialog(Vehicle vehicle) async {
    final numberCtrl = TextEditingController(text: vehicle.number);
    final modelCtrl = TextEditingController(text: vehicle.model);
    final mileageCtrl = TextEditingController(text: vehicle.previousMileage.toStringAsFixed(0));
    final tankCtrl = TextEditingController(text: vehicle.tankCapacity.toStringAsFixed(0));
    final ownerCtrl = TextEditingController(text: vehicle.owner);
    String fuelType = vehicle.fuelType.toLowerCase();

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Edit Vehicle'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: numberCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: modelCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Vehicle Model',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Fuel Type',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Expanded(
                          child: SegmentedButton<String>(
                            segments: const <ButtonSegment<String>>[
                              ButtonSegment<String>(
                                value: 'petrol',
                                label: Text('Petrol'),
                                icon: Icon(Icons.local_gas_station),
                              ),
                              ButtonSegment<String>(
                                value: 'diesel',
                                label: Text('Diesel'),
                                icon: Icon(Icons.local_shipping),
                              ),
                            ],
                            selected: <String>{fuelType},
                            onSelectionChanged: (Set<String> newSelection) {
                              setStateDialog(() {
                                fuelType = newSelection.first;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mileageCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Current Mileage (km)',
                        hintText: 'e.g., 50000',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.speed),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: tankCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tank Capacity (liters)',
                        hintText: 'e.g., 50',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.local_gas_station),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ownerCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Owner Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (numberCtrl.text.isEmpty || modelCtrl.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all required fields'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      return;
                    }

                    try {
                      final updatedMileage = double.tryParse(mileageCtrl.text);
                      final updatedTankCapacity = double.tryParse(tankCtrl.text);

                      if (updatedMileage == null || updatedMileage < 0 || updatedTankCapacity == null || updatedTankCapacity <= 0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Please enter valid mileage and tank capacity values'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }

                      final updatedVehicle = vehicle.copyWith(
                        number: numberCtrl.text.trim(),
                        model: modelCtrl.text.trim(),
                        fuelType: fuelType,
                        fuelVariant: fuelType == 'petrol' ? '92' : 'auto',
                        tankCapacity: updatedTankCapacity,
                        owner: ownerCtrl.text.trim(),
                        previousMileage: updatedMileage,
                      );

                      final result = await fuelService.updateVehicle(updatedVehicle);

                      setState(() {
                        final idx = vehicles.indexWhere((v) => v.id == result.id);
                        if (idx != -1) {
                          vehicles[idx] = result;
                          if (selectedVehicle?.id == result.id) selectedVehicle = result;
                        }
                      });

                      await _refreshCurrentFuelPrice();

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Vehicle updated successfully'), backgroundColor: Color(0xFF038124)),
                        );
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error updating vehicle: $e'), backgroundColor: Colors.red),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showChatBot() {
    final inputCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(AppLocalizations.of(context)!.rideBuddy),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: chatLog
                            .map(
                              (msg) => Align(
                                alignment: msg.fromUser
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: msg.fromUser
                                        ? Theme.of(
                                            context,
                                          ).colorScheme.primaryContainer
                                        : Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(msg.text),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: inputCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Type your message.....',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () {
                            final text = inputCtrl.text.trim();
                            if (text.isEmpty) return;
                            setStateDialog(() {
                              chatLog.add(ChatMessage(text, fromUser: true));
                              chatLog.add(
                                ChatMessage('You said: $text', fromUser: false),
                              );
                            });
                            inputCtrl.clear();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showFuelEstimationDialog() {
    final mileageText = _mileageController.text.trim();
    if (mileageText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter current mileage first")),
      );
      return;
    }

    final currentMileage = double.tryParse(mileageText);
    if (currentMileage == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Invalid mileage value")));
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return FutureBuilder<double>(
          future: selectedVehicle != null
              ? fuelService.estimateRemainingFuel(
                  selectedVehicle!.id!,
                  currentMileage,
                )
              : Future.value(0),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return AlertDialog(
                title: const Text('Checking Fuel Level...'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    const Text('Calculating estimated fuel...'),
                  ],
                ),
              );
            }

            if (snapshot.hasError) {
              return AlertDialog(
                title: const Text('Error'),
                content: Text('Error: ${snapshot.error}'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              );
            }

            final estimatedFuel = snapshot.data ?? 0;
            final tankCapacity = selectedVehicle?.tankCapacity ?? 50;
            final fuelPercentage = (estimatedFuel / tankCapacity * 100).clamp(
              0,
              100,
            );
            final isLowFuel = fuelPercentage < 30;
            final isCritical = fuelPercentage < 10;

            // Determine color based on fuel level
            Color fuelColor;
            Color backgroundColor;
            if (isCritical) {
              fuelColor = Colors.red;
              backgroundColor = Colors.red.withValues(alpha: 0.1);
            } else if (isLowFuel) {
              fuelColor = Colors.orange;
              backgroundColor = Colors.orange.withValues(alpha: 0.1);
            } else {
              fuelColor = Colors.green;
              backgroundColor = Colors.green.withValues(alpha: 0.1);
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(20),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.local_gas_station,
                            color: fuelColor,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            'Estimated Fuel Level',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Fuel gauge visualization
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer circle
                                Container(
                                  width: 150,
                                  height: 150,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: fuelColor.withValues(alpha: 0.3),
                                      width: 8,
                                    ),
                                  ),
                                ),
                                // Inner colored circle (animated)
                                TweenAnimationBuilder<double>(
                                  tween: Tween(
                                    begin: 0,
                                    end: fuelPercentage / 100,
                                  ),
                                  duration: const Duration(milliseconds: 800),
                                  curve: Curves.easeOutCubic,
                                  builder: (context, value, child) {
                                    return Container(
                                      width: 150,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            fuelColor.withValues(alpha: 0.8),
                                            fuelColor.withValues(alpha: 0.4),
                                          ],
                                        ),
                                      ),
                                      child: Stack(
                                        alignment: Alignment.center,
                                        children: [
                                          // Pie chart effect using ClipRRect
                                          ClipOval(
                                            child: Container(
                                              color: fuelColor.withValues(
                                                alpha: 0.2,
                                              ),
                                              child: SizedBox(
                                                width: 140,
                                                height: 140,
                                              ),
                                            ),
                                          ),
                                          // Animated fill
                                          CustomPaint(
                                            painter: FuelGaugePainter(
                                              value: value,
                                              color: fuelColor,
                                            ),
                                            size: const Size(140, 140),
                                          ),
                                          // Center text
                                          Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                '${estimatedFuel.toStringAsFixed(1)}L',
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.bold,
                                                  color: fuelColor,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                '${fuelPercentage.toStringAsFixed(0)}%',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  color: fuelColor.withValues(
                                                    alpha: 0.8,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Details
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            _buildDetailRow(
                              'Current Mileage',
                              '${currentMileage.toStringAsFixed(0)} km',
                              Icons.speed,
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              'Previous Mileage',
                              '${(selectedVehicle?.previousMileage ?? 0).toStringAsFixed(0)} km',
                              Icons.history,
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              'Distance Since Last Refill',
                              '${(currentMileage - (selectedVehicle?.previousMileage ?? 0)).toStringAsFixed(1)} km',
                              Icons.route,
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              'Tank Capacity',
                              '${tankCapacity.toStringAsFixed(1)}L',
                              Icons.water_drop,
                            ),
                            const Divider(height: 12),
                            _buildDetailRow(
                              'Current Average',
                              _hasValidFuelAverage
                                  ? '${selectedVehicle!.currentAvg!.toStringAsFixed(1)} km/L'
                                  : 'Not calculated',
                              Icons.trending_up,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Status message
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: fuelColor, width: 1),
                        ),
                        child: Text(
                          isCritical
                              ? 'âš ï¸ Critical fuel level! Refill immediately'
                              : isLowFuel
                              ? 'âš ï¸ Fuel running low. Consider refilling soon'
                              : 'âœ“ Fuel level is good',
                          style: TextStyle(
                            color: fuelColor,
                            fontWeight: FontWeight.w600,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        label: const Text('Close'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.secondary),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12)),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  String get _displayName {
    // prefer first name from full name field if available
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      final full = user.userMetadata?['full_name'] as String?;
      if (full != null && full.isNotEmpty) {
        return full.split(' ').first;
      }
      final email = user.email;
      if (email != null && email.contains('@')) {
        return email.split('@').first.split('.').first;
      }
    }
    // fallback to provided widget parameter
    return widget.userName.split(' ').first;
  }

  String? get _profilePhotoUrl {
    // Get profile picture from Google Sign-In metadata
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      return user.userMetadata?['picture'] as String?;
    }
    return null;
  }

  String _getVehicleCondition() {
    if (!_hasValidFuelAverage) {
      return 'Unknown';
    }
    final avg = selectedVehicle!.currentAvg!;
    if (avg >= 18) {
      return 'Excellent';
    } else if (avg >= 14) {
      return 'Good';
    } else if (avg >= 10) {
      return 'Fair';
    } else {
      return 'Poor';
    }
  }

  Color _getConditionColor() {
    final condition = _getVehicleCondition();
    switch (condition) {
      case 'Excellent':
        return Colors.green;
      case 'Good':
        return Colors.blue;
      case 'Fair':
        return Colors.orange;
      case 'Poor':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _buildEcoMessage({bool validAverage = false}) {
    if (!validAverage) {
      return 'Track your fuel efficiency to get smarter driving recommendations.';
    }

    final currentAvg = selectedVehicle!.currentAvg!;
    final previousAvg = selectedVehicle!.previousAvg ?? 0.0;

    if (previousAvg <= 0) {
      return 'Your current efficiency is ${currentAvg.toStringAsFixed(1)} km/l. Drive smoothly to save more fuel.';
    }

    final changePercent = ((currentAvg - previousAvg) / previousAvg) * 100;
    final absChange = changePercent.abs();

    if (changePercent >= 5) {
      return 'Great job! Fuel efficiency improved by ${absChange.toStringAsFixed(0)}%. Keep up the smooth driving.';
    }

    if (changePercent <= -5) {
      return 'Fuel consumption increased by ${absChange.toStringAsFixed(0)}%. Consider gentler driving or a service check soon.';
    }

    if (changePercent < 0) {
      return 'Fuel usage is slightly higher than before. Try easing acceleration or servicing the vehicle.';
    }

    return 'Your efficiency is stable. Keep up the steady driving habits to stay fuel smart.';
  }

  String _buildWarningMessage() {
    final tasks = _hasTodayTasks ? _todayTasks.length : 0;
    double? kmLeft;
    if (_nextServiceKm != null && selectedVehicle != null) {
      final currentMileage = selectedVehicle!.previousMileage ?? 0;
      kmLeft = (_nextServiceKm! - currentMileage).toInt().toDouble();
    }

    if (_hasTodayTasks && _hasServiceApproaching && kmLeft != null) {
      return '$tasks Task${tasks > 1 ? 's' : ''} due today • Service due in ~${kmLeft.toInt()} km';
    } else if (_hasTodayTasks) {
      return '$tasks Task${tasks > 1 ? 's' : ''} due today';
    } else if (_hasServiceApproaching && kmLeft != null) {
      return 'Service due in ~${kmLeft.toInt()} km';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 500;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 3,
        shadowColor: Colors.green.withOpacity(0.12),
        toolbarHeight: 80,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleSpacing: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage: _profilePhotoUrl != null
                    ? NetworkImage(_profilePhotoUrl!)
                    : null,
                backgroundColor: const Color(0xFF038124),
                child: _profilePhotoUrl == null
                    ? Text(
                        _displayName.isNotEmpty
                            ? _displayName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Hello, ${_displayName.isNotEmpty ? _displayName : 'Rider'}',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _showSelectVehicleDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          selectedVehicle != null
                              ? 'Vehicle • ${selectedVehicle!.number}'
                              : 'Select your vehicle',
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade900,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.calendar_today_outlined),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ReminderScreen()),
                  ).then((_) {
                    _loadTodayTasks();
                    _loadNextServiceReminder();
                  }); // Refresh tasks and service data when returning
                },
              ),
              if (_hasTodayTasks || _hasServiceApproaching)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.local_gas_station),
            tooltip: 'Fuel Price Settings',
            onPressed: () async {
              final result = await Navigator.pushNamed(context, '/fuel-price');
              if (result == true) {
                await _onFuelPricesChanged();
                await _refreshCurrentFuelPrice();
                if (mounted) setState(() {});
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.calculate),
            tooltip: 'Trip Cost Calculator',
            onPressed: () {
              Navigator.pushNamed(context, '/trip-cost');
            },
          ),
        ],
      ),
      body: SafeArea(
        child: selectedVehicle == null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.directions_car,
                      size: 64,
                      color: Theme.of(context).colorScheme.secondary,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No vehicles added yet',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Tap to add your first vehicle'),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => _showSelectVehicleDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Add Vehicle'),
                    ),
                  ],
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Eco message notification - positioned at top for visibility
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF038124),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.shade900.withOpacity(0.15),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.eco,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _buildEcoMessage(validAverage: _hasValidFuelAverage),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          // Warning message for tasks or service approaching
                          if (_hasTodayTasks || _hasServiceApproaching)
                            GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => const ReminderScreen()),
                                ).then((_) {
                                  _loadTodayTasks();
                                  _loadNextServiceReminder();
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.red.withOpacity(0.3),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.info,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _buildWarningMessage(),
                                        style: const TextStyle(
                                          fontSize: 10,
                                          height: 1.3,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.arrow_forward,
                                        color: Colors.white,
                                        size: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _buildWeatherAlertCard(),
                    // Today's Tasks Quick Access Button
                    if (_hasTodayTasks)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const ReminderScreen()),
                            ).then((_) => _loadTodayTasks());
                          },
                          icon: const Icon(Icons.warning, color: Colors.white),
                          label: Text(
                            '${_todayTasks.length} Task${_todayTasks.length > 1 ? 's' : ''} Due Today',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade600,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 4,
                          ),
                        ),
                      ),
                    // Vehicle info card
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(minHeight: 220),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFF0DFE3C),
                            const Color(0xFF03920E),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.shade900.withOpacity(0.25),
                            blurRadius: 14,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header Row: Plate & Excellent Badge
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        selectedVehicle?.number ?? 'CBC 6456',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        selectedVehicle?.model ?? 'Honda Civic',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius:
                                        BorderRadius.circular(30),
                                  ),
                                  child: Text(
                                    _getVehicleCondition(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _getConditionColor(),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height:0),
                            // Fuel efficiency stats block (current + previous) + car image
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Your Efficiency',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      if (_hasValidFuelAverage) ...[
                                        Text(
                                          '${selectedVehicle!.currentAvg!.toStringAsFixed(1)} km/l',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 22,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        if (selectedVehicle?.previousAvg != null && selectedVehicle!.previousAvg! > 0)
                                          Text(
                                            ' ${selectedVehicle!.previousAvg!.toStringAsFixed(1)} km/l',
                                            style: const TextStyle(
                                              color: Colors.redAccent,
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                      ] else ...[
                                        const Text(
                                          'Fill full tank to calculate average',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 2),
                                      Text(
                                        (selectedVehicle?.previousMileage ?? 0) > 0 ? '${selectedVehicle!.previousMileage!.toStringAsFixed(0)} km' : '0 km',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Image.asset(
                                  'assets/images/car.png',
                                  width: isSmallScreen ? screenWidth * 0.36 : 160,
                                  height: isSmallScreen ? 140 : 160,
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const Center(
                                      child: Icon(
                                        Icons.directions_car,
                                        color: Colors.white,
                                        size: 86,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            // Prominent Fuel Type and Price Section
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Current Fuel',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          selectedVehicle != null
                                              ? _formatFuelDisplay(selectedVehicle!.fuelType, selectedVehicle!.fuelVariant)
                                              : 'N/A',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Builder(
                                          builder: (context) {
                                            final vehicleKey = selectedVehicle != null
                                                ? '${selectedVehicle!.fuelType.toLowerCase()}_${selectedVehicle!.fuelVariant.toLowerCase()}'
                                                : null;
                                            final displayPrice = vehicleKey != null
                                                ? _vehicleFuelPriceMap[vehicleKey]
                                                : null;
                                            return Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Price',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  displayPrice != null && displayPrice > 0
                                                      ? 'Rs. ${displayPrice.toStringAsFixed(2)}/L'
                                                      : 'Not set',
                                                  style: TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Edit Button
                                  Align(
                                    alignment: Alignment.topCenter,
                                    child: Material(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(10),
                                      child: InkWell(
                                        onTap: () async {
                                          final result = await Navigator.pushNamed(context, '/fuel-price');
                                          if (result == true) {
                                            await _onFuelPricesChanged();
                                            await _refreshCurrentFuelPrice();
                                            if (mounted) setState(() {});
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(10),
                                        child: Padding(
                                          padding: const EdgeInsets.all(6),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.edit,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(height: 2),
                                              const Text(
                                                'Edit',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),

                            // Tank Capacity as normal text
                            Row(
                              children: [
                                Icon(
                                  Icons.water_drop,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Tank: ${selectedVehicle?.tankCapacity ?? 0} L',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),

                          ],
                        ),
                      ),
                    ),



                    // Quick refill entry section
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.local_gas_station,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Log Refill',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            isSmallScreen
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      TextField(
                                        controller: _mileageController,
                                        decoration: InputDecoration(
                                          contentPadding: const EdgeInsets.symmetric(
                                            vertical: 12,
                                            horizontal: 14,
                                          ),
                                          filled: true,
                                          fillColor: Theme.of(
                                            context,
                                          ).colorScheme.surface,
                                          labelText: 'Current Mileage (km)',
                                          prefixIcon: const Icon(Icons.speed, size: 20),
                                          labelStyle: const TextStyle(fontSize: 13),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        style: const TextStyle(fontSize: 14),
                                        keyboardType: TextInputType.number,
                                      ),
                                      const SizedBox(height: 6),
                                      SizedBox(
                                        height: 42,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _showFuelEstimationDialog(),
                                          icon: const Icon(Icons.local_gas_station, size: 18),
                                          label: const Text('Check'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            textStyle: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _mileageController,
                                          decoration: InputDecoration(
                                            contentPadding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                              horizontal: 12,
                                            ),
                                            filled: true,
                                            fillColor: Theme.of(
                                              context,
                                            ).colorScheme.surface,
                                            labelText: 'Current Mileage (km)',
                                            prefixIcon: const Icon(Icons.speed, size: 18),
                                            labelStyle: const TextStyle(fontSize: 12),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                          ),
                                          style: const TextStyle(fontSize: 13),
                                          keyboardType: TextInputType.number,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        height: 42,
                                        child: ElevatedButton.icon(
                                          onPressed: () => _showFuelEstimationDialog(),
                                          icon: const Icon(Icons.local_gas_station, size: 18),
                                          label: const Text('Check'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Theme.of(
                                              context,
                                            ).colorScheme.primaryContainer,
                                            foregroundColor: Theme.of(
                                              context,
                                            ).colorScheme.onPrimaryContainer,
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 8,
                                            ),
                                            textStyle: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _fuelCostController,
                              decoration: InputDecoration(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                filled: true,
                                fillColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                labelText: 'Fuel Cost',
                                prefixIcon: const Icon(Icons.attach_money, size: 18),
                                labelStyle: const TextStyle(fontSize: 12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              style: const TextStyle(fontSize: 13),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 8),
                            CheckboxListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Fill Full Tank',
                                style: TextStyle(fontSize: 13),
                              ),
                              value: tankFull,
                              onChanged: (val) {
                                setState(() {
                                  tankFull = val ?? false;
                                });
                              },
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => saveRefill(),
                                icon: const Icon(Icons.save, size: 18),
                                label: const Text('Save Refill'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF038124),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  textStyle: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (selectedVehicle != null) ...[
                      _buildVehicleQrCard(),
                      const SizedBox(height: 12),
                    ],
                    // Recent refills section
                    if (refills.isNotEmpty)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Recent Refills',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          FuelAnalyticsDashboard(
                                            vehicleId: selectedVehicle!.id!,
                                            vehicleName:
                                                selectedVehicle!.number,
                                          ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.arrow_forward, size: 16),
                                label: const Text('See All', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...refills.asMap().entries.map(
                            (entry) {
                              final e = entry.value;
                              final isLatestRefill = refills.isNotEmpty && refills.first.id == e.id;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 6),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  leading: const Icon(Icons.local_gas_station, color: Colors.red, size: 20),
                                  title: Text(
                                    '${e.fuelAdded}L @ ${e.mileage}km',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    e.createdAt.toString().split('.').first,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'LKR ${e.fuelCost}',
                                        style: TextStyle(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      if (isLatestRefill) ...[
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: const Icon(Icons.edit, size: 18),
                                          onPressed: () => _editLastRefill(e),
                                          tooltip: 'Edit latest refill',
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, size: 18),
                                          onPressed: () => _deleteLastRefill(e),
                                          tooltip: 'Delete latest refill',
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(
                                Icons.local_gas_station,
                                size: 40,
                                color: Theme.of(
                                  context,
                                ).colorScheme.secondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 10),
                              const Text(
                                'No refills logged yet',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Add your first refill above',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF038124),
        onPressed: _showChatBot,
        child: const Icon(Icons.smart_toy),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildGreenSubCard(BuildContext context, {required String label, required String value, bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFF038124).withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? const Color(0xFF038124) : const Color(0xFF038124).withOpacity(0.3),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xFF038124),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: highlight ? 14 : 12,
              color: const Color(0xFF038124),
              fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        boxShadow: [
          BoxShadow(
            color: Colors.green.shade900.withOpacity(0.12),
            blurRadius: 16,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/home'),
            child: _buildNavItem(Icons.home, true),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/petrol-station'),
            child: _buildNavItem(Icons.location_on, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/media'),
            child: _buildNavItem(Icons.videocam, false),
          ),
          GestureDetector(
            onTap: () {
              if (selectedVehicle != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => FuelAnalyticsDashboard(
                      vehicleId: selectedVehicle!.id!,
                      vehicleName: selectedVehicle!.number,
                    ),
                  ),
                );
              }
            },
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
        color: isActive
            ? const Color(0xFF038124)
            : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? const Color(0xFF038124) : Colors.grey.shade300,
          width: 1.2,
        ),
      ),
      child: Icon(
        icon,
        color: isActive ? Colors.white : const Color(0xFF038124),
      ),
    );
  }
}

/// Custom painter for animated fuel gauge
class FuelGaugePainter extends CustomPainter {
  final double value; // 0 to 1
  final Color color;

  FuelGaugePainter({required this.value, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw the filled portion based on the animated value
    if (value > 0) {
      // Create a pie slice from bottom going up based on value
      final startAngle = -3.14159; // Start from bottom
      final sweepAngle = 2 * 3.14159 * value; // Animated sweep

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 5),
        startAngle,
        sweepAngle,
        true,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(FuelGaugePainter oldDelegate) {
    return oldDelegate.value != value || oldDelegate.color != color;
  }
}

