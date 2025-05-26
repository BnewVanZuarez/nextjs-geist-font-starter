# Security Guide

This document outlines security measures and best practices implemented in the Kasir App.

## Authentication & Authorization

### JWT Authentication

```dart
// Example of secure JWT handling
class AuthService {
  final storage = const FlutterSecureStorage();
  
  Future<void> storeToken(String token) async {
    await storage.write(
      key: 'jwt_token',
      value: token,
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.first_unlock,
      ),
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    );
  }
}
```

### Role-Based Access Control (RBAC)

```dart
enum UserRole { admin, manager, cashier }

class RoleBasedAccess {
  static bool canAccessFeature(UserRole role, Feature feature) {
    switch (feature) {
      case Feature.manageUsers:
        return role == UserRole.admin;
      case Feature.manageProducts:
        return role == UserRole.admin || role == UserRole.manager;
      case Feature.processSales:
        return true; // All roles can process sales
    }
  }
}
```

## Data Security

### Encryption at Rest

- Use Flutter Secure Storage for sensitive data
- Encrypt local database using SQLCipher
- Hash passwords using bcrypt

### Data in Transit

- Use HTTPS for all API calls
- Certificate pinning
- Encrypt sensitive payloads

```dart
class ApiClient {
  static const String certificateHash = 'sha256/HASH';
  
  bool isValidCertificate(X509Certificate cert, String host) {
    final fingerprint = sha256.convert(cert.der).toString();
    return fingerprint == certificateHash;
  }
}
```

## Input Validation

### Form Validation

```dart
class InputValidator {
  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Email is required';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Invalid email format';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }
    if (value.length < 8) {
      return 'Password must be at least 8 characters';
    }
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'Password must contain uppercase letters';
    }
    if (!RegExp(r'[0-9]').hasMatch(value)) {
      return 'Password must contain numbers';
    }
    return null;
  }
}
```

### SQL Injection Prevention

- Use parameterized queries
- Validate and sanitize input
- Use ORM features

```dart
// Good: Using parameterized queries
Future<List<Product>> searchProducts(String query) async {
  return await supabase
    .from('products')
    .select()
    .ilike('name', '%$query%')
    .execute();
}

// Bad: Don't concatenate strings
Future<List<Product>> searchProducts(String query) async {
  return await supabase
    .from('products')
    .select()
    .execute('SELECT * FROM products WHERE name LIKE %$query%'); // Vulnerable!
}
```

## Session Management

### Session Handling

```dart
class SessionManager {
  static const sessionTimeout = Duration(hours: 24);
  
  Future<bool> isSessionValid() async {
    final lastActivity = await getLastActivity();
    if (lastActivity == null) return false;
    
    return DateTime.now().difference(lastActivity) < sessionTimeout;
  }
  
  Future<void> refreshSession() async {
    await updateLastActivity(DateTime.now());
  }
  
  Future<void> invalidateSession() async {
    await clearSessionData();
  }
}
```

### Token Management

```dart
class TokenManager {
  Future<void> rotateToken(String currentToken) async {
    try {
      final newToken = await refreshAccessToken(currentToken);
      await storeToken(newToken);
    } catch (e) {
      await forceLogout();
    }
  }
}
```

## Error Handling

### Secure Error Messages

```dart
class SecureErrorHandler {
  static String getPublicErrorMessage(Exception error) {
    // Log detailed error for debugging
    logError(error);
    
    // Return safe message to user
    return 'An error occurred. Please try again later.';
  }
}
```

## Audit Logging

### Activity Logging

```dart
class AuditLogger {
  Future<void> logActivity({
    required String userId,
    required String action,
    required String resource,
    Map<String, dynamic>? details,
  }) async {
    await supabase.from('audit_logs').insert({
      'user_id': userId,
      'action': action,
      'resource': resource,
      'details': details,
      'ip_address': await getCurrentIpAddress(),
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

## Security Headers

### HTTP Security Headers

```nginx
# In nginx.conf
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Content-Security-Policy "default-src 'self';" always;
```

## Rate Limiting

### API Rate Limiting

```dart
class RateLimiter {
  final _cache = <String, List<DateTime>>{};
  
  bool shouldAllowRequest(String userId) {
    final now = DateTime.now();
    final userRequests = _cache[userId] ?? [];
    
    // Remove old requests
    userRequests.removeWhere(
      (time) => now.difference(time) > const Duration(minutes: 1)
    );
    
    // Check rate limit (100 requests per minute)
    if (userRequests.length >= 100) {
      return false;
    }
    
    // Add new request
    userRequests.add(now);
    _cache[userId] = userRequests;
    return true;
  }
}
```

## File Upload Security

### Secure File Uploads

```dart
class FileUploader {
  static const _maxFileSize = 5 * 1024 * 1024; // 5MB
  static const _allowedTypes = ['image/jpeg', 'image/png'];
  
  Future<bool> isFileValid(File file) async {
    if (await file.length() > _maxFileSize) {
      return false;
    }
    
    final mimeType = lookupMimeType(file.path);
    return _allowedTypes.contains(mimeType);
  }
}
```

## Security Checklist

### Development
- [ ] Use latest dependencies
- [ ] Enable strict analysis options
- [ ] Implement proper error handling
- [ ] Use secure storage for sensitive data
- [ ] Implement input validation
- [ ] Use parameterized queries
- [ ] Implement rate limiting
- [ ] Set up security headers
- [ ] Configure CORS properly
- [ ] Implement audit logging

### Deployment
- [ ] Enable HTTPS
- [ ] Configure firewall rules
- [ ] Set up monitoring
- [ ] Configure backup system
- [ ] Set up alerting
- [ ] Review security logs
- [ ] Update SSL certificates
- [ ] Review access controls

### Regular Maintenance
- [ ] Update dependencies
- [ ] Review security logs
- [ ] Audit user permissions
- [ ] Test backup restoration
- [ ] Review rate limits
- [ ] Check SSL configuration
- [ ] Review error logs
- [ ] Update security policies

## Incident Response

1. **Detection**
   - Monitor logs
   - Set up alerts
   - Review metrics

2. **Response**
   - Isolate affected systems
   - Assess damage
   - Fix vulnerabilities
   - Restore from backup

3. **Recovery**
   - Verify fixes
   - Update documentation
   - Notify stakeholders
   - Implement preventive measures

## Resources

- [Flutter Security Best Practices](https://flutter.dev/security)
- [Supabase Security Documentation](https://supabase.com/docs/security)
- [OWASP Mobile Security Testing Guide](https://owasp.org/www-project-mobile-security-testing-guide/)
- [Common Flutter Security Pitfalls](https://medium.com/flutter-community/flutter-security-pitfalls-and-best-practices-3b82ce24910b)
