import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseService _instance = SupabaseService._internal();

  factory SupabaseService() {
    return _instance;
  }

  SupabaseService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  // Public getter to access Supabase client
  SupabaseClient get supabase => _client;

  // ===== USER PROFILE OPERATIONS =====
  Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    try {
      final response = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('Error fetching profile: $e');
      return null;
    }
  }

  Future<bool> updateUserProfile({
    required String userId,
    required String name,
    required String phoneNumber,
    required String dateOfBirth,
    required String email,
    required String gender,
  }) async {
    try {
      await _client
          .from('profiles')
          .update({
        'name': name,
        'phone_number': phoneNumber,
        'date_of_birth': dateOfBirth,
        'gender': gender,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', userId);
      return true;
    } catch (e) {
      print('Error updating profile: $e');
      return false;
    }
  }

  // ===== USER PREFERENCES =====
  Future<bool> updateUserPreferences({
    required String userId,
    required String language,
    required bool notificationsEnabled,
    required bool darkModeEnabled,
    required String fuelPrice,
  }) async {
    try {
      await _client.from('user_preferences').upsert({
        'user_id': userId,
        'language': language,
        'notifications_enabled': notificationsEnabled,
        'dark_mode': darkModeEnabled,
        'fuel_price': fuelPrice,
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id');
      return true;
    } catch (e) {
      print('Error updating preferences: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> getUserPreferences(String userId) async {
    try {
      final response = await _client
          .from('user_preferences')
          .select()
          .eq('user_id', userId)
          .single();
      return Map<String, dynamic>.from(response as Map);
    } catch (e) {
      print('Error fetching preferences: $e');
      return null;
    }
  }

  // ===== FUEL PURCHASES & STATS =====
  Future<bool> addFuelPurchase({
    required String userId,
    required String vehicle,
    required String fuelType,
    required String amount,
    required DateTime purchaseDate,
  }) async {
    try {
      await _client.from('fuel_purchases').insert({
        'user_id': userId,
        'vehicle': vehicle,
        'fuel_type': fuelType,
        'amount': amount,
        'purchase_date': purchaseDate.toIso8601String(),
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error adding fuel purchase: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getFuelPurchases(String userId) async {
    try {
      final response = await _client
          .from('fuel_purchases')
          .select()
          .eq('user_id', userId)
          .order('purchase_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching fuel purchases: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> getFuelStats(String userId) async {
    try {
      final response = await _client
          .from('fuel_purchases')
          .select('amount')
          .eq('user_id', userId);

      if (response.isEmpty) return null;

      final amounts = response
          .map((e) => double.tryParse(e['amount'].toString()) ?? 0.0)
          .toList();
      final total = amounts.fold<double>(0.0, (sum, val) => sum + val);
      final average = total / amounts.length;

      return {'total': total, 'average': average, 'count': amounts.length};
    } catch (e) {
      print('Error fetching fuel stats: $e');
      return null;
    }
  }

  // ===== MEDIA UPLOADS =====
  /// Add a media post (image or video)
  /// mediaType: 'image' or 'video'
  /// thumbnailUrl: required for videos, optional for images
  Future<bool> addMediaPost({
    required String userId,
    required String mediaType, // 'image' or 'video'
    required String description,
    required String mediaUrl,
    String? thumbnailUrl,
  }) async {
    try {
      // Ensure user profile exists before inserting post
      // This prevents foreign key constraint violations
      try {
        final profile = await _client
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        if (profile == null) {
          // Profile doesn't exist, create one
          print('Creating profile for user: $userId');
          final currentUser = _client.auth.currentUser;
          final name = currentUser?.userMetadata?['name'] ??
              currentUser?.email?.split('@').first ??
              'User';
          final email = currentUser?.email ?? 'user@example.com';

          try {
            await _client.from('profiles').insert({
              'id': userId,
              'name': name,
              'email': email,
            });
            print('✓ Profile created successfully');
          } catch (insertError) {
            print('Insert failed, trying upsert: $insertError');
            await _client.from('profiles').upsert({
              'id': userId,
              'name': name,
              'email': email,
            });
            print('✓ Profile created via upsert');
          }
        }
      } catch (e) {
        print('✗ Error ensuring profile exists: $e');
        // Continue anyway and let the insert fail with a clear error if profile truly doesn't exist
      }

      // Now insert the post
      await _client.from('posts').insert({
        'user_id': userId,
        'media_type': mediaType,
        'description': description,
        'media_url': mediaUrl,
        'thumbnail_url': thumbnailUrl,
        'status': 'pending',
      });
      return true;
    } catch (e) {
      print('Error adding media post: $e');
      return false;
    }
  }

  /// Get user's media posts (approved posts only, or all own posts)
  Future<List<Map<String, dynamic>>> getUserMediaPosts(String userId) async {
    try {
      final response = await _client
          .from('posts')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching media posts: $e');
      return [];
    }
  }

  /// Get all approved posts (for feed/gallery view)
  Future<List<Map<String, dynamic>>> getApprovedMediaPosts({
    int limit = 20,
    int offset = 0,
  }) async {
    try {
      final response = await _client
          .from('posts')
          .select()
          .eq('status', 'approved')
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching approved posts: $e');
      return [];
    }
  }

  // ===== FEEDBACK =====
  Future<bool> submitFeedback({
    required String userId,
    required String title,
    required String description,
  }) async {
    try {
      await _client.from('feedback').insert({
        'user_id': userId,
        'title': title,
        'description': description,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error submitting feedback: $e');
      return false;
    }
  }

  // ===== REMINDERS =====
  Future<bool> addReminder({
    required String userId,
    required String taskName,
    required String phoneNumber,
    required String description,
    required DateTime expireDate,
    required String? email,
  }) async {
    try {
      print('DEBUG SupabaseService: addReminder called');
      print('DEBUG SupabaseService: userId: $userId');
      print('DEBUG SupabaseService: taskName: $taskName');

      // Check if user profile exists
      final profile = await _client.from('profiles').select().eq('id', userId).maybeSingle();
      if (profile == null) {
        print('DEBUG SupabaseService: Profile missing, creating one...');
        try {
          await _client.from('profiles').insert({
            'id': userId,
            'name': _client.auth.currentUser?.userMetadata?['full_name'] ?? 'User',
          });
        } catch (e) {
          print('Profile insert failed: $e, trying upsert');
          await _client.from('profiles').upsert({
            'id': userId,
            'name': _client.auth.currentUser?.userMetadata?['full_name'] ?? 'User',
          });
        }
      }

      // Append phone and email to description if column is missing in DB
      String finalDescription = description;
      if (phoneNumber.isNotEmpty) {
        finalDescription += '\nPhone: $phoneNumber';
      }
      if (email != null && email.isNotEmpty) {
        finalDescription += '\nEmail: $email';
      }

      final data = {
        'user_id': userId,
        'reminder_type': 'other', // Default type for tasks
        'title': taskName,
        'description': finalDescription,
        'expiry_date': expireDate.toIso8601String().split('T')[0], // Date only
        'status': 'active',
        'notification_days_before': [7, 1, 0], // Default notifications
        'frequency': 'once',
      };

      print('DEBUG SupabaseService: Inserting data: $data');

      final response = await _client.from('reminders').insert(data).select();
      print('DEBUG SupabaseService: Insert response: $response');
      return true;
    } catch (e) {
      print('DEBUG SupabaseService: Error adding reminder: $e');
      rethrow; // Rethrow to show error in UI
    }
  }

  Future<List<Map<String, dynamic>>> getReminders(String userId) async {
    try {
      final response = await _client
          .from('reminders')
          .select()
          .eq('user_id', userId)
          .order('expire_date', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching reminders: $e');
      return [];
    }
  }

  Future<bool> updateReminderStatus(String reminderId, bool completed) async {
    try {
      await _client
          .from('reminders')
          .update({'completed': completed})
          .eq('id', reminderId);
      return true;
    } catch (e) {
      print('Error updating reminder: $e');
      return false;
    }
  }

  // ===== SERVICE DATA =====
  Future<bool> addServiceRecord({
    required String userId,
    required String vehicleId,
    required String serviceType,
    required String serviceDate,
    required double mileage,
    required double cost,
    required String serviceCenter,
    String? technicianName,
    String? description,
    String? partsReplaced,
  }) async {
    try {
      final dateStr = serviceDate.contains(' ') ? serviceDate.split(' ')[0] : serviceDate;

      await _client.from('service_history').insert({
        'vehicle_id': vehicleId,
        'service_type': serviceType,
        'service_date': dateStr,
        'service_mileage': mileage,
        'service_cost': cost,
        'service_center': serviceCenter,
        'technician_name': technicianName,
        'description': description,
        'parts_replaced': partsReplaced,
      });
      return true;
    } catch (e) {
      print('Error adding service record: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getServiceRecords(String userId, {String? vehicleId}) async {
    try {
      final query = _client
          .from('service_history')
          .select()
          .eq('user_id', userId);

      if (vehicleId != null && vehicleId.isNotEmpty) {
        query.eq('vehicle_id', vehicleId);
      }

      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching service records: $e');
      return [];
    }
  }

  // ===== TRIP HISTORY =====
  Future<bool> addTripRecord({
    required String userId,
    required String tripType, // 'on_way', 'return'
    required String fromLocation,
    required String toLocation,
    required String cost,
    required String consumption,
    required String duration,
  }) async {
    try {
      await _client.from('trip_records').insert({
        'user_id': userId,
        'trip_type': tripType,
        'from_location': fromLocation,
        'to_location': toLocation,
        'cost': cost,
        'consumption': consumption,
        'duration': duration,
        'created_at': DateTime.now().toIso8601String(),
      });
      return true;
    } catch (e) {
      print('Error adding trip record: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getTripHistory(String userId) async {
    try {
      final response = await _client
          .from('trip_records')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching trip history: $e');
      return [];
    }
  }

  // ===== GET CURRENT USER =====
  String? getCurrentUserId() {
    return _client.auth.currentUser?.id;
  }

  Future<bool> isUserLoggedIn() async {
    return _client.auth.currentUser != null;
  }

  // ===== EMERGENCY CONTACTS =====
  // Ensure user profile exists (create if it doesn't)
  Future<bool> ensureUserProfileExists(String userId) async {
    try {
      // Check if profile exists
      final existingProfile = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile != null) {
        print('✅ User profile already exists');
        return true;
      }

      // Profile doesn't exist, create one
      print('📝 Creating user profile for $userId');

      final currentUser = _client.auth.currentUser;
      await _client.from('profiles').insert({
        'id': userId,
        'name': currentUser?.userMetadata?['name'] ?? 'User',
        'email': currentUser?.email ?? '',
        'phone_number': '',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      print('✅ User profile created successfully');
      return true;
    } catch (e) {
      print('⚠️ Warning: Could not ensure profile exists: $e');
      // Don't fail completely, try to add the contact anyway
      return false;
    }
  }

  Future<bool> addEmergencyContact({
    required String? userId,
    required String contactName,
    required String phoneNumber,
    required String iconType,
    required bool isDefault,
  }) async {
    try {
      if (userId == null) {
        print(
          '❌ ERROR: User ID is null. User must be logged in to add contacts.',
        );
        return false;
      }

      print('📝 Attempting to add emergency contact...');
      print('  User ID: $userId');
      print('  Contact: $contactName');
      print('  Phone: $phoneNumber');
      print('  Icon Type: $iconType');
      print('  Is Default: $isDefault');

      // Ensure user profile exists before adding contact
      await ensureUserProfileExists(userId);

      final response = await _client.from('emergency_contacts').insert({
        'user_id': userId,
        'contact_name': contactName,
        'phone_number': phoneNumber,
        'icon_type': iconType,
        'is_default': isDefault,
        'is_pinned': false,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select();

      print('✅ Emergency contact added successfully!');
      print('Response: $response');
      return true;
    } catch (e) {
      print('❌ ERROR adding emergency contact: $e');
      print('Error type: ${e.runtimeType}');
      print('Error message: ${e.toString()}');

      if (e.toString().contains('23503')) {
        print('🗂️ FOREIGN KEY ERROR: User profile does not exist');
        print('   Solution: Profile should have been created during signup');
      } else if (e.toString().contains('1113')) {
        print(
          '🔒 RLS POLICY ERROR: The policy is blocking this insert operation',
        );
      } else if (e.toString().contains(
        'new row violates row-level security policy',
      )) {
        print(
          '🔒 RLS POLICY ERROR: Check the WITH CHECK constraint in your policy',
        );
      } else if (e.toString().contains('permission denied')) {
        print('🔒 PERMISSION ERROR: Check if policies are enabled and correct');
      }

      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getEmergencyContacts(
      String? userId,
      ) async {
    try {
      // Get default contacts + user's custom contacts
      final defaultContacts = await _client
          .from('emergency_contacts')
          .select()
          .eq('is_default', true)
          .order('contact_name', ascending: true);

      final customContacts = userId != null
          ? await _client
          .from('emergency_contacts')
          .select()
          .eq('user_id', userId)
          .eq('is_default', false)
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          : [];

      final allContacts = <Map<String, dynamic>>[];
      allContacts.addAll(List<Map<String, dynamic>>.from(defaultContacts));
      allContacts.addAll(List<Map<String, dynamic>>.from(customContacts));

      return allContacts;
    } catch (e) {
      print('Error fetching emergency contacts: $e');
      return [];
    }
  }

  Future<bool> updateEmergencyContact({
    required String contactId,
    required String contactName,
    required String phoneNumber,
  }) async {
    try {
      await _client
          .from('emergency_contacts')
          .update({
        'contact_name': contactName,
        'phone_number': phoneNumber,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', contactId);
      return true;
    } catch (e) {
      print('Error updating emergency contact: $e');
      return false;
    }
  }

  Future<bool> deleteEmergencyContact(String contactId) async {
    try {
      await _client.from('emergency_contacts').delete().eq('id', contactId);
      return true;
    } catch (e) {
      print('Error deleting emergency contact: $e');
      return false;
    }
  }

  Future<bool> togglePinEmergencyContact(
      String contactId,
      bool isPinned,
      ) async {
    try {
      await _client
          .from('emergency_contacts')
          .update({'is_pinned': isPinned})
          .eq('id', contactId);
      return true;
    } catch (e) {
      print('Error toggling pin status: $e');
      return false;
    }
  }

  // ===== VEHICLES =====
  Future<List<Map<String, dynamic>>> getUserVehicles(String userId) async {
    try {
      // Shared visibility for vehicle list: show all vehicles to authenticated users
      final response = await _client
          .from('vehicles')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } on PostgrestException catch (e) {
      if (e.message.contains('Could not find the user_id column') ||
          e.message.contains('column "user_id" does not exist')) {
        print('Error fetching vehicles: user_id column missing: $e');
        final fallback = await _client
            .from('vehicles')
            .select()
            .order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(fallback);
      }
      rethrow;
    } catch (e) {
      print('Error fetching vehicles: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getVehiclesByOwner(String userId) async {
    try {
      final response = await _client
          .from('vehicles')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching vehicles by owner ($userId): $e');
      return [];
    }
  }

  // ===== RAW QUERY EXECUTION =====
  Future<void> executeQuery(String query, {List<dynamic>? parameters}) async {
    try {
      // For INSERT queries, parse and use table insert
      if (query.trim().toUpperCase().startsWith('INSERT INTO service_history')) {
        // Parse the INSERT statement for service_history
        // Expected format: INSERT INTO service_history (user_id, vehicle_id, service_type, service_date, mileage, description) VALUES (?, ?, ?, ?, ?, ?)
        if (parameters != null && parameters.length >= 6) {
          await _client.from('service_history').insert({
            'user_id': parameters[0],
            'vehicle_id': parameters[1],
            'service_type': parameters[2],
            'service_date': parameters[3],
            'service_mileage': double.tryParse(parameters[4].toString()) ?? 0,
            'description': parameters[5],
            'created_at': DateTime.now().toIso8601String(),
          });
        } else {
          throw Exception('Invalid parameters for service_history insert');
        }
      } else {
        throw Exception('Unsupported query type: $query');
      }
    } catch (e) {
      print('Error executing query: $e');
      rethrow;
    }

  }
}
