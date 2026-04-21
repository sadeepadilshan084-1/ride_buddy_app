import 'package:supabase_flutter/supabase_flutter.dart';

// Constants
const double DEFAULT_AVG_KM_PER_LITER = 10.0;
const int AVERAGE_DECIMAL_PLACES = 1;
const double DEFAULT_PRICE_PER_LITRE = 100.0;
const double LOW_FUEL_THRESHOLD = 5.0; // Alert when below 5L

// ===== ANALYTICS MODELS =====

class FuelAnalytics {
  final double totalCost;
  final double totalFuelAdded;
  final double averageCostPerLiter;
  final double averageCostPerKm;
  final int totalRefills;
  final int fullTanks;
  final double bestAverage;
  final double worstAverage;
  final double latestAverage;
  final int daysTracked;

  FuelAnalytics({
    required this.totalCost,
    required this.totalFuelAdded,
    required this.averageCostPerLiter,
    required this.averageCostPerKm,
    required this.totalRefills,
    required this.fullTanks,
    required this.bestAverage,
    required this.worstAverage,
    required this.latestAverage,
    required this.daysTracked,
  });
}

class FuelRangeData {
  final double estimatedRange;
  final double fuelRemaining;
  final double currentAverage;
  final bool lowFuel;

  FuelRangeData({
    required this.estimatedRange,
    required this.fuelRemaining,
    required this.currentAverage,
    required this.lowFuel,
  });
}

class ChartDataPoint {
  final DateTime date;
  final double average;
  final int mileage;
  final double fuelAdded;
  final double cost;

  ChartDataPoint({
    required this.date,
    required this.average,
    required this.mileage,
    required this.fuelAdded,
    required this.cost,
  });
}

class CostAnalytics {
  final double totalSpent;
  final double averageCostPerTrip;
  final double costPerKm;
  final double monthlyProjection;
  final List<MonthlyExpense> monthlyBreakdown;
  final double mostExpensiveRefill;
  final double cheapestRefill;

  CostAnalytics({
    required this.totalSpent,
    required this.averageCostPerTrip,
    required this.costPerKm,
    required this.monthlyProjection,
    required this.monthlyBreakdown,
    required this.mostExpensiveRefill,
    required this.cheapestRefill,
  });
}

class MonthlyExpense {
  final int month;
  final int year;
  final double totalCost;
  final double totalFuel;
  final int refillCount;

  MonthlyExpense({
    required this.month,
    required this.year,
    required this.totalCost,
    required this.totalFuel,
    required this.refillCount,
  });
}

class NotificationEvent {
  final String id;
  final String vehicleId;
  final String type; // 'low_fuel', 'service_due', 'price_spike'
  final String title;
  final String message;
  final DateTime createdAt;
  final bool read;

  NotificationEvent({
    required this.id,
    required this.vehicleId,
    required this.type,
    required this.title,
    required this.message,
    required this.createdAt,
    this.read = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'type': type,
    'title': title,
    'message': message,
    'created_at': createdAt.toIso8601String(),
    'read': read,
  };

  factory NotificationEvent.fromJson(Map<String, dynamic> json) =>
      NotificationEvent(
        id: json['id'] as String? ?? '',
        vehicleId: json['vehicle_id'] as String? ?? '',
        type: json['type'] as String? ?? 'info',
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        createdAt: json['created_at'] != null
            ? DateTime.parse(json['created_at'] as String)
            : DateTime.now(),
        read: json['read'] as bool? ?? false,
      );
}

// ===== MAIN SERVICE CLASS =====

class AdvancedFuelTrackerService {
  late final SupabaseClient _supabase;
  static const String vehiclesTable = 'vehicles';
  static const String refillsTable = 'refill_records';
  static const String notificationsTable = 'notifications';

  AdvancedFuelTrackerService() {
    _supabase = Supabase.instance.client;
  }

  // ===== ANALYTICS METHODS =====

