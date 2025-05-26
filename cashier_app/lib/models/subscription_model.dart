import 'package:intl/intl.dart';

enum SubscriptionPackage {
  basic,
  pro,
  premium;

  String get displayName => name[0].toUpperCase() + name.substring(1);
  
  // Get features available for each package
  List<String> get features {
    switch (this) {
      case SubscriptionPackage.basic:
        return [
          'Basic cash register features',
          'Up to 100 products',
          'Single store management',
          'Basic reports',
        ];
      case SubscriptionPackage.pro:
        return [
          'All Basic features',
          'Up to 1000 products',
          'Multiple store management',
          'Advanced reports',
          'Customer management',
          'Digital receipts',
        ];
      case SubscriptionPackage.premium:
        return [
          'All Pro features',
          'Unlimited products',
          'Advanced analytics',
          'Priority support',
          'Custom branding',
          'API access',
          'Data export',
        ];
    }
  }

  // Get monthly price for each package
  double get monthlyPrice {
    switch (this) {
      case SubscriptionPackage.basic:
        return 99000;  // Rp 99,000
      case SubscriptionPackage.pro:
        return 199000; // Rp 199,000
      case SubscriptionPackage.premium:
        return 299000; // Rp 299,000
    }
  }
}

class SubscriptionModel {
  final String id;
  final String userId;
  final SubscriptionPackage package;
  final DateTime startDate;
  final DateTime endDate;
  final DateTime createdAt;
  final bool isActive;

  SubscriptionModel({
    required this.id,
    required this.userId,
    required this.package,
    required this.startDate,
    required this.endDate,
    required this.createdAt,
    required this.isActive,
  });

  factory SubscriptionModel.fromJson(Map<String, dynamic> json) {
    return SubscriptionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      package: SubscriptionPackage.values.firstWhere(
        (e) => e.name == (json['package'] as String).toLowerCase(),
      ),
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      isActive: json['is_active'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'package': package.name,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }

  SubscriptionModel copyWith({
    String? id,
    String? userId,
    SubscriptionPackage? package,
    DateTime? startDate,
    DateTime? endDate,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return SubscriptionModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      package: package ?? this.package,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }

  // Helper methods
  bool get isExpired => DateTime.now().isAfter(endDate);
  
  int get daysRemaining {
    final now = DateTime.now();
    if (now.isAfter(endDate)) return 0;
    return endDate.difference(now).inDays;
  }

  String get formattedStartDate => DateFormat('dd/MM/yyyy').format(startDate);
  
  String get formattedEndDate => DateFormat('dd/MM/yyyy').format(endDate);
  
  String get formattedPrice => 'Rp ${NumberFormat('#,###').format(package.monthlyPrice)}';

  // Check if a specific feature is available in the current package
  bool hasFeature(String feature) {
    return package.features.contains(feature);
  }

  // Get subscription status description
  String get status {
    if (!isActive) return 'Inactive';
    if (isExpired) return 'Expired';
    if (daysRemaining <= 7) return 'Expiring Soon';
    return 'Active';
  }

  @override
  String toString() {
    return 'SubscriptionModel(id: $id, userId: $userId, package: ${package.displayName}, startDate: $startDate, endDate: $endDate, createdAt: $createdAt, isActive: $isActive)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is SubscriptionModel &&
      other.id == id &&
      other.userId == userId &&
      other.package == package &&
      other.startDate == startDate &&
      other.endDate == endDate &&
      other.createdAt == createdAt &&
      other.isActive == isActive;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      userId.hashCode ^
      package.hashCode ^
      startDate.hashCode ^
      endDate.hashCode ^
      createdAt.hashCode ^
      isActive.hashCode;
  }

  // Display information
  String get displayInfo => '''
Package: ${package.displayName}
Status: $status
Start Date: $formattedStartDate
End Date: $formattedEndDate
Days Remaining: $daysRemaining
Monthly Price: $formattedPrice
''';
}
