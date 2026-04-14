import 'package:flutter/material.dart';

class ServiceReminderScreen extends StatelessWidget {
  final double currentMileage;
  final double nextServiceKm;
  final DateTime? nextServiceDate;

  const ServiceReminderScreen({
    Key? key,
    required this.currentMileage,
    required this.nextServiceKm,
    this.nextServiceDate,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final remainingKm = (nextServiceKm - currentMileage).clamp(0, double.infinity);
    final daysRemaining = nextServiceDate != null
        ? nextServiceDate!.difference(DateTime.now()).inDays
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Service Reminder'),
        backgroundColor: Colors.green.shade600,
      ),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Current mileage: ${currentMileage.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Next service due: ${nextServiceKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              Text('Remaining km: ${remainingKm.toStringAsFixed(1)} km', style: const TextStyle(fontSize: 16, color: Colors.orange)),
              const SizedBox(height: 8),
              if (daysRemaining != null) Text('Days remaining: ${daysRemaining < 0 ? 0 : daysRemaining} days', style: const TextStyle(fontSize: 16, color: Colors.blueGrey)),
              const SizedBox(height: 22),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('What this means', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text('• Service is due at $nextServiceKm km', style: const TextStyle(fontSize: 14)),
                      Text('• You are ${remainingKm.toStringAsFixed(1)} km away', style: const TextStyle(fontSize: 14)),
                      if (daysRemaining != null) Text('• $daysRemaining days left until scheduled service date', style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.popUntil(context, (route) => route.isFirst);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade700, padding: const EdgeInsets.symmetric(vertical: 14)),
                child: const Text('Return Home', style: TextStyle(fontSize: 16, color: Colors.white)),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
