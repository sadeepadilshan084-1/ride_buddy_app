import 'package:flutter/material.dart';
import '../services/advanced_fuel_tracker_service.dart';

class MultiVehicleDashboard extends StatefulWidget {
  final List<String> vehicleIds;
  final Map<String, String> vehicleNames; // vehicleId -> name mapping

  const MultiVehicleDashboard({
    Key? key,
    required this.vehicleIds,
    required this.vehicleNames,
  }) : super(key: key);

  @override
  State<MultiVehicleDashboard> createState() => _MultiVehicleDashboardState();
}

class _MultiVehicleDashboardState extends State<MultiVehicleDashboard> {
  late AdvancedFuelTrackerService _service;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _comparison;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _service = AdvancedFuelTrackerService();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      final summary = await _service.getDashboardSummary(widget.vehicleIds);
      final comparison = await _service.compareVehicles(widget.vehicleIds);

      setState(() {
        _summary = summary;
        _comparison = comparison;
        _isLoading = false;
      });
    } catch (e) {
      _showError('Error loading dashboard: $e');
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet Dashboard'),
        backgroundColor: Colors.blueAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _summary == null || _comparison == null
          ? const Center(child: Text('No data available'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary Section
                  _buildSummarySection(),
                  const SizedBox(height: 24),

                  // Vehicle Comparison
                  _buildComparisonSection(),
                  const SizedBox(height: 24),

                  // Performance Ranking
                  _buildPerformanceRanking(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fleet Summary',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSummaryCard(
              'Total Fuel',
              '${_summary!['total_fuel_in_all_vehicles'].toStringAsFixed(1)}L',
              Icons.local_gas_station,
              Colors.green,
            ),
            _buildSummaryCard(
              'This Month',
              'Rs ${_summary!['total_cost_this_month'].toStringAsFixed(0)}',
              Icons.money,
              Colors.blue,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSummaryCard(
              'Refills',
              _summary!['total_refills_this_month'].toString(),
              Icons.local_gas_station,
              Colors.orange,
            ),
            _buildSummaryCard(
              'Best Avg',
              '${_summary!['best_average_across_all'].toStringAsFixed(1)} km/L',
              Icons.trending_up,
              Colors.purple,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildComparisonSection() {
    final comparison = _comparison!['comparison'] as Map<String, FuelAnalytics>;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicle Comparison',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...widget.vehicleIds.map((vehicleId) {
          final analytics = comparison[vehicleId];
          if (analytics == null) return const SizedBox.shrink();

          final vehicleName = widget.vehicleNames[vehicleId] ?? vehicleId;
          final isBestPerformer = vehicleId == _comparison!['best_performer'];
          final isWorstPerformer = vehicleId == _comparison!['worst_performer'];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isBestPerformer
                    ? Colors.green
                    : isWorstPerformer
                    ? Colors.orange
                    : Colors.transparent,
                width: 2,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        vehicleName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isBestPerformer)
                        const Chip(
                          label: Text('Best'),
                          backgroundColor: Colors.green,
                          labelStyle: TextStyle(color: Colors.white),
                        )
                      else if (isWorstPerformer)
                        const Chip(
                          label: Text('Needs Attention'),
                          backgroundColor: Colors.orange,
                          labelStyle: TextStyle(color: Colors.white),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildComparisonRow(
                    'Current Average',
                    '${analytics!.latestAverage.toStringAsFixed(1)} km/L',
                  ),
                  _buildComparisonRow(
                    'Total Cost',
                    'Rs ${analytics.totalCost.toStringAsFixed(0)}',
                  ),
                  _buildComparisonRow(
                    'Refill Count',
                    analytics.totalRefills.toString(),
                  ),
                  _buildComparisonRow(
                    'Cost per km',
                    'Rs ${(analytics.totalCost / (analytics.totalFuelAdded * 10)).toStringAsFixed(2)}/km',
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildPerformanceRanking() {
    final comparison = _comparison!['comparison'] as Map<String, FuelAnalytics>;

    // Create ranking list
    final ranking = comparison.entries.toList()
      ..sort((a, b) => b.value.latestAverage.compareTo(a.value.latestAverage));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fuel Economy Ranking',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ...ranking.asMap().entries.map((entry) {
          final index = entry.key;
          final vehicleId = entry.value.key;
          final analytics = entry.value.value;
          final vehicleName = widget.vehicleNames[vehicleId] ?? vehicleId;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _getRankingColor(index),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${analytics.latestAverage.toStringAsFixed(1)} km/L',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 60,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: analytics.latestAverage / 20,
                        backgroundColor: Colors.transparent,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _getRankingColor(index),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Color _getRankingColor(int index) {
    switch (index) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.blue;
      case 2:
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  Widget _buildComparisonRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade700)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
