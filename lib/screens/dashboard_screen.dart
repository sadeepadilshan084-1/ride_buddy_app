import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../data/mock_data.dart';
import '../models/fuel_entry.dart';
import '../widgets/fuel_chart_widget.dart';
import '../widgets/period_selector_widget.dart';
import '../widgets/stat_card_widget.dart';
import '../widgets/date_filter_widget.dart';
import '../widgets/fuel_entry_tile.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {

  String _selectedPeriod = 'Weekly';
  DateTime _startDate = DateTime(2025, 4, 1);
  DateTime _endDate = DateTime.now();
  bool _isCustomFiltered = false;
  int _selectedNavIndex = 3;

  late List<double> _chartData;
  late List<String> _chartLabels;
  late List<FuelEntry> _entries;
  late Map<String, dynamic> _stats;

  late AnimationController _fadeCtrl;
  late AnimationController _slideCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();

    _fadeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeInOut,
    );

    _slideCtrl = AnimationController(
      duration: const Duration(milliseconds: 380),
      vsync: this,
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic),
    );

    _loadDataForPeriod(_selectedPeriod);

    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _slideCtrl.dispose();
    super.dispose();
  }

  void _loadDataForPeriod(String period) {
    _chartData = List<double>.from(MockData.chartData[period]!);
    _chartLabels = List<String>.from(MockData.chartLabels[period]!);
    _stats = Map<String, dynamic>.from(MockData.statsData[period]!);

    switch (period) {
      case 'Today':
        _entries = List<FuelEntry>.from(MockData.todayEntries);
        break;
      case 'Weekly':
        _entries = List<FuelEntry>.from(MockData.weeklyEntries);
        break;
      case 'Monthly':
        _entries = List<FuelEntry>.from(MockData.monthlyEntries);
        break;
      case 'Yearly':
        _entries = List<FuelEntry>.from(MockData.yearlyEntries);
        break;
      default:
        _entries = List<FuelEntry>.from(MockData.weeklyEntries);
    }
  }

  void _onPeriodChanged(String period) {
    if (_selectedPeriod == period && !_isCustomFiltered) return;

    HapticFeedback.lightImpact();

    _fadeCtrl.reset();
    _slideCtrl.reset();

    setState(() {
      _selectedPeriod = period;
      _isCustomFiltered = false;
      _loadDataForPeriod(period);
    });

    _fadeCtrl.forward();
    _slideCtrl.forward();
  }

  void _applyDateFilter() {

    if (_startDate.isAfter(_endDate)) {
      _showSnackBar("Start date must be before end date", isError: true);
      return;
    }

    HapticFeedback.mediumImpact();

    final allEntries = <String, FuelEntry>{};

    for (final e in [
      ...MockData.todayEntries,
      ...MockData.weeklyEntries,
      ...MockData.monthlyEntries,
      ...MockData.yearlyEntries,
    ]) {
      allEntries[e.id] = e;
    }

    final filtered = allEntries.values.where((e) {
      return e.date.isAfter(_startDate.subtract(const Duration(days: 1))) &&
          e.date.isBefore(_endDate.add(const Duration(days: 1)));
    }).toList();

    setState(() {

      _isCustomFiltered = true;


      _entries = filtered;

      final totalCost = filtered.fold(0.0, (sum, e) => sum + e.cost);
      final totalLiters = filtered.fold(0.0, (sum, e) => sum + e.liters);

      _stats = {
        'currentAmount': totalCost,
        'currentLiters': totalLiters,
        'predictionAmount': totalCost * 1.1,
        'predictionLiters': totalLiters * 1.1,
      };
    });

    _showSnackBar("${filtered.length} records found");
  }

  void _showSnackBar(String message, {bool isError = false}) {

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            isError ? Colors.red : const Color(0xFF1DB954),
      ),
    );
  }

  Widget _buildHeaderCard() {

    final dateLabel = _isCustomFiltered
        ? '${DateFormat('MMM d').format(_startDate)} - ${DateFormat('MMM d').format(_endDate)}'
        : _selectedPeriod;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                const Text(
                  "Fuel Dashboard",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  dateLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          const Icon(
            Icons.local_gas_station,
            color: Colors.white,
            size: 30,
          )
        ],
      ),
    );
  }

  Widget _buildBottomNav() {

    final items = [
      Icons.home,
      Icons.map,
      Icons.videocam,
      Icons.bar_chart,
      Icons.person
    ];

    return BottomNavigationBar(

      currentIndex: _selectedNavIndex,

      onTap: (i) {
        setState(() {
          _selectedNavIndex = i;
        });
      },

      items: items
          .map(
            (icon) => BottomNavigationBarItem(
              icon: Icon(icon),
              label: "",
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      backgroundColor: const Color(0xFF27AE60),

      bottomNavigationBar: _buildBottomNav(),

      body: SafeArea(

        child: SingleChildScrollView(

          padding: const EdgeInsets.all(16),


          child: Column(

            crossAxisAlignment: CrossAxisAlignment.start,

            children: [

              _buildHeaderCard(),

              const SizedBox(height: 20),

              FuelChartWidget(
                data: _chartData,
                labels: _chartLabels,
              ),

              const SizedBox(height: 20),

              PeriodSelectorWidget(
                selectedPeriod:
                    _isCustomFiltered ? "Custom" : _selectedPeriod,
                onPeriodChanged: _onPeriodChanged,
              ),

              const SizedBox(height: 20),

              Row(
  children: [
    Expanded(
      child: StatCardWidget(
        title: _isCustomFiltered
            ? 'Filtered Total'
            : _selectedPeriod == 'Today'
                ? 'Today Used'
                : 'Period Total',
        amount: _stats['currentAmount'],
        liters: _stats['currentLiters'],
        accentColor: const Color(0xFFE74C3C),
      ),
    ),
    const SizedBox(width: 12),
    Expanded(
      child: StatCardWidget(
        title: 'Prediction',
        amount: _stats['predictionAmount'],
        liters: _stats['predictionLiters'],
        accentColor: const Color(0xFF3498DB),
      ),
    ),
  ],
),

              const SizedBox(height: 20),

              DateFilterWidget(
                startDate: _startDate,
                endDate: _endDate,
                onFilter: _applyDateFilter,
                onStartDateChanged: (d) {
                  setState(() {
                    _startDate = d;
                  });
                },
                onEndDateChanged: (d) {
                  setState(() {
                    _endDate = d;
                  });
                },
              ),

              const SizedBox(height: 21),


              Column(
                children: _entries.map((e) {
                  return FuelEntryTile(entry: e);
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}