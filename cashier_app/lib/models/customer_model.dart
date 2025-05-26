class CustomerModel {
  final String id;
  final String name;
  final String telephone;
  final String? note;
  final DateTime createdAt;
  final List<String>? transactionIds; // References to transactions

  CustomerModel({
    required this.id,
    required this.name,
    required this.telephone,
    this.note,
    required this.createdAt,
    this.transactionIds,
  });

  factory CustomerModel.fromJson(Map<String, dynamic> json) {
    return CustomerModel(
      id: json['id'] as String,
      name: json['name'] as String,
      telephone: json['telephone'] as String,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      transactionIds: (json['transaction_ids'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'telephone': telephone,
      'note': note,
      'created_at': createdAt.toIso8601String(),
      'transaction_ids': transactionIds,
    };
  }

  CustomerModel copyWith({
    String? id,
    String? name,
    String? telephone,
    String? note,
    DateTime? createdAt,
    List<String>? transactionIds,
  }) {
    return CustomerModel(
      id: id ?? this.id,
      name: name ?? this.name,
      telephone: telephone ?? this.telephone,
      note: note ?? this.note,
      createdAt: createdAt ?? this.createdAt,
      transactionIds: transactionIds ?? this.transactionIds,
    );
  }

  // Helper methods
  bool get hasTransactions => transactionIds?.isNotEmpty ?? false;
  
  int get transactionCount => transactionIds?.length ?? 0;

  // Format telephone number
  String get formattedTelephone {
    if (telephone.startsWith('+62')) {
      return telephone;
    }
    if (telephone.startsWith('0')) {
      return '+62${telephone.substring(1)}';
    }
    return '+62$telephone';
  }

  // Generate WhatsApp link
  String get whatsappLink => 'https://wa.me/${formattedTelephone.replaceAll('+', '')}';

  @override
  String toString() {
    return 'CustomerModel(id: $id, name: $name, telephone: $telephone, note: $note, createdAt: $createdAt, transactionIds: $transactionIds)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is CustomerModel &&
      other.id == id &&
      other.name == name &&
      other.telephone == telephone &&
      other.note == note &&
      other.createdAt == createdAt &&
      other.transactionIds == transactionIds;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      telephone.hashCode ^
      note.hashCode ^
      createdAt.hashCode ^
      transactionIds.hashCode;
  }

  // Display information
  String get displayInfo => '''
Name: $name
Phone: $formattedTelephone
${note != null ? 'Note: $note' : ''}
Transactions: $transactionCount
''';
}