  /// Get comprehensive fuel analytics for a vehicle
  Future<FuelAnalytics> getFuelAnalytics(String vehicleId) async {
    try {
      final vehicle = await _getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      final refills = await _getRefills(vehicleId);
      final fullTankRefills = refills
          .where((r) => r['tank_full'] as bool)
          .toList();

      if (refills.isEmpty) {
        return FuelAnalytics(
          totalCost: 0,
          totalFuelAdded: 0,
          averageCostPerLiter: 0,
          averageCostPerKm: 0,
          totalRefills: 0,
          fullTanks: 0,
          bestAverage: 0,
          worstAverage: 0,
          latestAverage: vehicle['current_avg'] as double? ?? 0,
          daysTracked: 0,
        );
      }

      double totalCost = refills.fold(
        0,
        (sum, r) => sum + (r['fuel_cost'] as num),
      );
      double totalFuel = refills.fold(
        0,
        (sum, r) => sum + (r['fuel_added'] as num),
      );
      double totalDistance = refills.isNotEmpty
          ? ((refills.last['mileage'] as num) -
                    (refills.first['mileage'] as num))
                .toDouble()
          : 0;

      List<double> averages = fullTankRefills
          .map((r) => (r['average_at_fill'] as num?)?.toDouble() ?? 0)
          .where((a) => a > 0)
          .toList();

      DateTime firstRefill = DateTime.parse(refills.first['created_at']);
      DateTime lastRefill = DateTime.parse(refills.last['created_at']);
      int daysTracked = lastRefill.difference(firstRefill).inDays + 1;

      return FuelAnalytics(
        totalCost: totalCost,
        totalFuelAdded: totalFuel,
        averageCostPerLiter: totalFuel > 0 ? totalCost / totalFuel : 0,
        averageCostPerKm: totalDistance > 0 ? totalCost / totalDistance : 0,
        totalRefills: refills.length,
        fullTanks: fullTankRefills.length,
        bestAverage: averages.isNotEmpty
            ? averages.reduce((a, b) => a > b ? a : b)
            : 0,
        worstAverage: averages.isNotEmpty
            ? averages.reduce((a, b) => a < b ? a : b)
            : 0,
        latestAverage: vehicle['current_avg'] as double? ?? 0,
        daysTracked: daysTracked,
      );
    } catch (e) {
      throw Exception('Error getting fuel analytics: $e');
    }
  }

  /// Get cost analytics with monthly breakdown
  Future<CostAnalytics> getCostAnalytics(String vehicleId) async {
    try {
      final refills = await _getRefills(vehicleId);
      if (refills.isEmpty) {
        return CostAnalytics(
          totalSpent: 0,
          averageCostPerTrip: 0,
          costPerKm: 0,
          monthlyProjection: 0,
          monthlyBreakdown: [],
          mostExpensiveRefill: 0,
          cheapestRefill: 0,
        );
      }

      double totalSpent = refills.fold(
        0,
        (sum, r) => sum + (r['fuel_cost'] as num),
      );
      double costPerTrip = totalSpent / refills.length;

      double totalDistance = refills.isNotEmpty
          ? ((refills.last['mileage'] as num) -
                    (refills.first['mileage'] as num))
                .toDouble()
          : 0;

      double costPerKm = totalDistance > 0 ? totalSpent / totalDistance : 0;

      // Calculate monthly breakdown
      Map<String, MonthlyExpense> monthlyMap = {};
      for (var refill in refills) {
        DateTime date = DateTime.parse(refill['created_at']);
        String monthKey = '${date.year}-${date.month}';

        if (!monthlyMap.containsKey(monthKey)) {
          monthlyMap[monthKey] = MonthlyExpense(
            month: date.month,
            year: date.year,
            totalCost: 0,
            totalFuel: 0,
            refillCount: 0,
          );
        }

        final current = monthlyMap[monthKey]!;
        monthlyMap[monthKey] = MonthlyExpense(
          month: current.month,
          year: current.year,
          totalCost:
              current.totalCost + (refill['fuel_cost'] as num).toDouble(),
          totalFuel:
              current.totalFuel + (refill['fuel_added'] as num).toDouble(),
          refillCount: current.refillCount + 1,
        );
      }

      // Calculate projection for current month
      DateTime now = DateTime.now();
      String currentMonthKey = '${now.year}-${now.month}';
      double monthlyProjection = monthlyMap[currentMonthKey]?.totalCost ?? 0;
      int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
      int daysElapsed = now.day;
      if (daysElapsed > 0) {
        monthlyProjection = (monthlyProjection / daysElapsed) * daysInMonth;
      }

      List<double> costs = refills
          .map((r) => (r['fuel_cost'] as num).toDouble())
          .toList();

      return CostAnalytics(
        totalSpent: totalSpent,
        averageCostPerTrip: costPerTrip,
        costPerKm: costPerKm,
        monthlyProjection: monthlyProjection,
        monthlyBreakdown: monthlyMap.values.toList(),
        mostExpensiveRefill: costs.reduce((a, b) => a > b ? a : b),
        cheapestRefill: costs.reduce((a, b) => a < b ? a : b),
      );
    } catch (e) {
      throw Exception('Error getting cost analytics: $e');
    }
  }

