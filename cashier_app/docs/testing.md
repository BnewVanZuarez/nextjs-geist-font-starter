# Testing Guide

This guide covers testing strategies and best practices for the Kasir App.

## Testing Structure

```
test/
├── unit/                    # Unit tests
│   ├── models/             # Model tests
│   ├── providers/          # Provider tests
│   └── services/           # Service tests
├── widget/                 # Widget tests
│   ├── pages/             # Page widget tests
│   └── components/        # Reusable component tests
└── integration/           # Integration tests
    └── flows/            # User flow tests
```

## Unit Testing

### Model Tests

```dart
void main() {
  group('Product Model', () {
    test('fromJson creates correct instance', () {
      final json = {
        'id': '123',
        'name': 'Test Product',
        'price': 99.99,
        'stock': 10,
      };
      
      final product = Product.fromJson(json);
      
      expect(product.id, '123');
      expect(product.name, 'Test Product');
      expect(product.price, 99.99);
      expect(product.stock, 10);
    });
    
    test('toJson creates correct map', () {
      final product = Product(
        id: '123',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
      
      final json = product.toJson();
      
      expect(json['id'], '123');
      expect(json['name'], 'Test Product');
      expect(json['price'], 99.99);
      expect(json['stock'], 10);
    });
    
    test('copyWith creates new instance with updated values', () {
      final product = Product(
        id: '123',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
      
      final updated = product.copyWith(price: 89.99);
      
      expect(updated.id, product.id);
      expect(updated.name, product.name);
      expect(updated.price, 89.99);
      expect(updated.stock, product.stock);
    });
  });
}
```

### Provider Tests

```dart
void main() {
  group('CartProvider', () {
    late ProviderContainer container;
    
    setUp(() {
      container = ProviderContainer();
    });
    
    tearDown(() {
      container.dispose();
    });
    
    test('initial state is empty', () {
      final cart = container.read(cartProvider);
      
      expect(cart.items, isEmpty);
      expect(cart.total, 0.0);
    });
    
    test('adding item updates state correctly', () {
      final notifier = container.read(cartProvider.notifier);
      final product = Product(
        id: '123',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
      
      notifier.addItem(product, 2);
      
      final cart = container.read(cartProvider);
      expect(cart.items.length, 1);
      expect(cart.total, 199.98);
    });
  });
}
```

### Service Tests

```dart
void main() {
  group('SupabaseService', () {
    late MockSupabaseClient mockClient;
    late SupabaseService service;
    
    setUp(() {
      mockClient = MockSupabaseClient();
      service = SupabaseService(client: mockClient);
    });
    
    test('getProducts returns list of products', () async {
      when(mockClient.from('products').select())
          .thenAnswer((_) async => [
                {
                  'id': '123',
                  'name': 'Test Product',
                  'price': 99.99,
                  'stock': 10,
                }
              ]);
      
      final products = await service.getProducts();
      
      expect(products.length, 1);
      expect(products.first.id, '123');
    });
    
    test('getProducts handles errors', () {
      when(mockClient.from('products').select())
          .thenThrow(Exception('Network error'));
      
      expect(
        () => service.getProducts(),
        throwsA(isA<ServiceException>()),
      );
    });
  });
}
```

## Widget Testing

### Page Tests

```dart
void main() {
  group('LoginPage', () {
    testWidgets('shows validation errors for empty fields',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      
      // Find login button
      final loginButton = find.text('Login');
      
      // Tap button without entering credentials
      await tester.tap(loginButton);
      await tester.pump();
      
      // Verify error messages
      expect(find.text('Email is required'), findsOneWidget);
      expect(find.text('Password is required'), findsOneWidget);
    });
    
    testWidgets('calls login when form is valid',
        (WidgetTester tester) async {
      final mockAuth = MockAuthNotifier();
      
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWithValue(mockAuth),
          ],
          child: const MaterialApp(
            home: LoginPage(),
          ),
        ),
      );
      
      // Enter credentials
      await tester.enterText(
        find.byType(TextFormField).first,
        'test@example.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'password123',
      );
      
      // Tap login button
      await tester.tap(find.text('Login'));
      
      // Verify login was called
      verify(mockAuth.login(
        email: 'test@example.com',
        password: 'password123',
      )).called(1);
    });
  });
}
```

