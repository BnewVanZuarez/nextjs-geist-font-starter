# Contributing to Kasir App

Thank you for your interest in contributing to Kasir App! This document provides guidelines and instructions for contributing.

## Code of Conduct

By participating in this project, you agree to abide by our Code of Conduct. Please read it before contributing.

## How to Contribute

1. **Fork the Repository**
   - Fork the repository to your GitHub account
   - Clone your fork locally: `git clone https://github.com/YOUR-USERNAME/cashier_app.git`

2. **Set Up Development Environment**
   - Install Flutter (latest stable version)
   - Install dependencies: `flutter pub get`
   - Copy `lib/config/env.example.dart` to `lib/config/env.dart` and update with your Supabase credentials
   - Run tests to ensure everything is set up correctly: `flutter test`

3. **Create a Branch**
   - Create a branch for your feature/fix: `git checkout -b feature/your-feature-name`
   - Keep branch names descriptive and use kebab-case

4. **Development Guidelines**

   - **Code Style**
     - Follow the [Flutter style guide](https://flutter.dev/docs/development/style-guide)
     - Use the provided analysis_options.yaml
     - Run `flutter analyze` before committing

   - **Testing**
     - Write tests for new features
     - Ensure all tests pass: `flutter test`
     - Maintain or improve code coverage

   - **Documentation**
     - Document new features or changes in behavior
     - Update README.md if necessary
     - Add comments for complex logic

   - **Commit Messages**
     - Use clear and descriptive commit messages
     - Format: `type(scope): description`
     - Types: feat, fix, docs, style, refactor, test, chore
     - Example: `feat(auth): add biometric authentication`

5. **Submit a Pull Request**
   - Push your changes to your fork
   - Create a Pull Request against the main repository
   - Fill out the PR template completely
   - Link any related issues

## Pull Request Process

1. **Before Submitting**
   - Ensure code passes all tests
   - Update documentation if needed
   - Add tests for new features
   - Squash related commits

2. **Review Process**
   - Maintainers will review your PR
   - Address any requested changes
   - PR must receive approval from at least one maintainer

3. **After Merging**
   - Delete your branch
   - Update your fork

## Development Setup

1. **Required Software**
   - Flutter SDK
   - Dart SDK
   - VS Code or Android Studio
   - Git

2. **Environment Setup**
   ```bash
   # Clone your fork
   git clone https://github.com/YOUR-USERNAME/cashier_app.git
   cd cashier_app

   # Install dependencies
   flutter pub get

   # Set up pre-commit hooks
   dart run tool/setup_hooks.dart

   # Run tests
   flutter test
   ```

3. **Database Setup**
   - Create a Supabase project
   - Run the database migrations
   - Update environment variables

## Project Structure

```
lib/
├── config/          # Configuration files
├── models/          # Data models
├── pages/           # UI screens
├── providers/       # State management
├── services/        # Backend services
└── widgets/         # Reusable widgets
```

## Testing

- **Unit Tests**: `flutter test`
- **Integration Tests**: `flutter test integration_test`
- **Coverage**: `flutter test --coverage`

## Common Tasks

1. **Adding a New Feature**
   - Create feature branch
   - Implement feature
   - Add tests
   - Update documentation
   - Submit PR

2. **Fixing a Bug**
   - Create bug fix branch
   - Add test to reproduce bug
   - Fix bug
   - Verify fix
   - Submit PR

3. **Updating Documentation**
   - Create documentation branch
   - Make changes
   - Submit PR

## Getting Help

- Create an issue for questions
- Join our Discord community
- Check the FAQ in the README

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
