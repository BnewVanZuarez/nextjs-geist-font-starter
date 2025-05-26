# State Management Guide

This guide explains how state management is implemented in the Kasir App using Riverpod.

## Overview

We use Riverpod for state management because it provides:
- Dependency injection
- State management
- Side effect handling
- Testing utilities
- Compile-time safety

## Provider Types

### 1. State Providers

```dart
// Simple state
final counterProvider = StateProvider<int>((ref) => 0);

// Complex state with StateNotifier
final cartProvider = StateNotifierProvider<CartNotifier, CartState>((ref) {
  return CartNotifier();
});

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(CartState.initial());
  
  void addItem(Product product, int quantity) {
    state = state.copyWith(
      items: [...state.items, CartItem(product, quantity)],
      total: state.total + (product.price * quantity),
    );
  }
}
```

### 2. Future Providers

```dart
// Async data fetching
final productsProvider = FutureProvider<List<Product>>((ref) async {
  final supabase = ref.watch(supabaseServiceProvider);
  return supabase.getProducts();
});

// With auto-refresh
final productsProvider = FutureProvider.autoDispose((ref) async {
  // Cancel token for cleanup
  final cancelToken = CancelToken();
  ref.onDispose(() => cancelToken.cancel());
  
  return await getProducts(cancelToken);
});
```

### 3. Stream Providers

```dart
// Real-time data
final ordersStreamProvider = StreamProvider<List<Order>>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return supabase
    .from('orders')
    .stream()
    .map((data) => data.map(Order.fromJson).toList());
});
```

## State Organization

### 1. Application State

```dart
// Global app state
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>((ref) {
  return AppStateNotifier();
});

class AppState {
  final ThemeMode themeMode;
  final Locale locale;
  final bool isOnline;
  
  AppState({
    required this.themeMode,
    required this.locale,
    required this.isOnline,
  });
}
```

### 2. Authentication State

```dart
final authStateProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return AuthNotifier(supabase);
});

class AuthState {
  final User? user;
  final bool isLoading;
  final String? error;
  
  const AuthState({
    this.user,
    this.isLoading = false,
    this.error,
  });
}
```

### 3. Feature State

```dart
// Store management state
final storeStateProvider = StateNotifierProvider<StoreNotifier, StoreState>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return StoreNotifier(supabase);
});

// Product management state
final productStateProvider = StateNotifierProvider<ProductNotifier, ProductState>((ref) {
  final supabase = ref.watch(supabaseServiceProvider);
  return ProductNotifier(supabase);
});
```

## State Usage in UI

### 1. Reading State

```dart
class ProductList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Watch for state changes
    final products = ref.watch(productsProvider);
    
    return products.when(
      data: (data) => ListView.builder(
        itemCount: data.length,
        itemBuilder: (context, index) => ProductCard(data[index]),
      ),
      loading: () => const CircularProgressIndicator(),
      error: (error, stack) => ErrorWidget(error.toString()),
    );
  }
}
```

### 2. Modifying State

```dart
class AddToCartButton extends ConsumerWidget {
  final Product product;
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () {
        // Modify state
        ref.read(cartProvider.notifier).addItem(product, 1);
      },
      child: Text('Add to Cart'),
    );
  }
}
```

### 3. Combining States

```dart
final filteredProductsProvider = Provider<List<Product>>((ref) {
  final products = ref.watch(productsProvider).value ?? [];
  final searchQuery = ref.watch(searchQueryProvider);
  final category = ref.watch(categoryFilterProvider);
  
  return products.where((product) {
    final matchesSearch = product.name.toLowerCase().contains(searchQuery.toLowerCase());
    final matchesCategory = category == null || product.category == category;
    return matchesSearch && matchesCategory;
  }).toList();
});
```

## State Persistence

### 1. Local Storage

