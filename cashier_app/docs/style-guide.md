# Style Guide

This document outlines coding conventions and best practices for the Kasir App project.

## Flutter/Dart Style

### Code Formatting

Use the official Dart formatter:
```bash
# Format a specific file
dart format lib/main.dart

# Format all files
dart format lib/
```

### File Organization

```dart
// 1. Dart imports
import 'dart:async';
import 'dart:convert';

// 2. Package imports
import 'package:flutter/material.dart';
import 'package:riverpod/riverpod.dart';

// 3. Local imports
import 'package:kasir_app/models/product.dart';
import 'package:kasir_app/services/supabase_service.dart';

// 4. Part directives
part 'product_state.freezed.dart';
```

### Class Organization

```dart
class ProductPage extends ConsumerStatefulWidget {
  // 1. Static variables/methods
  static const route = '/products';
  
  // 2. Instance variables
  final String storeId;
  
  // 3. Constructors
  const ProductPage({super.key, required this.storeId});
  
  // 4. Override methods
  @override
  ConsumerState<ProductPage> createState() => _ProductPageState();
}
```

### Naming Conventions

```dart
// Classes use PascalCase
class ProductDetailPage extends ConsumerWidget {}

// Variables and methods use camelCase
final productList = <Product>[];
void updateProduct(Product product) {}

// Constants use SCREAMING_SNAKE_CASE
const MAX_ITEMS_PER_PAGE = 20;

// Private members start with underscore
class _ProductPageState extends ConsumerState<ProductPage> {}
```

## Widget Structure

### Widget Organization

```dart
class ProductCard extends StatelessWidget {
  // 1. Constructor and fields
  const ProductCard({
    super.key,
    required this.product,
    this.onTap,
  });

  // 2. Fields
  final Product product;
  final VoidCallback? onTap;

  // 3. Private methods
  Widget _buildPrice() {
    return Text(
      '\$${product.price.toStringAsFixed(2)}',
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // 4. Build method
  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(product.name),
              const SizedBox(height: 8),
              _buildPrice(),
            ],
          ),
        ),
      ),
    );
  }
}
```

### State Management

```dart
// Providers are named with 'Provider' suffix
final productsProvider = StateNotifierProvider<ProductsNotifier, AsyncValue<List<Product>>>((ref) {
  return ProductsNotifier(ref.watch(supabaseServiceProvider));
});

// Notifiers are named with 'Notifier' suffix
class ProductsNotifier extends StateNotifier<AsyncValue<List<Product>>> {
  ProductsNotifier(this._supabase) : super(const AsyncValue.loading());

  final SupabaseService _supabase;

  Future<void> loadProducts() async {
    state = const AsyncValue.loading();
    try {
      final products = await _supabase.getProducts();
      state = AsyncValue.data(products);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
```

## Model Classes

### Using Freezed

```dart
@freezed
class Product with _$Product {
  const factory Product({
    required String id,
    required String name,
    required double price,
    required int stock,
    String? imageUrl,
    @Default(false) bool isActive,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}
```

### Extension Methods

```dart
extension ProductX on Product {
  bool get isLowStock => stock <= 10;
  
  String get displayPrice => '\$${price.toStringAsFixed(2)}';
  
  Product updateStock(int quantity) {
    return copyWith(stock: stock + quantity);
  }
}
```

## Error Handling

### Custom Exceptions

```dart
class ServiceException implements Exception {
  const ServiceException(this.message, {this.code});
  
  final String message;
  final String? code;
  
  @override
  String toString() => 'ServiceException: $message${code != null ? ' ($code)' : ''}';
}
```

### Error Handling Pattern

```dart
Future<void> handleOperation() async {
  try {
    await performOperation();
  } on ServiceException catch (e) {
    showErrorDialog(e.message);
  } on Exception catch (e, stack) {
    logError(e, stack);
    showGenericError();
  }
}
```

## Testing

### Test File Organization

```dart
void main() {
  group('ProductCard', () {
    // Setup
    late Product testProduct;
    
    setUp(() {
      testProduct = Product(
        id: '1',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
    });
    
    // Tests
    testWidgets('displays product information', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ProductCard(product: testProduct),
        ),
      );
      
      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('\$99.99'), findsOneWidget);
    });
  });
}
```

## Documentation

### Class Documentation

```dart
/// A service that handles all Supabase-related operations.
///
/// This service provides methods for:
/// * Authentication
/// * CRUD operations
/// * Real-time subscriptions
class SupabaseService {
  /// Creates a new instance with the given [client].
  ///
  /// Throws [ArgumentError] if [client] is null.
  SupabaseService(this._client) {
    ArgumentError.checkNotNull(_client, 'client');
  }
  
  final SupabaseClient _client;
  
  /// Fetches all products for the given [storeId].
  ///
  /// Throws [ServiceException] if the operation fails.
  Future<List<Product>> getProducts(String storeId) async {
    // Implementation
  }
}
```

## Constants and Configuration

### Constants Organization

```dart
// lib/constants/app_constants.dart
abstract class AppConstants {
  static const appName = 'Kasir App';
  static const appVersion = '1.0.0';
  
  // API endpoints
  static const apiVersion = 'v1';
  static const baseUrl = 'https://api.example.com/$apiVersion';
  
  // Timeouts
  static const connectionTimeout = Duration(seconds: 30);
  static const receiveTimeout = Duration(seconds: 30);
}

// lib/constants/ui_constants.dart
abstract class UIConstants {
  // Spacing
  static const double spacing4 = 4.0;
  static const double spacing8 = 8.0;
  static const double spacing16 = 16.0;
  
  // Border radius
  static const double borderRadius = 8.0;
  static final borderRadiusCircular = BorderRadius.circular(borderRadius);
}
```

## Performance Guidelines

1. **Widget Optimization**
   - Use `const` constructors
   - Implement `shouldRebuild` for custom widgets
   - Keep widget tree depth minimal

2. **State Management**
   - Use `select` for granular rebuilds
   - Dispose providers and controllers
   - Cache expensive computations

3. **Image Handling**
   - Use appropriate image formats
   - Implement image caching
   - Lazy load images

4. **List Optimization**
   - Use `ListView.builder` for long lists
   - Implement pagination
   - Cache list items

## Resources

- [Effective Dart](https://dart.dev/guides/language/effective-dart)
- [Flutter Style Guide](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo)
- [Riverpod Documentation](https://riverpod.dev/docs/concepts/about_code_generation)
- [Material Design Guidelines](https://material.io/design)
