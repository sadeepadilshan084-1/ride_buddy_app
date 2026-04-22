import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/advanced_fuel_tracker_service.dart';

class FuelAnalyticsDashboard extends StatefulWidget {
  final String vehicleId;
  final String vehicleName;

  const FuelAnalyticsDashboard({
    Key? key,
    required this.vehicleId,
    required this.vehicleName,
  }) : super(key: key);

  @override
  State<FuelAnalyticsDashboard> createState() => _FuelAnalyticsDashboardState();
}

class _FuelAnalyticsDashboardState extends State<FuelAnalyticsDashboard> {

  late AdvancedFuelTrackerService _service;
  FuelAnalytics? _analytics;
  CostAnalytics? _costAnalytics;
  FuelRangeData? _fuelRange;

  //ignore: unused_field

  List<MonthlyExpense> _monthlyHistory = [];
  Map<String, dynamic> _currentMonthDetails = {};
  Map<String, dynamic> _nextMonthPrediction = {};
  List<ChartDataPoint> _chartDataPoints = [];
  List<ChartDataPoint> _todayChartData = [];
  List<ChartDataPoint> _weeklyChartData = [];
  List<ChartDataPoint> _monthlyChartData = [];
  List<ChartDataPoint> _yearlyChartData = [];
  bool _isLoading = true;
  String _selectedPeriod = 'Monthly'; // Today, Weekly, Monthly, Yearly

