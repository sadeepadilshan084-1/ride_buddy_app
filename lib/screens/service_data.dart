import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/supabase_service.dart';
import '../services/vehicle_detail_service.dart';

class ServiceDataPage extends StatefulWidget {
  final String? vehicleId;

  const ServiceDataPage({Key? key, this.vehicleId}) : super(key: key);

  @override
  State<ServiceDataPage> createState() => _ServiceDataPageState();
}

class _ServiceDataPageState extends State<ServiceDataPage> {
  final SupabaseService _supabaseService = SupabaseService();
  final VehicleDetailService _vehicleDetailService = VehicleDetailService();

  final TextEditingController _vehicleController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _currentMileageController = TextEditingController();
  final TextEditingController _lastServiceDateController = TextEditingController();
  final TextEditingController _nextServiceDateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _noVehicles = false;
  bool _isServiceLocked = false;
  String? _errorMessage;
  String? _serviceLockMessage;
  String? _vehicleId;
  double _lastServiceMileage = 0;
  double _kmSinceLast = 0;
  double _serviceSubmissionKmLimit = 5000;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _currentMileageController.addListener(_onMileageChanged);
  }

  void _onMileageChanged() {
    // Auto-calculate next service mileage when current mileage changes
    final currentMileage = double.tryParse(_currentMileageController.text) ?? 0;
    if (currentMileage > 0) {
      final nextService = currentMileage + 5000;
      // This will help the user see the expected next service mileage
    }
  }

  @override
  void dispose() {
    _currentMileageController.removeListener(_onMileageChanged);
    _vehicleController.dispose();
    _vehicleNumberController.dispose();
    _currentMileageController.dispose();
    _lastServiceDateController.dispose();
    _nextServiceDateController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        throw Exception('User not authenticated.');
      }

      final vehicles = await _supabaseService.getUserVehicles(userId);
      if (vehicles.isEmpty) {
        setState(() {
          _noVehicles = true;
          _isLoading = false;
        });
        return;
      }

      _vehicleId = widget.vehicleId ?? vehicles.first['id']?.toString();
      if (_vehicleId == null) {
        throw Exception('Vehicle id is missing.');
      }

      // Load vehicle from the vehicles table
      final vehicleResponse = await _supabaseService.supabase
          .from('vehicles')
          .select()
          .eq('id', _vehicleId!)
          .single();

      // Set vehicle name and number from database (using correct column names)
      _vehicleController.text = vehicleResponse['model']?.toString() ?? 'Unknown';
      _vehicleNumberController.text = vehicleResponse['number']?.toString() ?? 'Unknown';

      // Get current mileage from vehicle
      _lastServiceMileage = (vehicleResponse['previous_mileage'] as num?)?.toDouble() ?? 0.0;
      _currentMileageController.text = _lastServiceMileage > 0 ? _lastServiceMileage.toStringAsFixed(0) : '';

      // Check service submission lock status
      await _checkServiceLockStatus();

      // Set last service date to today
      _lastServiceDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());

      // Set next service date 6 months from now
      _nextServiceDateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now().add(const Duration(days: 180)));

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkServiceLockStatus() async {
    try {
      // Get last service submission from service_history
      final lastService = await _supabaseService.supabase
          .from('service_history')
          .select('created_at, service_mileage')
          .eq('vehicle_id', _vehicleId!)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (lastService != null) {
        final lastServiceMileage = (lastService['service_mileage'] as num?)?.toDouble() ?? 0;
        final currentMileage = _lastServiceMileage;
        _kmSinceLast = currentMileage - lastServiceMileage;

        // Check if cooldown is still active (less than 5000 km since last service)
        if (_kmSinceLast < _serviceSubmissionKmLimit) {
          final kmRemaining = (_serviceSubmissionKmLimit - _kmSinceLast).toStringAsFixed(0);
          setState(() {
            _isServiceLocked = true;
            _serviceLockMessage = '⏱️ Service cooldown active. $kmRemaining km remaining until new submission allowed.';
          });
        } else {
          setState(() {
            _isServiceLocked = false;
            _serviceLockMessage = null;
          });
        }
      } else {
        // No previous service, user can submit
        setState(() {
          _isServiceLocked = false;
          _serviceLockMessage = null;
        });
      }
    } catch (e) {
      print('Error checking service lock: $e');
      // On error, default to unlocked to allow user to proceed
      setState(() {
        _isServiceLocked = false;
        _serviceLockMessage = null;
      });
    }
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final currentText = controller.text;
    DateTime initialDate = DateTime.now();
    
    if (currentText.isNotEmpty) {
      try {
        initialDate = DateTime.parse(currentText);
      } catch (e) {
        initialDate = DateTime.now();
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.green.shade400,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(picked);
      controller.text = formattedDate;
      
      // Auto-update next service date if last service date changed
      if (controller == _lastServiceDateController) {
        final nextDate = picked.add(const Duration(days: 180));
        _nextServiceDateController.text = DateFormat('yyyy-MM-dd').format(nextDate);
      }
    }
  }

  void _autoCalculateNextServiceMileage() {
    final currentMileage = double.tryParse(_currentMileageController.text) ?? 0;
    if (currentMileage > 0) {
      // Auto-calculate next service at +5000 km
      _nextServiceDateController.text = (currentMileage + 5000).toStringAsFixed(0);
    }
  }

  Future<void> _saveServiceData() async {
    final userId = _supabaseService.getCurrentUserId();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not logged in.')));
      return;
    }

    if (_vehicleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle not loaded.')));
      return;
    }

    final currentMileage = double.tryParse(_currentMileageController.text) ?? -1;
    if (currentMileage < 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a valid current mileage.')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Update vehicle with new mileage
      await _supabaseService.supabase
          .from('vehicles')
          .update({
            'previous_mileage': currentMileage,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', _vehicleId!);

      // Update service details (non-critical)
      try {
        await _vehicleDetailService.updateServiceDetails(
          _vehicleId!,
          lastServiceDate: DateTime.tryParse(_lastServiceDateController.text) ?? DateTime.now(),
          lastServiceMileage: currentMileage,
          serviceIntervalKm: 5000,
          serviceIntervalDays: 180,
        );
      } catch (e) {
        print('Warning: Could not update service details: $e');
        // Non-critical - continue with save
      }

      // Add service record
      final bool result = await _supabaseService.addServiceRecord(
        userId: userId,
        vehicleId: _vehicleId!,
        serviceType: 'routine',
        serviceDate: _lastServiceDateController.text.isNotEmpty
            ? _lastServiceDateController.text
            : DateFormat('yyyy-MM-dd').format(DateTime.now()),
        mileage: currentMileage,
        cost: 0,
        serviceCenter: _vehicleController.text,
        description: _noteController.text.isNotEmpty ? _noteController.text : 'Service update',
      );

      if (!result) {
        throw Exception('Unable to save service record.');
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service saved successfully'), backgroundColor: Colors.green));

      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_noVehicles) {
      return Scaffold(
        appBar: AppBar(title: const Text('Service Data Entry')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.directions_car, size: 72, color: Colors.green),
                const SizedBox(height: 16),
                const Text('No vehicles found', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('Please add a vehicle first to log service data.', textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/home');
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700),
                  child: const Text('Add Vehicle'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(body: Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Data Entry'),
        backgroundColor: Colors.green.shade700,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Service Lock Status Message
            if (_isServiceLocked)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lock, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Service Entry Locked',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _serviceLockMessage ?? 'Service submission is currently locked.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isServiceLocked) const SizedBox(height: 16),
            if (_isServiceLocked)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Please wait until the cooldown period is complete before submitting new service data.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue.shade800,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            if (_isServiceLocked) const SizedBox(height: 16),
            _buildTextField('Vehicle', _vehicleController, readOnly: true),
            const SizedBox(height: 8),
            _buildTextField('Vehicle Number', _vehicleNumberController, readOnly: true),
            const SizedBox(height: 8),
            _buildTextField('Current Mileage (km)', _currentMileageController, keyboardType: TextInputType.number, readOnly: _isServiceLocked),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Last Service Date', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _isServiceLocked ? null : () => _pickDate(_lastServiceDateController),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: _isServiceLocked ? Colors.grey.shade300 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: _isServiceLocked ? Colors.grey.shade100 : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: _isServiceLocked ? Colors.grey : Colors.green.shade600, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                _lastServiceDateController.text.isEmpty ? 'Select date' : _lastServiceDateController.text,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _lastServiceDateController.text.isEmpty ? Colors.grey : (_isServiceLocked ? Colors.grey : Colors.black),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Next Service Date', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: _isServiceLocked ? null : () => _pickDate(_nextServiceDateController),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: _isServiceLocked ? Colors.grey.shade300 : Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                            color: _isServiceLocked ? Colors.grey.shade100 : Colors.white,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.calendar_today, color: _isServiceLocked ? Colors.grey : Colors.green.shade600, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _nextServiceDateController.text.isEmpty ? 'Select date' : _nextServiceDateController.text,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: _nextServiceDateController.text.isEmpty ? Colors.grey : (_isServiceLocked ? Colors.grey : Colors.black),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildTextField('Note Engineer', _noteController, maxLines: 3, readOnly: _isServiceLocked),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving || _isServiceLocked ? null : _saveServiceData,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isServiceLocked ? Colors.grey : Colors.green.shade700, 
                padding: const EdgeInsets.symmetric(vertical: 14)
              ),
              child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : Text(
                _isServiceLocked ? 'Service Entry Locked' : 'Save and Reminder',
                style: const TextStyle(fontSize: 16)
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          readOnly: readOnly,
          maxLines: maxLines,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: readOnly ? Colors.grey.shade200 : Colors.white,
          ),
        ),
      ],
    );
  }
}
