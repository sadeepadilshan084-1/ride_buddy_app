import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ride_buddy/services/fuel_service.dart';
import 'package:ride_buddy/services/backend_models.dart';

class FuelRefillScreen extends StatefulWidget {
  final String vehicleId;
  final VehicleServiceDetailsModel? vehicleService;

  const FuelRefillScreen({
    super.key,
    required this.vehicleId,
    this.vehicleService,
  });

  @override
  State<FuelRefillScreen> createState() => _FuelRefillScreenState();
}

class _FuelRefillScreenState extends State<FuelRefillScreen> {
  final FuelService _fuelService = FuelService();
  List<FuelRefillModel> fuelRefills = [];

  Map<String, dynamic> fuelStats = {};
  ServiceReminderStatusModel? serviceStatus;


  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFuelData();
  }

  Future<void> _loadFuelData() async {
    try {
      setState(() => isLoading = true);
      
      final refills = await _fuelService.getVehicleFuelRefills(widget.vehicleId);
      final stats = await _fuelService.getFuelEconomyStats(widget.vehicleId);
      final service = await _fuelService.calculateServiceStatus(
        widget.vehicleId,
        widget.vehicleService?.serviceIntervalDays ?? 365,
      );

      setState(() {
        fuelRefills = refills;
        fuelStats = stats;
        serviceStatus = service;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading fuel data: $e';
        isLoading = false;
      });
    }
  }

  void _showAddRefillDialog() {
    final dateController = TextEditingController();
    final mileageController = TextEditingController();
    final amountController = TextEditingController();
    final costController = TextEditingController();
    final stationController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String selectedFuelType = 'petrol';
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Fuel Refill'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Date picker
                ListTile(
                  title: const Text('Date'),
                  subtitle: Text(
                    '${selectedDate.day}/${selectedDate.month}/${selectedDate.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setState(() => selectedDate = picked);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Fuel type
                DropdownButtonFormField<String>(
                  value: selectedFuelType,
                  decoration: const InputDecoration(
                    label: Text('Fuel Type'),
                    border: OutlineInputBorder(),
                  ),
                  items: ['petrol', 'diesel', 'cng', 'electric', 'hybrid']
                      .map((type) => DropdownMenuItem(
                        value: type,
                        child: Text(type.toUpperCase()),
                      ))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedFuelType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Millage set
                TextField(
                  controller: mileageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    label: Text('Mileage (km)'),
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 45300',
                  ),
                ),
                const SizedBox(height: 12),

                // Amount
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    label: Text('Amount (Liters)'),
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 40.5',
                  ),
                ),
                const SizedBox(height: 12),

                // Cost
                TextField(
                  controller: costController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    label: Text('Cost'),
                    border: OutlineInputBorder(),
                    hintText: 'e.g., 2430',
                  ),
                ),
                const SizedBox(height: 12),

                // Station
                TextField(
                  controller: stationController,
                  decoration: const InputDecoration(
                    label: Text('Filling Station (Optional)'),
                    border: OutlineInputBorder(),
                    hintText: 'e.g., Shell Petrol Station',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ),
            Expanded(
              child: ElevatedButton(
                onPressed: isSubmitting ? null : () async {
                  if (mileageController.text.isEmpty ||
                      amountController.text.isEmpty ||
                      costController.text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all required fields')),
                    );
                    return;
                  }

                setState(() => isSubmitting = true);

                try {
                  final user = Supabase.instance.client.auth.currentUser;
                  if (user == null) {
                    throw Exception('User not authenticated');
                  }

                  await _fuelService.createFuelRefill(
                    vehicleId: widget.vehicleId,
                    userId: user.id,
                    refillDate: selectedDate,
                    mileage: double.parse(mileageController.text),
                    amount: double.parse(amountController.text),
                    cost: double.parse(costController.text),
                    fuelType: selectedFuelType,
                    fillingStation: stationController.text.isEmpty
                        ? null
                        : stationController.text,
                  );

                  Navigator.pop(context);
                  await _loadFuelData();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('✅ Fuel refill recorded successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                } finally {
                  setState(() => isSubmitting = false);
                }
              },
              child: isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add'),
            ),            ),          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFA7F3D0),
      appBar: AppBar(
        title: const Text('Fuel Tracking'),
        centerTitle: true,
        backgroundColor: Colors.green[700],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(errorMessage!),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadFuelData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fuel Economy Stats
                      _buildFuelStatsCard(),
                      const SizedBox(height: 24),

                      // Service Reminder
                      if (serviceStatus != null) ...[
                        _buildServiceReminderCard(),
                        const SizedBox(height: 24),
                      ],

                      // Recent Refills
                      const Text(
                        'Recent Refills',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildRefillsList(),
                    ],
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddRefillDialog,
        backgroundColor: Colors.green[700],
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildFuelStatsCard() {
    final totalRefills = fuelStats['totalRefills'] as int? ?? 0;
    final totalLiters = fuelStats['totalLiters'] as double? ?? 0.0;
    final totalCost = fuelStats['totalCost'] as double? ?? 0.0;
    final avgFuelEconomy = fuelStats['averageFuelEconomy'] as double? ?? 0.0;
    final avgPrice = fuelStats['averagePricePerLiter'] as double? ?? 0.0;
    final lastMileage = fuelStats['lastMileage'] as double? ?? 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Fuel Economy',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatTile('Refills', totalRefills.toString()),
              _buildStatTile('Liters', '${totalLiters.toStringAsFixed(1)}L'),
              _buildStatTile('Cost', 'LKR ${totalCost.toStringAsFixed(0)}'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatTile('Economy', '${avgFuelEconomy.toStringAsFixed(2)} km/L'),
              _buildStatTile('Avg Price', 'LKR ${avgPrice.toStringAsFixed(2)}/L'),
              _buildStatTile('Mileage', '${lastMileage.toStringAsFixed(0)} km'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServiceReminderCard() {
    final status = serviceStatus!;
    final isOverdue = status.isOverdueByTime;
    final statusColor = isOverdue ? Colors.red : Colors.orange;
    final daysUntilService = status.nextServiceDate.difference(DateTime.now()).inDays;

    return Container(
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build, color: statusColor),
              const SizedBox(width: 12),
              Text(
                'Service Status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            status.status == 'overdue'
                ? '⚠️ Service Overdue!'
                : status.status == 'due-soon'
                    ? '📅 Service Coming Up'
                    : '✅ On Schedule',
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Next Service: ${status.nextServiceDate.toString().split(' ')[0]}',
            style: const TextStyle(fontSize: 14),
          ),
          if (daysUntilService >= 0)
            Text(
              'In $daysUntilService days',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          else
            Text(
              'Overdue by ${(-daysUntilService)} days',
              style: TextStyle(
                fontSize: 12,
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRefillsList() {
    if (fuelRefills.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No fuel refills recorded yet',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: fuelRefills.length,
      itemBuilder: (context, index) {
        final refill = fuelRefills[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      refill.refillDate.toString().split(' ')[0],
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        refill.fuelType ?? 'Unknown',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${refill.amount} L',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      'LKR ${refill.cost}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${refill.mileage} km',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                if (refill.fillingStation != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '📍 ${refill.fillingStation}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatTile(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
}