  @override
  void initState() {
    super.initState();
    _service = AdvancedFuelTrackerService();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    try {
      final analytics = await _service.getFuelAnalytics(widget.vehicleId);
      final costAnalytics = await _service.getCostAnalytics(widget.vehicleId);
      final fuelRange = await _service.getFuelRange(widget.vehicleId);
      final monthlyHistory = await _service.getMonthlyHistory(widget.vehicleId);
      final currentMonth = await _service.getCurrentMonthDetails(
        widget.vehicleId,
      );
      final nextMonthPred = await _service.predictNextMonth(widget.vehicleId);

      // Load chart data for different periods
      final todayData = await _service.getChartData(widget.vehicleId, daysBack: 1);
      final weeklyData = await _service.getChartData(widget.vehicleId, daysBack: 7);
      final monthlyData = await _service.getMonthlyCostingChart(widget.vehicleId, monthsBack: 1);
      final yearlyData = await _service.getMonthlyCostingChart(widget.vehicleId, monthsBack: 12);

      setState(() {
        _analytics = analytics;
        _costAnalytics = costAnalytics;
        _fuelRange = fuelRange;
        _monthlyHistory = monthlyHistory;
        _currentMonthDetails = currentMonth;
        _nextMonthPrediction = nextMonthPred;
        _todayChartData = todayData;
        _weeklyChartData = weeklyData;
        _monthlyChartData = monthlyData;
        _yearlyChartData = yearlyData;
        _chartDataPoints = monthlyData; // Default to monthly
        _isLoading = false;
      });
    } catch (e) {
      _showError('Error loading analytics: $e');
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
        title: Text('${widget.vehicleName} - Analytics'),
        backgroundColor: const Color(0xFF038124),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _analytics == null || _costAnalytics == null || _fuelRange == null
          ? const Center(child: Text('No analytics data available'))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Period Filter Buttons
                  _buildPeriodFilterButtons(),
                  const SizedBox(height: 16),

                  // Cost Trend Chart
                  _buildCostTrendChart(),
                  const SizedBox(height: 20),

                  // Current Month & Prediction Cards
                  _buildCurrentAndPredictionCards(),
                  const SizedBox(height: 20),

                  // Fuel Range Card
                  _buildFuelRangeCard(),
                  const SizedBox(height: 20),

                  // Key Metrics Row
                  _buildKeyMetricsRow(),
                  const SizedBox(height: 20),

                  // Fuel Economy Stats
                  _buildFuelEconomySection(),
                  const SizedBox(height: 20),

                  // Cost Analytics
                  _buildCostAnalyticsSection(),
                  const SizedBox(height: 20),

                  // Tracking Summary
                  _buildTrackingSummary(),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodFilterButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        _buildPeriodButton('Today'),
        _buildPeriodButton('Weekly'),
        _buildPeriodButton('Monthly'),
        _buildPeriodButton('Yearly'),
      ],
    );
  }

  Widget _buildPeriodButton(String period) {
    bool isSelected = _selectedPeriod == period;
    return ElevatedButton(
      onPressed: () {
        setState(() {
          _selectedPeriod = period;
          // Switch chart data based on selected period
          switch (period) {
            case 'Today':
              _chartDataPoints = _todayChartData;
              break;
            case 'Weekly':
              _chartDataPoints = _weeklyChartData;
              break;
            case 'Monthly':
              _chartDataPoints = _monthlyChartData;
              break;
            case 'Yearly':
              _chartDataPoints = _yearlyChartData;
              break;
          }
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.green : Colors.grey.shade300,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      child: Text(
        period,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCostTrendChart() {
    if (_chartDataPoints.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(child: Text('No chart data available')),
        ),
      );
    }

    // Show different chart types based on period
    switch (_selectedPeriod) {
      case 'Today':
      case 'Weekly':
        return _buildBarChart();
      case 'Monthly':
      case 'Yearly':
      default:
        return _buildLineChart();
    }
  }

  Widget _buildLineChart() {
    // Sort chart data points by date
    final sortedData = List<ChartDataPoint>.from(_chartDataPoints);
    sortedData.sort((a, b) => a.date.compareTo(b.date));

    // Prepare line chart spots
    List<FlSpot> spots = [];
    for (int i = 0; i < sortedData.length; i++) {
      spots.add(FlSpot(i.toDouble(), sortedData[i].cost));
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fuel Cost Trend - $_selectedPeriod',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              width: double.infinity,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 5000,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= sortedData.length) {
                            return const SizedBox.shrink();
                          }
                          String label;
                          if (_selectedPeriod == 'Monthly') {
                            label = '${sortedData[index].date.month}/${sortedData[index].date.day}';
                          } else {
                            label = '${sortedData[index].date.year}-${sortedData[index].date.month.toString().padLeft(2, '0')}';
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          );
                        },
                        interval: sortedData.length > 6 ? (sortedData.length / 6).ceil().toDouble() : 1,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            'Rs ${value.toInt()}',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        },
                        interval: 5000,
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  minX: 0,
                  maxX: sortedData.length.toDouble() - 1,
                  minY: 0,
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) {
                          return FlDotCirclePainter(
                            radius: 4,
                            color: Colors.green,
                            strokeWidth: 2,
                            strokeColor: Colors.white,
                          );
                        },
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withValues(alpha: 0.1),
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.withValues(alpha: 0.3),
                            Colors.green.withValues(alpha: 0.1),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final index = spot.x.toInt();
                          if (index >= 0 && index < sortedData.length) {
                            String dateLabel;
                            if (_selectedPeriod == 'Monthly') {
                              dateLabel = '${sortedData[index].date.month}/${sortedData[index].date.day}';
                            } else {
                              dateLabel = '${sortedData[index].date.year}-${sortedData[index].date.month.toString().padLeft(2, '0')}';
                            }
                            return LineTooltipItem(
                              'Rs ${spot.y.toInt()}\n$dateLabel',
                              const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return null;
                        }).toList();
                      },
                      tooltipBgColor: Colors.green.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarChart() {
    // Sort chart data points by date
    final sortedData = List<ChartDataPoint>.from(_chartDataPoints);
    sortedData.sort((a, b) => a.date.compareTo(b.date));

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Fuel Consumption - $_selectedPeriod',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              width: double.infinity,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: true,
                    horizontalInterval: 5,
                    verticalInterval: 1,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 1,
                      );
                    },
                    getDrawingVerticalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          int index = value.toInt();
                          if (index < 0 || index >= sortedData.length) {
                            return const SizedBox.shrink();
                          }
                          String label;
                          if (_selectedPeriod == 'Today') {
                            label = '${sortedData[index].date.hour}:00';
                          } else {
                            label = '${sortedData[index].date.day}/${sortedData[index].date.month}';
                          }
                          return SideTitleWidget(
                            axisSide: meta.axisSide,
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                            ),
                          );
                        },
                        interval: sortedData.length > 7 ? (sortedData.length / 7).ceil().toDouble() : 1,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}L',
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          );
                        },
                        interval: 5,
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: true,
                    border: Border.all(color: Colors.grey.shade300, width: 1),
                  ),
                  barGroups: List.generate(sortedData.length, (index) {
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: sortedData[index].fuelAdded,
                          color: Colors.blue,
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final data = sortedData[groupIndex];
                        String dateLabel;
                        if (_selectedPeriod == 'Today') {
                          dateLabel = '${data.date.hour}:${data.date.minute.toString().padLeft(2, '0')}';
                        } else {
                          dateLabel = '${data.date.day}/${data.date.month}';
                        }
                        return BarTooltipItem(
                          '${data.fuelAdded.toStringAsFixed(1)}L\n$dateLabel',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                      tooltipBgColor: Colors.blue.shade700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentAndPredictionCards() {
    final currentMonth = _currentMonthDetails;
    final prediction = _nextMonthPrediction;

    return Row(
      children: [
        // Current Month Card
        Expanded(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Current Month',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rs ${(currentMonth['total_cost'] ?? 0).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(currentMonth['total_fuel'] ?? 0).toStringAsFixed(1)}L',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Next Month Prediction Card
        Expanded(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Next Month Pred.',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rs ${(prediction['predicted_cost'] ?? 0).toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${(prediction['predicted_fuel'] ?? 0).toStringAsFixed(1)}L',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFuelRangeCard() {
    final fuelRange = _fuelRange!;
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      color: fuelRange.lowFuel ? Colors.red.shade50 : Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Estimated Range',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Icon(
                  fuelRange.lowFuel
                      ? Icons.warning_rounded
                      : Icons.check_circle,
                  color: fuelRange.lowFuel ? Colors.red : Colors.green,
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 15),
            Text(
              '${fuelRange.estimatedRange.toStringAsFixed(0)} km',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: fuelRange.lowFuel ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Fuel: ${fuelRange.fuelRemaining.toStringAsFixed(1)}L @ ${fuelRange.currentAverage.toStringAsFixed(1)} km/L',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyMetricsRow() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        _buildMetricCard(
          'Best Avg',
          '${_analytics!.bestAverage.toStringAsFixed(1)} km/L',
          Colors.green,
        ),
        _buildMetricCard(
          'Current Avg',
          '${_analytics!.latestAverage.toStringAsFixed(1)} km/L',
          Colors.green,
        ),
        _buildMetricCard(
          'Worst Avg',
          '${_analytics!.worstAverage.toStringAsFixed(1)} km/L',
          Colors.orange,
        ),
      ],
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return SizedBox(
      width: 100,
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFuelEconomySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Fuel Economy',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAnalyticsRow(
                  'Total Refills',
                  _analytics!.totalRefills.toString(),
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Full Tanks',
                  _analytics!.fullTanks.toString(),
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Total Fuel Added',
                  '${_analytics!.totalFuelAdded.toStringAsFixed(1)}L',
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Days Tracked',
                  _analytics!.daysTracked.toString(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCostAnalyticsSection() {
    final cost = _costAnalytics!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cost Analysis',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        Card(
          elevation: 2,
          color: Colors.green.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildAnalyticsRow(
                  'Total Spent',
                  'Rs ${cost.totalSpent.toStringAsFixed(0)}',
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Cost per Liter',
                  'Rs ${_analytics!.averageCostPerLiter.toStringAsFixed(2)}/L',
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Cost per km',
                  'Rs ${cost.costPerKm.toStringAsFixed(2)}/km',
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Monthly Projection',
                  'Rs ${cost.monthlyProjection.toStringAsFixed(0)}',
                ),
                const Divider(),
                _buildAnalyticsRow(
                  'Avg Cost per Trip',
                  'Rs ${cost.averageCostPerTrip.toStringAsFixed(0)}',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrackingSummary() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tracking Summary',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.purple.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.purple.shade200, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Period Tracked:'),
                  ),
                  Text('${_analytics!.daysTracked} days'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Most Expensive Refill:'),
                  ),
                  Text(
                    'Rs ${_costAnalytics!.mostExpensiveRefill.toStringAsFixed(0)}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('Cheapest Refill:'),
                  ),
                  Text(
                    'Rs ${_costAnalytics!.cheapestRefill.toStringAsFixed(0)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnalyticsRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
