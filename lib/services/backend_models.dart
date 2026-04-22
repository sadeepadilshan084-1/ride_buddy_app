// ============================================
// MODELS FOR BACKEND
// ============================================

class UserModel {
  final String id;
  final String authId;
  final String fullName;
  final String email;


  final String? phone;
  final String? profileImageUrl;
  final String? fcmToken;
  final bool notificationEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;


  UserModel({
    required this.id,
    required this.authId,
    required this.fullName,
    required this.email,
    this.phone,
    this.profileImageUrl,
    this.fcmToken,
    this.notificationEnabled = true,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      authId: json['auth_id'] as String,
      fullName: json['full_name'] as String? ?? '',
      email: json['email'] as String,
      phone: json['phone'] as String?,
      profileImageUrl: json['profile_image_url'] as String?,
      fcmToken: json['fcm_token'] as String?,
      notificationEnabled: json['notification_enabled'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'auth_id': authId,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'profile_image_url': profileImageUrl,
    'fcm_token': fcmToken,
    'notification_enabled': notificationEnabled,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// ============================================
// REMINDER MODEL
// ============================================

enum ReminderType { license, insurance, service, inspection, pollutionCheck, other }
enum ReminderStatus { active, completed, expired, cancelled }
enum ReminderFrequency { once, monthly, yearly }

class ReminderModel {
  final String id;
  final String userId;
  final String? vehicleId;
  final ReminderType reminderType;
  final String title;
  final String? description;
  final DateTime expiryDate;
  final List<int> notificationDaysBefore;
  final ReminderFrequency frequency;
  final String? reminderPhoneNumber;
  final ReminderStatus status;
  final DateTime? nextNotificationDate;
  final bool isNotified;
  final DateTime createdAt;
  final DateTime updatedAt;

  ReminderModel({
    required this.id,
    required this.userId,
    this.vehicleId,
    required this.reminderType,
    required this.title,
    this.description,
    required this.expiryDate,
    this.notificationDaysBefore = const [7, 1, 0],
    this.frequency = ReminderFrequency.yearly,
    this.reminderPhoneNumber,
    this.status = ReminderStatus.active,
    this.nextNotificationDate,
    this.isNotified = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ReminderModel.fromJson(Map<String, dynamic> json) {
    return ReminderModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vehicleId: json['vehicle_id'] as String?,
      reminderType: ReminderType.values.firstWhere(
        (type) => type.name == json['reminder_type'],
        orElse: () => ReminderType.other,
      ),
      title: json['title'] as String,
      description: json['description'] as String?,
      expiryDate: DateTime.parse(json['expiry_date'] as String),
      notificationDaysBefore: List<int>.from(json['notification_days_before'] as List? ?? [7, 1, 0]),
      frequency: ReminderFrequency.values.firstWhere(
        (freq) => freq.name == json['frequency'],
        orElse: () => ReminderFrequency.yearly,
      ),
      reminderPhoneNumber: json['reminder_phone_number'] as String?,
      status: ReminderStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => ReminderStatus.active,
      ),
      nextNotificationDate: json['next_notification_date'] != null
          ? DateTime.parse(json['next_notification_date'] as String)
          : null,
      isNotified: json['is_notified'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'vehicle_id': vehicleId,
    'reminder_type': reminderType.name,
    'title': title,
    'description': description,
    'expiry_date': expiryDate.toIso8601String().split('T')[0],
    'notification_days_before': notificationDaysBefore,
    'frequency': frequency.name,
    'reminder_phone_number': reminderPhoneNumber,
    'status': status.name,
    'next_notification_date': nextNotificationDate?.toIso8601String(),
    'is_notified': isNotified,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;
  bool get isExpired => DateTime.now().isAfter(expiryDate);
  bool get isUrgent => daysUntilExpiry <= 7 && daysUntilExpiry >= 0;
  bool get isUpcoming => daysUntilExpiry <= 30 && daysUntilExpiry > 7;
}

// ============================================
// VEHICLE SERVICE MODEL
// ============================================

class VehicleServiceDetailsModel {
  final String id;
  final String vehicleId;
  final DateTime? lastServiceDate;
  final double? lastServiceMileage;
  final double? nextServiceMileage;
  final int serviceIntervalDays;
  final double serviceIntervalKm;
  final String? serviceCenterName;
  final String? serviceCenterPhone;
  final String? serviceCenterLocation;
  final DateTime? warrantyExpiryDate;
  final DateTime createdAt;
  final DateTime updatedAt;

  VehicleServiceDetailsModel({
    required this.id,
    required this.vehicleId,
    this.lastServiceDate,
    this.lastServiceMileage,
    this.nextServiceMileage,
    this.serviceIntervalDays = 365,
    this.serviceIntervalKm = 10000,
    this.serviceCenterName,
    this.serviceCenterPhone,
    this.serviceCenterLocation,
    this.warrantyExpiryDate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory VehicleServiceDetailsModel.fromJson(Map<String, dynamic> json) {
    return VehicleServiceDetailsModel(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      lastServiceDate: json['last_service_date'] != null
          ? DateTime.parse(json['last_service_date'] as String)
          : null,
      lastServiceMileage: json['last_service_mileage'] != null
          ? (json['last_service_mileage'] as num).toDouble()
          : null,
      nextServiceMileage: json['next_service_mileage'] != null
          ? (json['next_service_mileage'] as num).toDouble()
          : null,
      serviceIntervalDays: json['service_interval_days'] as int? ?? 365,
      serviceIntervalKm: (json['service_interval_km'] as num?)?.toDouble() ?? 10000,
      serviceCenterName: json['service_center_name'] as String?,
      serviceCenterPhone: json['service_center_phone'] as String?,
      serviceCenterLocation: json['service_center_location'] as String?,
      warrantyExpiryDate: json['warranty_expiry_date'] != null
          ? DateTime.parse(json['warranty_expiry_date'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'last_service_date': lastServiceDate?.toIso8601String(),
    'last_service_mileage': lastServiceMileage,
    'next_service_mileage': nextServiceMileage,
    'service_interval_days': serviceIntervalDays,
    'service_interval_km': serviceIntervalKm,
    'service_center_name': serviceCenterName,
    'service_center_phone': serviceCenterPhone,
    'service_center_location': serviceCenterLocation,
    'warranty_expiry_date': warrantyExpiryDate?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// ============================================
// SERVICE HISTORY MODEL
// ============================================

enum ServiceType { regular, emergency, inspection }

class ServiceHistoryModel {
  final String id;
  final String vehicleId;
  final ServiceType serviceType;
  final DateTime serviceDate;
  final double? serviceMileage;
  final double? serviceCost;
  final String? serviceCenter;
  final String? description;
  final String? technicianName;
  final DateTime? nextServiceDate;
  final double? nextServiceMileage;
  final String? partsReplaced;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServiceHistoryModel({
    required this.id,
    required this.vehicleId,
    required this.serviceType,
    required this.serviceDate,
    this.serviceMileage,
    this.serviceCost,
    this.serviceCenter,
    this.description,
    this.technicianName,
    this.nextServiceDate,
    this.nextServiceMileage,
    this.partsReplaced,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ServiceHistoryModel.fromJson(Map<String, dynamic> json) {
    return ServiceHistoryModel(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      serviceType: ServiceType.values.firstWhere(
        (type) => type.name == json['service_type'],
        orElse: () => ServiceType.regular,
      ),
      serviceDate: DateTime.parse(json['service_date'] as String),
      serviceMileage: json['service_mileage'] != null
          ? (json['service_mileage'] as num).toDouble()
          : null,
      serviceCost: json['service_cost'] != null
          ? (json['service_cost'] as num).toDouble()
          : null,
      serviceCenter: json['service_center'] as String?,
      description: json['description'] as String?,
      technicianName: json['technician_name'] as String?,
      nextServiceDate: json['next_service_date'] != null
          ? DateTime.parse(json['next_service_date'] as String)
          : null,
      nextServiceMileage: json['next_service_mileage'] != null
          ? (json['next_service_mileage'] as num).toDouble()
          : null,
      partsReplaced: json['parts_replaced'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'service_type': serviceType.name,
    'service_date': serviceDate.toIso8601String().split('T')[0],
    'service_mileage': serviceMileage,
    'service_cost': serviceCost,
    'service_center': serviceCenter,
    'description': description,
    'technician_name': technicianName,
    'next_service_date': nextServiceDate?.toIso8601String(),
    'next_service_mileage': nextServiceMileage,
    'parts_replaced': partsReplaced,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// ============================================
// NOTIFICATION LOG MODEL
// ============================================

enum NotificationType { push, sms, email }
enum DeliveryStatus { pending, sent, failed }

class NotificationLogModel {
  final String id;
  final String userId;
  final String reminderId;
  final NotificationType notificationType;
  final String title;
  final String message;
  final int? daysBeforeExpiry;
  final DateTime sentAt;
  final DateTime? readAt;
  final bool isDelivered;
  final DeliveryStatus deliveryStatus;
  final String? errorMessage;

  NotificationLogModel({
    required this.id,
    required this.userId,
    required this.reminderId,
    required this.notificationType,
    required this.title,
    required this.message,
    this.daysBeforeExpiry,
    required this.sentAt,
    this.readAt,
    this.isDelivered = false,
    this.deliveryStatus = DeliveryStatus.pending,
    this.errorMessage,
  });

  factory NotificationLogModel.fromJson(Map<String, dynamic> json) {
    return NotificationLogModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      reminderId: json['reminder_id'] as String,
      notificationType: NotificationType.values.firstWhere(
        (type) => type.name == json['notification_type'],
        orElse: () => NotificationType.push,
      ),
      title: json['title'] as String,
      message: json['message'] as String,
      daysBeforeExpiry: json['days_before_expiry'] as int?,
      sentAt: DateTime.parse(json['sent_at'] as String),
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      isDelivered: json['is_delivered'] as bool? ?? false,
      deliveryStatus: DeliveryStatus.values.firstWhere(
        (status) => status.name == json['delivery_status'],
        orElse: () => DeliveryStatus.pending,
      ),
      errorMessage: json['error_message'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'reminder_id': reminderId,
    'notification_type': notificationType.name,
    'title': title,
    'message': message,
    'days_before_expiry': daysBeforeExpiry,
    'sent_at': sentAt.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
    'is_delivered': isDelivered,
    'delivery_status': deliveryStatus.name,
    'error_message': errorMessage,
  };
}

// ============================================
// EMERGENCY CONTACT MODEL
// ============================================

class EmergencyContactModel {
  final String id;
  final String userId;
  final String contactName;
  final String phoneNumber;
  final String? relationship;
  final bool isPrimary;
  final DateTime createdAt;
  final DateTime updatedAt;

  EmergencyContactModel({
    required this.id,
    required this.userId,
    required this.contactName,
    required this.phoneNumber,
    this.relationship,
    this.isPrimary = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory EmergencyContactModel.fromJson(Map<String, dynamic> json) {
    return EmergencyContactModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      contactName: json['contact_name'] as String,
      phoneNumber: json['phone_number'] as String,
      relationship: json['relationship'] as String?,
      isPrimary: json['is_primary'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'contact_name': contactName,
    'phone_number': phoneNumber,
    'relationship': relationship,
    'is_primary': isPrimary,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };
}

// ============================================
// DOCUMENT MODEL
// ============================================

enum DocumentType { license, insurance, rc, registration, serviceRecord, other }

class DocumentModel {
  final String id;
  final String userId;
  final String? vehicleId;
  final DocumentType documentType;
  final String documentName;
  final String? documentUrl;
  final String? documentNumber;
  final DateTime? expiryDate;
  final DateTime? issuedDate;
  final String? issuingAuthority;
  final int? fileSize;
  final String? fileType;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentModel({
    required this.id,
    required this.userId,
    this.vehicleId,
    required this.documentType,
    required this.documentName,
    this.documentUrl,
    this.documentNumber,
    this.expiryDate,
    this.issuedDate,
    this.issuingAuthority,
    this.fileSize,
    this.fileType,
    required this.createdAt,
    required this.updatedAt,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      vehicleId: json['vehicle_id'] as String?,
      documentType: DocumentType.values.firstWhere(
        (type) => type.name == json['document_type'],
        orElse: () => DocumentType.other,
      ),
      documentName: json['document_name'] as String,
      documentUrl: json['document_url'] as String?,
      documentNumber: json['document_number'] as String?,
      expiryDate: json['expiry_date'] != null
          ? DateTime.parse(json['expiry_date'] as String)
          : null,
      issuedDate: json['issued_date'] != null
          ? DateTime.parse(json['issued_date'] as String)
          : null,
      issuingAuthority: json['issuing_authority'] as String?,
      fileSize: json['file_size'] as int?,
      fileType: json['file_type'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'vehicle_id': vehicleId,
    'document_type': documentType.name,
    'document_name': documentName,
    'document_url': documentUrl,
    'document_number': documentNumber,
    'expiry_date': expiryDate?.toIso8601String(),
    'issued_date': issuedDate?.toIso8601String(),
    'issuing_authority': issuingAuthority,
    'file_size': fileSize,
    'file_type': fileType,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  bool get isExpired => expiryDate != null && DateTime.now().isAfter(expiryDate!);
  int? get daysUntilExpiry => expiryDate != null
      ? expiryDate!.difference(DateTime.now()).inDays
      : null;
}

// ============================================
// FUEL REFILL MODEL
// ============================================

class FuelRefillModel {
  final String id;
  final String vehicleId;
  final String userId;
  final DateTime refillDate;
  final double mileage;
  final double amount; // liters
  final double cost;
  final String? fuelType; // petrol, diesel, cng, electric
  final double? pricePerLiter;
  final String? fillingStation;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  FuelRefillModel({
    required this.id,
    required this.vehicleId,
    required this.userId,
    required this.refillDate,
    required this.mileage,
    required this.amount,
    required this.cost,
    this.fuelType,
    this.pricePerLiter,
    this.fillingStation,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FuelRefillModel.fromJson(Map<String, dynamic> json) {
    return FuelRefillModel(
      id: json['id'] as String,
      vehicleId: json['vehicle_id'] as String,
      userId: json['user_id'] as String,
      refillDate: DateTime.parse(json['refill_date'] as String),
      mileage: (json['mileage'] as num).toDouble(),
      amount: (json['amount'] as num).toDouble(),
      cost: (json['cost'] as num).toDouble(),
      fuelType: json['fuel_type'] as String?,
      pricePerLiter: json['price_per_liter'] != null
          ? (json['price_per_liter'] as num).toDouble()
          : null,
      fillingStation: json['filling_station'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'vehicle_id': vehicleId,
    'user_id': userId,
    'refill_date': refillDate.toIso8601String().split('T')[0],
    'mileage': mileage,
    'amount': amount,
    'cost': cost,
    'fuel_type': fuelType,
    'price_per_liter': pricePerLiter,
    'filling_station': fillingStation,
    'notes': notes,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  // Calculate fuel economy (km per liter)
  double get fuelEconomy => mileage / amount;
  
  // Calculate average cost per km
  double get costPerKm => cost / mileage;
}

// ============================================
// SERVICE REMINDER STATUS MODEL
// ============================================

class ServiceReminderStatusModel {
  final String vehicleId;
  final String lastRefillMileage; // mileage at last refill
  final DateTime nextServiceDate; // calculated based on lastServiceDate + interval
  final double? nextServiceMileage; // calculated based on lastServiceMileage + interval
  final bool isOverdueByTime; // days-based check
  final bool isOverdueByMileage; // mileage-based check (if tracked)
  final String status; // 'on-schedule', 'due-soon', 'overdue'
  final Map<String, dynamic> details; // extra context

  ServiceReminderStatusModel({
    required this.vehicleId,
    required this.lastRefillMileage,
    required this.nextServiceDate,
    this.nextServiceMileage,
    required this.isOverdueByTime,
    required this.isOverdueByMileage,
    required this.status,
    required this.details,
  });

  factory ServiceReminderStatusModel.fromJson(Map<String, dynamic> json) {
    return ServiceReminderStatusModel(
      vehicleId: json['vehicle_id'] as String,
      lastRefillMileage: json['last_refill_mileage'] as String,
      nextServiceDate: DateTime.parse(json['next_service_date'] as String),
      nextServiceMileage: json['next_service_mileage'] != null
          ? (json['next_service_mileage'] as num).toDouble()
          : null,
      isOverdueByTime: json['is_overdue_by_time'] as bool? ?? false,
      isOverdueByMileage: json['is_overdue_by_mileage'] as bool? ?? false,
      status: json['status'] as String? ?? 'on-schedule',
      details: json['details'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toJson() => {
    'vehicle_id': vehicleId,
    'last_refill_mileage': lastRefillMileage,
    'next_service_date': nextServiceDate.toIso8601String(),
    'next_service_mileage': nextServiceMileage,
    'is_overdue_by_time': isOverdueByTime,
    'is_overdue_by_mileage': isOverdueByMileage,
    'status': status,
    'details': details,
  };
}
