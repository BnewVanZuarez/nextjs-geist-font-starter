# Deployment Guide

This guide covers the deployment process for the Kasir App across different environments and platforms.

## Environments

### 1. Development

```bash
# Start development server
./scripts/docker.sh dev

# Or without Docker
flutter run -d chrome --web-port 8000
```

Configuration:
- Debug mode enabled
- Hot reload active
- Local Supabase instance
- Development API keys

### 2. Staging

```bash
# Build staging version
flutter build web --dart-define=ENVIRONMENT=staging

# Deploy to staging server
./scripts/docker.sh deploy staging
```

Configuration:
- Profile mode
- Staging Supabase instance
- Test data available
- Monitoring enabled

### 3. Production

```bash
# Build production version
flutter build web --release --dart-define=ENVIRONMENT=production

# Deploy to production
./scripts/docker.sh deploy prod
```

Configuration:
- Release mode
- Production Supabase instance
- Analytics enabled
- Error reporting active

## Deployment Platforms

### 1. Docker Deployment

```bash
# Build Docker image
docker build -t kasir-app:latest .

# Run container
docker run -p 8000:8000 kasir-app:latest

# Or using docker-compose
docker-compose up -d
```

Configuration in `docker-compose.yml`:
```yaml
version: '3.8'

services:
  web:
    build: .
    ports:
      - "8000:8000"
    environment:
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 2. Cloud Platforms

#### Google Cloud Run

```bash
# Build and push to Container Registry
gcloud builds submit --tag gcr.io/PROJECT_ID/kasir-app

# Deploy to Cloud Run
gcloud run deploy kasir-app \
  --image gcr.io/PROJECT_ID/kasir-app \
  --platform managed \
  --allow-unauthenticated \
  --region asia-southeast1
```

#### AWS Elastic Beanstalk

```bash
# Initialize EB CLI
eb init -p docker kasir-app

# Deploy application
eb create kasir-app-env

# Update environment variables
eb setenv \
  SUPABASE_URL=$SUPABASE_URL \
  SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY
```

#### Digital Ocean App Platform

```yaml
# .do/app.yaml
name: kasir-app
services:
- name: web
  github:
    repo: username/kasir-app
    branch: main
  build_command: flutter build web --release
  run_command: nginx -g 'daemon off;'
  envs:
  - key: SUPABASE_URL
    value: ${SUPABASE_URL}
  - key: SUPABASE_ANON_KEY
    value: ${SUPABASE_ANON_KEY}
```

### 3. Static Hosting

#### Firebase Hosting

```bash
# Install Firebase CLI
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize project
firebase init hosting

# Deploy
firebase deploy
```

Configuration in `firebase.json`:
```json
{
  "hosting": {
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      {
        "source": "**",
        "destination": "/index.html"
      }
    ]
  }
}
```

#### GitHub Pages

```yaml
# .github/workflows/gh-pages.yml
name: Deploy to GitHub Pages

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v2
    
    - uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.16.0'
    
    - name: Build
      run: flutter build web --release
    
    - name: Deploy
      uses: peaceiris/actions-gh-pages@v3
      with:
        github_token: ${{ secrets.GITHUB_TOKEN }}
        publish_dir: ./build/web
```

## Database Migration

### 1. Prepare Migration

```sql
-- migrations/001_initial_schema.sql
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create tables
CREATE TABLE users (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- ...
);

-- Add indexes
CREATE INDEX idx_users_email ON users(email);
```

### 2. Apply Migration

```bash
# Development
psql -U postgres -d kasir_dev -a -f migrations/001_initial_schema.sql

# Staging
psql -h $STAGING_DB_HOST -U $DB_USER -d kasir_staging -a -f migrations/001_initial_schema.sql

# Production
psql -h $PROD_DB_HOST -U $DB_USER -d kasir_prod -a -f migrations/001_initial_schema.sql
```

## SSL Configuration

### 1. Generate Certificate

```bash
# Using Let's Encrypt
certbot certonly --nginx -d yourdomain.com
```

### 2. Configure Nginx

```nginx
# nginx.conf
server {
    listen 443 ssl http2;
    server_name yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/yourdomain.com/privkey.pem;
    
    # ... rest of configuration
}
```

## Monitoring Setup

### 1. Application Monitoring

```dart
// Initialize Sentry
void main() {
  Sentry.init((options) {
    options.dsn = 'YOUR_SENTRY_DSN';
    options.environment = const String.fromEnvironment('ENVIRONMENT');
  });
  
  runApp(const MyApp());
}
```

### 2. Performance Monitoring

```yaml
# docker-compose.yml
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
      
  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    depends_on:
      - prometheus
```

## Backup Strategy

### 1. Database Backup

```bash
#!/bin/bash
# backup.sh

# Backup database
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -F c -f backup.dump

# Upload to cloud storage
aws s3 cp backup.dump s3://your-bucket/backups/$(date +%Y%m%d)/
```

### 2. Media Backup

```bash
# Backup uploaded files
rsync -av /path/to/media/ backup-server:/path/to/backup/
```

## Rollback Procedure

### 1. Code Rollback

```bash
# Revert to previous version
git revert HEAD

# Rebuild and deploy
./scripts/docker.sh deploy prod
```

### 2. Database Rollback

```bash
# Restore from backup
pg_restore -h $DB_HOST -U $DB_USER -d $DB_NAME backup.dump
```

## Security Checklist

Pre-deployment security checks:
- [ ] Environment variables are set
- [ ] SSL certificates are valid
- [ ] Database backups are configured
- [ ] Firewall rules are updated
- [ ] Access controls are configured
- [ ] Monitoring is active
- [ ] Error reporting is configured
- [ ] Rate limiting is enabled
- [ ] CORS is properly configured

## Troubleshooting

### Common Issues

1. **Database Connection Issues**
```bash
# Check connection
psql -h $DB_HOST -U $DB_USER -d $DB_NAME

# Check logs
docker-compose logs db
```

2. **SSL Certificate Issues**
```bash
# Test SSL configuration
openssl s_client -connect yourdomain.com:443 -servername yourdomain.com
```

3. **Container Issues**
```bash
# Check container status
docker ps -a

# View logs
docker logs kasir-app
```

## Resources

- [Flutter Web Deployment](https://flutter.dev/docs/deployment/web)
- [Docker Documentation](https://docs.docker.com/)
- [Supabase Documentation](https://supabase.com/docs)
- [Nginx Documentation](https://nginx.org/en/docs/)
