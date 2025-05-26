import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_model.dart';
import '../services/supabase_service.dart';

// Provider for the Supabase service
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

// Provider for the current auth state
final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

// Provider for the current user session
final sessionProvider = StateProvider<Session?>((ref) {
  return Supabase.instance.client.auth.currentSession;
});

// Provider for the current user model
final currentUserProvider = FutureProvider<UserModel?>((ref) async {
  final session = ref.watch(sessionProvider);
  if (session == null) return null;

  try {
    final response = await Supabase.instance.client
        .from('users')
        .select()
        .eq('id', session.user.id)
        .single();
    
    return UserModel.fromJson(response);
  } catch (e) {
    print('Error fetching user data: $e');
    return null;
  }
});

// Auth notifier to handle authentication state
class AuthNotifier extends StateNotifier<AsyncValue<UserModel?>> {
  final SupabaseService _supabaseService;
  final Ref _ref;

  AuthNotifier(this._supabaseService, this._ref) : super(const AsyncValue.loading()) {
    // Initialize the state
    _init();
  }

  Future<void> _init() async {
    final session = _ref.read(sessionProvider);
    if (session == null) {
      state = const AsyncValue.data(null);
      return;
    }

    // Fetch user data
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select()
          .eq('id', session.user.id)
          .single();
      
      state = AsyncValue.data(UserModel.fromJson(response));
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
    }
  }

  Future<void> signIn(String email, String password) async {
    try {
      state = const AsyncValue.loading();
      final response = await _supabaseService.signIn(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', response.user!.id)
            .single();
        
        state = AsyncValue.data(UserModel.fromJson(userData));
        _ref.read(sessionProvider.notifier).state = response.session;
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> signUp(String email, String password, String fullName) async {
    try {
      state = const AsyncValue.loading();
      final response = await _supabaseService.signUp(
        email: email,
        password: password,
        fullName: fullName,
      );
      
      if (response.user != null) {
        final userData = await Supabase.instance.client
            .from('users')
            .select()
            .eq('id', response.user!.id)
            .single();
        
        state = AsyncValue.data(UserModel.fromJson(userData));
        _ref.read(sessionProvider.notifier).state = response.session;
      }
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _supabaseService.signOut();
      state = const AsyncValue.data(null);
      _ref.read(sessionProvider.notifier).state = null;
    } catch (e) {
      state = AsyncValue.error(e, StackTrace.current);
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _supabaseService.resetPassword(email);
    } catch (e) {
      rethrow;
    }
  }

  // Check if user has admin privileges
  bool get isAdmin => state.value?.isAdmin ?? false;

  // Check if user has manager privileges
  bool get isManager => state.value?.isManager ?? false;

  // Check if user is a cashier
  bool get isCashier => state.value?.isCashier ?? false;
}

// Provider for auth notifier
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AsyncValue<UserModel?>>((ref) {
  final supabaseService = ref.watch(supabaseServiceProvider);
  return AuthNotifier(supabaseService, ref);
});

// Provider to check if user is authenticated
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.value?.session != null;
});

// Provider to get user role
final userRoleProvider = Provider<String?>((ref) {
  final user = ref.watch(currentUserProvider);
  return user.value?.role;
});
