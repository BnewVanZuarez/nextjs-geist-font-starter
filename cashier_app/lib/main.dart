import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/env.dart';
import 'pages/auth/login_page.dart';
import 'pages/auth/register_page.dart';
import 'pages/auth/forgot_password_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/store_management_page.dart';
import 'pages/product_management_page.dart';
import 'pages/cashier_page.dart';
import 'pages/customer_management_page.dart';
import 'pages/subscription_page.dart';
import 'pages/user_management_page.dart';
import 'providers/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseKey,
  );
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/register',
          builder: (context, state) => const RegisterPage(),
        ),
        GoRoute(
          path: '/forgot-password',
          builder: (context, state) => const ForgotPasswordPage(),
        ),
        GoRoute(
          path: '/dashboard',
          builder: (context, state) => const DashboardPage(),
        ),
        GoRoute(
          path: '/stores',
          builder: (context, state) => const StoreManagementPage(),
        ),
        GoRoute(
          path: '/products',
          builder: (context, state) => const ProductManagementPage(),
        ),
        GoRoute(
          path: '/cashier',
          builder: (context, state) => const CashierPage(),
        ),
        GoRoute(
          path: '/customers',
          builder: (context, state) => const CustomerManagementPage(),
        ),
        GoRoute(
          path: '/subscription',
          builder: (context, state) => const SubscriptionPage(),
        ),
        GoRoute(
          path: '/users',
          builder: (context, state) => const UserManagementPage(),
        ),
      ],
      redirect: (context, state) {
        final isAuthenticated = ref.read(isAuthenticatedProvider);
        final isAuthPage = state.location == '/' || 
                          state.location == '/register' || 
                          state.location == '/forgot-password';

        if (!isAuthenticated && !isAuthPage) {
          return '/';
        }

        if (isAuthenticated && isAuthPage) {
          return '/dashboard';
        }

        return null;
      },
    );

    return MaterialApp.router(
      title: 'Kasir App',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 12,
            ),
          ),
        ),
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
