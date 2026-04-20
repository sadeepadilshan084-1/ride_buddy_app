import 'dart:math';
import 'package:flutter/material.dart';
import 'package:ride_buddy/services/reminder_service.dart';
import 'package:ride_buddy/services/backend_models.dart';
import 'package:ride_buddy/services/fuel_tracker_service.dart';
import 'package:ride_buddy/services/supabase_service.dart';
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

  late double _currentMileage;
  double _serviceSubmissionKmLimit = 5000;
  bool _isServiceEntryLocked = false;
  String? _serviceLockedMessage;
  String? _debugError;
  String? _selectedVehicleId;
  Vehicle? _selectedVehicle;
  bool _showCalendarView = true; // Toggle between calendar and list view

  bool get _isCompactLayout => MediaQuery.of(context).size.width < 420;

  @override
  void initState() {
    super.initState();
    _reminderService = ReminderService();
    _supabaseService = SupabaseService();
    _selectedVehicleProvider = SelectedVehicleProvider();
    selectedDate = DateTime.now();
    reminders = [];

    _currentMileage = widget.currentMileage;

    _initializeSelectedVehicle();
  }

  Future<void> _initializeSelectedVehicle() async {
    await _selectedVehicleProvider.initialize();
    await _resolveSelectedVehicle();
    _loadReminders();
  }

  Future<void> _resolveSelectedVehicle() async {
    final selectedVehicle = _selectedVehicleProvider.getSelectedVehicle();
    if (selectedVehicle?.id != null) {
      _selectedVehicleId = selectedVehicle!.id;
      _selectedVehicle = selectedVehicle;
      _currentMileage = selectedVehicle.previousMileage;
      if (mounted) {
        setState(() {});
      }
      print('✓ ReminderScreen: Using selected vehicle: $_selectedVehicleId');
    } else {
      _selectedVehicleId = null;
      _selectedVehicle = null;
      _currentMileage = 0;
      if (mounted) {
        setState(() {});
      }
      print('⚠️ ReminderScreen: No vehicle selected');
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
        // Get last service submission time from service_histSory
        final lastService = await _supabaseService.supabase
            .from('service_history')
            .select('created_at, service_mileage')
            .eq('vehicle_id', vehicleId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        if (lastService != null) {
          try {
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
      setState(() {
        isLoading = true;
        errorMessage = null;
      });

      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() {
          errorMessage = 'User not authenticated';
          reminders = [];
          isLoading = false;
        });
        return;
      }

      if (_selectedVehicleId == null) {
        setState(() {
          reminders = [];
          errorMessage = 'Select a vehicle to see reminders';
          isLoading = false;
        });
        return;
      }

      final fetchedReminders = await _reminderService.getVehicleReminders(_selectedVehicleId!);

      setState(() {
        reminders = fetchedReminders;
        errorMessage = null;
        isLoading = false;
      });

      await _checkServiceEntryLockStatus();
    } catch (e) {
      setState(() {
        errorMessage = 'Failed to load reminders: $e';
        reminders = [];
        isLoading = false;
      });
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

  void _showAddReminderDialog(BuildContext context) {
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
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 420;
    final sectionSpacing = isCompact ? 10.0 : 14.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F7F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFF038124),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Service Reminders',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: isCompact ? 18 : 20,
          ),
        ),
        centerTitle: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                      : ListView(
                          padding: const EdgeInsets.all(16.0),
                          children: [
                              // Vehicle Info Section
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.grey.shade200,
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                padding: EdgeInsets.all(isCompact ? 16 : 20),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: isCompact ? 42 : 46,
                                          height: isCompact ? 42 : 46,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFE6F4EA),
                                            borderRadius: BorderRadius.circular(14),
                                          ),
                                          child: Icon(
                                            Icons.directions_car,
                                            color: const Color(0xFF047857),
                                            size: isCompact ? 22 : 26,
                                          ),
                                        ),
                                        SizedBox(width: isCompact ? 12 : 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                _selectedVehicle != null
                                                    ? '${_selectedVehicle!.model} • ${_selectedVehicle!.number}'
                                                    : 'No selected vehicle',
                                                style: TextStyle(
                                                  fontSize: isCompact ? 18 : 20,
                                                  fontWeight: FontWeight.bold,
                                                  color: const Color(0xFF0F172A),
                                                ),
                                              ),
                                              SizedBox(height: isCompact ? 6 : 8),
                                              Text(
                                                _selectedVehicle != null
                                                    ? 'Current mileage ${_currentMileage.toStringAsFixed(0)} km'
                                                    : 'Select a vehicle to view reminders',
                                                style: TextStyle(
                                                  fontSize: isCompact ? 13 : 14,
                                                  color: const Color(0xFF475569),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(height: sectionSpacing / 1.5),

                              SizedBox(height: sectionSpacing / 1.5),

                              // View Toggle Buttons
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildViewToggleButton(
                                      'Calendar',
                                      Icons.calendar_view_month,
                                      _showCalendarView,
                                      () => setState(() => _showCalendarView = true),
                                      isCompact,
                                    ),
                                  ),
                                  SizedBox(width: isCompact ? 10 : 12),
                                  Expanded(
                                    child: _buildViewToggleButton(
                                      'List',
                                      Icons.list,
                                      !_showCalendarView,
                                      () => setState(() => _showCalendarView = false),
                                      isCompact,
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: sectionSpacing),

                              // Calendar/List View Section
                              Container(
                                padding: EdgeInsets.all(isCompact ? 14 : 16),
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

                              SizedBox(height: sectionSpacing),

                              // Completed Tasks Section
                              Container(
                                padding: EdgeInsets.all(isCompact ? 14 : 16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: const Color(0xFFD1FAE5)),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.shade100.withValues(alpha: 0.5),
                                      blurRadius: 12,
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
                                        Text(
                                          'Completed Tasks',
                                          style: TextStyle(
                                            fontSize: isCompact ? 16 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: const Color(0xFF047857),
                                          ),
                                        ),
                                        Text(
                                          '${reminders.where((r) => r.status == ReminderStatus.completed).length} completed',
                                          style: TextStyle(
                                            fontSize: isCompact ? 13 : 14,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF134E4A),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildCompletedServicesList(),
                                  ],
                                ),
                              ),

                              SizedBox(height: sectionSpacing),

                              // Service Entry Status - Clickable
                              GestureDetector(
                                onTap: _showTodayTasksDialog,
                                child: Container(
                                  padding: EdgeInsets.all(isCompact ? 14 : 16),
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
                                    ],
                                  ),
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

                              SizedBox(height: isCompact ? 20 : 24),

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
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isServiceEntryLocked ? Colors.grey : const Color(0xFF038124),
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(horizontal: isCompact ? 22 : 24, vertical: isCompact ? 12 : 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    elevation: 4,
                                  ),
                                  child: const Icon(Icons.build, size: 20),
                                ),
                              ),

                              SizedBox(height: isCompact ? 24 : 32),
                            ],
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

  Widget _buildViewToggleButton(String label, IconData icon, bool isSelected, [VoidCallback? onTap, bool isCompact = false]) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 12, horizontal: isCompact ? 14 : 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF038124) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF038124) : Colors.grey.shade300,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: Colors.green.shade900.withValues(alpha: 0.2),
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
              size: isCompact ? 16 : 18,
            ),
            SizedBox(width: isCompact ? 6 : 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF038124),
                fontWeight: FontWeight.w600,
                fontSize: isCompact ? 13 : 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendarView() {
    final isCompact = _isCompactLayout;
    final totalPending = reminders.where((r) => r.status == ReminderStatus.active && !r.isExpired).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCalendarHeader(),
        SizedBox(height: isCompact ? 10 : 12),
        if (totalPending > 0)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: isCompact ? 10 : 12, horizontal: isCompact ? 12 : 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.event_available, color: const Color(0xFF047857), size: isCompact ? 18 : 20),
                SizedBox(width: isCompact ? 8 : 10),
                Expanded(
                  child: Text(
                    '$totalPending upcoming task${totalPending > 1 ? 's' : ''} for this vehicle',
                    style: TextStyle(
                      color: const Color(0xFF14532D),
                      fontSize: isCompact ? 13 : 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        SizedBox(height: isCompact ? 14 : 16),
        _buildCalendarGrid(),
      ],
    );
  }

  Widget _buildListView() {
    final isCompact = _isCompactLayout;
    final totalPending = reminders.where((r) => r.status == ReminderStatus.active && !r.isExpired).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Tasks ($totalPending)',
          style: TextStyle(
            fontSize: isCompact ? 16 : 18,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF038124),
          ),
        ),
        SizedBox(height: isCompact ? 12 : 16),
        _buildTasksList(),
      ],
    );
  }

  Widget _buildCalendarHeader() {
    final isCompact = _isCompactLayout;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Text(
                  '${_getMonthName(selectedDate)} ${selectedDate.year}',
                  style: TextStyle(
                    fontSize: isCompact ? 16 : 18,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF038124),
                  ),
                ),
                Icon(Icons.arrow_drop_down, color: const Color(0xFF038124), size: isCompact ? 20 : 24),
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
                  icon: Icon(Icons.chevron_left, color: const Color(0xFF038124), size: isCompact ? 18 : 20),
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
                  icon: Icon(Icons.chevron_right, color: const Color(0xFF038124), size: isCompact ? 18 : 20),
                  constraints: const BoxConstraints(),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ],
        ),
        SizedBox(height: isCompact ? 8 : 10),
        Row(
          children: [
            Chip(
              label: Text(
                _getDayName(selectedDate),
                style: TextStyle(color: const Color(0xFF065F46), fontSize: isCompact ? 12 : 13),
              ),
              backgroundColor: const Color(0xFFD1FAE5),
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 12, vertical: isCompact ? 4 : 6),
            ),
            SizedBox(width: isCompact ? 6 : 8),
            Chip(
              label: Text(
                '${getRemindersForDate(selectedDate).length} tasks',
                style: TextStyle(color: const Color(0xFF065F46), fontSize: isCompact ? 12 : 13),
              ),
              backgroundColor: const Color(0xFFD1FAE5),
              padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 12, vertical: isCompact ? 4 : 6),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCalendarGrid() {
    final isCompact = _isCompactLayout;
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
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: isCompact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )).toList(),
        ),
        SizedBox(height: isCompact ? 10 : 12),
        for (var i = 0; i < 6; i++)
          Padding(
            padding: EdgeInsets.symmetric(vertical: isCompact ? 3.5 : 4.0),
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
                        padding: EdgeInsets.all(isCompact ? 6 : 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF038124)
                              : isToday
                                  ? Colors.red.shade100
                                  : hasReminder
                                  ? Colors.orange.withValues(alpha: 0.18)
                                      : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: const Color(0xFF065F46), width: isCompact ? 1.5 : 2)
                              : isToday
                                  ? Border.all(color: Colors.red, width: isCompact ? 1.5 : 2)
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
                                fontSize: isCompact ? 12 : 14,
                                fontWeight: hasReminder || isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            if (hasReminder)
                              Container(
                                width: 4,
                                height: 4,
                                margin: EdgeInsets.only(top: isCompact ? 2 : 3),
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
    final isCompact = _isCompactLayout;
    if (reminders.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 18.0 : 24.0),
          child: Text(
            'No tasks scheduled for the selected vehicle',
            style: TextStyle(
              color: Colors.grey,
              fontSize: isCompact ? 13 : 14,
            ),
          ),
        ),
      );
    }

    final upcoming = reminders
        .where((reminder) => reminder.status == ReminderStatus.active && !reminder.isExpired)
        .toList();

    upcoming.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));

    if (upcoming.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 18.0 : 24.0),
          child: Text(
            'No upcoming tasks for this vehicle',
            style: TextStyle(
              color: Colors.grey,
              fontSize: isCompact ? 13 : 14,
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
        final statusColor = daysRemaining <= 0
            ? Colors.red
            : daysRemaining <= 7
                ? Colors.orange
                : Colors.green;

        return Container(
          margin: EdgeInsets.only(bottom: isCompact ? 10 : 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade200,
                blurRadius: isCompact ? 6 : 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isCompact ? 12 : 16, vertical: isCompact ? 10 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: isCompact ? 44 : 48,
                  height: isCompact ? 44 : 48,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getReminderIcon(reminder.reminderType),
                    color: statusColor,
                    size: isCompact ? 20 : 24,
                  ),
                ),
                SizedBox(width: isCompact ? 12 : 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 15 : 16,
                          fontWeight: FontWeight.bold,
                          color: isToday ? Colors.red.shade800 : Colors.black87,
                        ),
                      ),
                      SizedBox(height: isCompact ? 4 : 6),
                      Text(
                        '${reminder.expiryDate.day} ${_getMonthName(reminder.expiryDate)} ${reminder.expiryDate.year}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: isCompact ? 12 : 13,
                          color: Colors.grey,
                        ),
                      ),
                      if (reminder.description != null && reminder.description!.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: isCompact ? 6.0 : 8.0),
                          child: Text(
                            reminder.description!,
                            maxLines: isCompact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: isCompact ? 12 : 13,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                SizedBox(width: isCompact ? 10 : 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 10, vertical: isCompact ? 4 : 6),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        daysRemaining <= 0 ? 'Overdue' : '$daysRemaining days',
                        style: TextStyle(
                          fontSize: isCompact ? 11 : 12,
                          fontWeight: FontWeight.bold,
                          color: statusColor,
                        ),
                      ),
                    ),
                    SizedBox(height: isCompact ? 8 : 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => _markReminderComplete(reminder.id),
                          child: Container(
                            width: isCompact ? 32 : 34,
                            height: isCompact ? 32 : 34,
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.check, color: Colors.green, size: isCompact ? 16 : 18),
                          ),
                        ),
                        SizedBox(width: isCompact ? 6 : 8),
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
                            width: isCompact ? 32 : 34,
                            height: isCompact ? 32 : 34,
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.delete, color: Colors.red, size: isCompact ? 16 : 18),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCompletedServicesList() {
    final isCompact = _isCompactLayout;
    final completed = reminders.where((r) => r.status == ReminderStatus.completed).toList();

    if (completed.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: isCompact ? 18.0 : 24.0),
          child: Text(
            'No completed tasks yet',
            style: TextStyle(
              color: Colors.grey,
              fontSize: isCompact ? 13 : 14,
            ),
          ),
        ),
      );
    }

    completed.sort((a, b) => b.updatedAt.compareTo(a.updatedAt)); // Most recent first

    return Column(
      children: completed.map((reminder) {
        return Container(
          margin: EdgeInsets.only(bottom: isCompact ? 8 : 10),
          padding: EdgeInsets.symmetric(vertical: isCompact ? 12 : 14, horizontal: isCompact ? 14 : 16),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6EF),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD1FAE5)),
          ),
          child: Row(
            children: [
              Container(
                width: isCompact ? 38 : 42,
                height: isCompact ? 38 : 42,
                decoration: const BoxDecoration(
                  color: Color(0xFF047857),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _getReminderIcon(reminder.reminderType),
                  color: Colors.white,
                  size: isCompact ? 16 : 18,
                ),
              ),
              SizedBox(width: isCompact ? 12 : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.title,
                      style: TextStyle(
                        fontSize: isCompact ? 14 : 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    SizedBox(height: isCompact ? 4 : 6),
                    Text(
                      'Completed on ${reminder.updatedAt.day} ${_getMonthName(reminder.updatedAt)} ${reminder.updatedAt.year}',
                      style: TextStyle(
                        fontSize: isCompact ? 11 : 12,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: isCompact ? 34 : 36,
                height: isCompact ? 34 : 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1FAE5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check,
                  color: const Color(0xFF047857),
                  size: isCompact ? 18 : 20,
                ),
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
