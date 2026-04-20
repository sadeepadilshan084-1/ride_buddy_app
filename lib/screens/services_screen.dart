import 'package:flutter/material.dart';
import 'package:ride_buddy/services/vehicle_service_manager.dart';
import 'package:ride_buddy/services/backend_models.dart';
import 'package:ride_buddy/services/supabase_service.dart';

class ServicesScreen extends StatefulWidget {
  final String userId;
  final String vehicleId;

  const ServicesScreen({
    super.key,
    required this.userId,
    required this.vehicleId,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  late VehicleServiceManager _serviceManager;
  late SupabaseService _supabaseService;

  List<ServiceHistoryModel> serviceHistory = [];
  Map<String, dynamic> serviceAnalytics = {};
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _serviceManager = VehicleServiceManager();
    _supabaseService = SupabaseService();
    _loadServiceData();
  }

  Future<void> _loadServiceData() async {
    try {
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      // Fetch service records
      final records = await _supabaseService.getServiceRecords(widget.userId);
      final services = records
          .where((r) => r['vehicle_id'] == widget.vehicleId)
          .map((r) => ServiceHistoryModel.fromJson(r))
          .toList();

      // Get analytics
      final analytics =
          await _serviceManager.getServiceAnalytics(widget.vehicleId);

      setState(() {
        serviceHistory = services;
        serviceAnalytics = analytics ?? {};
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading services: $e';
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green.shade400,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Vehicle Services',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadServiceData,
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? _buildErrorWidget()
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildAnalyticsSummary(),
                      _buildServicesList(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: () => _showAddServiceDialog(),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(errorMessage!),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadServiceData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsSummary() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Service Summary',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _buildSummaryCard(
                'Total Services',
                '${serviceAnalytics['total_services'] ?? 0}',
                Colors.blue,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryCard(
                'Total Cost',
                'Rs. ${(serviceAnalytics['total_cost'] ?? 0).toStringAsFixed(0)}',
                Colors.green,
              )),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildSummaryCard(
                'Last Service',
                serviceAnalytics['last_service_date'] ?? 'N/A',
                Colors.orange,
              )),
              const SizedBox(width: 12),
              Expanded(child: _buildSummaryCard(
                'Avg. Cost',
                'Rs. ${(serviceAnalytics['average_cost'] ?? 0).toStringAsFixed(0)}',
                Colors.purple,
              )),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServicesList() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Service History',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (serviceHistory.isNotEmpty)
                Text(
                  '${serviceHistory.length} records',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (serviceHistory.isEmpty)
            Center(
              child: Column(
                children: [
                  Icon(Icons.build_outlined,
                      size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 16),
                  const Text('No service records yet',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: serviceHistory.length,
              itemBuilder: (context, index) {
                final service = serviceHistory[index];
                return _buildServiceCard(service, index);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(ServiceHistoryModel service, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Container(
          width: 4,
          decoration: BoxDecoration(
            color: Colors.green,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        title: Text(
          service.serviceType.name.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'Date: ${service.serviceDate.toString().split(' ')[0]}',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Mileage: ${service.serviceMileage?.toStringAsFixed(0) ?? '0'} km',
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              'Cost: Rs. ${service.serviceCost?.toStringAsFixed(0) ?? '0'}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.green.shade600,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (service.serviceCenter != null)
              Text(
                'Center: ${service.serviceCenter}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            PopupMenuItem(
              child: const Text('View Details'),
              onTap: () => _showServiceDetails(service),
            ),
            PopupMenuItem(
              child: const Text('Delete'),
              onTap: () => _deleteService(service.id),
            ),
          ],
        ),
      ),
    );
  }

  void _showServiceDetails(ServiceHistoryModel service) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(service.serviceType.name.toUpperCase()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow('Service Date:', service.serviceDate.toString().split(' ')[0]),
              _detailRow('Mileage:', '${service.serviceMileage?.toStringAsFixed(0) ?? '0'} km'),
              _detailRow('Cost:', 'Rs. ${service.serviceCost?.toStringAsFixed(0) ?? '0'}'),
              if (service.serviceCenter != null)
                _detailRow('Service Center:', service.serviceCenter!),
              if (service.technicianName != null)
                _detailRow('Technician:', service.technicianName!),
              if (service.partsReplaced != null)
                _detailRow('Parts Replaced:', service.partsReplaced!),
              if (service.description != null)
                _detailRow('Description:', service.description!),
              if (service.nextServiceMileage != null)
                _detailRow('Next Service At:', '${service.nextServiceMileage!.toStringAsFixed(0)} km'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteService(String serviceId) async {
    final confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Service Record?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
          ),
          Expanded(
            child: TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ),
        ],
      ),
    );

    if (confirmDelete == true) {
      try {
        await _serviceManager.deleteServiceRecord(serviceId);
        _loadServiceData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Service record deleted'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  void _showAddServiceDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => AddServiceBottomSheet(
        userId: widget.userId,
        vehicleId: widget.vehicleId,
        onServiceAdded: _loadServiceData,
      ),
    );
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
          _buildNavItem(Icons.home, false, () => Navigator.pushNamed(context, '/home')),
          _buildNavItem(Icons.location_on, false, () => Navigator.pushNamed(context, '/petrol-station')),
          _buildNavItem(Icons.videocam, false, () => Navigator.pushNamed(context, '/media')),
          _buildNavItem(Icons.bar_chart, false, () => Navigator.pushNamed(context, '/stats')),
          _buildNavItem(Icons.person, false, () => Navigator.pushNamed(context, '/profile')),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isActive ? Colors.green : Colors.grey.shade200,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: isActive ? Colors.white : Colors.grey),
      ),
    );
  }
}

class AddServiceBottomSheet extends StatefulWidget {
  final String userId;
  final String vehicleId;
  final VoidCallback onServiceAdded;

  const AddServiceBottomSheet({
    super.key,
    required this.userId,
    required this.vehicleId,
    required this.onServiceAdded,
  });

  @override
  State<AddServiceBottomSheet> createState() => _AddServiceBottomSheetState();
}

class _AddServiceBottomSheetState extends State<AddServiceBottomSheet> {
  late TextEditingController _mileageController;
  late TextEditingController _costController;
  late TextEditingController _centerController;
  late TextEditingController _technicianController;
  late TextEditingController _partsController;
  late TextEditingController _descriptionController;
  late TextEditingController _dateController;

  DateTime? _selectedDate;
  ServiceType _selectedType = ServiceType.regular;
  final SupabaseService _supabaseService = SupabaseService();
  bool _isSaving = false;
  bool _isLoadingVehicle = false;
  double? _currentMileage;

  @override
  void initState() {
    super.initState();
    _mileageController = TextEditingController();
    _costController = TextEditingController();
    _centerController = TextEditingController();
    _technicianController = TextEditingController();
    _partsController = TextEditingController();
    _descriptionController = TextEditingController();
    _dateController = TextEditingController();
    _selectedDate = DateTime.now();
    _dateController.text = _formatDate(_selectedDate!);
    
    // Auto-load vehicle data
    _loadVehicleData();
  }

  Future<void> _loadVehicleData() async {
    setState(() => _isLoadingVehicle = true);
    try {
      final response = await _supabaseService.supabase
          .from('vehicles')
          .select()
          .eq('id', widget.vehicleId)
          .single();
      
      if (response != null) {
        setState(() {
          _currentMileage = (response['previous_mileage'] as num?)?.toDouble() ?? 0;
          _mileageController.text = _currentMileage?.toStringAsFixed(2) ?? '';
        });
      }
    } catch (e) {
      print('Error loading vehicle data: $e');
    } finally {
      setState(() => _isLoadingVehicle = false);
    }
  }

  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _mileageController.dispose();
    _costController.dispose();
    _centerController.dispose();
    _technicianController.dispose();
    _partsController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Add Service Record',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('Service Type', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            DropdownButton<ServiceType>(
              value: _selectedType,
              isExpanded: true,
              items: ServiceType.values
                  .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.name.toUpperCase()),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedType = value);
                }
              },
            ),
            const SizedBox(height: 16),
            const Text('Service Date', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now(),
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
                if (date != null) {
                  setState(() {
                    _selectedDate = date;
                    _dateController.text = _formatDate(date);
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: Colors.green.shade400, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _dateController.text,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Current Mileage (km)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _isLoadingVehicle
                ? Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _buildTextField('Current Mileage (km)', _mileageController, _currentMileage?.toString() ?? '50000'),
            const SizedBox(height: 16),
            _buildTextField('Service Cost (Rs)', _costController, '5000'),
            const SizedBox(height: 16),
            _buildTextField('Service Center', _centerController, 'e.g., ABC Motors'),
            const SizedBox(height: 16),
            _buildTextField('Technician Name', _technicianController, 'Optional'),
            const SizedBox(height: 16),
            _buildTextField('Parts Replaced', _partsController, 'Optional'),
            const SizedBox(height: 16),
            _buildTextField('Description', _descriptionController, 'Additional notes...',
                maxLines: 3),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveService,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                              strokeWidth: 2,
                            ),
                          )
                        : const Text('Save', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveService() async {
    if (_mileageController.text.isEmpty || _costController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in required fields')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final success = await _supabaseService.addServiceRecord(
        userId: widget.userId,
        vehicleId: widget.vehicleId,
        serviceType: _selectedType.name,
        serviceDate: _selectedDate?.toString() ?? DateTime.now().toString(),
        mileage: double.parse(_mileageController.text),
        cost: double.parse(_costController.text),
        serviceCenter: _centerController.text,
        technicianName: _technicianController.text.isEmpty ?  null : _technicianController.text,
        description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
        partsReplaced: _partsController.text.isEmpty ? null : _partsController.text,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Service record added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
        widget.onServiceAdded();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: label.contains('km') || label.contains('Cost')
              ? TextInputType.number
              : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ],
    );
  }
}
