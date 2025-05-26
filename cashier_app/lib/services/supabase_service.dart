import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Authentication Methods
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    String role = 'kasir',
  }) async {
    return await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'role': role,
      },
    );
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }

  // Store Management Methods
  Future<List<Map<String, dynamic>>> getStores() async {
    final response = await _supabase
        .from('stores')
        .select()
        .order('created_at');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> createStore({
    required String name,
    required String address,
    required String contact,
    required String adminId,
  }) async {
    final response = await _supabase.from('stores').insert({
      'name': name,
      'address': address,
      'contact': contact,
      'admin_id': adminId,
    }).select().single();
    return response;
  }

  Future<void> updateStore({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    await _supabase.from('stores').update(data).eq('id', id);
  }

  Future<void> deleteStore(String id) async {
    await _supabase.from('stores').delete().eq('id', id);
  }

  // Product Management Methods
  Future<List<Map<String, dynamic>>> getProducts(String storeId) async {
    final response = await _supabase
        .from('products')
        .select()
        .eq('store_id', storeId)
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> createProduct({
    required String storeId,
    required String name,
    required String category,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final response = await _supabase.from('products').insert({
      'store_id': storeId,
      'name': name,
      'category': category,
      'price': price,
      'stock': stock,
      'image_url': imageUrl,
    }).select().single();
    return response;
  }

  Future<void> updateProduct({
    required String id,
    required Map<String, dynamic> data,
  }) async {
    await _supabase.from('products').update(data).eq('id', id);
  }

  Future<void> deleteProduct(String id) async {
    await _supabase.from('products').delete().eq('id', id);
  }

  // Transaction Methods
  Future<Map<String, dynamic>> createTransaction({
    required String storeId,
    required String userId,
    required double totalAmount,
    double discount = 0,
    double tax = 0,
  }) async {
    final response = await _supabase.from('transactions').insert({
      'store_id': storeId,
      'user_id': userId,
      'total_amount': totalAmount,
      'discount': discount,
      'tax': tax,
    }).select().single();
    return response;
  }

  Future<List<Map<String, dynamic>>> getTransactions({
    required String storeId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase
        .from('transactions')
        .select()
        .eq('store_id', storeId)
        .gte('transaction_date', startDate.toIso8601String())
        .lte('transaction_date', endDate.toIso8601String())
        .order('transaction_date', ascending: false);
    return List<Map<String, dynamic>>.from(response);
  }

  // Customer Management Methods
  Future<List<Map<String, dynamic>>> getCustomers() async {
    final response = await _supabase
        .from('customers')
        .select()
        .order('name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> createCustomer({
    required String name,
    required String telephone,
    String? note,
  }) async {
    final response = await _supabase.from('customers').insert({
      'name': name,
      'telephone': telephone,
      'note': note,
    }).select().single();
    return response;
  }

  // Subscription Methods
  Future<Map<String, dynamic>> getCurrentSubscription(String userId) async {
    final response = await _supabase
        .from('subscriptions')
        .select()
        .eq('user_id', userId)
        .lte('start_date', DateTime.now().toIso8601String())
        .gte('end_date', DateTime.now().toIso8601String())
        .single();
    return response;
  }

  Future<Map<String, dynamic>> createSubscription({
    required String userId,
    required String package,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase.from('subscriptions').insert({
      'user_id': userId,
      'package': package,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
    }).select().single();
    return response;
  }

  // User Management Methods
  Future<List<Map<String, dynamic>>> getUsers() async {
    final response = await _supabase
        .from('users')
        .select()
        .order('full_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> updateUserRole({
    required String userId,
    required String role,
  }) async {
    await _supabase.from('users').update({
      'role': role,
    }).eq('id', userId);
  }
}
