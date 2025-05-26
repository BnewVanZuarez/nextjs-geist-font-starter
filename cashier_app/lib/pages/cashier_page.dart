import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product_model.dart';
import '../models/store_model.dart';
import '../models/transaction_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Cart item class
class CartItem {
  final ProductModel product;
  int quantity;
  double get total => product.price * quantity;

  CartItem({
    required this.product,
    this.quantity = 1,
  });
}

// Cart provider
final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>((ref) {
  return CartNotifier();
});

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addItem(ProductModel product) {
    final existingIndex = state.indexWhere((item) => item.product.id == product.id);
    if (existingIndex >= 0) {
      if (state[existingIndex].quantity < product.stock) {
        state = [
          ...state.sublist(0, existingIndex),
          CartItem(
            product: product,
            quantity: state[existingIndex].quantity + 1,
          ),
          ...state.sublist(existingIndex + 1),
        ];
      }
    } else {
      state = [...state, CartItem(product: product)];
    }
  }

  void removeItem(String productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void updateQuantity(String productId, int quantity) {
    state = state.map((item) {
      if (item.product.id == productId) {
        return CartItem(
          product: item.product,
          quantity: quantity,
        );
      }
      return item;
    }).toList();
  }

  void clear() {
    state = [];
  }

  double get total => state.fold(0, (sum, item) => sum + item.total);
}

class CashierPage extends ConsumerStatefulWidget {
  const CashierPage({super.key});

  @override
  ConsumerState<CashierPage> createState() => _CashierPageState();
}

class _CashierPageState extends ConsumerState<CashierPage> {
  StoreModel? _selectedStore;
  String? _searchQuery;
  bool _isProcessing = false;
  final _discountController = TextEditingController(text: '0');
  final _taxController = TextEditingController(text: '0');

  @override
  void dispose() {
    _discountController.dispose();
    _taxController.dispose();
    super.dispose();
  }

