import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class EmergencyContactsService {
  static final EmergencyContactsService _instance =
      EmergencyContactsService._internal();

  factory EmergencyContactsService() {
    return _instance;
  }

  EmergencyContactsService._internal();

  final SupabaseService _supabaseService = SupabaseService();
  final SupabaseClient _client = Supabase.instance.client;

  // Initialize default emergency contacts (call this once after app startup)
  Future<void> initializeDefaultContacts() async {
    try {
      // Check if default contacts already exist
      final existingDefaults = await _client
          .from('emergency_contacts')
          .select()
          .eq('is_default', true);

      if (existingDefaults.isNotEmpty) {
        print('Default contacts already initialized');
        return;
      }

      // List of default emergency contacts for Sri Lanka
      final defaultContacts = [
        {
          'contact_name': 'Police Emergency',
          'phone_number': '119',
          'icon_type': 'police',
        },
        {
          'contact_name': 'Ambulance / Medical Emergency (Suwasariya)',
          'phone_number': '1990',
          'icon_type': 'ambulance',
        },
        {
          'contact_name': 'Fire Brigade (Colombo)',
          'phone_number': '191',
          'icon_type': 'fire',
        },
        {
          'contact_name': 'Highway Emergency Hotline',
          'phone_number': '1969',
          'icon_type': 'phone',
        },
        {
          'contact_name': 'National Road Rescue (NRSC)',
          'phone_number': '+94112360360',
          'icon_type': 'car',
        },
        {
          'contact_name': 'Colombo General Hospital',
          'phone_number': '+94112681111',
          'icon_type': 'hospital',
        },
        {
          'contact_name': 'Asiri Central Hospital',
          'phone_number': '+94115240800',
          'icon_type': 'hospital',
        },
        {
          'contact_name': 'National Blood Bank',
          'phone_number': '+94112696905',
          'icon_type': 'bloodtype',
        },
        {
          'contact_name': 'Ceylon Petroleum Corporation (Fuel)',
          'phone_number': '+94114715000',
          'icon_type': 'gas',
        },
        {
          'contact_name': 'Department of Motor Traffic (DMT)',
          'phone_number': '+94112388888',
          'icon_type': 'car',
        },
      ];

      // Insert default contacts
      for (final contact in defaultContacts) {
        await _client.from('emergency_contacts').insert({
          'user_id': null, // No user assigned for default contacts
          'contact_name': contact['contact_name'],
          'phone_number': contact['phone_number'],
          'icon_type': contact['icon_type'],
          'is_default': true,
          'is_pinned': false,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      print('Default emergency contacts initialized successfully');
    } catch (e) {
      print('Error initializing default contacts: $e');
    }
  }

  // Get all contacts for a user (default + custom)
  Future<List<Map<String, dynamic>>> getUserEmergencyContacts(
    String? userId,
  ) async {
    return _supabaseService.getEmergencyContacts(userId);
  }

  // Add custom emergency contact
  Future<bool> addCustomContact({
    required String? userId,
    required String contactName,
    required String phoneNumber,
    required String iconType,
  }) async {
    return _supabaseService.addEmergencyContact(
      userId: userId,
      contactName: contactName,
      phoneNumber: phoneNumber,
      iconType: iconType,
      isDefault: false,
    );
  }

  // Update emergency contact
  Future<bool> updateContact({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    return _supabaseService.updateEmergencyContact(
      contactId: contactId,
      contactName: contactName,
      phoneNumber: phoneNumber,
    );
  }

  // Delete emergency contact
  Future<bool> deleteContact(String contactId) async {
    return _supabaseService.deleteEmergencyContact(contactId);
  }

  // Toggle pin status
  Future<bool> togglePin(String contactId, bool isPinned) async {
    return _supabaseService.togglePinEmergencyContact(contactId, isPinned);
  }
}
