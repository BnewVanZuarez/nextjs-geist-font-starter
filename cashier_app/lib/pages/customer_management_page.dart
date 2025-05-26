import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/customer_model.dart';
import '../providers/auth_provider.dart';
import '../services/supabase_service.dart';

// Provider for customers
final customersProvider = FutureProvider<List<CustomerModel>>((ref) async {
  final supabase = ref.watch(supabaseServiceProvider);
  final customers = await supabase.getCustomers();
  return customers.map((customer) => CustomerModel.fromJson(customer)).toList();
});

class CustomerManagementPage extends ConsumerStatefulWidget {
  const CustomerManagementPage({super.key});

  @override
  ConsumerState<CustomerManagementPage> createState() => _CustomerManagementPageState();
}

class _CustomerManagementPageState extends ConsumerState<CustomerManagementPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _telephoneController = TextEditingController();
  final _noteController = TextEditingController();
  
  CustomerModel? _selectedCustomer;
  bool _isLoading = false;
  String? _searchQuery;

  @override
  void dispose() {
    _nameController.dispose();
    _telephoneController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _nameController.clear();
    _telephoneController.clear();
    _noteController.clear();
    _selectedCustomer = null;
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(supabaseServiceProvider).createCustomer(
        name: _nameController.text.trim(),
        telephone: _telephoneController.text.trim(),
        note: _noteController.text.trim(),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer added successfully'),
            backgroundColor: Colors.green,
          ),
        );
        _resetForm();
        ref.refresh(customersProvider);
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

  List<CustomerModel> _filterCustomers(List<CustomerModel> customers) {
    if (_searchQuery == null || _searchQuery!.isEmpty) {
      return customers;
    }

    final query = _searchQuery!.toLowerCase();
    return customers.where((customer) {
      return customer.name.toLowerCase().contains(query) ||
          customer.telephone.contains(query);
    }).toList();
  }

  void _showCustomerDetails(CustomerModel customer) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer.name),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.phone),
                title: const Text('Phone'),
                subtitle: Text(customer.formattedTelephone),
                trailing: IconButton(
                  icon: const Icon(Icons.whatsapp),
                  onPressed: () {
                    // TODO: Implement WhatsApp integration
                  },
                ),
              ),
              if (customer.note != null && customer.note!.isNotEmpty)
                ListTile(
                  leading: const Icon(Icons.note),
                  title: const Text('Note'),
                  subtitle: Text(customer.note!),
                ),
              ListTile(
                leading: const Icon(Icons.shopping_bag),
                title: const Text('Total Transactions'),
                subtitle: Text('${customer.transactionCount}'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customer Management'),
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
                // Customer List
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      // Search Bar
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: TextField(
                          decoration: const InputDecoration(
                            labelText: 'Search Customers',
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

                      // Customer List
                      Expanded(
                        child: customersAsync.when(
                          data: (customers) {
                            final filteredCustomers = _filterCustomers(customers);
                            return filteredCustomers.isEmpty
                                ? const Center(
                                    child: Text('No customers found'),
                                  )
                                : ListView.builder(
                                    itemCount: filteredCustomers.length,
                                    itemBuilder: (context, index) {
                                      final customer = filteredCustomers[index];
                                      return Card(
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        child: ListTile(
                                          leading: const CircleAvatar(
                                            child: Icon(Icons.person),
                                          ),
                                          title: Text(customer.name),
                                          subtitle: Text(customer.formattedTelephone),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.whatsapp),
                                                onPressed: () {
                                                  // TODO: Implement WhatsApp integration
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.info),
                                                onPressed: () => _showCustomerDetails(customer),
                                              ),
                                            ],
                                          ),
                                          onTap: () => _showCustomerDetails(customer),
                                        ),
                                      );
                                    },
                                  );
                          },
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (error, stack) => Center(
                            child: Text('Error: ${error.toString()}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Add Customer Form
                SizedBox(
                  width: 400,
                  child: Card(
                    margin: const EdgeInsets.all(16),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Add New Customer',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 24),

                            // Name Field
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter customer name';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Telephone Field
                            TextFormField(
                              controller: _telephoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.phone),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter phone number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // Note Field
                            TextFormField(
                              controller: _noteController,
                              decoration: const InputDecoration(
                                labelText: 'Note (Optional)',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.note),
                              ),
                              maxLines: 3,
                            ),
                            const SizedBox(height: 24),

                            // Submit Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleSubmit,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 16),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Add Customer'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