  List<ProductModel> _filterProducts(List<ProductModel> products) {
    if (_searchQuery == null || _searchQuery!.isEmpty) {
      return products;
    }

    final query = _searchQuery!.toLowerCase();
    return products.where((product) {
      return product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _processTransaction() async {
    final cart = ref.read(cartProvider);
    if (cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cart is empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception('User not found');

      // Calculate totals
      final subtotal = cart.fold(0.0, (sum, item) => sum + item.total);
      final discount = double.tryParse(_discountController.text) ?? 0;
      final tax = double.tryParse(_taxController.text) ?? 0;
      final total = subtotal - discount + tax;

      // Create transaction
      final transaction = await ref.read(supabaseServiceProvider).createTransaction(
        storeId: _selectedStore!.id,
        userId: user.id,
        totalAmount: total,
        discount: discount,
        tax: tax,
      );

      // Update product stock
      for (final item in cart) {
        await ref.read(supabaseServiceProvider).updateProduct(
          id: item.product.id,
          data: {
            'stock': item.product.stock - item.quantity,
          },
        );
      }

      // Clear cart and refresh products
      ref.read(cartProvider.notifier).clear();
      ref.refresh(productsProvider(_selectedStore!.id));

      // Show receipt
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => ReceiptDialog(
            transaction: TransactionModel(
              id: transaction['id'],
              storeId: _selectedStore!.id,
              userId: user.id,
              totalAmount: total,
              discount: discount,
              tax: tax,
              transactionDate: DateTime.now(),
              items: cart
                  .map((item) => TransactionItem(
                        productId: item.product.id,
                        name: item.product.name,
                        price: item.product.price,
                        quantity: item.quantity,
                      ))
                  .toList(),
            ),
            storeName: _selectedStore!.name,
            storeAddress: _selectedStore!.address,
            cashierName: user.fullName,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(storesProvider);
    final productsAsync = _selectedStore != null
        ? ref.watch(productsProvider(_selectedStore!.id))
        : null;
    final cart = ref.watch(cartProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cashier'),
      ),
      body: Column(
        children: [
          // Store Selector and Search Bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: storesAsync.when(
                    data: (stores) => DropdownButtonFormField<StoreModel>(
                      value: _selectedStore,
                      decoration: const InputDecoration(
                        labelText: 'Select Store',
                        border: OutlineInputBorder(),
                      ),
                      items: stores.map((store) {
                        return DropdownMenuItem(
                          value: store,
                          child: Text(store.name),
                        );
                      }).toList(),
                      onChanged: (store) {
                        setState(() {
                          _selectedStore = store;
                        });
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: ${error.toString()}'),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search Products',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Main Content
          Expanded(
            child: Row(
              children: [
                // Products Grid
                Expanded(
                  flex: 2,
                  child: _selectedStore == null
                      ? const Center(
                          child: Text('Please select a store'),
                        )
                      : productsAsync!.when(
                          data: (products) {
                            final filteredProducts = _filterProducts(products);
                            return filteredProducts.isEmpty
                                ? const Center(
                                    child: Text('No products found'),
                                  )
                                : GridView.builder(
                                    padding: const EdgeInsets.all(16),
                                    gridDelegate:
                                        const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 1,
                                      crossAxisSpacing: 16,
                                      mainAxisSpacing: 16,
                                    ),
                                    itemCount: filteredProducts.length,
                                    itemBuilder: (context, index) {
                                      final product = filteredProducts[index];
                                      return Card(
                                        child: InkWell(
                                          onTap: product.stock > 0
                                              ? () {
                                                  ref
                                                      .read(cartProvider.notifier)
                                                      .addItem(product);
                                                }
                                              : null,
                                          child: Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                if (product.imageUrl != null)
                                                  Expanded(
                                                    child: Image.network(
                                                      product.imageUrl!,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  )
                                                else
                                                  const Icon(
                                                    Icons.inventory,
                                                    size: 48,
                                                  ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  product.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                                Text(
                                                  product.formattedPrice,
                                                  style: const TextStyle(
                                                    color: Colors.green,
                                                  ),
                                                ),
                                                Text(
                                                  'Stock: ${product.stock}',
                                                  style: TextStyle(
                                                    color: product.isLowStock
                                                        ? Colors.red
                                                        : null,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(
                            child: Text('Error: ${error.toString()}'),
                          ),
                        ),
                ),

                // Cart
                SizedBox(
                  width: 400,
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Cart Items
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: cart.length,
                            itemBuilder: (context, index) {
                              final item = cart[index];
                              return Card(
                                child: ListTile(
                                  title: Text(item.product.name),
                                  subtitle: Text(
                                      '${item.product.formattedPrice} x ${item.quantity}'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Rp ${item.total.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle),
                                        onPressed: () {
                                          if (item.quantity > 1) {
                                            ref
                                                .read(cartProvider.notifier)
                                                .updateQuantity(
                                                  item.product.id,
                                                  item.quantity - 1,
                                                );
                                          } else {
                                            ref
                                                .read(cartProvider.notifier)
                                                .removeItem(item.product.id);
                                          }
                                        },
                                      ),
                                      Text('${item.quantity}'),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle),
                                        onPressed: item.quantity <
                                                item.product.stock
                                            ? () {
                                                ref
                                                    .read(cartProvider.notifier)
                                                    .updateQuantity(
                                                      item.product.id,
                                                      item.quantity + 1,
                                                    );
                                              }
                                            : null,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Cart Summary
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              // Discount
                              TextField(
                                controller: _discountController,
                                decoration: const InputDecoration(
                                  labelText: 'Discount',
                                  border: OutlineInputBorder(),
                                  prefixText: 'Rp ',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+\.?\d{0,2}'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Tax
                              TextField(
                                controller: _taxController,
                                decoration: const InputDecoration(
                                  labelText: 'Tax',
                                  border: OutlineInputBorder(),
                                  prefixText: 'Rp ',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d+\.?\d{0,2}'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Total
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total:',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    'Rp ${(ref.read(cartProvider.notifier).total - (double.tryParse(_discountController.text) ?? 0) + (double.tryParse(_taxController.text) ?? 0)).toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Process Button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: _isProcessing
                                      ? null
                                      : _processTransaction,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16),
                                  ),
                                  child: _isProcessing
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Text('Process Transaction'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ReceiptDialog extends StatelessWidget {
  final TransactionModel transaction;
  final String storeName;
  final String storeAddress;
  final String cashierName;

  const ReceiptDialog({
    super.key,
    required this.transaction,
    required this.storeName,
    required this.storeAddress,
    required this.cashierName,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Receipt',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              transaction.generateReceiptContent(
                storeName: storeName,
                storeAddress: storeAddress,
                cashierName: cashierName,
              ),
              style: const TextStyle(fontFamily: 'Courier'),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement print functionality
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.print),
                  label: const Text('Print'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement email functionality
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.email),
                  label: const Text('Email'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // TODO: Implement WhatsApp functionality
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.whatsapp),
                  label: const Text('WhatsApp'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
