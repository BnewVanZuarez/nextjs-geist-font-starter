# Troubleshooting Guide

This guide covers common issues and their solutions for the Kasir App.

## Development Issues

### Flutter Setup

#### Flutter Not Found
```bash
Error: flutter: command not found
```

**Solution:**
1. Verify Flutter installation:
   ```bash
   which flutter
   ```
2. Add Flutter to PATH:
   ```bash
   export PATH="$PATH:`pwd`/flutter/bin"
   ```
3. Verify installation:
   ```bash
   flutter doctor
   ```

#### Dependency Issues
```bash
Error: Dependencies not resolved
```

**Solution:**
```bash
# Clean pub cache
flutter pub cache clean

# Get dependencies
flutter pub get

# Update dependencies
flutter pub upgrade
```

### Build Errors

#### Code Generation Failures
```bash
Error: Target of URI hasn't been generated: 'package:kasir_app/models/product.freezed.dart'
```

**Solution:**
```bash
# Clean project
flutter clean

# Get dependencies
flutter pub get

# Run build runner
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

#### Compilation Errors
```bash
Error: Compilation failed
```

**Solution:**
1. Check syntax errors
2. Update Flutter:
   ```bash
   flutter upgrade
   ```
3. Clean and rebuild:
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

## Docker Issues

### Container Startup

#### Port Already in Use
```bash
Error: listen tcp :8000: bind: address already in use
```

**Solution:**
```bash
# Find process using port 8000
sudo lsof -i :8000

# Kill the process
kill -9 <PID>

# Or stop all containers
docker-compose down
```

#### Container Fails to Start
```bash
Error: Container exited with code 1
```

**Solution:**
1. Check logs:
   ```bash
   docker-compose logs web
   ```
2. Verify environment variables:
   ```bash
   cat .env
   ```
3. Rebuild container:
   ```bash
   docker-compose build --no-cache web
   ```

## Database Issues

### Connection Errors

#### Supabase Connection Failed
```dart
Error: Connection refused
```

**Solution:**
1. Check Supabase credentials in `env.dart`
2. Verify network connection
3. Check Supabase service status
4. Test connection:
   ```dart
   try {
     await supabase.from('products').select().limit(1);
     print('Connection successful');
   } catch (e) {
     print('Connection failed: $e');
   }
   ```

#### Authentication Failed
```dart
Error: Invalid JWT token
```

**Solution:**
1. Check token expiration
2. Verify Supabase anon key
3. Clear local storage:
   ```dart
   await storage.deleteAll();
   ```
4. Re-authenticate user

## State Management

### Provider Issues

#### Provider Not Found
```dart
Error: ProviderNotFoundException
```

**Solution:**
1. Wrap widget with `ProviderScope`:
   ```dart
   void main() {
     runApp(
       const ProviderScope(
         child: MyApp(),
       ),
     );
   }
   ```
2. Check provider definition
3. Verify provider dependencies

#### State Not Updating
```dart
// UI not reflecting state changes
```

**Solution:**
1. Use `ref.watch` instead of `ref.read`
2. Implement proper state updates:
   ```dart
   class CounterNotifier extends StateNotifier<int> {
     CounterNotifier() : super(0);
     
     void increment() {
       state = state + 1; // Correct
       // state++; // Incorrect
     }
   }
   ```

## UI Issues

### Layout Problems

#### Overflow Errors
```
A RenderFlex overflowed by 123 pixels on the bottom
```

**Solution:**
1. Wrap with `SingleChildScrollView`
2. Use `Expanded` or `Flexible`
3. Constrain dimensions:
   ```dart
   SizedBox(
     height: 200,
     child: ListView(
       children: [...],
     ),
   )
   ```

#### Responsive Layout Issues
```
Layout not adapting to screen size
```

**Solution:**
1. Use `LayoutBuilder`:
   ```dart
   LayoutBuilder(
     builder: (context, constraints) {
       if (constraints.maxWidth < 600) {
         return MobileLayout();
       }
       return DesktopLayout();
     },
   )
   ```
2. Implement responsive values:
   ```dart
   final width = MediaQuery.of(context).size.width;
   final padding = width > 600 ? 32.0 : 16.0;
   ```

## Performance Issues

### Memory Leaks

#### Widget Disposal
```dart
Error: setState() called after dispose()
```

**Solution:**
1. Cancel subscriptions:
   ```dart
   @override
   void dispose() {
     _subscription?.cancel();
     super.dispose();
   }
   ```
2. Use `mounted` check:
   ```dart
   if (mounted) setState(() {});
   ```

#### Resource Management
```
High memory usage
```

**Solution:**
1. Dispose controllers:
   ```dart
   @override
   void dispose() {
     _controller.dispose();
     super.dispose();
   }
   ```
2. Clear caches when needed:
   ```dart
   ImageCache().clear();
   ImageCache().clearLiveImages();
   ```

### Slow Performance

#### UI Jank
```
Frames dropping, UI not smooth
```

**Solution:**
1. Use `const` widgets
2. Implement pagination
3. Cache expensive computations:
   ```dart
   final expensiveValue = useMemoized(() {
     return compute(expensiveOperation);
   }, [dependencies]);
   ```

## Network Issues

### API Calls

#### Timeout Errors
```dart
Error: Connection timed out
```

**Solution:**
1. Implement retry logic:
   ```dart
   Future<T> withRetry<T>(Future<T> Function() fn) async {
     for (var i = 0; i < 3; i++) {
       try {
         return await fn();
       } catch (e) {
         if (i == 2) rethrow;
         await Future.delayed(Duration(seconds: 1 << i));
       }
     }
     throw Exception('Retry failed');
   }
   ```
2. Add timeout:
   ```dart
   await Future.timeout(
     apiCall(),
     const Duration(seconds: 30),
   );
   ```

#### Offline Handling
```dart
Error: No internet connection
```

**Solution:**
1. Check connectivity:
   ```dart
   final connectivity = await Connectivity().checkConnectivity();
   if (connectivity == ConnectivityResult.none) {
     // Handle offline state
   }
   ```
2. Implement offline storage:
   ```dart
   final box = await Hive.openBox('offline_data');
   await box.put('key', data);
   ```

## Error Reporting

### Logging

#### Debug Information
```dart
void logError(dynamic error, StackTrace? stackTrace) {
  // Development
  print('Error: $error\n$stackTrace');
  
  // Production
  Sentry.captureException(error, stackTrace: stackTrace);
}
```

#### Error Boundaries
```dart
class ErrorBoundary extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ErrorWidget.builder = (details) {
      return Scaffold(
        body: Center(
          child: Text('Something went wrong: ${details.exception}'),
        ),
      );
    };
  }
}
```

## Support Resources

1. Check documentation in `/docs`
2. Search GitHub Issues
3. Join Discord community
4. Contact support team

For critical issues:
1. Gather logs and error messages
2. Document reproduction steps
3. Create detailed bug report
4. Follow up with support team