  /// Get chart data for UI visualization
  Future<List<ChartDataPoint>> getChartData(
    String vehicleId, {
    int daysBack = 30,
  }) async {
    try {
      final refills = await _getRefills(vehicleId);
      final cutoffDate = DateTime.now().subtract(Duration(days: daysBack));

      List<ChartDataPoint> dataPoints = [];
      for (var refill in refills) {
        final date = DateTime.parse(refill['created_at']);
        if (date.isBefore(cutoffDate)) continue;

        dataPoints.add(
          ChartDataPoint(
            date: date,
            average:
                (refill['average_at_fill'] as num?)?.toDouble() ??
                (refill['current_avg'] as num?)?.toDouble() ??
                0,
            mileage: (refill['mileage'] as num).toInt(),
            fuelAdded: (refill['fuel_added'] as num).toDouble(),
            cost: (refill['fuel_cost'] as num).toDouble(),
          ),
        );
      }

      return dataPoints;
    } catch (e) {
      throw Exception('Error getting chart data: $e');
    }
  }

  // ===== FUEL RANGE PREDICTION =====

  /// Get fuel range estimation
  Future<FuelRangeData> getFuelRange(
    String vehicleId, {
    double? currentMileage,
  }) async {
    try {
      final vehicle = await _getVehicle(vehicleId);
      if (vehicle == null) throw Exception('Vehicle not found');

      double fuelRemaining = (vehicle['fuel_remaining'] as num).toDouble();
      double currentAvg =
          (vehicle['current_avg'] as num?)?.toDouble() ??
          DEFAULT_AVG_KM_PER_LITER;

      // Calculate remaining range
      double estimatedRange = fuelRemaining * currentAvg;

      bool lowFuel = fuelRemaining < LOW_FUEL_THRESHOLD;

      return FuelRangeData(
        estimatedRange: estimatedRange,
        fuelRemaining: fuelRemaining,
        currentAverage: currentAvg,
        lowFuel: lowFuel,
      );
    } catch (e) {
      throw Exception('Error calculating fuel range: $e');
    }
  }

  // ===== NOTIFICATION METHODS =====

  /// Create a new notification
  Future<NotificationEvent> createNotification({
    required String vehicleId,
    required String type,
    required String title,
    required String message,
  }) async {
    try {
      final response = await _supabase.from(notificationsTable).insert({
        'vehicle_id': vehicleId,
        'type': type,
        'title': title,
        'message': message,
      }).select();

      if (response.isEmpty) throw Exception('Failed to create notification');
      return NotificationEvent.fromJson(response.first);
    } catch (e) {
      throw Exception('Error creating notification: $e');
    }
  }

