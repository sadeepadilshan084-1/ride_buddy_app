import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ride_buddy/services/reminder_service.dart';
import 'package:ride_buddy/services/backend_models.dart';
import 'package:ride_buddy/services/supabase_service.dart';
import 'package:ride_buddy/screens/add_task_screen.dart';
import 'package:ride_buddy/screens/service_data.dart';
import 'package:ride_buddy/services/selected_vehicle_provider.dart';

class ReminderScreen extends StatefulWidget {
  final double currentMileage;
  final double nextServiceKm;
  final DateTime? nextServiceDate;

  const ReminderScreen({
    Key? key,
    this.currentMileage = 0,
    this.nextServiceKm = 0,
    this.nextServiceDate,
  }) : super(key: key);

  @override
  State<ReminderScreen> createState() => _ReminderScreenState();
}

class _ReminderScreenState extends State<ReminderScreen> {
  late ReminderService _reminderService;
  late SupabaseService _supabaseService;
  late SelectedVehicleProvider _selectedVehicleProvider;
  late DateTime selectedDate;
  late List<ReminderModel> reminders;
  bool isLoading = true;
  String? errorMessage;
  bool isLoadingServiceData = false;
  Map<String, dynamic>? nextServiceReminder;

  late double _currentMileage;
  late double _nextServiceKm;
  DateTime? _nextServiceDate;
  DateTime? _lastServiceSubmissionTime;
  double _serviceSubmissionKmLimit = 5000;
  bool _isServiceEntryLocked = false;
  String? _serviceLockedMessage;
  String? _debugError;
  String? _selectedVehicleId;
  bool _showCalendarView = true; // Toggle between calendar and list view

  @override
  void initState() {
    super.initState();
    _reminderService = ReminderService();
    _supabaseService = SupabaseService();
    _selectedVehicleProvider = SelectedVehicleProvider();
    selectedDate = DateTime.now();
    reminders = [];

    _currentMileage = widget.currentMileage;
    _nextServiceKm = widget.nextServiceKm;
    _nextServiceDate = widget.nextServiceDate;

    _initializeSelectedVehicle();
  }

  Future<void> _initializeSelectedVehicle() async {
    await _selectedVehicleProvider.initialize();
    await _resolveSelectedVehicle();
    _loadReminders();
    _loadNextServiceReminder();
  }

  Future<void> _resolveSelectedVehicle() async {
    final selectedVehicle = _selectedVehicleProvider.getSelectedVehicle();
    if (selectedVehicle?.id != null) {
      _selectedVehicleId = selectedVehicle!.id;
      print('✓ ReminderScreen: Using selected vehicle: $_selectedVehicleId');
    } else {
      _selectedVehicleId = null;
      print('⚠️ ReminderScreen: No vehicle selected');
    }
  }

  Future<Map<String, dynamic>?> _getSelectedVehicleInfo() async {
    if (_selectedVehicleId == null) return null;

    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) return null;

      final vehicles = await _supabaseService.getUserVehicles(userId);
      final selectedVehicle = vehicles.firstWhere(
        (v) => v['id'] == _selectedVehicleId,
        orElse: () => <String, dynamic>{}, // Return empty map instead of null
      );

