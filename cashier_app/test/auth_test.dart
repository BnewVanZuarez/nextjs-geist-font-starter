import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import '../lib/models/user_model.dart';
import '../lib/providers/auth_provider.dart';
import '../lib/services/supabase_service.dart';

// Generate mock classes
@GenerateMocks([SupabaseClient, SupabaseAuth, Session, User, AuthResponse])
import 'auth_test.mocks.dart';

void main() {
  late MockSupabaseClient mockSupabaseClient;
  late MockSupabaseAuth mockSupabaseAuth;
  late ProviderContainer container;

  setUp(() {
    mockSupabaseClient = MockSupabaseClient();
    mockSupabaseAuth = MockSupabaseAuth();
    
    when(mockSupabaseClient.auth).thenReturn(mockSupabaseAuth);

    container = ProviderContainer(
      overrides: [
        supabaseServiceProvider.overrideWithValue(
          SupabaseService(),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  group('Authentication Tests', () {
    test('Initial auth state should be null', () {
      final authState = container.read(authNotifierProvider);
      expect(authState.value, null);
    });

    test('Sign in with valid credentials should succeed', () async {
      final mockSession = MockSession();
      final mockUser = MockUser();
      final mockAuthResponse = MockAuthResponse();

      when(mockUser.id).thenReturn('test-user-id');
      when(mockUser.email).thenReturn('test@example.com');
      when(mockSession.user).thenReturn(mockUser);
      when(mockAuthResponse.session).thenReturn(mockSession);
      when(mockAuthResponse.user).thenReturn(mockUser);

      when(mockSupabaseAuth.signInWithPassword(
        email: 'test@example.com',
        password: 'password123',
      )).thenAnswer((_) async => mockAuthResponse);

      final mockUserData = {
        'id': 'test-user-id',
        'email': 'test@example.com',
        'full_name': 'Test User',
        'role': 'kasir',
        'created_at': DateTime.now().toIso8601String(),
      };

      when(mockSupabaseClient.from('users').select<Map<String, dynamic>>())
          .thenAnswer((_) async => [mockUserData]);

      // Attempt sign in
      await container.read(authNotifierProvider.notifier).signIn(
        'test@example.com',
        'password123',
      );

      // Verify auth state
      final authState = container.read(authNotifierProvider);
      expect(authState.value, isNotNull);
      expect(authState.value?.email, 'test@example.com');
    });

    test('Sign in with invalid credentials should fail', () async {
      when(mockSupabaseAuth.signInWithPassword(
        email: 'invalid@example.com',
        password: 'wrongpassword',
      )).thenThrow(AuthException('Invalid credentials'));

      expect(
        () => container.read(authNotifierProvider.notifier).signIn(
          'invalid@example.com',
          'wrongpassword',
        ),
        throwsA(isA<AuthException>()),
      );
    });

    test('Sign out should clear auth state', () async {
      // Setup initial authenticated state
      final mockUser = UserModel(
        id: 'test-user-id',
        email: 'test@example.com',
        fullName: 'Test User',
        role: 'kasir',
        createdAt: DateTime.now(),
      );

      container = ProviderContainer(
        overrides: [
          authNotifierProvider
              .overrideWith((ref) => AuthNotifier(SupabaseService(), ref)..state = AsyncData(mockUser)),
        ],
      );

      when(mockSupabaseAuth.signOut()).thenAnswer((_) async => {});

      // Perform sign out
      await container.read(authNotifierProvider.notifier).signOut();

      // Verify auth state is cleared
      final authState = container.read(authNotifierProvider);
      expect(authState.value, null);
    });

    test('User role checks should work correctly', () {
      final adminUser = UserModel(
        id: 'admin-id',
        email: 'admin@example.com',
        fullName: 'Admin User',
        role: 'admin',
        createdAt: DateTime.now(),
      );

      final managerUser = UserModel(
        id: 'manager-id',
        email: 'manager@example.com',
        fullName: 'Manager User',
        role: 'manajer',
        createdAt: DateTime.now(),
      );

      final cashierUser = UserModel(
        id: 'cashier-id',
        email: 'cashier@example.com',
        fullName: 'Cashier User',
        role: 'kasir',
        createdAt: DateTime.now(),
      );

      expect(adminUser.isAdmin, true);
      expect(adminUser.isManager, false);
      expect(adminUser.isCashier, false);

      expect(managerUser.isAdmin, false);
      expect(managerUser.isManager, true);
      expect(managerUser.isCashier, false);

      expect(cashierUser.isAdmin, false);
      expect(cashierUser.isManager, false);
      expect(cashierUser.isCashier, true);
    });
  });
}
