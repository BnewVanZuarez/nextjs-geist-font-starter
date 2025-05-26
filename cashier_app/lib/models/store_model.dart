class StoreModel {
  final String id;
  final String name;
  final String address;
  final String contact;
  final String adminId;
  final DateTime createdAt;

  StoreModel({
    required this.id,
    required this.name,
    required this.address,
    required this.contact,
    required this.adminId,
    required this.createdAt,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String,
      contact: json['contact'] as String,
      adminId: json['admin_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'contact': contact,
      'admin_id': adminId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  StoreModel copyWith({
    String? id,
    String? name,
    String? address,
    String? contact,
    String? adminId,
    DateTime? createdAt,
  }) {
    return StoreModel(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      contact: contact ?? this.contact,
      adminId: adminId ?? this.adminId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'StoreModel(id: $id, name: $name, address: $address, contact: $contact, adminId: $adminId, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is StoreModel &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.contact == contact &&
      other.adminId == adminId &&
      other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      address.hashCode ^
      contact.hashCode ^
      adminId.hashCode ^
      createdAt.hashCode;
  }

  // Helper method to get store display information
  String get displayInfo => '$name\n$address\nContact: $contact';
  
  // Helper method to check if a user is the admin of this store
  bool isAdmin(String userId) => adminId == userId;
}
