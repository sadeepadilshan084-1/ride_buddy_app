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
import 'package:ride_buddy/screens/reminder_screen.dart';

typedef Vehicle = fts.Vehicle;
typedef RefillRecord = fts.RefillRecord;

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
  Map<String, double> _vehicleFuelPriceMap = {};
  RealtimeChannel? _fuelPriceChannel;

  late fts.FuelTrackerService fuelService;
  late SelectedVehicleProvider _selectedVehicleProvider;
  late ReminderService _reminderService;
  late SupabaseService _supabaseService;

  bool _isWeatherLoading = false;
  WeatherData? _currentWeather;
  WeatherAlert? _currentWeatherAlert;
  Timer? _weatherTimer;

  bool _isQrUploading = false;
  List<ReminderModel> _todayTasks = [];
  bool _hasTodayTasks = false;
  bool _hasServiceApproaching = false;

  final TextEditingController _mileageController = TextEditingController();
  final TextEditingController _fuelCostController = TextEditingController();
  bool tankFull = false;
  double currentFuelPrice = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    fuelService = fts.FuelTrackerService();
    _selectedVehicleProvider = SelectedVehicleProvider();
    _reminderService = ReminderService();
    _supabaseService = SupabaseService();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    await _selectedVehicleProvider.initialize();
    _bindFuelPriceRealtime();
    await _refreshData();
    _initializeWeatherMonitoring();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fuelPriceChannel?.unsubscribe();
    _weatherTimer?.cancel();
    _mileageController.dispose();
    _fuelCostController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    await loadVehicles();
    if (selectedVehicle != null) await loadRefills();
    await _loadFuelPriceMap();
    await _refreshCurrentFuelPrice();
    await _loadTodayTasks();
    await _loadNextServiceReminder();
  }

  Future<void> loadVehicles() async {
    try {
      final loadedVehicles = await fuelService.getVehicles();
      Vehicle? vehicleToSelect;
      final activeVehicle = await fuelService.getActiveVehicle();
      if (activeVehicle != null) {
        final matches = loadedVehicles.where((v) => v.id == activeVehicle.id);
        if (matches.isNotEmpty) vehicleToSelect = matches.first;
      }
      if (vehicleToSelect == null && loadedVehicles.isNotEmpty) {
        vehicleToSelect = await _selectedVehicleProvider.validateSelectedVehicle(loadedVehicles) ?? loadedVehicles.first;
      }
      setState(() {
        vehicles = loadedVehicles;
        selectedVehicle = vehicleToSelect;
      });
      if (vehicleToSelect?.id != null) {
        await _selectedVehicleProvider.setSelectedVehicle(vehicleToSelect!);
        await fuelService.setActiveVehicle(vehicleToSelect.id!);
      }
    } catch (e) {
      debugPrint('Error loading vehicles: $e');
    }
  }

  Future<void> loadRefills() async {
    if (selectedVehicle?.id == null) return;
    try {
      final loadedRefills = await fuelService.getRefills(selectedVehicle!.id!);
      setState(() {
        refills = loadedRefills;
        if (selectedVehicle != null && selectedVehicle!.previousMileage > 0) {
          _mileageController.text = selectedVehicle!.previousMileage.toStringAsFixed(0);
        }
      });
    } catch (e) {
      debugPrint('Error loading refills: $e');
    }
  }

  Future<void> _loadFuelPriceMap() async {
    try {
      final prices = await FuelPriceService().getFuelPrices();
      final map = <String, double>{};
      for (final item in prices) {
        final type = (item['fuel_type'] as String?)?.toLowerCase();
        final variant = (item['variant'] as String?)?.toLowerCase();
        final price = (item['price'] as num?)?.toDouble();
        if (type != null && variant != null && price != null) {
          map['${type}_$variant'] = price;
        }
      }
      setState(() => _vehicleFuelPriceMap = map);
    } catch (e) {
      debugPrint('Error loading price map: $e');
    }
  }

  Future<void> _refreshCurrentFuelPrice() async {
    if (selectedVehicle == null) return;
    final key = '${selectedVehicle!.fuelType.toLowerCase()}_${selectedVehicle!.fuelVariant.toLowerCase()}';
    final price = _vehicleFuelPriceMap[key] ?? await FuelPriceService().getFuelPrice(selectedVehicle!.fuelType, selectedVehicle!.fuelVariant) ?? 0.0;
    setState(() => currentFuelPrice = price);
  }

  void _bindFuelPriceRealtime() {
    _fuelPriceChannel = Supabase.instance.client
        .channel('public:fuel_prices')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'fuel_prices',
          callback: (_) => _refreshData(),
        )
        .subscribe();
  }

  void _initializeWeatherMonitoring() {
    _fetchWeather();
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) => _fetchWeather());
  }

  Future<void> _fetchWeather() async {
    if (!mounted) return;
    setState(() => _isWeatherLoading = true);
    try {
      final pos = await LocationService().getCurrentPosition();
      final weather = await WeatherService().fetchCurrentWeather(pos.latitude, pos.longitude);
      if (mounted) setState(() { _currentWeather = weather; _currentWeatherAlert = getWeatherAlert(weather); });
    } catch (_) {} finally { if (mounted) setState(() => _isWeatherLoading = false); }
  }

  Future<void> _loadTodayTasks() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || selectedVehicle?.id == null) return;
    try {
      final today = DateTime.now();
      final reminders = await _reminderService.getUserReminders(userId);
      final tasks = reminders.where((r) => r.vehicleId == selectedVehicle!.id && r.expiryDate.day == today.day && r.status == ReminderStatus.active).toList();
      setState(() { _todayTasks = tasks; _hasTodayTasks = tasks.isNotEmpty; });
    } catch (_) {}
  }

  Future<void> _loadNextServiceReminder() async {
    final userId = _supabaseService.getCurrentUserId();
    if (userId == null || selectedVehicle?.id == null) return;
    try {
      final response = await _supabaseService.supabase.from('reminders').select().eq('user_id', userId).eq('vehicle_id', selectedVehicle!.id!).eq('reminder_type', 'service').eq('status', 'active').order('expiry_date', ascending: true).limit(1).maybeSingle();
      if (response != null) {
        final nextKm = (response['service_km'] as num?)?.toDouble();
        setState(() { _hasServiceApproaching = nextKm != null && (nextKm - (selectedVehicle?.previousMileage ?? 0)) <= 500; });
      }
    } catch (_) {}
  }

  Future<void> saveRefill() async {
    if (selectedVehicle == null) return;
    final mileage = double.tryParse(_mileageController.text);
    final cost = double.tryParse(_fuelCostController.text);
    if (mileage == null || cost == null || currentFuelPrice <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid data and ensure fuel price is set.')));
      return;
    }
    try {
      await fuelService.addRefill(vehicleId: selectedVehicle!.id!, currentMileage: mileage, fuelCost: cost, isManualFull: tankFull, fuelPrice: currentFuelPrice);
      _fuelCostController.clear();
      setState(() => tankFull = false);
      await _refreshData();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Refill logged!'), backgroundColor: Color(0xFF038124)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: _buildAppBar(),
      body: selectedVehicle == null ? _buildEmptyState() : _buildDashboard(),
      bottomNavigationBar: _buildBottomNavBar(),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF038124),
        child: const Icon(Icons.smart_toy, color: Colors.white),
        onPressed: () {}, // Chatbot logic here
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final user = Supabase.instance.client.auth.currentUser;
    final name = user?.userMetadata?['full_name']?.toString().split(' ').first ?? 'User';
    final photo = user?.userMetadata?['picture']?.toString();
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 80,
      title: Row(
        children: [
          CircleAvatar(radius: 22, backgroundColor: const Color(0xFF038124), backgroundImage: photo != null ? NetworkImage(photo) : null, child: photo == null ? Text(name[0], style: const TextStyle(color: Colors.white)) : null),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Good Morning,', style: TextStyle(fontSize: 12, color: Colors.grey)),
            Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          ]),
        ],
      ),
      actions: [
        IconButton(icon: const Icon(Icons.notifications_none_rounded, color: Colors.black87), onPressed: () => Navigator.pushNamed(context, '/reminder')),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: const Color(0xFF038124),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildVehicleSelector(),
            const SizedBox(height: 16),
            _buildMainCard(),
            const SizedBox(height: 20),
            if (_currentWeatherAlert != null) _buildWeatherAlert(),
            _buildQuickActions(),
            const SizedBox(height: 20),
            _buildRefillForm(),
            const SizedBox(height: 24),
            _buildHistoryHeader(),
            _buildRecentHistory(),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleSelector() {
    return GestureDetector(
      onTap: _showVehiclePicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(children: [
          const Icon(Icons.directions_car_filled, color: Color(0xFF038124), size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(selectedVehicle?.number ?? 'Select Vehicle', style: const TextStyle(fontWeight: FontWeight.w600))),
          const Icon(Icons.unfold_more_rounded, color: Colors.grey, size: 20),
        ]),
      ),
    );
  }

  Widget _buildMainCard() {
    final avg = selectedVehicle?.currentAvg?.toStringAsFixed(1) ?? '--';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF038124), Color(0xFF014B15)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: const Color(0xFF038124).withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 8))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selectedVehicle?.model ?? '', style: const TextStyle(color: Colors.white70, fontSize: 14)),
              Text(selectedVehicle?.number ?? '', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            ]),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Text(selectedVehicle?.fuelType.toUpperCase() ?? '', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 32),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _buildMetric('Efficiency', avg, 'km/L'),
            _buildMetric('Odometer', selectedVehicle?.previousMileage.toStringAsFixed(0) ?? '0', 'km'),
            _buildMetric('Remaining', selectedVehicle?.fuelRemaining.toStringAsFixed(1) ?? '0', 'L'),
          ]),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(16)),
            child: Row(children: [
              const Icon(Icons.local_gas_station, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text('Current Price: Rs. ${currentFuelPrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
              const Spacer(),
              GestureDetector(onTap: () => Navigator.pushNamed(context, '/fuel-price'), child: const Text('Update', style: TextStyle(color: Colors.white, fontSize: 12, decoration: TextDecoration.underline))),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildMetric(String label, String value, String unit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
      Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(width: 2),
        Text(unit, style: const TextStyle(color: Colors.white70, fontSize: 10)),
      ]),
    ]);
  }

  Widget _buildQuickActions() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      _actionIcon(Icons.bar_chart_rounded, 'Stats', () => Navigator.push(context, MaterialPageRoute(builder: (_) => FuelAnalyticsDashboard(vehicleId: selectedVehicle!.id!, vehicleName: selectedVehicle!.number)))),
      _actionIcon(Icons.local_gas_station_outlined, 'Stations', () => Navigator.pushNamed(context, '/petrol-station')),
      _actionIcon(Icons.calculate_outlined, 'Calculator', () => Navigator.pushNamed(context, '/trip-cost')),
      _actionIcon(Icons.qr_code_scanner_rounded, 'QR Pass', () {}),
    ]);
  }

  Widget _actionIcon(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]), child: Icon(icon, color: const Color(0xFF038124))),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildRefillForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick Log Refill', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: TextField(controller: _mileageController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Mileage (km)', prefixIcon: const Icon(Icons.speed, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
          const SizedBox(width: 12),
          Expanded(child: TextField(controller: _fuelCostController, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Cost (LKR)', prefixIcon: const Icon(Icons.payments_outlined, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))))),
        ]),
        CheckboxListTile(contentPadding: EdgeInsets.zero, title: const Text('Tank is full', style: TextStyle(fontSize: 14)), value: tankFull, activeColor: const Color(0xFF038124), onChanged: (v) => setState(() => tankFull = v ?? false)),
        SizedBox(width: double.infinity, height: 50, child: ElevatedButton(onPressed: saveRefill, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF038124), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), child: const Text('Save Record', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ]),
    );
  }

  Widget _buildRecentHistory() {
    final recent = refills.take(3).toList();
    if (recent.isEmpty) return Container(width: double.infinity, padding: const EdgeInsets.all(32), child: const Text('No recent refills', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)));
    return Column(children: recent.map((r) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const CircleAvatar(backgroundColor: Color(0xFFE8F5E9), child: Icon(Icons.local_gas_station, color: Color(0xFF038124), size: 18)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rs. ${r.fuelCost.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${r.fuelAdded.toStringAsFixed(1)}L • ${r.mileage.toStringAsFixed(0)} km', style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ])),
        Text('${r.createdAt.day}/${r.createdAt.month}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ]),
    )).toList());
  }

  Widget _buildBottomNavBar() {
    return Container(
      height: 70, margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20)]),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _navIcon(Icons.home_rounded, true),
        _navIcon(Icons.location_on_rounded, false, route: '/petrol-station'),
        _navIcon(Icons.videocam_rounded, false, route: '/media'),
        _navIcon(Icons.bar_chart_rounded, false, route: '/stats'),
        _navIcon(Icons.person_rounded, false, route: '/profile'),
      ]),
    );
  }

  Widget _navIcon(IconData icon, bool active, {String? route}) {
    return IconButton(icon: Icon(icon, color: active ? const Color(0xFF038124) : Colors.grey.shade400, size: 28), onPressed: () => route != null ? Navigator.pushNamed(context, route) : null);
  }

  void _showVehiclePicker() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (_) => Container(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Switch Vehicle', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ...vehicles.map((v) => ListTile(leading: const Icon(Icons.directions_car), title: Text(v.number), subtitle: Text(v.model), onTap: () { setState(() => selectedVehicle = v); _refreshData(); Navigator.pop(context); })),
      ]),
    ));
  }

  Widget _buildWeatherAlert() => Container(); // simplified for now
  Widget _buildHistoryHeader() => Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('View All', style: TextStyle(color: Color(0xFF038124), fontSize: 12))]));
  Widget _buildEmptyState() => const Center(child: Text('No vehicle selected'));
}
