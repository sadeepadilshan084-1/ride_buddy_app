// Test file to check if task saving works
import 'package:flutter/material.dart';
import 'package:ride_buddy/services/supabase_service.dart';

class TaskTestScreen extends StatelessWidget {
  const TaskTestScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task Test')),
      body: Center(
        child: ElevatedButton(
          onPressed: () async {
            final service = SupabaseService();
            final userId = service.getCurrentUserId();

            print('User ID: $userId');

            if (userId != null) {
              final success = await service.addReminder(
                userId: userId,
                taskName: 'Test Task',
                phoneNumber: '+1234567890',
                description: 'Test description',
                expireDate: DateTime.now().add(const Duration(days: 7)),
                email: 'test@example.com',
              );

              print('Task save result: $success');

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(success ? 'Task saved!' : 'Failed to save task'),
                  backgroundColor: success ? Colors.green : Colors.red,
                ),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('User not logged in'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: const Text('Test Save Task'),
        ),
      ),
    );
  }
}