### Component Tests

```dart
void main() {
  group('ProductCard', () {
    testWidgets('displays product information',
        (WidgetTester tester) async {
      final product = Product(
        id: '123',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(product: product),
          ),
        ),
      );
      
      expect(find.text('Test Product'), findsOneWidget);
      expect(find.text('\$99.99'), findsOneWidget);
      expect(find.text('In Stock: 10'), findsOneWidget);
    });
    
    testWidgets('calls onTap when pressed',
        (WidgetTester tester) async {
      var tapped = false;
      final product = Product(
        id: '123',
        name: 'Test Product',
        price: 99.99,
        stock: 10,
      );
      
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductCard(
              product: product,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      
      await tester.tap(find.byType(ProductCard));
      expect(tapped, true);
    });
  });
}
```

## Integration Testing

### User Flow Tests

```dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  
  group('End-to-end test', () {
    testWidgets('complete purchase flow', (tester) async {
      await tester.pumpWidget(const MyApp());
      
      // Login
      await tester.enterText(
        find.byKey(const Key('email_field')),
        'test@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('password_field')),
        'password123',
      );
      await tester.tap(find.byKey(const Key('login_button')));
      await tester.pumpAndSettle();
      
      // Navigate to products
      await tester.tap(find.byKey(const Key('products_tab')));
      await tester.pumpAndSettle();
      
      // Add product to cart
      await tester.tap(find.byKey(const Key('add_to_cart_button')).first);
      await tester.pumpAndSettle();
      
      // Go to cart
      await tester.tap(find.byKey(const Key('cart_button')));
      await tester.pumpAndSettle();
      
      // Complete purchase
      await tester.tap(find.byKey(const Key('checkout_button')));
      await tester.pumpAndSettle();
      
      // Verify success message
      expect(find.text('Purchase Complete'), findsOneWidget);
    });
  });
}
```

## Test Coverage

### Running Coverage

```bash
# Generate coverage report
flutter test --coverage

# Generate HTML report
genhtml coverage/lcov.info -o coverage/html

# Open report
open coverage/html/index.html
```

### Coverage Goals

- Models: 100% coverage
- Providers: 100% coverage
- Services: 100% coverage
- Widgets: 80% coverage
- Pages: 70% coverage

## Mocking

### Creating Mocks

```dart
@GenerateMocks([SupabaseClient, AuthService])
import 'services.mocks.dart';

// Use in tests
final mockSupabase = MockSupabaseClient();
final mockAuth = MockAuthService();
```

### Mock Responses

```dart
// Success response
when(mockSupabase.from('products').select())
    .thenAnswer((_) async => [/* mock data */]);

// Error response
when(mockSupabase.from('products').select())
    .thenThrow(Exception('Network error'));
```

## Best Practices

1. **Test Organization**
   - Group related tests
   - Use descriptive test names
   - Follow AAA pattern (Arrange, Act, Assert)

2. **Test Data**
   - Use factory methods for test data
   - Keep test data realistic
   - Don't share mutable state

3. **Assertions**
   - Make assertions specific
   - Test edge cases
   - Verify error handling

4. **Mocking**
   - Mock external dependencies
   - Don't mock value objects
   - Keep mocks simple

5. **Maintenance**
   - Update tests with code changes
   - Remove obsolete tests
   - Keep tests DRY

## CI/CD Integration

```yaml
# In .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.16.0'
    
    - name: Install dependencies
      run: flutter pub get
    
    - name: Run tests
      run: flutter test --coverage
    
    - name: Upload coverage
      uses: codecov/codecov-action@v3
      with:
        file: coverage/lcov.info
```

## Resources

- [Flutter Testing Documentation](https://flutter.dev/docs/testing)
- [Integration Testing](https://flutter.dev/docs/testing/integration-tests)
- [Mock Objects](https://flutter.dev/docs/cookbook/testing/unit/mocking)
- [Widget Testing](https://flutter.dev/docs/cookbook/testing/widget/introduction)
