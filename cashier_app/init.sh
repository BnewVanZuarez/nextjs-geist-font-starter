#!/bin/bash

# Exit on any error
set -e

echo "Initializing Kasir App project..."

# Check if Flutter is installed
if ! command -v flutter &> /dev/null; then
    echo "Error: Flutter is not installed"
    echo
    echo "Please install Flutter by following these steps:"
    echo "1. Visit https://flutter.dev/docs/get-started/install"
    echo "2. Download Flutter SDK for your platform"
    echo "3. Add Flutter to your PATH"
    echo "4. Run 'flutter doctor' to verify installation"
    echo
    echo "After installing Flutter, run this script again."
    exit 1
fi

# Create required directories
echo "Creating required directories..."
mkdir -p \
    lib/config \
    lib/models \
    lib/pages/auth \
    lib/providers \
    lib/services \
    lib/widgets \
    assets/icons \
    assets/images \
    test \
    scripts

# Check if env.dart exists, if not copy from example
if [ ! -f "lib/config/env.dart" ] && [ -f "lib/config/env.example.dart" ]; then
    echo "Creating env.dart from example..."
    cp lib/config/env.example.dart lib/config/env.dart
    echo "Please update lib/config/env.dart with your credentials."
fi

echo
echo "Project directory structure created successfully!"
echo
echo "Next steps:"
echo "1. Install Flutter (https://flutter.dev/docs/get-started/install)"
echo "2. Run 'flutter pub get' to install dependencies"
echo "3. Update lib/config/env.dart with your Supabase credentials"
echo "4. Run 'flutter pub run build_runner build' to generate code"
echo "5. Run 'flutter test' to verify setup"
echo "6. Run 'flutter run' to start the app"
echo
echo "For more information, see the README.md file."