```dart
class PersistedStateNotifier<T> extends StateNotifier<T> {
  final String key;
  final SharedPreferences prefs;
  
  PersistedStateNotifier(T state, this.key, this.prefs) : super(state) {
    // Load persisted state
    final json = prefs.getString(key);
    if (json != null) {
      state = deserializeState(json);
    }
  }
  
  @override
  set state(T value) {
    super.state = value;
    // Persist state changes
    prefs.setString(key, serializeState(value));
  }
}
```

### 2. Hydration

```dart
final hydratedCartProvider = StateNotifierProvider<HydratedCartNotifier, CartState>((ref) {
  return HydratedCartNotifier();
});

class HydratedCartNotifier extends StateNotifier<CartState> with Hydrated<CartState> {
  HydratedCartNotifier() : super(CartState.initial());
  
  @override
  CartState fromJson(Map<String, dynamic> json) {
    return CartState.fromJson(json);
  }
  
  @override
  Map<String, dynamic> toJson(CartState state) {
    return state.toJson();
  }
}
```

## State Testing

### 1. Provider Tests

```dart
void main() {
  test('counter increments', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    
    expect(container.read(counterProvider), 0);
    container.read(counterProvider.notifier).state++;
    expect(container.read(counterProvider), 1);
  });
}
```

### 2. StateNotifier Tests

```dart
void main() {
  test('cart adds items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    
    final cart = container.read(cartProvider.notifier);
    final product = Product(id: '1', name: 'Test', price: 10);
    
    cart.addItem(product, 1);
    
    expect(container.read(cartProvider).items.length, 1);
    expect(container.read(cartProvider).total, 10);
  });
}
```

## Best Practices

1. **Provider Organization**
   - Group related providers
   - Use meaningful names
   - Document complex providers

2. **State Updates**
   - Make state immutable
   - Use copyWith for updates
   - Validate state changes

3. **Error Handling**
   - Handle loading states
   - Provide error states
   - Show user feedback

4. **Performance**
   - Use select for fine-grained rebuilds
   - Dispose of providers when not needed
   - Cache expensive computations

5. **Testing**
   - Test state transitions
   - Mock dependencies
   - Test error cases

## Common Patterns

### 1. Loading States

```dart
class AsyncValue<T> {
  final T? data;
  final bool isLoading;
  final String? error;
  
  const AsyncValue({
    this.data,
    this.isLoading = false,
    this.error,
  });
}
```

### 2. Form State

```dart
final formStateProvider = StateNotifierProvider<FormNotifier, FormState>((ref) {
  return FormNotifier();
});

class FormState {
  final Map<String, String> values;
  final Map<String, String?> errors;
  final bool isValid;
  final bool isSubmitting;
  
  // ...
}
```

### 3. Pagination

```dart
final paginatedDataProvider = StateNotifierProvider<PaginationNotifier, PaginationState>((ref) {
  return PaginationNotifier();
});

class PaginationState {
  final List<Item> items;
  final bool hasMore;
  final bool isLoading;
  final int currentPage;
  
  // ...
}
```

## Advanced Topics

### 1. Side Effects

```dart
final sideEffectProvider = Provider((ref) {
  ref.listen<AuthState>(
    authStateProvider,
    (previous, next) {
      if (next.user == null && previous?.user != null) {
        // Handle logout
        ref.read(routerProvider).push('/login');
      }
    },
  );
});
```

### 2. Family Providers

```dart
final productDetailsProvider = FutureProvider.family<Product, String>((ref, id) async {
  final supabase = ref.watch(supabaseServiceProvider);
  return supabase.getProduct(id);
});
```

### 3. Auto-dispose

```dart
final searchResultsProvider = FutureProvider.autoDispose.family<List<Product>, String>((ref, query) async {
  // Provider will be disposed when no longer listened to
  ref.onDispose(() {
    print('Disposed search for: $query');
  });
  
  return searchProducts(query);
});
```

## Resources

- [Riverpod Documentation](https://riverpod.dev/)
- [Flutter State Management](https://flutter.dev/docs/development/data-and-backend/state-mgmt/options)
- [State Management Patterns](https://codewithandrea.com/articles/flutter-state-management-riverpod/)
