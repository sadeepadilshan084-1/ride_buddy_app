import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/fuel_price_service_new.dart';

class FuelPriceSettingsScreen extends StatefulWidget {
  final List<FuelPrice> fuelPrices;
  final VoidCallback onPriceUpdated;

  const FuelPriceSettingsScreen({
    Key? key,
    required this.fuelPrices,
    required this.onPriceUpdated,
  }) : super(key: key);

  @override
  State<FuelPriceSettingsScreen> createState() => _FuelPriceSettingsScreenState();
}

class _FuelPriceSettingsScreenState extends State<FuelPriceSettingsScreen> {
  final _fuelPriceService = FuelPriceService();
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fuel Price Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: widget.onPriceUpdated,
            tooltip: 'Refresh prices',
          ),
        ],
      ),
      body: widget.fuelPrices.isEmpty
          ? const Center(
              child: Text('No fuel prices available'),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: widget.fuelPrices.length,
              itemBuilder: (context, index) {
                final fuelPrice = widget.fuelPrices[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      Icons.local_gas_station,
                      color: Theme.of(context).primaryColor,
                    ),
                    title: Text(
                      fuelPrice.fuelType,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rs. ${fuelPrice.price.toStringAsFixed(2)} per liter',
                          style: const TextStyle(fontSize: 16),
                        ),
                        Text(
                          'Last updated: ${_formatDateTime(fuelPrice.updatedAt)}',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showUpdatePriceDialog(fuelPrice),
                      tooltip: 'Update price',
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} minutes ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    }
  }

  void _showUpdatePriceDialog(FuelPrice fuelPrice) {
    final controller = TextEditingController(text: fuelPrice.price.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update ${fuelPrice.fuelType} Price'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Price per liter (Rs.)',
                border: OutlineInputBorder(),
                prefixText: 'Rs. ',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
              ],
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a price';
                }
                final price = double.tryParse(value);
                if (price == null || price <= 0) {
                  return 'Please enter a valid price';
                }
                return null;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final price = double.tryParse(controller.text);
              if (price == null || price <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a valid price')),
                );
                return;
              }

              Navigator.pop(context);
              await _updateFuelPrice(fuelPrice.fuelType, price);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _updateFuelPrice(String fuelType, double newPrice) async {
    setState(() => _isLoading = true);

    try {
      await _fuelPriceService.updateFuelPrice(fuelType, newPrice);
      widget.onPriceUpdated();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$fuelType price updated to Rs. ${newPrice.toStringAsFixed(2)}'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating price: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }
}