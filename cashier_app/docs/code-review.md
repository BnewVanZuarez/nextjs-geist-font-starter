# Code Review Guide

This guide outlines the code review process and standards for the Kasir App project.

## Code Review Process

### 1. Before Submitting

✅ **Checklist:**
- [ ] Code follows [style guide](style-guide.md)
- [ ] Tests are written and passing
- [ ] Documentation is updated
- [ ] No debug/commented code
- [ ] Commit messages are clear
- [ ] Branch is up to date with main

### 2. Pull Request Template

```markdown
## Description
[Describe the changes and their purpose]

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
- [ ] Unit tests added/updated
- [ ] Widget tests added/updated
- [ ] Integration tests added/updated
- [ ] Manually tested

## Screenshots
[If applicable, add screenshots]

## Related Issues
Fixes #[issue_number]
```

## Review Guidelines

### 1. Code Quality

#### Architecture
```dart
// ❌ Bad: Mixed concerns
class ProductPage extends StatelessWidget {
  Future<void> saveProduct(Product product) async {
    final response = await http.post('/api/products', body: product.toJson());
    if (response.statusCode != 200) throw Exception('Failed to save');
  }
}

// ✅ Good: Separation of concerns
class ProductPage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProductForm(
      onSave: (product) => ref.read(productServiceProvider).saveProduct(product),
    );
  }
}
```

#### State Management
```dart
// ❌ Bad: State management in widget
class Counter extends StatefulWidget {
  int count = 0;
  
  void increment() => setState(() => count++);
}

// ✅ Good: Using providers
final counterProvider = StateNotifierProvider<CounterNotifier, int>((ref) {
  return CounterNotifier();
});

class CounterNotifier extends StateNotifier<int> {
  CounterNotifier() : super(0);
  void increment() => state++;
}
```

#### Error Handling
```dart
// ❌ Bad: Generic error handling
try {
  await operation();
} catch (e) {
  print(e);
}

// ✅ Good: Specific error handling
try {
  await operation();
} on NetworkException catch (e) {
  showNetworkError(e);
} on ValidationException catch (e) {
  showValidationError(e.errors);
} catch (e, stack) {
  logError(e, stack);
  showGenericError();
}
```

### 2. Performance

#### Widget Optimization
```dart
// ❌ Bad: Unnecessary rebuilds
class ProductTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(DateTime.now().toString()), // Rebuilds unnecessarily
    );
  }
}

// ✅ Good: Optimized builds
class ProductTile extends StatelessWidget {
  const ProductTile({super.key}); // Use const constructor

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(product.name), // Only data that changes
    );
  }
}
```

#### Resource Management
```dart
// ❌ Bad: Resource leak
class MyWidget extends StatefulWidget {
  StreamSubscription? _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscription = stream.listen((_) {});
  }
}

// ✅ Good: Proper cleanup
class MyWidget extends StatefulWidget {
  StreamSubscription? _subscription;
  
  @override
  void initState() {
    super.initState();
    _subscription = stream.listen((_) {});
  }
  
  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
```

### 3. Testing

#### Test Coverage
```dart
// ❌ Bad: Insufficient testing
test('product creation', () {
  final product = Product('name', 10);
  expect(product.name, 'name');
});

// ✅ Good: Comprehensive testing
group('Product', () {
  test('creation with valid data', () {
    final product = Product('name', 10);
    expect(product.name, 'name');
    expect(product.price, 10);
  });
  
  test('throws on invalid price', () {
    expect(() => Product('name', -1), throwsArgumentError);
  });
  
  test('serialization', () {
    final product = Product('name', 10);
    final json = product.toJson();
    final decoded = Product.fromJson(json);
    expect(decoded, equals(product));
  });
});
```

### 4. Documentation

#### Code Comments
```dart
// ❌ Bad: Obvious comments
// This function adds two numbers
int add(int a, int b) => a + b;

// ✅ Good: Meaningful documentation
/// Calculates the total price including tax and discounts.
///
/// Throws [ArgumentError] if [price] is negative.
/// Returns the final price rounded to 2 decimal places.
double calculateFinalPrice({
  required double price,
  double taxRate = 0.1,
  double? discount,
}) {
  if (price < 0) throw ArgumentError('Price cannot be negative');
  // Implementation...
}
```

#### API Documentation
```dart
// ❌ Bad: Missing documentation
class PaymentService {
  Future<void> processPayment(double amount) async {}
}

// ✅ Good: Well-documented API
/// Handles payment processing and verification.
///
/// Supports multiple payment methods and currencies.
class PaymentService {
  /// Processes a payment transaction.
  ///
  /// Parameters:
  /// - [amount]: The payment amount (must be positive)
  /// - [currency]: ISO 4217 currency code (defaults to USD)
  ///
  /// Throws [PaymentException] if the transaction fails.
  /// Returns a [Transaction] object on success.
  Future<Transaction> processPayment({
    required double amount,
    String currency = 'USD',
  }) async {
    // Implementation...
  }
}
```

## Review Feedback

### 1. Constructive Feedback

✅ **Do:**
- Be specific and actionable
- Explain the reasoning
- Provide examples
- Focus on the code, not the person

❌ **Don't:**
- Make assumptions
- Be condescending
- Use absolute terms
- Make it personal

### 2. Example Feedback

```markdown
#### Good Feedback:
Consider using a `const` constructor here since this widget doesn't maintain any state. This would improve performance by preventing unnecessary rebuilds.

#### Better Feedback:
```dart
// Current:
class ProductTile extends StatelessWidget {
  ProductTile({required this.product});
}

// Suggestion:
class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product});
}
```
This change would prevent unnecessary rebuilds when the parent widget rebuilds.
```

## Review Response

### 1. Receiving Feedback

✅ **Do:**
- Thank the reviewer
- Ask for clarification if needed
- Explain your reasoning
- Be open to suggestions

❌ **Don't:**
- Take it personally
- Defend without consideration
- Ignore feedback
- Rush changes

### 2. Example Response

```markdown
Thanks for the review! I've made the suggested changes:
- Added const constructor
- Updated documentation
- Added missing tests

I kept the current error handling approach because [explanation].
Let me know if you'd like me to make any other changes.
```

## Common Review Points

1. **Code Organization**
   - File structure follows conventions
   - Related code is grouped together
   - Clear separation of concerns

2. **Naming**
   - Clear and descriptive names
   - Consistent naming conventions
   - Appropriate use of prefixes/suffixes

3. **Error Handling**
   - Appropriate error types
   - User-friendly error messages
   - Proper error logging

4. **Testing**
   - Sufficient test coverage
   - Edge cases covered
   - Tests are readable and maintainable

5. **Performance**
   - Efficient algorithms
   - Proper resource management
   - Optimized widget rebuilds

## Resources

- [Flutter Style Guide](https://github.com/flutter/flutter/wiki/Style-guide-for-Flutter-repo)
- [Effective Dart](https://dart.dev/guides/language/effective-dart)
- [Flutter Performance Best Practices](https://flutter.dev/docs/perf/rendering/best-practices)
