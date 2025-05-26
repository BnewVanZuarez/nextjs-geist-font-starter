# Kasir App

A modern Flutter-based Point of Sale (POS) application with Supabase backend.

## Features

- 🔐 **Authentication**
  - Email & password login/registration
  - Role-based access control (admin, manager, cashier)
  - Password reset functionality

- 🏪 **Store Management**
  - Create and manage multiple stores/branches
  - Store details and contact information
  - Role-based store access

- 💰 **Cash Register**
  - Intuitive point-of-sale interface
  - Real-time stock updates
  - Multiple payment methods
  - Digital receipts (print, email, WhatsApp)

- 📦 **Inventory Management**
  - Product categories
  - Stock tracking
  - Low stock alerts
  - Bulk import/export

- 👥 **Customer Management**
  - Customer database
  - Purchase history
  - Digital receipt delivery
  - Customer loyalty tracking

- 📊 **Reporting**
  - Sales reports
  - Inventory reports
  - Customer analytics
  - Export functionality

## Quick Start

### Using Docker (Recommended)

1. **Prerequisites**
   - Docker
   - Docker Compose

2. **Setup**
   ```bash
   # Clone the repository
   git clone https://github.com/yourusername/cashier_app.git
   cd cashier_app

   # Copy environment files
   cp .env.example .env
   cp lib/config/env.example.dart lib/config/env.dart

   # Update environment files with your Supabase credentials
   # Edit .env and lib/config/env.dart

   # Start the application
   ./scripts/docker.sh start
   ```

3. **Development Mode**
   ```bash
   ./scripts/docker.sh dev
   ```

4. **Running Tests**
   ```bash
   ./scripts/docker.sh test
   ```

### Manual Setup

1. **Prerequisites**
   - Flutter SDK (3.16.0 or higher)
   - Dart SDK (3.0.0 or higher)
   - Supabase account

2. **Setup**
   ```bash
   # Clone the repository
   git clone https://github.com/yourusername/cashier_app.git
   cd cashier_app

   # Initialize the project
   ./init.sh

   # Install dependencies
   flutter pub get

   # Generate code
   flutter pub run build_runner build --delete-conflicting-outputs

   # Run the app
   flutter run
   ```

## Project Structure

```
lib/
├── config/          # Configuration files
├── models/          # Data models
├── pages/          # UI screens
│   └── auth/       # Authentication pages
├── providers/      # State management
├── services/       # Backend services
└── widgets/        # Reusable components
```

## Database Setup

1. Create a new Supabase project
2. Run the database setup script from `scripts/setup_db.sql`
3. Update environment variables with your Supabase credentials

## Available Scripts

- `./scripts/docker.sh start` - Start production mode
- `./scripts/docker.sh dev` - Start development mode with hot-reload
- `./scripts/docker.sh test` - Run tests
- `./scripts/docker.sh build` - Build Docker images
- `./scripts/docker.sh stop` - Stop running containers
- `./scripts/docker.sh clean` - Clean up Docker resources
- `./init.sh` - Initialize project (non-Docker setup)

## Environment Variables

Key environment variables that need to be set:

```bash
SUPABASE_URL=your-project-url.supabase.co
SUPABASE_ANON_KEY=your-anon-key
```

See `.env.example` for all available options.

## Testing

```bash
# Run all tests
flutter test

# Run tests with coverage
flutter test --coverage
```

## Deployment

### Production Build

```bash
# Build web version
flutter build web --release

# Build Android APK
flutter build apk --release

# Build iOS
flutter build ios --release
```

### Docker Deployment

```bash
# Build and start production containers
docker-compose up -d web
```

## Contributing

Please read [CONTRIBUTING.md](CONTRIBUTING.md) for details on our code of conduct and the process for submitting pull requests.

## Security

- All API requests are authenticated
- Data is encrypted in transit
- Passwords are hashed using bcrypt
- Row Level Security enabled in Supabase

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- Documentation: [docs/](docs/)
- Issue Tracker: [GitHub Issues](https://github.com/yourusername/cashier_app/issues)
- Discord: [Join our community](https://discord.gg/your-invite)

## Acknowledgments

- Flutter team for the amazing framework
- Supabase team for the backend platform
- All contributors who have helped shape this project
