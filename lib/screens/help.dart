import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/supabase_service.dart';

class HelpPage extends StatefulWidget {
  const HelpPage({Key? key}) : super(key: key);

  @override
  State<HelpPage> createState() => _HelpPageState();
}

class _HelpPageState extends State<HelpPage> {
  late Future<List<Map<String, dynamic>>> contactsFuture;
  final SupabaseService supabaseService = SupabaseService();

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  void _loadContacts() {
    final userId = supabaseService.getCurrentUserId();
    setState(() {
      contactsFuture = supabaseService.getEmergencyContacts(userId);
    });
  }

  IconData _getIconForType(String? iconType) {
    switch (iconType) {
      case 'hospital':
        return Icons.local_hospital;
      case 'police':
        return Icons.security;
      case 'fire':
        return Icons.local_fire_department;
      case 'ambulance':
        return Icons.emergency;
      case 'car':
        return Icons.directions_car;
      case 'bloodtype':
        return Icons.bloodtype;
      case 'gas':
        return Icons.local_gas_station;
      case 'custom':
        return Icons.phone;
      default:
        return Icons.phone;
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(scheme: 'tel', path: phoneNumber);
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone dialer')),
        );
      }
    }
  }

  void _showAddContactDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    String selectedIconType = 'phone';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Add Emergency Contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'Contact Name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Phone Number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedIconType,
                  items: const [
                    DropdownMenuItem(value: 'phone', child: Text('Phone')),
                    DropdownMenuItem(
                      value: 'hospital',
                      child: Text('Hospital'),
                    ),
                    DropdownMenuItem(value: 'police', child: Text('Police')),
                    DropdownMenuItem(
                      value: 'ambulance',
                      child: Text('Ambulance'),
                    ),
                    DropdownMenuItem(value: 'fire', child: Text('Fire')),
                    DropdownMenuItem(value: 'car', child: Text('Car Repair')),
                    DropdownMenuItem(value: 'gas', child: Text('Gas Station')),
                    DropdownMenuItem(
                      value: 'bloodtype',
                      child: Text('Blood Bank'),
                    ),
                    DropdownMenuItem(value: 'custom', child: Text('Custom')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      selectedIconType = value ?? 'phone';
                    });
                  },
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
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
                onPressed: () async {
                  if (nameController.text.isNotEmpty &&
                      phoneController.text.isNotEmpty) {
                    final userId = supabaseService.getCurrentUserId();

                    if (userId == null) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Please login first to add custom contacts',
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                      return;
                    }

                    final success = await supabaseService.addEmergencyContact(
                      userId: userId,
                      contactName: nameController.text,
                      phoneNumber: phoneController.text,
                      iconType: selectedIconType,
                      isDefault: false,
                    );

                    if (mounted) {
                      Navigator.pop(context);
                      if (success) {
                        _loadContacts();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✓ Contact added successfully'),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Failed to add contact - Check your internet connection',
                            ),
                            backgroundColor: Colors.red,
                            duration: Duration(seconds: 3),
                          ),
                        );
                      }
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please fill all fields')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContactOptions(Map<String, dynamic> contact) {
    final isCustom = contact['user_id'] != null;

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.phone, color: Colors.green),
              title: const Text('Call'),
              onTap: () {
                Navigator.pop(context);
                _makePhoneCall(contact['phone_number']);
              },
            ),
            if (isCustom) ...[
              ListTile(
                leading: const Icon(Icons.edit, color: Colors.blue),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditContactDialog(contact);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete'),
                onTap: () async {
                  Navigator.pop(context);
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete Contact?'),
                      content: Text(
                        'Are you sure you want to delete ${contact['contact_name']}?',
                      ),
                      actions: [
                        Expanded(
                          child: TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                            ),
                            child: const Text('Delete'),
                          ),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    final success = await supabaseService
                        .deleteEmergencyContact(contact['id']);
                    if (mounted) {
                      if (success) {
                        _loadContacts();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Contact deleted'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showEditContactDialog(Map<String, dynamic> contact) {
    final nameController = TextEditingController(text: contact['contact_name']);
    final phoneController = TextEditingController(
      text: contact['phone_number'],
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                hintText: 'Contact Name',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                hintText: 'Phone Number',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
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
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    phoneController.text.isNotEmpty) {
                  final success = await supabaseService.updateEmergencyContact(
                    contactId: contact['id'],
                    contactName: nameController.text,
                    phoneNumber: phoneController.text,
                  );

                  if (mounted) {
                    Navigator.pop(context);
                    if (success) {
                      _loadContacts();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Contact updated'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Update'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.green.shade400,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Help',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: contactsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final contacts = snapshot.data ?? [];
          final defaultContacts = contacts
              .where((c) => c['is_default'] == true)
              .toList();
          final customContacts = contacts
              .where((c) => c['is_default'] != true)
              .toList();

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Text(
                    'Emergency Contact Numbers',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  if (defaultContacts.isNotEmpty) ...[
                    const Text(
                      'Default Contacts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: defaultContacts.length,
                      itemBuilder: (context, index) {
                        final contact = defaultContacts[index];
                        return _buildContactCard(contact);
                      },
                    ),
                  ],
                  if (customContacts.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'My Contacts',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey,
                          ),
                        ),
                        GestureDetector(
                          onTap: _showAddContactDialog,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.add,
                              color: Colors.green.shade700,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customContacts.length,
                      itemBuilder: (context, index) {
                        final contact = customContacts[index];
                        return _buildContactCard(contact);
                      },
                    ),
                  ] else ...[
                    const SizedBox(height: 20),
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            'No custom contacts added',
                            style: TextStyle(color: Colors.grey),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _showAddContactDialog,
                            icon: const Icon(Icons.add),
                            label: const Text('Add Contact'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: _buildBottomNavBar(context),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GestureDetector(
        onTap: () => _showContactOptions(contact),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                _getIconForType(contact['icon_type']),
                color: Colors.grey,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact['contact_name'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      contact['phone_number'],
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _makePhoneCall(contact['phone_number']),
                child: Icon(
                  Icons.phone,
                  color: Colors.green.shade600,
                  size: 22,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(0.1), blurRadius: 10),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/home'),
            child: _buildNavItem(Icons.home, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/petrol-station'),
            child: _buildNavItem(Icons.location_on, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/media'),
            child: _buildNavItem(Icons.videocam, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/stats'),
            child: _buildNavItem(Icons.bar_chart, false),
          ),
          GestureDetector(
            onTap: () => Navigator.pushNamed(context, '/profile'),
            child: _buildNavItem(Icons.person, true),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, bool isActive) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green : Colors.grey.shade200,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: isActive ? Colors.white : Colors.grey),
    );
  }
}
