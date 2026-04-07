import 'package:flutter/material.dart';

class PasswordChangedPage extends StatelessWidget {
  const PasswordChangedPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.green, size: 60),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Password Changed!',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushReplacementNamed('/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 48,
                    ),
                  ),
                  child: const Text('Log in', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

