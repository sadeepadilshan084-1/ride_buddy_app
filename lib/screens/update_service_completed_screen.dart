import 'package:flutter/material.dart';
import 'update_service_data_screen.dart';

class UpdateServiceCompletedScreen extends StatelessWidget {
  const UpdateServiceCompletedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFA7F3D0),
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context),
                  Expanded(
                    child: Stack(
                      children: [
                        _buildBackgroundContent(),
                        Positioned(
                          top: 0,
                          left: 16,
                          right: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00FF41),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.check_circle_outline, color: Colors.black, size: 28),
                                SizedBox(width: 12),
                                Text(
                                  'Remainder make as Completed !',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBottomNavBar(),
                ],
              ),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.4)),
          Center(
            child: SingleChildScrollView(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Update Service Data',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader('Vehicle Information'),
                    _buildVehicleInfoCard(),
                    const SizedBox(height: 16),
                    _buildSectionHeader('Service Details'),
                    const SizedBox(height: 12),
                    _buildServiceDetailRow('Current Millage (km)', '43015.0'),
                    const SizedBox(height: 8),
                    _buildServiceDetailRowWithIcon('Service Date', '25 Oct 2025', Icons.calendar_month),
                    const SizedBox(height: 8),
                    _buildServiceDetailRow('Next Service Due (km)', '53015'),
                    const SizedBox(height: 12),
                    _buildNotesSection(),
                    const SizedBox(height: 24),
                    _buildDialogButtons(context),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildCircleButton(Icons.arrow_back, onTap: () => Navigator.pop(context)),
          const Text('Remainder', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          _buildCircleButton(Icons.directions_car, onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const UpdateServiceDataScreen()),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCircleButton(IconData icon, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.black, size: 20),
      ),
    );
  }

  Widget _buildBackgroundContent() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
      children: [
        Container(
          height: 150,
          decoration: BoxDecoration(color: const Color(0xFFE2E8F0).withOpacity(0.5), borderRadius: BorderRadius.circular(24)),
          padding: const EdgeInsets.all(20),
          child: const Text('Mon, Aug 17', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 16),
        _buildMockCard('31 December 2026', 'License update'),
        _buildMockCard('31 December 2026', 'Eco test'),
      ],
    );
  }

  Widget _buildMockCard(String date, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.5), borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.list_alt, color: Colors.white)),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(title, style: const TextStyle(color: Colors.black54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(32)),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(Icons.home_outlined),
          Icon(Icons.location_on_outlined),
          Icon(Icons.videocam_outlined),
          Icon(Icons.bar_chart_outlined),
          CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.person_outline, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title, style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  Widget _buildVehicleInfoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(8)),
      child: const Column(
        children: [
          _LabelValueRow(label: 'Vehicle :', value: 'Toyota Axio'),
          SizedBox(height: 6),
          _LabelValueRow(label: 'Vehicle Number :', value: 'CBC 6734'),
        ],
      ),
    );
  }

  Widget _buildServiceDetailRow(String label, String value) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            height: 38,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            height: 38,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Text(value, style: const TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceDetailRowWithIcon(String label, String value, IconData icon) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
            child: Row(
              children: [
                Icon(icon, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6),
                Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 3,
          child: Container(
            height: 38,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: Text(value, style: const TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Notes (optional)', style: TextStyle(color: Colors.grey, fontSize: 12)),
        const SizedBox(height: 6),
        Container(
          height: 40,
          width: double.infinity,
          decoration: BoxDecoration(color: const Color(0xFFE5E7EB), borderRadius: BorderRadius.circular(8)),
        ),
      ],
    );
  }

  Widget _buildDialogButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE5E7EB),
              foregroundColor: Colors.black87,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF15803D),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              minimumSize: const Size(0, 44),
            ),
            child: const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  final String label;
  final String value;

  const _LabelValueRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87)),
      ],
    );
  }
}
