// Copy this file to env.dart and replace with your actual Supabase credentials
class Env {
  // Your Supabase project URL (found in your project settings)
  static const String supabaseUrl = 'https://your-project.supabase.co';
  
  // Your Supabase anon/public key (found in your project settings)
  static const String supabaseKey = 'your-anon-key';
  
  // Feature flags
  static const bool isDevelopment = true;
  
  // Subscription package IDs (customize as needed)
  static const String basicPackageId = 'basic_package';
  static const String proPackageId = 'pro_package';
  static const String premiumPackageId = 'premium_package';
  
  // Receipt sharing options
  static const bool enablePrintReceipt = true;
  static const bool enableWhatsAppShare = true;
  static const bool enableEmailShare = true;
  
  // API endpoints (if using additional services)
  static const String apiBaseUrl = 'https://api.example.com';
  
  // Cache configuration
  static const int maxCacheAge = 3600; // 1 hour in seconds
  
  // Pagination defaults
  static const int defaultPageSize = 20;
  
  // Image upload limits
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> allowedImageTypes = ['jpg', 'jpeg', 'png'];
  
  // Stock threshold for low stock warnings
  static const int lowStockThreshold = 10;
  
  // Transaction settings
  static const double defaultTaxRate = 0.11; // 11% tax
  static const int receiptValidityDays = 30;
  
  // Session configuration
  static const int sessionTimeout = 3600; // 1 hour in seconds
  static const bool requireEmailVerification = true;
  
  // Password policy
  static const int minPasswordLength = 8;
  static const bool requireSpecialCharacters = true;
  static const bool requireNumbers = true;
  static const bool requireUppercase = true;
  
  // Rate limiting
  static const int maxLoginAttempts = 5;
  static const int loginLockoutDuration = 300; // 5 minutes in seconds
}
