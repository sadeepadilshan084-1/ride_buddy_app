import 'package:flutter/material.dart';
import 'package:ride_buddy/screens/update_service_completed_screen.dart';
import 'package:ride_buddy/screens/vehicle_detail_screen.dart';
import 'package:ride_buddy/services/vehicle_detail_service.dart';
import 'package:ride_buddy/services/supabase_service.dart';
import 'package:ride_buddy/services/selected_vehicle_provider.dart';

class UpdateServiceDataScreen extends StatefulWidget {
  final String? vehicleId;

  const UpdateServiceDataScreen({super.key, this.vehicleId});

  @override
  State<UpdateServiceDataScreen> createState() => _UpdateServiceDataScreenState();
}

class _UpdateServiceDataScreenState extends State<UpdateServiceDataScreen> {
  late VehicleDetailService _vehicleDetailService;
  late SupabaseService _supabaseService;
  late SelectedVehicleProvider _selectedVehicleProvider;

  // Auto-filled fields (from database)
  String? vehicleName;
  String? vehicleNumber;
  String? _resolvedVehicleId;
  double? currentMileage;
  double? nextServiceMileage;
  String? lastServiceDate;

  // User-editable fields
  final TextEditingController _currentMillageCtrl = TextEditingController();
  final TextEditingController _serviceDateCtrl = TextEditingController();
  final TextEditingController _nextServiceCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _vehicleDetailService = VehicleDetailService();
    _supabaseService = SupabaseService();
    _selectedVehicleProvider = SelectedVehicleProvider();
    _loadVehicleDetails();
  }

  Future<void> _loadVehicleDetails() async {
    try {
      setState(() => isLoading = true);

      // Initialize the provider first
      await _selectedVehicleProvider.initialize();

      // Get current user's vehicle
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() {
          errorMessage = 'User not authenticated';
          isLoading = false;
        });
        return;
      }

      // Get all vehicles to validate
      final vehicles = await _supabaseService.getUserVehicles(userId);
      if (vehicles.isEmpty) {
        setState(() {
          errorMessage = 'No vehicles found';
          isLoading = false;
        });
        return;
      }

      // Resolve vehicleId from parameter or persisted provider
      String? vehicleId;
      if (widget.vehicleId != null && widget.vehicleId!.isNotEmpty) {
        vehicleId = widget.vehicleId;
        print('✓ Using explicitly passed vehicleId');
      } else {
        final selectedVehicle = _selectedVehicleProvider.getSelectedVehicle();
        if (selectedVehicle?.id != null) {
          vehicleId = selectedVehicle!.id;
          print('✓ Using persisted vehicleId');
        } else {
          vehicleId = vehicles.first['id'];
          print('⚠️ Using first vehicle as fallback');
        }
      }

      _resolvedVehicleId = vehicleId;

      // Get vehicle details
      final details = await _vehicleDetailService.getVehicleDetails(_resolvedVehicleId!);

      setState(() {
        vehicleName = '${details['vehicle_make'] ?? 'N/A'} ${details['vehicle_model'] ?? 'N/A'}';
        vehicleNumber = details['vehicle_number'] ?? 'N/A';
        currentMileage = details['last_recorded_mileage']?.toDouble() ?? 0;
        nextServiceMileage = details['next_service_mileage']?.toDouble() ?? 5000;
        lastServiceDate = details['last_service_date']?.toString() ?? 'N/A';

        // Auto-fill editable fields
        _currentMillageCtrl.text = currentMileage?.toStringAsFixed(1) ?? '0.0';
        _serviceDateCtrl.text = lastServiceDate ?? DateTime.now().toString().split(' ')[0];
        _nextServiceCtrl.text = nextServiceMileage?.toStringAsFixed(0) ?? '5000';

        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading vehicle details: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _saveServiceData() async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User not authenticated')),
        );
        return;
      }

      setState(() => isLoading = true);

      // Get vehicle ID - use resolved ID from initialization
      if (_resolvedVehicleId == null) {
        setState(() {
          errorMessage = 'No vehicle selected';
          isLoading = false;
        });
        return;
      }

      // Parse input values
      final currentMileageValue = double.tryParse(_currentMillageCtrl.text) ?? 0;
      final nextServiceValue = double.tryParse(_nextServiceCtrl.text) ?? 5000;
      final serviceDateValue = _serviceDateCtrl.text;

      // Update vehicle service details in database
      await _vehicleDetailService.updateServiceDetails(
        _resolvedVehicleId!,
        lastServiceDate: DateTime.now(),
        lastServiceMileage: currentMileageValue,
        serviceIntervalKm: nextServiceValue - currentMileageValue,
      );

      // Log the service record
      await _supabaseService.executeQuery(
        'INSERT INTO service_history (user_id, vehicle_id, service_type, service_date, mileage, description) VALUES (?, ?, ?, ?, ?, ?)',
        parameters: [userId, _resolvedVehicleId!, 'maintenance', serviceDateValue, currentMileageValue, _notesCtrl.text],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service details updated successfully'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const UpdateServiceCompletedScreen()),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _currentMillageCtrl.dispose();
    _serviceDateCtrl.dispose();
    _nextServiceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFA7F3D0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFA7F3D0),
        body: Center(
          child: Text(
            errorMessage!,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFA7F3D0),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(child: _buildBackgroundContent()),
                  _buildBottomNavBar(),
                ],
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.4)),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Update Service Data',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader('Vehicle Information (Auto-Filled)'),
                    _buildVehicleInfoCard(),
                    const SizedBox(height: 16),
                    _buildSectionHeader('Service Details'),
                    const SizedBox(height: 12),
                    _buildEditableRow(
                      label: 'Current Mileage (km)',
                      controller: _currentMillageCtrl,
                      keyboardType: TextInputType.number,
                      readOnly: false,
                    ),
                    const SizedBox(height: 8),
                    _buildEditableRow(
                      label: 'Service Date',
                      controller: _serviceDateCtrl,
                      suffixIcon: Icons.calendar_month,
                      readOnly: false,
                    ),
                    const SizedBox(height: 8),
                    _buildEditableRow(
                      label: 'Next Service Due (km)',
                      controller: _nextServiceCtrl,
                      keyboardType: TextInputType.number,
                      readOnly: false,
                    ),
                    const SizedBox(height: 12),
                    _buildNotesSection(),
                    const SizedBox(height: 24),
                    _buildDialogButtons(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(Icons.arrow_back, onTap: () => Navigator.pop(context)),
          const Text('Remainder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          _buildCircleButton(
            Icons.directions_car,
            onTap: () async {
              if (_resolvedVehicleId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Unable to identify vehicle yet')),
                );
                return;
              }
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => VehicleDetailScreen(
                    vehicleId: _resolvedVehicleId!,
                    vehicleName: vehicleName,
                    vehicleNumber: vehicleNumber,
                  ),
                ),
              );
              // Refresh service form after coming back from vehicle data
              await _loadVehicleDetails();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.black, size: 20),
      ),
    );
  }

  Widget _buildBackgroundContent() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(20),
          child: const Text('Mon, Aug 17', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 16),
        _buildMockCard('31 December 2026', 'License update'),
        _buildMockCard('31 December 2026', 'Eco test'),
      ],
    );
  }

  Widget _buildMockCard(String date, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.list_alt, color: Colors.white)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(32)),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.home_outlined),
          Icon(Icons.location_on_outlined),
          Icon(Icons.videocam_outlined),
          Icon(Icons.bar_chart_outlined),
          CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.person_outline, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildVehicleInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          _LabelValueRow(label: 'Vehicle :', value: vehicleName ?? 'Loading...'),
          const SizedBox(height: 6),
          _LabelValueRow(label: 'Vehicle Number :', value: vehicleNumber ?? 'Loading...'),
          const SizedBox(height: 6),
          _LabelValueRow(label: 'Current Mileage :', value: '${(currentMileage ?? 0).toStringAsFixed(0)} km'),
          const SizedBox(height: 6),
          _LabelValueRow(label: 'Last Service Date :', value: lastServiceDate ?? 'N/A'),
        ],
      ),
    );
  }

  Widget _buildEditableRow({
    required String label,
    required TextEditingController controller,
    TextInputType? keyboardType,
    IconData? suffixIcon,
    bool readOnly = false,
  }) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                if (suffixIcon != null) Icon(suffixIcon, size: 16, color: Colors.grey.shade600),
                if (suffixIcon != null) const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            readOnly: readOnly,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Notes (optional)', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Add notes',
            filled: true,
            fillColor: const Color(0xFFE5E7EB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _buildDialogButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5E7EB),
              foregroundColor: Colors.black87,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: isLoading ? null : _saveServiceData,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 44),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }
}
