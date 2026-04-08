import 'package:flutter/material.dart';
import '../services/fuel_price_service.dart';

class FuelPricePage extends StatefulWidget {
  const FuelPricePage({Key? key}) : super(key: key);

  @override
  State<FuelPricePage> createState() => _FuelPricePageState();
}

class _FuelPricePageState extends State<FuelPricePage> {
  late TextEditingController _petrol92Controller;
  late TextEditingController _petrol95Controller;
  late TextEditingController _autoDieselController;
  late TextEditingController _superDieselController;

  bool _isSaving = false;

  final FuelPriceService _fuelPriceService = FuelPriceService();

  final Map<String, double?> _currentPrices = {
    'petrol_92': null,
    'petrol_95': null,
    'diesel_auto': null,
    'diesel_super': null,
  };

  final Map<String, DateTime?> _lastUpdated = {
    'petrol_92': null,
    'petrol_95': null,
    'diesel_auto': null,
    'diesel_super': null,
  };

  final List<Tab> _tabs = const [
    Tab(text: 'Petrol'),
    Tab(text: 'Diesel'),
  ];

  @override
  void initState() {
    super.initState();
    _petrol92Controller = TextEditingController();
    _petrol95Controller = TextEditingController();
    _autoDieselController = TextEditingController();
    _superDieselController = TextEditingController();
    _loadFuelPrices();
  }

  @override
  void dispose() {
    _petrol92Controller.dispose();
    _petrol95Controller.dispose();
    _autoDieselController.dispose();
    _superDieselController.dispose();
    super.dispose();
  }

  Future<void> _loadFuelPrices() async {
    try {
      final records = await _fuelPriceService.getFuelPrices();

      if (!mounted) return;

      final dataMap = <String, double?>{
        'petrol_92': null,
        'petrol_95': null,
        'diesel_auto': null,
        'diesel_super': null,
      };

      final timeMap = <String, DateTime?>{
        'petrol_92': null,
        'petrol_95': null,
        'diesel_auto': null,
        'diesel_super': null,
      };

      for (final record in records) {
        final fuelType = (record['fuel_type'] as String?)?.toLowerCase();
        final variant = (record['variant'] as String?)?.toLowerCase();
        final price = (record['price'] as num?)?.toDouble();
        final updatedAt = record['updated_at'] != null
            ? DateTime.tryParse(record['updated_at'].toString())
            : null;

        if (fuelType != null && variant != null) {
          final key = '${fuelType}_$variant';
          if (dataMap.containsKey(key)) {
            dataMap[key] = price;
            timeMap[key] = updatedAt;
          }
        }
      }

      setState(() {
        _currentPrices.addAll(dataMap);
        _lastUpdated.addAll(timeMap);

        _petrol92Controller.text = _currentPrices['petrol_92']?.toStringAsFixed(2) ?? '';
        _petrol95Controller.text = _currentPrices['petrol_95']?.toStringAsFixed(2) ?? '';
        _autoDieselController.text = _currentPrices['diesel_auto']?.toStringAsFixed(2) ?? '';
        _superDieselController.text = _currentPrices['diesel_super']?.toStringAsFixed(2) ?? '';
      });
    } catch (e) {
      print('Error loading fuel prices: $e');
    }
  }

  Future<void> _saveFuelPrice(
    String fuelType,
    String variant,
    TextEditingController controller,
  ) async {
    setState(() => _isSaving = true);
    try {
      final priceText = controller.text;
      if (priceText.isEmpty) {
        throw Exception('Please enter a price');
      }

      final price = double.tryParse(priceText);
      if (price == null || price <= 0) {
        throw Exception('Please enter a valid positive price');
      }

      final success = await _fuelPriceService.upsertFuelPrice(
        fuelType: fuelType,
        variant: variant,
        price: price,
        source: 'manual',
      );

      if (!success) throw Exception('Failed to update fuel price');

      await _loadFuelPrices();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✓ Fuel price updated successfully'),
            backgroundColor: const Color(0xFF038124),
            duration: Duration(seconds: 2),
          ),
        );

        // close page and signal data changed
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Widget _buildFuelVariantRow({
    required String label,
    required String fuelType,
    required String variant,
    required TextEditingController controller,
  }) {
    final key = '${fuelType}_$variant';
    final localPrice = _currentPrices[key];
    final updatedAt = _lastUpdated[key];

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            const SizedBox(height: 6),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Price (LKR/L)',
                hintText: 'e.g., 420.00',
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                suffixText: localPrice != null ? 'current: ${localPrice.toStringAsFixed(2)}' : null,
                suffixStyle: const TextStyle(fontSize: 12),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 4),
            if (updatedAt != null)
              Text('Last updated: ${updatedAt.toLocal()}', style: const TextStyle(fontSize: 10, color: Colors.black54)),
            const SizedBox(height: 6),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: _isSaving
                    ? null
                    : () => _saveFuelPrice(fuelType, variant, controller),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF038124),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Update'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: const Color(0xFF038124),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context, true),
          ),
          title: const Text(
            'Fuel Prices',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          bottom: TabBar(
            tabs: _tabs,
            indicatorColor: Colors.white,
          ),
        ),
        body: TabBarView(
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Petrol Prices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildFuelVariantRow(
                    label: 'Petrol 92',
                    fuelType: 'petrol',
                    variant: '92',
                    controller: _petrol92Controller,
                  ),
                  _buildFuelVariantRow(
                    label: 'Petrol 95',
                    fuelType: 'petrol',
                    variant: '95',
                    controller: _petrol95Controller,
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Diesel Prices', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildFuelVariantRow(
                    label: 'Auto Diesel',
                    fuelType: 'diesel',
                    variant: 'auto',
                    controller: _autoDieselController,
                  ),
                  _buildFuelVariantRow(
                    label: 'Super Diesel',
                    fuelType: 'diesel',
                    variant: 'super',
                    controller: _superDieselController,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Note: Diesel price changes affect all vehicles using Diesel Auto/Super variants.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