  /// Get unread notifications for a vehicle
  Future<List<NotificationEvent>> getUnreadNotifications(
    String vehicleId,
  ) async {
    try {
      final response = await _supabase
          .from(notificationsTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .eq('read', false)
          .order('created_at', ascending: false);

      return (response as List)
          .map((n) => NotificationEvent.fromJson(n))
          .toList();
    } catch (e) {
      throw Exception('Error fetching notifications: $e');
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      await _supabase
          .from(notificationsTable)
          .update({'read': true})
          .eq('id', notificationId);
    } catch (e) {
      throw Exception('Error marking notification as read: $e');
    }
  }

  /// Check and create low fuel notification if needed
  Future<void> checkAndNotifyLowFuel(String vehicleId) async {
    try {
      final vehicle = await _getVehicle(vehicleId);
      if (vehicle == null) return;

      double fuelRemaining = (vehicle['fuel_remaining'] as num).toDouble();

      if (fuelRemaining < LOW_FUEL_THRESHOLD) {
        // Check if notification already exists for today
        final existingNotifications = await _supabase
            .from(notificationsTable)
            .select()
            .eq('vehicle_id', vehicleId)
            .eq('type', 'low_fuel');

        bool hasRecentNotification = false;
        for (var notif in existingNotifications) {
          final createdAt = DateTime.parse(notif['created_at']);
          if (DateTime.now().difference(createdAt).inHours < 24) {
            hasRecentNotification = true;
            break;
          }
        }

        if (!hasRecentNotification) {
          await createNotification(
            vehicleId: vehicleId,
            type: 'low_fuel',
            title: 'Low Fuel Alert',
            message:
                'Your vehicle has only ${fuelRemaining.toStringAsFixed(1)}L remaining. Please refuel soon.',
          );
        }
      }
    } catch (e) {
      print('Error checking low fuel: $e');
    }
  }

  // ===== HELPER METHODS =====

  Future<Map<String, dynamic>?> _getVehicle(String vehicleId) async {
    try {
      final response = await _supabase
          .from(vehiclesTable)
          .select()
          .eq('id', vehicleId)
          .single();
      return response;
    } catch (e) {
      return null;
    }
  }

  Future<List<dynamic>> _getRefills(String vehicleId) async {
    try {
      final response = await _supabase
          .from(refillsTable)
          .select()
          .eq('vehicle_id', vehicleId)
          .order('created_at', ascending: true);
      return response as List<dynamic>;
    } catch (e) {
      return [];
    }
  }

  /// Get all refills for multiple vehicles
  Future<List<dynamic>> getMultipleVehicleRefills(
    List<String> vehicleIds,
  ) async {
    try {
      final response = await _supabase
          .from(refillsTable)
          .select()
          .inFilter('vehicle_id', vehicleIds)
          .order('created_at', ascending: false);
      return response as List<dynamic>;
    } catch (e) {
      throw Exception('Error fetching refills: $e');
    }
  }

  /// Get vehicle comparison analytics
  Future<Map<String, dynamic>> compareVehicles(List<String> vehicleIds) async {
    try {
      final analytics = <String, FuelAnalytics>{};

      for (var vehicleId in vehicleIds) {
        final vehicleAnalytics = await getFuelAnalytics(vehicleId);
        analytics[vehicleId] = vehicleAnalytics;
      }

      // Find best and worst performers
      final avgsList = analytics.values.map((a) => a.latestAverage).toList();
      final bestAvg = avgsList.reduce((a, b) => a > b ? a : b);
      final worstAvg = avgsList.reduce((a, b) => a < b ? a : b);

      return {
        'comparison': analytics,
        'best_performer': analytics.entries
            .firstWhere((e) => e.value.latestAverage == bestAvg)
            .key,
        'worst_performer': analytics.entries
            .firstWhere((e) => e.value.latestAverage == worstAvg)
            .key,
      };
    } catch (e) {
      throw Exception('Error comparing vehicles: $e');
    }
  }

  /// Get summary for dashboard
  Future<Map<String, dynamic>> getDashboardSummary(
    List<String> vehicleIds,
  ) async {
    try {
      double totalFuelInAllVehicles = 0;
      double totalCostThisMonth = 0;
      int totalRefillsThisMonth = 0;
      double bestAverageAcrossAll = 0;

      DateTime now = DateTime.now();
      DateTime monthStart = DateTime(now.year, now.month, 1);

      for (var vehicleId in vehicleIds) {
        final vehicle = await _getVehicle(vehicleId);
        if (vehicle != null) {
          totalFuelInAllVehicles += (vehicle['fuel_remaining'] as num)
              .toDouble();
          bestAverageAcrossAll = ([
            bestAverageAcrossAll,
            (vehicle['current_avg'] as num?)?.toDouble() ?? 0,
          ].reduce((a, b) => a > b ? a : b));
        }

        final refills = await _getRefills(vehicleId);
        for (var refill in refills) {
          final refillDate = DateTime.parse(refill['created_at']);
          if (refillDate.isAfter(monthStart) && refillDate.isBefore(now)) {
            totalCostThisMonth += (refill['fuel_cost'] as num).toDouble();
            totalRefillsThisMonth++;
          }
        }
      }

      return {
        'total_fuel_in_all_vehicles': totalFuelInAllVehicles,
        'total_cost_this_month': totalCostThisMonth,
        'total_refills_this_month': totalRefillsThisMonth,
        'best_average_across_all': bestAverageAcrossAll,
      };
    } catch (e) {
      throw Exception('Error getting dashboard summary: $e');
    }
  }

  // ===== COST PREDICTION & FORECASTING =====

  /// Get monthly cost data for last 12 months
  Future<List<MonthlyExpense>> getMonthlyHistory(String vehicleId) async {
    try {
      final refills = await _getRefills(vehicleId);
      Map<String, MonthlyExpense> monthlyMap = {};

      for (var refill in refills) {
        DateTime date = DateTime.parse(refill['created_at']);
        String monthKey = '${date.year}-${date.month}';

        if (!monthlyMap.containsKey(monthKey)) {
          monthlyMap[monthKey] = MonthlyExpense(
            month: date.month,
            year: date.year,
            totalCost: 0,
            totalFuel: 0,
            refillCount: 0,
          );
        }

        final current = monthlyMap[monthKey]!;
        monthlyMap[monthKey] = MonthlyExpense(
          month: current.month,
          year: current.year,
          totalCost:
              current.totalCost + (refill['fuel_cost'] as num).toDouble(),
          totalFuel:
              current.totalFuel + (refill['fuel_added'] as num).toDouble(),
          refillCount: current.refillCount + 1,
        );
      }

      // Sort by date
      final sortedMonths = monthlyMap.values.toList();
      sortedMonths.sort((a, b) {
        int yearComp = a.year.compareTo(b.year);
        if (yearComp != 0) return yearComp;
        return a.month.compareTo(b.month);
      });

      return sortedMonths;
    } catch (e) {
      throw Exception('Error getting monthly history: $e');
    }
  }

  /// Get current month cost and fuel details
  Future<Map<String, dynamic>> getCurrentMonthDetails(String vehicleId) async {
    try {
      final refills = await _getRefills(vehicleId);
      DateTime now = DateTime.now();
      DateTime monthStart = DateTime(now.year, now.month, 1);

      double totalCost = 0;
      double totalFuel = 0;
      int refillCount = 0;

      for (var refill in refills) {
        final refillDate = DateTime.parse(refill['created_at']);
        if (refillDate.isAfter(monthStart) && refillDate.isBefore(now)) {
          totalCost += (refill['fuel_cost'] as num).toDouble();
          totalFuel += (refill['fuel_added'] as num).toDouble();
          refillCount++;
        }
      }

      return {
        'total_cost': totalCost,
        'total_fuel': totalFuel,
        'refill_count': refillCount,
        'avg_cost_per_refill': refillCount > 0 ? totalCost / refillCount : 0,
        'avg_fuel_per_refill': refillCount > 0 ? totalFuel / refillCount : 0,
      };
    } catch (e) {
      throw Exception('Error getting current month details: $e');
    }
  }

  /// Predict next month cost based on historical average
  Future<Map<String, dynamic>> predictNextMonth(String vehicleId) async {
    try {
      final monthlyHistory = await getMonthlyHistory(vehicleId);

      // Calculate average from last 3 months (or available data)
      int monthsToConsider = monthlyHistory.length >= 3
          ? 3
          : monthlyHistory.length;
      if (monthsToConsider == 0) {
        return {
          'predicted_cost': 0,
          'predicted_fuel': 0,
          'confidence': 0.0,
          'message': 'Insufficient data for prediction',
        };
      }

      double totalCost = 0;
      double totalFuel = 0;

      final recentMonths = monthlyHistory.sublist(
        monthlyHistory.length - monthsToConsider,
      );

      for (var month in recentMonths) {
        totalCost += month.totalCost;
        totalFuel += month.totalFuel;
      }

      double avgCost = totalCost / monthsToConsider;
      double avgFuel = totalFuel / monthsToConsider;

      // Calculate confidence (higher if consistent spending)
      List<double> costs = recentMonths.map((m) => m.totalCost).toList();
      double variance = 0;
      for (var cost in costs) {
        variance += (cost - avgCost) * (cost - avgCost);
      }
      variance /= monthsToConsider;
      double stdDev = variance > 0 ? (variance < 100 ? variance : 100.0) : 0.0;
      double costRatio = stdDev / avgCost;
      double clampedRatio = costRatio > 1
          ? 1.0
          : (costRatio < 0 ? 0.0 : costRatio);
      double confidence = 1.0 - clampedRatio;

      return {
        'predicted_cost': avgCost,
        'predicted_fuel': avgFuel,
        'confidence': confidence,
        'based_on_months': monthsToConsider,
        'message': 'Prediction based on last $monthsToConsider months',
      };
    } catch (e) {
      throw Exception('Error predicting next month: $e');
    }
  }

  /// Get chart data for cost trends
  Future<List<ChartDataPoint>> getMonthlyCostingChart(
    String vehicleId, {
    int monthsBack = 12,
  }) async {
    try {
      final monthlyHistory = await getMonthlyHistory(vehicleId);
      final cutoffDate = DateTime.now().subtract(
        Duration(days: 30 * monthsBack),
      );

      List<ChartDataPoint> dataPoints = [];

      for (var month in monthlyHistory) {
        final monthDate = DateTime(month.year, month.month, 1);
        if (monthDate.isBefore(cutoffDate)) continue;

        dataPoints.add(
          ChartDataPoint(
            date: monthDate,
            average: month.totalFuel > 0
                ? month.totalCost / month.totalFuel
                : 0,
            mileage: 0,
            fuelAdded: month.totalFuel,
            cost: month.totalCost,
          ),
        );
      }

      return dataPoints;
    } catch (e) {
      throw Exception('Error getting monthly costing chart: $e');
    }
  }
}