      return selectedVehicle.isNotEmpty ? selectedVehicle : null;
    } catch (e) {
      print('Error getting selected vehicle info: $e');
      return null;
    }
  }

  Future<void> _checkServiceEntryLockStatus() async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() {
          _isServiceEntryLocked = false;
          _serviceLockedMessage = 'Ready to add service data';
        });
        return;
      }

      if (_selectedVehicleId == null) {
        setState(() {
          _isServiceEntryLocked = false;
          _serviceLockedMessage = 'No vehicle selected';
        });
        return;
      }

      final vehicleId = _selectedVehicleId!;

      try {
        // Get last service submission time from service_history
        final lastService = await _supabaseService.supabase
            .from('service_history')
            .select('created_at, service_mileage')
            .eq('vehicle_id', vehicleId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (lastService != null) {
          try {
            _lastServiceSubmissionTime = DateTime.parse(lastService['created_at']);

            // Get current vehicle mileage
            final vehicleData = await _supabaseService.supabase
                .from('vehicles')
                .select('previous_mileage')
                .eq('id', vehicleId)
                .single();

            final currentMileage = (vehicleData['previous_mileage'] as num?)?.toDouble() ?? 0;
            final lastServiceMileage = (lastService['service_mileage'] as num?)?.toDouble() ?? 0;
            final kmSinceLast = currentMileage - lastServiceMileage;

            // Check if cooldown is still active (less than 5000 km since last service)
            if (kmSinceLast < _serviceSubmissionKmLimit) {
              final kmRemaining = (_serviceSubmissionKmLimit - kmSinceLast).toStringAsFixed(0);
              setState(() {
                _isServiceEntryLocked = true;
                _serviceLockedMessage = '⏱️ Cooldown Active: $kmRemaining km remaining';
                _debugError = null;
              });
            } else {
              setState(() {
                _isServiceEntryLocked = false;
                _serviceLockedMessage = '✅ Service Cooldown Complete - Ready for new data';
                _debugError = null;
              });
            }
          } catch (parseError) {
            print('Error parsing service data: $parseError');
            setState(() {
              _isServiceEntryLocked = false;
              _serviceLockedMessage = '🚗 Ready to add service data';
              _debugError = 'Parse Error: ${parseError.toString()}';
            });
          }
        } else {
          // First service submission
          setState(() {
            _isServiceEntryLocked = false;
            _serviceLockedMessage = '🚗 Ready to add your first service data';
            _debugError = null;
          });
        }
      } catch (dbError) {
        print('Database error: $dbError');
        // If database query fails, allow service entry
        setState(() {
          _isServiceEntryLocked = false;
          _serviceLockedMessage = '🚗 Ready to add service data';
          _debugError = 'DB Error: ${dbError.toString()}';
        });
      }
    } catch (e) {
      print('Error checking service lock status: $e');
      setState(() {
        _isServiceEntryLocked = false;
        _serviceLockedMessage = '🚗 Ready to add service data';
        _debugError = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _loadReminders() async {
    try {
      setState(() => isLoading = true);

      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() {
          errorMessage = 'User not authenticated';
          isLoading = false;
        });
        return;
      }

      final fetchedReminders = await _reminderService.getUserReminders(userId);

      setState(() {
        reminders = fetchedReminders;
        errorMessage = null;
        isLoading = false;
      });

      await _checkServiceEntryLockStatus();
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load reminders: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _loadNextServiceReminder() async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null || _selectedVehicleId == null) return;
      final vehicleId = _selectedVehicleId!;

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
        setState(() {
          nextServiceReminder = response;
        });
      }
    } catch (e) {
      print('Error loading next service reminder: $e');
    }
  }

  Future<void> _deleteReminder(String reminderId) async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) return;

      await _reminderService.deleteReminder(reminderId);
      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting task: $e')),
        );
      }
    }
  }

  Future<void> _markReminderComplete(String reminderId) async {
    try {
      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) return;

      await _reminderService.completeReminder(reminderId);
      await _loadReminders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task marked as complete'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error completing task: $e')),
        );
      }
    }
  }

  List<ReminderModel> getRemindersForDate(DateTime date) {
    return reminders.where((reminder) {
      return reminder.expiryDate.year == date.year &&
          reminder.expiryDate.month == date.month &&
          reminder.expiryDate.day == date.day;
    }).toList();
  }

  void _showTodayTasksDialog() {
    final todayTasks = getRemindersForDate(DateTime.now());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Today\'s Tasks'),
        content: SizedBox(
          width: double.maxFinite,
          child: todayTasks.isEmpty
              ? const Center(
                  child: Text('No tasks for today'),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: todayTasks.length,
                  itemBuilder: (context, index) {
                    final task = todayTasks[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(
                          task.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            decoration: task.status == 'completed' 
                                ? TextDecoration.lineThrough 
                                : TextDecoration.none,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (task.description != null && task.description!.isNotEmpty)
                              Text(task.description!),
                            Text(
                              'Type: ${task.reminderType.name}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: task.status == 'completed'
                            ? const Icon(Icons.check_circle, color: Colors.green)
                            : IconButton(
                                icon: const Icon(Icons.check, color: Colors.blue),
                                onPressed: () {
                                  _markReminderComplete(task.id);
                                  Navigator.pop(context);
                                  _showTodayTasksDialog();
                                },
                                tooltip: 'Mark as completed',
                              ),
                        onLongPress: () {
                          _deleteReminder(task.id);
                          Navigator.pop(context);
                          _showTodayTasksDialog();
                        },
                      ),
                    );
                  },
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
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    DateTime selectedExpiryDate = DateTime.now().add(const Duration(days: 30));
    ReminderType selectedType = ReminderType.other;
    ReminderFrequency selectedFrequency = ReminderFrequency.once;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add New Reminder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title field
                const Text('Title', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  decoration: InputDecoration(
                    hintText: 'e.g., Car Insurance',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 12),

                // Description field
                const Text('Description', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Optional description',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(height: 12),

                // Expiry Date
                const Text('Expiry Date', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedExpiryDate,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
                    );
                    if (picked != null) {
                      setState(() => selectedExpiryDate = picked);
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedExpiryDate.day}/${selectedExpiryDate.month}/${selectedExpiryDate.year}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Type dropdown
                const Text('Type', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<ReminderType>(
                  value: selectedType,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  items: ReminderType.values.map((type) {
                    return DropdownMenuItem(
                      value: type,
                      child: Text(type.name),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedType = value!),
                ),
                const SizedBox(height: 12),

                // Frequency dropdown
                const Text('Frequency', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                const SizedBox(height: 6),
                DropdownButtonFormField<ReminderFrequency>(
                  value: selectedFrequency,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  items: ReminderFrequency.values.map((freq) {
                    return DropdownMenuItem(
                      value: freq,
                      child: Text(freq.name),
                    );
                  }).toList(),
                  onChanged: (value) => setState(() => selectedFrequency = value!),
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
                onPressed: isLoading
                    ? null
                    : () async {
                        if (titleController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please enter a title')),
                          );
                          return;
                        }

                      setState(() => isLoading = true);

                      try {
                        final userId = _supabaseService.getCurrentUserId();
                        if (userId == null) return;

                        await _reminderService.createReminder(
                          userId: userId,
                          vehicleId: _selectedVehicleId,
                          reminderType: selectedType,
                          title: titleController.text.trim(),
                          expiryDate: selectedExpiryDate,
                          description: descriptionController.text.trim().isEmpty
                              ? null
                              : descriptionController.text.trim(),
                          frequency: selectedFrequency,
                        );

                        Navigator.pop(context);
                        await _loadReminders();

                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Reminder added successfully')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error adding reminder: $e')),
                          );
                        }
                      } finally {
                        setState(() => isLoading = false);
                      }
                    },
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Add'),
            ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayTasks = getRemindersForDate(DateTime.now());
    final hasTodayTasks = todayTasks.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFA7F3D0), // Light green background
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: const Color(0xFF038124), // Consistent green theme
        elevation: 0,
        leading: CircleAvatar(
          backgroundColor: Colors.white,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF038124)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        title: const Text(
          'Service Reminders',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        actions: [
          // Today's tasks indicator
          if (hasTodayTasks)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${todayTasks.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.add_task, color: Color(0xFF038124)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddTaskScreen()),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            backgroundColor: Colors.white,
            child: IconButton(
              icon: const Icon(Icons.build, color: Color(0xFF038124)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ServiceDataPage()),
                );
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Today's Tasks Highlight Section
            if (hasTodayTasks)
              Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.red.shade200, width: 2),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.warning,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Today\'s Tasks',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          Text(
                            '${todayTasks.length} task${todayTasks.length > 1 ? 's' : ''} due today',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.red.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          selectedDate = DateTime.now();
                        });
                      },
                      icon: const Icon(Icons.arrow_forward, color: Colors.red),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : errorMessage != null
                      ? Center(
                          child: Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.red,
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Vehicle Info Section
                              if (_selectedVehicleId != null)
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [Color(0xFF038124), Color(0xFF065F46)],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.green.shade900.withOpacity(0.2),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.directions_car,
                                            color: Colors.white,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          FutureBuilder<Map<String, dynamic>?>(
                                            future: _getSelectedVehicleInfo(),
                                            builder: (context, snapshot) {
                                              if (snapshot.hasData && snapshot.data != null) {
                                                return Text(
                                                  snapshot.data!['vehicle_number'] ?? 'Unknown Vehicle',
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                );
                                              }
                                              return const Text(
                                                'Loading vehicle...',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.white,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      // Service Status Cards
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _buildServiceStatusCard(
                                              'Next Service',
                                              '${_nextServiceDate != null ? _nextServiceDate!.difference(DateTime.now()).inDays : '0'} days',
                                              Icons.calendar_today,
                                              Colors.blue,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: _buildServiceStatusCard(
                                              'Mileage Left',
                                              '${(_nextServiceKm - _currentMileage).clamp(0, double.infinity).toStringAsFixed(0)} km',
                                              Icons.speed,
                                              Colors.orange,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 24),

                              // View Toggle Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildViewToggleButton(
                                      'Calendar View',
                                      Icons.calendar_view_month,
                                      _showCalendarView,
                                      () => setState(() => _showCalendarView = true),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildViewToggleButton(
                                      'List View',
                                      Icons.list,
                                      !_showCalendarView,
                                      () => setState(() => _showCalendarView = false),
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 24),

                              // Calendar/List View Section
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.shade200,
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _showCalendarView ? _buildCalendarView() : _buildListView(),
                              ),

                              const SizedBox(height: 24),

                              // Completed Services Section
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.shade200,
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Completed Services',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF038124),
                                          ),
                                        ),
                                        Text(
                                          '${reminders.where((r) => r.status == ReminderStatus.completed).length} completed',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildCompletedServicesList(),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Service Entry Status - Clickable
                              GestureDetector(
                                onTap: _showTodayTasksDialog,
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _isServiceEntryLocked ? Colors.orange.shade50 : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: _isServiceEntryLocked ? Colors.orange.shade200 : Colors.green.shade200,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Icon(
                                            _isServiceEntryLocked ? Icons.lock_clock : Icons.check_circle,
                                            color: _isServiceEntryLocked ? Colors.orange : Colors.green,
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              _isServiceEntryLocked ? 'Service Cooldown Active' : 'Service Status',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: _isServiceEntryLocked ? Colors.orange.shade800 : Colors.green.shade800,
                                              ),
                                            ),
                                          ),
                                          Icon(
                                            Icons.touch_app,
                                            color: _isServiceEntryLocked ? Colors.orange.shade700 : Colors.green.shade700,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _serviceLockedMessage ?? 'Loading...',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: _isServiceEntryLocked ? Colors.orange.shade700 : Colors.green.shade700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Tap to view today\'s tasks',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade600,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    if (_debugError != null) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade100,
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _debugError!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.red.shade800,
                                            fontFamily: 'Courier',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 24),

                              // Update Service Data Button
                              Center(
                                child: ElevatedButton(
                                  onPressed: _isServiceEntryLocked ? null : () async {
                                    final result = await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => const ServiceDataPage(),
                                      ),
                                    );
                                    if (result == true) {
                                      _loadReminders();
                                      _loadNextServiceReminder();
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isServiceEntryLocked ? Colors.grey : const Color(0xFF038124),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.all(14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    elevation: 4,
                                  ),
                                  child: const Icon(Icons.build, size: 20),
                                ),
                              ),

                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedVehicleId != null ? FloatingActionButton(
        onPressed: () => _showAddReminderDialog(context),
        backgroundColor: const Color(0xFF038124),
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  Widget _buildServiceStatusCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              color: Colors.white.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggleButton(String label, IconData icon, bool isSelected, [VoidCallback? onTap]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF038124) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF038124) : Colors.grey.shade300,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.green.shade900.withOpacity(0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ] : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF038124),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF038124),
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCalendarHeader(),
        const SizedBox(height: 16),
        _buildCalendarGrid(),
      ],
    );
  }

  Widget _buildListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'All Tasks',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF038124),
          ),
        ),
        const SizedBox(height: 16),
        _buildTasksList(),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              '${_getMonthName(selectedDate)} ${selectedDate.year}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF038124),
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Color(0xFF038124)),
          ],
        ),
        Row(
          children: [
            IconButton(
              onPressed: () {
                setState(() {
                  final prevMonth = DateTime(selectedDate.year, selectedDate.month - 1, 1);
                  selectedDate = DateTime(prevMonth.year, prevMonth.month, min(selectedDate.day, DateTime(prevMonth.year, prevMonth.month + 1, 0).day));
                });
              },
              icon: const Icon(Icons.chevron_left, color: Color(0xFF038124)),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
            IconButton(
              onPressed: () {
                setState(() {
                  final nextMonth = DateTime(selectedDate.year, selectedDate.month + 1, 1);
                  selectedDate = DateTime(nextMonth.year, nextMonth.month, min(selectedDate.day, DateTime(nextMonth.year, nextMonth.month + 1, 0).day));
                });
              },
              icon: const Icon(Icons.chevron_right, color: Color(0xFF038124)),
              constraints: const BoxConstraints(),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final firstDay = DateTime(selectedDate.year, selectedDate.month, 1);
    final lastDay = DateTime(selectedDate.year, selectedDate.month + 1, 0);
    final daysInMonth = lastDay.day;
    final startingWeekday = firstDay.weekday % 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: days.map((day) => Expanded(
            child: Center(
              child: Text(
                day,
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )).toList(),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (index) {
                int dayNum = (i * 7 + index - startingWeekday + 1);
                if (dayNum < 1 || dayNum > daysInMonth) {
                  return const Expanded(child: SizedBox());
                }

                final dateToCheck = DateTime(selectedDate.year, selectedDate.month, dayNum);
                bool isSelected = dayNum == selectedDate.day;
                bool isToday = dateToCheck.year == DateTime.now().year &&
                              dateToCheck.month == DateTime.now().month &&
                              dateToCheck.day == DateTime.now().day;
                bool hasReminder = getRemindersForDate(dateToCheck).isNotEmpty;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        selectedDate = dateToCheck;
                      });
                    },
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF038124)
                              : isToday
                                  ? Colors.red.shade100
                                  : hasReminder
                                      ? Colors.orange.withOpacity(0.18)
                                      : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: const Color(0xFF065F46), width: 2)
                              : isToday
                                  ? Border.all(color: Colors.red, width: 2)
                                  : hasReminder
                                      ? Border.all(color: Colors.orange, width: 1.5)
                                      : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNum',
                              style: TextStyle(
                                color: isSelected || isToday
                                    ? Colors.white
                                    : hasReminder
                                        ? Colors.orange.shade800
                                        : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
                                fontSize: 14,
                                fontWeight: hasReminder || isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (hasReminder)
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  color: isSelected ? Colors.white : Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }

  Widget _buildTasksList() {
    if (reminders.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No tasks scheduled',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    // Filter for active, non-expired reminders and sort by date
    final upcoming = reminders
        .where((reminder) => reminder.status == ReminderStatus.active && !reminder.isExpired)
        .toList();

    upcoming.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    if (upcoming.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No upcoming tasks',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    return Column(
      children: upcoming.map((reminder) {
        final daysRemaining = reminder.daysUntilExpiry;
        final isToday = reminder.expiryDate.year == DateTime.now().year &&
                       reminder.expiryDate.month == DateTime.now().month &&
                       reminder.expiryDate.day == DateTime.now().day;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isToday ? Colors.red.shade50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isToday ? Colors.red.shade200 : Colors.grey.shade200,
              width: isToday ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isToday ? Colors.red : const Color(0xFF038124),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _getReminderIcon(reminder.reminderType),
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          reminder.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isToday ? Colors.red.shade800 : Colors.black87,
                          ),
                        ),
                        Text(
                          '${reminder.expiryDate.day} ${_getMonthName(reminder.expiryDate)} ${reminder.expiryDate.year}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: daysRemaining <= 0
                              ? Colors.red.shade100
                              : daysRemaining <= 7
                                  ? Colors.orange.shade100
                                  : Colors.green.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          daysRemaining <= 0 ? 'Overdue' : '$daysRemaining days',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: daysRemaining <= 0
                                ? Colors.red.shade800
                                : daysRemaining <= 7
                                    ? Colors.orange.shade800
                                    : Colors.green.shade800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _markReminderComplete(reminder.id),
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.green.shade400,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.check, color: Colors.white, size: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Task'),
                                  content: const Text('Are you sure you want to delete this task?'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancel'),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        _deleteReminder(reminder.id);
                                      },
                                      child: const Text('Delete', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.red.shade400,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.delete, color: Colors.white, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              if (reminder.description != null && reminder.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  reminder.description!,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompletedServicesList() {
    final completed = reminders.where((r) => r.status == ReminderStatus.completed).toList();

    if (completed.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24.0),
          child: Text(
            'No completed services yet',
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
            ),
          ),
        ),
      );
    }

    completed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Most recent first

    return Column(
      children: completed.map((reminder) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.green.shade200),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getReminderIcon(reminder.reminderType),
                  color: Colors.white,
                  size: 14,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.green,
                      ),
                    ),
                    Text(
                      'Completed on ${reminder.updatedAt.day} ${_getMonthName(reminder.updatedAt)} ${reminder.updatedAt.year}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 20,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  IconData _getReminderIcon(ReminderType type) {
    switch (type) {
      case ReminderType.license:
        return Icons.badge;
      case ReminderType.insurance:
        return Icons.security;
      case ReminderType.service:
        return Icons.build;
      case ReminderType.inspection:
        return Icons.search;
      case ReminderType.pollutionCheck:
        return Icons.eco;
      default:
        return Icons.event;
    }
  }

  String _getDayName(DateTime date) {
    final days = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    return days[date.weekday % 7];
  }

  String _getMonthName(DateTime date) {
    final months = ['January', 'February', 'March', 'April', 'May', 'June',
                    'July', 'August', 'September', 'October', 'November', 'December'];
    return months[date.month - 1];
  }
}