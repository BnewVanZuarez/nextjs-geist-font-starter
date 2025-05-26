import 'package:intl/intl.dart';

class TransactionModel {
  final String id;
  final String storeId;
  final String userId;
  final double totalAmount;
  final double discount;
  final double tax;
  final DateTime transactionDate;
  final List<TransactionItem> items;

  TransactionModel({
    required this.id,
    required this.storeId,
    required this.userId,
    required this.totalAmount,
    required this.discount,
    required this.tax,
    required this.transactionDate,
    required this.items,
  });

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      storeId: json['store_id'] as String,
      userId: json['user_id'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      discount: (json['discount'] as num).toDouble(),
      tax: (json['tax'] as num).toDouble(),
      transactionDate: DateTime.parse(json['transaction_date'] as String),
      items: (json['items'] as List<dynamic>?)
          ?.map((item) => TransactionItem.fromJson(item as Map<String, dynamic>))
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'store_id': storeId,
      'user_id': userId,
      'total_amount': totalAmount,
      'discount': discount,
      'tax': tax,
      'transaction_date': transactionDate.toIso8601String(),
      'items': items.map((item) => item.toJson()).toList(),
    };
  }

  // Helper methods
  String get formattedDate => DateFormat('dd/MM/yyyy HH:mm').format(transactionDate);
  
  String get formattedTotalAmount => 'Rp ${totalAmount.toStringAsFixed(2)}';
  
  String get formattedDiscount => 'Rp ${discount.toStringAsFixed(2)}';
  
  String get formattedTax => 'Rp ${tax.toStringAsFixed(2)}';
  
  double get subtotal => totalAmount - tax + discount;
  
  String get formattedSubtotal => 'Rp ${subtotal.toStringAsFixed(2)}';

  // Generate receipt content
  String generateReceiptContent({
    required String storeName,
    required String storeAddress,
    required String cashierName,
  }) {
    final buffer = StringBuffer();
    
    // Header
    buffer.writeln(storeName.toUpperCase());
    buffer.writeln(storeAddress);
    buffer.writeln('');
    buffer.writeln('Date: $formattedDate');
    buffer.writeln('Cashier: $cashierName');
    buffer.writeln('Transaction ID: $id');
    buffer.writeln('----------------------------------------');
    
    // Items
    for (var item in items) {
      buffer.writeln(item.name);
      buffer.writeln('${item.quantity} x ${item.formattedPrice} = ${item.formattedTotal}');
    }
    
    // Footer
    buffer.writeln('----------------------------------------');
    buffer.writeln('Subtotal: $formattedSubtotal');
    if (discount > 0) {
      buffer.writeln('Discount: $formattedDiscount');
    }
    buffer.writeln('Tax: $formattedTax');
    buffer.writeln('Total: $formattedTotalAmount');
    buffer.writeln('');
    buffer.writeln('Thank you for your purchase!');
    
    return buffer.toString();
  }

  TransactionModel copyWith({
    String? id,
    String? storeId,
    String? userId,
    double? totalAmount,
    double? discount,
    double? tax,
    DateTime? transactionDate,
    List<TransactionItem>? items,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      userId: userId ?? this.userId,
      totalAmount: totalAmount ?? this.totalAmount,
      discount: discount ?? this.discount,
      tax: tax ?? this.tax,
      transactionDate: transactionDate ?? this.transactionDate,
      items: items ?? this.items,
    );
  }

  @override
  String toString() {
    return 'TransactionModel(id: $id, storeId: $storeId, userId: $userId, totalAmount: $totalAmount, discount: $discount, tax: $tax, transactionDate: $transactionDate, items: $items)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is TransactionModel &&
      other.id == id &&
      other.storeId == storeId &&
      other.userId == userId &&
      other.totalAmount == totalAmount &&
      other.discount == discount &&
      other.tax == tax &&
      other.transactionDate == transactionDate &&
      other.items == items;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      storeId.hashCode ^
      userId.hashCode ^
      totalAmount.hashCode ^
      discount.hashCode ^
      tax.hashCode ^
      transactionDate.hashCode ^
      items.hashCode;
  }
}

class TransactionItem {
  final String productId;
  final String name;
  final double price;
  final int quantity;

  TransactionItem({
    required this.productId,
    required this.name,
    required this.price,
    required this.quantity,
  });

  factory TransactionItem.fromJson(Map<String, dynamic> json) {
    return TransactionItem(
      productId: json['product_id'] as String,
      name: json['name'] as String,
      price: (json['price'] as num).toDouble(),
      quantity: json['quantity'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'name': name,
      'price': price,
      'quantity': quantity,
    };
  }

  // Helper methods
  double get total => price * quantity;
  
  String get formattedPrice => 'Rp ${price.toStringAsFixed(2)}';
  
  String get formattedTotal => 'Rp ${total.toStringAsFixed(2)}';

  @override
  String toString() {
    return 'TransactionItem(productId: $productId, name: $name, price: $price, quantity: $quantity)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is TransactionItem &&
      other.productId == productId &&
      other.name == name &&
      other.price == price &&
      other.quantity == quantity;
  }

  @override
  int get hashCode {
    return productId.hashCode ^
      name.hashCode ^
      price.hashCode ^
      quantity.hashCode;
  }
}
