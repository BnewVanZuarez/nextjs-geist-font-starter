import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/store_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Provider for stores
final storesProvider = FutureProvider<List<StoreModel>>((ref) async {
  final supabase = ref.watch(supabaseServiceProvider);
  final stores = await supabase.getStores();
  return stores.map((store) => StoreModel.fromJson(store)).toList();
});

class StoreManagementPage extends ConsumerStatefulWidget {
  const StoreManagementPage({super.key});

  @override
  ConsumerState<StoreManagementPage> createState() => _StoreManagementPageState();
}

class _StoreManagementPageState extends ConsumerState<StoreManagementPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _contactController = TextEditingController();
  
  StoreModel? _selectedStore;
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _addressController.clear();
    _contactController.clear();
    _selectedStore = null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(currentUserProvider).value;
      if (user == null) throw Exception('User not found');

      if (_selectedStore == null) {
        // Create new store
        await ref.read(supabaseServiceProvider).createStore(
          name: _nameController.text.trim(),
          address: _addressController.text.trim(),
          contact: _contactController.text.trim(),
          adminId: user.id,
        );
      } else {
        // Update existing store
        await ref.read(supabaseServiceProvider).updateStore(
          id: _selectedStore!.id,
          data: {
            'name': _nameController.text.trim(),
            'address': _addressController.text.trim(),
            'contact': _contactController.text.trim(),
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _selectedStore == null
                  ? 'Store created successfully'
                  : 'Store updated successfully',
            ),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
        ref.refresh(storesProvider);
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

  Future<void> _handleDelete(StoreModel store) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Store'),
        content: Text('Are you sure you want to delete ${store.name}?'),
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
      await ref.read(supabaseServiceProvider).deleteStore(store.id);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Store deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
        ref.refresh(storesProvider);
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

  void _editStore(StoreModel store) {
    setState(() {
      _selectedStore = store;
      _nameController.text = store.name;
      _addressController.text = store.address;
      _contactController.text = store.contact;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storesAsync = ref.watch(storesProvider);
    final user = ref.watch(currentUserProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _isLoading ? null : _resetForm,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Store List
                Expanded(
                  flex: 2,
                  child: storesAsync.when(
                    data: (stores) => stores.isEmpty
                        ? const Center(
                            child: Text('No stores found'),
                          )
                        : ListView.builder(
                            itemCount: stores.length,
                            itemBuilder: (context, index) {
                              final store = stores[index];
                              final isSelected = store.id == _selectedStore?.id;

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
                                  title: Text(store.name),
                                  subtitle: Text(store.address),
                                  trailing: user?.isAdmin == true ||
                                          store.isAdmin(user?.id ?? '')
                                      ? Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.edit),
                                              onPressed: () => _editStore(store),
                                            ),
                                            IconButton(
                                              icon: const Icon(Icons.delete),
                                              onPressed: () =>
                                                  _handleDelete(store),
                                            ),
                                          ],
                                        )
                                      : null,
                                  onTap: () => _editStore(store),
                                ),
                              );
                            },
                          ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, stack) => Center(
                      child: Text('Error: ${error.toString()}'),
                    ),
                  ),
                ),

                // Form
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
                            _selectedStore == null
                                ? 'Add New Store'
                                : 'Edit Store',
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 24),
                          
                          // Name Field
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Store Name',
                              hintText: 'Enter store name',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter store name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Address Field
                          TextFormField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              hintText: 'Enter store address',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter store address';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          // Contact Field
                          TextFormField(
                            controller: _contactController,
                            decoration: const InputDecoration(
                              labelText: 'Contact',
                              hintText: 'Enter contact information',
                              border: OutlineInputBorder(),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter contact information';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Submit Button
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: Text(
                              _selectedStore == null ? 'Create Store' : 'Update Store',
                            ),
                          ),
                          if (_selectedStore != null) ...[
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: _isLoading ? null : _resetForm,
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
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
    );
  }
}
