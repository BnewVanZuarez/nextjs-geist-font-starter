# Getting Started with Kasir App

This guide will help you set up and run the Kasir App for development or production use.

## Prerequisites

### Docker Setup (Recommended)
- Docker Engine 20.10.0 or higher
- Docker Compose 2.0.0 or higher
- 4GB RAM minimum
- 10GB free disk space

### Manual Setup
- Flutter SDK 3.16.0 or higher
- Dart SDK 3.0.0 or higher
- IDE (VS Code or Android Studio)
- Git
- 8GB RAM minimum
- 20GB free disk space

## Installation Steps

### 1. Clone the Repository
```bash
git clone https://github.com/yourusername/cashier_app.git
cd cashier_app
```

### 2. Set Up Environment Variables

#### Using Docker
```bash
cp .env.example .env
# Edit .env with your Supabase credentials
```

#### Manual Setup
```bash
cp lib/config/env.example.dart lib/config/env.dart
# Edit env.dart with your Supabase credentials
```

### 3. Start the Application

#### Using Docker
```bash
# Production mode
./scripts/docker.sh start

# Development mode with hot-reload
./scripts/docker.sh dev
```

#### Manual Setup
```bash
# Install dependencies
flutter pub get

# Generate code
flutter pub run build_runner build --delete-conflicting-outputs

# Run the app
flutter run
```

## Initial Configuration

### 1. Database Setup
1. Create a Supabase project at https://supabase.com
2. Go to Project Settings > Database
3. Copy the SQL from `scripts/setup_db.sql`
4. Run the SQL in Supabase's SQL editor
5. Update your environment variables with the Supabase credentials

### 2. First Login
1. Access the application at http://localhost:8000
2. Log in with the default admin credentials:
   - Email: admin@example.com
   - Password: admin123
3. Change the default password immediately

### 3. Create Your First Store
1. Go to Store Management
2. Click "Add New Store"
3. Fill in the store details
4. Add products to your store

## Development Workflow

### Code Generation
When you modify model classes:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

### Running Tests
```bash
# All tests
flutter test

# Specific test file
flutter test test/auth_test.dart

# With coverage
flutter test --coverage
```

### Code Style
The project uses strict analysis options:
```bash
# Check formatting
dart format --set-exit-if-changed .

# Run analyzer
flutter analyze
```

## Common Issues and Solutions

### Docker Issues

1. **Port Already in Use**
```bash
# Check what's using port 8000
sudo lsof -i :8000

# Stop the process
./scripts/docker.sh stop
```

2. **Container Won't Start**
```bash
# Check logs
./scripts/docker.sh logs

# Clean and rebuild
./scripts/docker.sh clean
./scripts/docker.sh start
```

### Flutter Issues

1. **Pub Get Fails**
```bash
# Clear pub cache
flutter pub cache clean
flutter pub get
```

2. **Build Runner Errors**
```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
```

## Next Steps

1. Read the [Architecture Overview](architecture.md)
2. Check the [API Documentation](api.md)
3. Learn about [State Management](state-management.md)
4. Understand [Security Best Practices](security.md)

## Support

If you encounter any issues:
1. Check the [FAQ](faq.md)
2. Search existing [GitHub Issues](https://github.com/yourusername/cashier_app/issues)
3. Join our [Discord Community](https://discord.gg/your-invite)
4. Create a new issue with detailed information about your problem

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on contributing to the project.
