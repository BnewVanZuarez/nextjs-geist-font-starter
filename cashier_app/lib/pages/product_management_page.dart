import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product_model.dart';
import '../models/store_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Provider for products of the selected store
final productsProvider = FutureProvider.family<List<ProductModel>, String>(
  (ref, storeId) async {
    final supabase = ref.watch(supabaseServiceProvider);
    final products = await supabase.getProducts(storeId);
    return products.map((product) => ProductModel.fromJson(product)).toList();
  },
);

class ProductManagementPage extends ConsumerStatefulWidget {
  const ProductManagementPage({super.key});

  @override
  ConsumerState<ProductManagementPage> createState() => _ProductManagementPageState();
}

class _ProductManagementPageState extends ConsumerState<ProductManagementPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _categoryController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _imageUrlController = TextEditingController();
  
  ProductModel? _selectedProduct;
  StoreModel? _selectedStore;
  bool _isLoading = false;
  String? _searchQuery;

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _imageUrlController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _categoryController.clear();
    _priceController.clear();
    _stockController.clear();
    _imageUrlController.clear();
    _selectedProduct = null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a store first'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedProduct == null) {
        // Create new product
        await ref.read(supabaseServiceProvider).createProduct(
          storeId: _selectedStore!.id,
          name: _nameController.text.trim(),
          category: _categoryController.text.trim(),
          price: double.parse(_priceController.text),
          stock: int.parse(_stockController.text),
          imageUrl: _imageUrlController.text.trim(),
        );
      } else {
        // Update existing product
        await ref.read(supabaseServiceProvider).updateProduct(
          id: _selectedProduct!.id,
          data: {
            'name': _nameController.text.trim(),
            'category': _categoryController.text.trim(),
            'price': double.parse(_priceController.text),
            'stock': int.parse(_stockController.text),
            'image_url': _imageUrlController.text.trim(),
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedProduct == null
                  ? 'Product created successfully'
                  : 'Product updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
        ref.refresh(productsProvider(_selectedStore!.id));
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
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleDelete(ProductModel product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete ${product.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(supabaseServiceProvider).deleteProduct(product.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        ref.refresh(productsProvider(_selectedStore!.id));
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
        setState(() => _isLoading = false);
      }
    }
  }

  void _editProduct(ProductModel product) {
    setState(() {
      _selectedProduct = product;
      _nameController.text = product.name;
      _categoryController.text = product.category;
      _priceController.text = product.price.toString();
      _stockController.text = product.stock.toString();
      _imageUrlController.text = product.imageUrl ?? '';
    });
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

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(storesProvider);
    final productsAsync = _selectedStore != null
        ? ref.watch(productsProvider(_selectedStore!.id))
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _isLoading ? null : _resetForm,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                                _resetForm();
                              });
                            },
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
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

                // Products List and Form
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Products List
                      Expanded(
                        flex: 2,
                        child: _selectedStore == null
                            ? const Center(
                                child: Text('Please select a store'),
                              )
                            : productsAsync!.when(
                                data: (products) {
                                  final filteredProducts =
                                      _filterProducts(products);
                                  return filteredProducts.isEmpty
                                      ? const Center(
                                          child: Text('No products found'),
                                        )
                                      : ListView.builder(
                                          itemCount: filteredProducts.length,
                                          itemBuilder: (context, index) {
                                            final product = filteredProducts[index];
                                            final isSelected = product.id ==
                                                _selectedProduct?.id;

                                            return Card(
                                              margin: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                              color: isSelected
                                                  ? Theme.of(context)
                                                      .colorScheme
                                                      .primaryContainer
                                                  : null,
                                              child: ListTile(
                                                leading: product.imageUrl != null
                                                    ? Image.network(
                                                        product.imageUrl!,
                                                        width: 50,
                                                        height: 50,
                                                        fit: BoxFit.cover,
                                                        errorBuilder: (context,
                                                                error,
                                                                stackTrace) =>
                                                            const Icon(
                                                                Icons.image),
                                                      )
                                                    : const Icon(Icons.inventory),
                                                title: Text(product.name),
                                                subtitle: Text(
                                                    '${product.category} - ${product.formattedPrice}'),
                                                trailing: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      'Stock: ${product.stock}',
                                                      style: TextStyle(
                                                        color: product.isLowStock
                                                            ? Colors.red
                                                            : null,
                                                        fontWeight:
                                                            product.isLowStock
                                                                ? FontWeight.bold
                                                                : null,
                                                      ),
                                                    ),
                                                    IconButton(
                                                      icon:
                                                          const Icon(Icons.edit),
                                                      onPressed: () =>
                                                          _editProduct(product),
                                                    ),
                                                    IconButton(
                                                      icon:
                                                          const Icon(Icons.delete),
                                                      onPressed: () =>
                                                          _handleDelete(product),
                                                    ),
                                                  ],
                                                ),
                                                onTap: () => _editProduct(product),
                                              ),
                                            );
                                          },
                                        );
                                },
                                loading: () => const Center(
                                    child: CircularProgressIndicator()),
                                error: (error, stack) => Center(
                                  child: Text('Error: ${error.toString()}'),
                                ),
                              ),
                      ),

                      // Product Form
                      if (_selectedStore != null)
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    _selectedProduct == null
                                        ? 'Add New Product'
                                        : 'Edit Product',
                                    style:
                                        Theme.of(context).textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 24),

                                  // Name Field
                                  TextFormField(
                                    controller: _nameController,
                                    decoration: const InputDecoration(
                                      labelText: 'Product Name',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter product name';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Category Field
                                  TextFormField(
                                    controller: _categoryController,
                                    decoration: const InputDecoration(
                                      labelText: 'Category',
                                      border: OutlineInputBorder(),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter category';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Price Field
                                  TextFormField(
                                    controller: _priceController,
                                    decoration: const InputDecoration(
                                      labelText: 'Price',
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
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter price';
                                      }
                                      if (double.tryParse(value) == null) {
                                        return 'Please enter a valid price';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Stock Field
                                  TextFormField(
                                    controller: _stockController,
                                    decoration: const InputDecoration(
                                      labelText: 'Stock',
                                      border: OutlineInputBorder(),
                                    ),
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                    ],
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter stock quantity';
                                      }
                                      if (int.tryParse(value) == null) {
                                        return 'Please enter a valid number';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),

                                  // Image URL Field
                                  TextFormField(
                                    controller: _imageUrlController,
                                    decoration: const InputDecoration(
                                      labelText: 'Image URL (optional)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                  const SizedBox(height: 24),

                                  // Submit Button
                                  ElevatedButton(
                                    onPressed: _isLoading ? null : _handleSubmit,
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                    ),
                                    child: Text(
                                      _selectedProduct == null
                                          ? 'Create Product'
                                          : 'Update Product',
                                    ),
                                  ),
                                  if (_selectedProduct != null) ...[
                                    const SizedBox(height: 16),
                                    OutlinedButton(
                                      onPressed: _isLoading ? null : _resetForm,
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                      ),
                                      child: const Text('Cancel Edit'),
                                    ),
                                  ],
                                ],
                              ),
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
