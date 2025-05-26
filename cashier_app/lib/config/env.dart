class Env {
  static const String supabaseUrl = 'YOUR_SUPABASE_URL';
  static const String supabaseKey = 'YOUR_SUPABASE_ANON_KEY';
  
  // Add other environment variables as needed
  static const bool isDevelopment = true;
  
  // Subscription package IDs
  static const String basicPackageId = 'basic_package';
  static const String proPackageId = 'pro_package';
  static const String premiumPackageId = 'premium_package';
  
  // Feature flags
  static const bool enablePrintReceipt = true;
  static const bool enableWhatsAppShare = true;
  static const bool enableEmailShare = true;
}
