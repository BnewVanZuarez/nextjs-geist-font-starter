class ProductModel {
  final String id;
  final String storeId;
  final String name;
  final String category;
  final double price;
  final int stock;
  final String? imageUrl;
  final DateTime createdAt;

  ProductModel({
    required this.id,
    required this.storeId,
    required this.name,
    required this.category,
    required this.price,
    required this.stock,
    this.imageUrl,
    required this.createdAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String,
      name: json['name'] as String,
      category: json['category'] as String,
      price: (json['price'] as num).toDouble(),
      stock: json['stock'] as int,
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'image_url': imageUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  ProductModel copyWith({
    String? id,
    String? storeId,
    String? name,
    String? category,
    double? price,
    int? stock,
    String? imageUrl,
    DateTime? createdAt,
  }) {
    return ProductModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      category: category ?? this.category,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      imageUrl: imageUrl ?? this.imageUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'ProductModel(id: $id, storeId: $storeId, name: $name, category: $category, price: $price, stock: $stock, imageUrl: $imageUrl, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is ProductModel &&
      other.id == id &&
      other.storeId == storeId &&
      other.name == name &&
      other.category == category &&
      other.price == price &&
      other.stock == stock &&
      other.imageUrl == imageUrl &&
      other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      storeId.hashCode ^
      name.hashCode ^
      category.hashCode ^
      price.hashCode ^
      stock.hashCode ^
      imageUrl.hashCode ^
      createdAt.hashCode;
  }

  // Helper methods
  bool get isLowStock => stock <= 10;
  bool get isOutOfStock => stock <= 0;
  
  // Format price to currency
  String get formattedPrice => 'Rp ${price.toStringAsFixed(2)}';
  
  // Check if product can fulfill order quantity
  bool canFulfillOrder(int quantity) => stock >= quantity;
  
  // Calculate total price for quantity
  double calculateTotal(int quantity) => price * quantity;
}
