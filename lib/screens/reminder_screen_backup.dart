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

      if (_selectedVehicleId == null) {
        setState(() {
          reminders = [];
          errorMessage = 'No vehicle selected. Please select a vehicle to view reminders.';
          isLoading = false;
        });
        return;
      }

      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() {
          errorMessage = 'User not authenticated';
          isLoading = false;
        });
        return;
      }

      // Get reminders for the selected vehicle only
      final loadedReminders = await _reminderService.getVehicleReminders(_selectedVehicleId!);
      setState(() {
        reminders = loadedReminders;
        errorMessage = null;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Error loading reminders: $e';
        isLoading = false;
        reminders = [];
      });
    }
  }

  Future<void> _loadNextServiceReminder() async {
    try {
      setState(() => isLoadingServiceData = true);

      if (_selectedVehicleId == null) {
        setState(() => isLoadingServiceData = false);
        return;
      }

      final userId = _supabaseService.getCurrentUserId();
      if (userId == null) {
        setState(() => isLoadingServiceData = false);
        return;
      }

      // Get service reminders for selected vehicle
      final serviceReminders = await _reminderService.getVehicleReminders(_selectedVehicleId!);
      
      if (serviceReminders.isNotEmpty) {
        // Get the next upcoming service reminder
        final upcomingReminders = serviceReminders.where((r) => 
          r.status == ReminderStatus.active && r.expiryDate.isAfter(DateTime.now())
        ).toList();
        
        if (upcomingReminders.isNotEmpty) {
          upcomingReminders.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
          final nextReminder = upcomingReminders.first;
          
          // Calculate days remaining
          final daysRemaining = nextReminder.expiryDate.difference(DateTime.now()).inDays;
          
          // Extract km from description
          String kmText = 'N/A';
          if (nextReminder.description != null && nextReminder.description!.isNotEmpty) {
            final kmRegex = RegExp(r'(\d+)\s*km');
            final match = kmRegex.firstMatch(nextReminder.description!);
            if (match != null) {
              kmText = match.group(1)!;
            }
          }
          
          setState(() {
            nextServiceReminder = {
              'title': nextReminder.title,
              'date': nextReminder.expiryDate,
              'km': kmText,
              'daysRemaining': daysRemaining,
            };
          });
        }
      }
      
      setState(() => isLoadingServiceData = false);
      
      // Check service entry lock status
      await _checkServiceEntryLockStatus();
    } catch (e) {
      print('Error loading next service reminder: $e');
      setState(() => isLoadingServiceData = false);
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
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          '${selectedExpiryDate.day}/${selectedExpiryDate.month}/${selectedExpiryDate.year}',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Reminder Type
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
                      child: Text(type.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedType = value);
                    }
                  },
                ),
                const SizedBox(height: 12),

                // Frequency
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
                      child: Text(freq.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedFrequency = value);
                    }
                  },
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
                onPressed: isLoading ? null : () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a title')),
                    );
                    return;
                  }

                setState(() => isLoading = true);

                try {
                  final userId = _supabaseService.getCurrentUserId();
                  if (userId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('User not authenticated')),
                    );
                    return;
                  }

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
    return Scaffold(
      backgroundColor: const Color(0xFFA7F3D0),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.black),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        const Text(
                          'Remainder',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                        if (_selectedVehicleId != null)
                          FutureBuilder<Map<String, dynamic>?>(
                            future: _getSelectedVehicleInfo(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Text(
                                  'Vehicle: ${snapshot.data!['vehicle_number'] ?? 'Unknown'}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          )
                        else
                          const Text(
                            'No vehicle selected',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        child: IconButton(
                          icon: const Icon(Icons.add_task, color: Colors.black),
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
                        backgroundColor: const Color(0xFF22C55E),
                        child: IconButton(
                          icon: const Icon(Icons.build, color: Colors.white),
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
                      : ListView(
                          padding: const EdgeInsets.all(16.0),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3E8FF),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_getDayName(selectedDate)}, ${_getMonthName(selectedDate)} ${selectedDate.day}',
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  // Task Count for Today Only
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade600,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.shade400.withOpacity(0.3),
                                          blurRadius: 8,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        Text(
                                          '${getRemindersForDate(DateTime.now()).length}',
                                          style: const TextStyle(
                                            fontSize: 48,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        const Text(
                                          'Tasks Today',
                                          style: TextStyle(
                                            fontSize: 16,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (_nextServiceKm > 0) ...[
                                    Text(
                                      'Service Schedule',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade600,
                                              borderRadius: BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.shade400.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '${_nextServiceDate != null ? _nextServiceDate!.difference(DateTime.now()).inDays : '0'}',
                                                  style: const TextStyle(
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                const Text(
                                                  'Days',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade600,
                                              borderRadius: BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.orange.shade400.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.center,
                                              children: [
                                                Text(
                                                  '${(_nextServiceKm - _currentMileage).clamp(0, double.infinity).toStringAsFixed(0)}',
                                                  style: const TextStyle(
                                                    fontSize: 42,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                                const SizedBox(height: 6),
                                                const Text(
                                                  'KM',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  if (_nextServiceKm <= 0)
                                    const SizedBox(height: 12),
                                  if (nextServiceReminder != null) ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.9),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Colors.green.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.build, color: Colors.green, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  nextServiceReminder!['title'],
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                                Text(
                                                  'Due at ${nextServiceReminder!['km']} km',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 20),
                                  ],
                                  // Service Entry Lock Status - Clickable
                                  GestureDetector(
                                    onTap: _showTodayTasksDialog,
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _isServiceEntryLocked ? Colors.orange.shade50 : Colors.green.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: _isServiceEntryLocked ? Colors.orange.shade300 : Colors.green.shade300,
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Row(
                                            children: [
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
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Service Data Button
                                  Center(
                                    child: ElevatedButton.icon(
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
                                      icon: const Icon(Icons.build, size: 18),
                                      label: const Text('Update Service Data'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _isServiceEntryLocked ? Colors.grey : Colors.green.shade700,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 28),
                                  // Calendar Header
                                  _buildCalendarHeader(),
                                  const SizedBox(height: 16),
                                  // Calendar Grid
                                  _buildCalendarGrid(),
                                  const SizedBox(height: 28),
                                  // Task List
                                  _buildTasksList(),
                                ],
                              ),
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
      floatingActionButton: _selectedVehicleId != null ? FloatingActionButton(
        onPressed: () => _showAddReminderDialog(context),
        backgroundColor: Colors.green[800],
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
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

  List<Widget> _buildUpcomingRemindersList() {
    if (reminders.isEmpty) {
      return [const SizedBox()];
    }

    // Filter for upcoming reminders (active and not expired)
    final upcoming = reminders.where((reminder) =>
      reminder.status == ReminderStatus.active &&
      !reminder.isExpired
    ).toList();

    if (upcoming.isEmpty) {
      return [const SizedBox()];
    }

    return upcoming.map((reminder) {
      final daysRemaining = reminder.daysUntilExpiry;
      final statusColor = daysRemaining <= 0
          ? Colors.red
          : daysRemaining <= 7
              ? Colors.orange
              : Colors.green;

      // Calculate km remaining from description
      double kmRemaining = 0;
      if (reminder.description != null && reminder.description!.isNotEmpty) {
        final kmRegex = RegExp(r'(\d+)\s*km');
        final match = kmRegex.firstMatch(reminder.description!);
        if (match != null) {
          final nextServiceMileage = double.tryParse(match.group(1)!) ?? 0;
          kmRemaining = (nextServiceMileage - _currentMileage).clamp(0, double.infinity);
        }
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.build, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reminder.title,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        '${reminder.expiryDate.day} ${_getMonthName(reminder.expiryDate)} ${reminder.expiryDate.year}',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${kmRemaining.toStringAsFixed(0)} km remaining',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: Colors.green,
                        ),
                      ),
                      Text(
                        'In $daysRemaining days',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () async {
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
                    icon: const Icon(Icons.edit, size: 16),
                    label: const Text('Edit'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildCalendarHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              '${_getMonthName(selectedDate)} ${selectedDate.year}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Icon(Icons.arrow_drop_down),
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
              icon: const Icon(Icons.chevron_left),
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
              icon: const Icon(Icons.chevron_right),
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
            child: Center(child: Text(day, style: const TextStyle(color: Colors.grey, fontSize: 11))),
          )).toList(),
        ),
        const SizedBox(height: 8),
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
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.green.shade700
                              : hasReminder
                                  ? Colors.orange.withOpacity(0.18)
                                  : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isSelected
                              ? Border.all(color: Colors.green.shade900, width: 1.5)
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
                                color: isSelected
                                    ? Colors.white
                                    : hasReminder
                                        ? Colors.orange.shade800
                                        : Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black,
                                fontSize: 12,
                                fontWeight: hasReminder ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (hasReminder)
                              Container(
                                width: 6,
                                height: 6,
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

  Widget _buildBottomNavBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/home'),
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/petrol-station'),
            icon: const Icon(Icons.location_on_outlined),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/media'),
            icon: const Icon(Icons.videocam_outlined),
          ),
          IconButton(
            onPressed: () => Navigator.pushNamed(context, '/stats'),
            icon: const Icon(Icons.bar_chart_outlined),
          ),
          Container(
            decoration: BoxDecoration(
              color: Colors.green[800],
              shape: BoxShape.circle,
            ),
            child: IconButton(
              onPressed: () => Navigator.pushNamed(context, '/profile'),
              icon: const Icon(Icons.person_outline, color: Colors.white),
            ),
          ),
        ],
      ),
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        children: upcoming.map((reminder) {
          final daysRemaining = reminder.daysUntilExpiry;

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${reminder.expiryDate.day} ${_getMonthName(reminder.expiryDate)} ${reminder.expiryDate.year}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reminder.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: [
                    GestureDetector(
                      onTap: () => _markReminderComplete(reminder.id),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(height: 4),
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
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.red.shade400,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
