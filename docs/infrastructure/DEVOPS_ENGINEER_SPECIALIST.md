---
Last Updated: 2026-01-17
Platform Version: 1.0.0
---

# DevOps Engineer Specialist

**MCP Connection**: `devops_engineer`
**Primary Role**: DevOps specialist handling deployment, CI/CD, monitoring, and infrastructure automation

## Role & Responsibilities

The DevOps Engineer specializes in infrastructure automation, deployment pipelines, and production monitoring for the Powernode subscription platform. This role coordinates with the platform architect and other specialists to ensure reliable, scalable infrastructure.

### Core Areas
- **CI/CD Pipeline Management**: GitHub Actions workflow automation
- **Deployment Orchestration**: Multi-environment deployment strategies
- **Infrastructure as Code**: Docker containerization and orchestration
- **Monitoring & Alerting**: Application and infrastructure health monitoring
- **Security Infrastructure**: Production security and compliance automation
- **Database Operations**: Backup, recovery, and migration automation
- **Performance Monitoring**: Resource optimization and scaling strategies

### Integration Points
- **Platform Architect**: Infrastructure planning and resource allocation
- **Security Specialist**: Security automation and compliance monitoring
- **Performance Optimizer**: Resource monitoring and scaling automation
- **Backend/Frontend Specialists**: Application deployment coordination
- **Test Engineers**: Test environment provisioning and CI/CD integration

## Infrastructure Architecture

### Production Environment Stack
```yaml
# Infrastructure Components
Load Balancer: Nginx/HAProxy
Application Servers: Puma (Rails API)
Background Processing: Sidekiq with Redis
Database: PostgreSQL with read replicas
Cache Layer: Redis for sessions and caching
File Storage: AWS S3/Azure Blob for uploads
CDN: CloudFlare for static assets
Monitoring: Datadog/New Relic for APM
```

### Environment Strategy
```bash
# Environment Tiers
Production:  Main branch deployment - Full monitoring
Staging:     Develop branch deployment - Pre-production testing
Development: Feature branch deployment - Development testing
Preview:     Pull request deployments - Code review testing
```

### Container Architecture
```dockerfile
# Multi-stage Docker builds
FROM ruby:3.2-alpine AS backend-base
# Rails API container configuration

FROM node:18-alpine AS frontend-build
# React build optimization

FROM ruby:3.2-alpine AS worker
# Sidekiq worker configuration
```

## CI/CD Pipeline Standards

### GitHub Actions Workflow
```yaml
# .github/workflows/ci.yml
name: Continuous Integration
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test-backend:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: powernode_test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
    - uses: actions/checkout@v4
    - name: Setup Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: '3.2'
        bundler-cache: true
        working-directory: './server'
    
    - name: Setup Database
      run: |
        cd $POWERNODE_ROOT/server
        bundle exec rails db:setup
        bundle exec rails db:migrate
    
    - name: Run Tests
      run: |
        cd $POWERNODE_ROOT/server
        bundle exec rspec --format documentation
        
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./server/coverage/coverage.xml

  test-frontend:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Setup Node.js
      uses: actions/setup-node@v4
      with:
        node-version: '18'
        cache: 'npm'
        cache-dependency-path: frontend/package-lock.json
    
    - name: Install Dependencies
      run: |
        cd $POWERNODE_ROOT/frontend
        npm ci
    
    - name: Run Linting
      run: |
        cd $POWERNODE_ROOT/frontend
        npm run lint
        npm run type-check
    
    - name: Run Tests
      run: |
        cd $POWERNODE_ROOT/frontend
        npm run test:coverage
    
    - name: Upload Coverage
      uses: codecov/codecov-action@v3
      with:
        file: ./frontend/coverage/lcov.info

  security-scan:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4
    - name: Run Security Audit
      run: |
        cd $POWERNODE_ROOT/server && bundle audit --update
        cd $POWERNODE_ROOT/frontend && npm audit --audit-level high
    
    - name: Run CodeQL Analysis
      uses: github/codeql-action/analyze@v2
      with:
        languages: ruby, javascript
```

### Deployment Pipeline
```yaml
# .github/workflows/deploy.yml
name: Deploy Application
on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production
    steps:
    - uses: actions/checkout@v4
    
    - name: Build Images
      run: |
        docker build -t powernode-api:${{ github.sha }} -f server/Dockerfile server/
        docker build -t powernode-frontend:${{ github.sha }} -f frontend/Dockerfile frontend/
        docker build -t powernode-worker:${{ github.sha }} -f worker/Dockerfile worker/
    
    - name: Push to Registry
      run: |
        echo ${{ secrets.DOCKER_PASSWORD }} | docker login -u ${{ secrets.DOCKER_USERNAME }} --password-stdin
        docker push powernode-api:${{ github.sha }}
        docker push powernode-frontend:${{ github.sha }}
        docker push powernode-worker:${{ github.sha }}
    
    - name: Deploy to Production
      run: |
        # Blue-green deployment strategy
        kubectl set image deployment/api-deployment api=powernode-api:${{ github.sha }}
        kubectl set image deployment/frontend-deployment frontend=powernode-frontend:${{ github.sha }}
        kubectl set image deployment/worker-deployment worker=powernode-worker:${{ github.sha }}
        kubectl rollout status deployment/api-deployment
```

## Container Configuration

### Rails API Container
```dockerfile
# server/Dockerfile
FROM ruby:3.2-alpine AS base

# Install dependencies
RUN apk add --no-cache \
    build-base \
    postgresql-dev \
    curl \
    tzdata

WORKDIR /app

# Install gems
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install

# Copy application
COPY . .

# Precompile assets if needed
RUN bundle exec rails assets:precompile

EXPOSE 3000
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
```

### React Frontend Container
```dockerfile
# frontend/Dockerfile
FROM node:18-alpine AS build

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY . .
RUN npm run build

# Production nginx container
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

### Sidekiq Worker Container
```dockerfile
# worker/Dockerfile
FROM ruby:3.2-alpine

RUN apk add --no-cache \
    build-base \
    curl \
    tzdata

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle install

COPY . .

CMD ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
```

## Infrastructure as Code

### Docker Compose Development
```yaml
# docker-compose.yml
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: powernode_development
      POSTGRES_USER: powernode
      POSTGRES_PASSWORD: powernode
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  api:
    build:
      context: ./server
      dockerfile: Dockerfile.dev
    volumes:
      - ./server:/app
      - gem_cache:/usr/local/bundle
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - redis
    environment:
      DATABASE_URL: postgres://powernode:powernode@postgres:5432/powernode_development
      REDIS_URL: redis://redis:6379/0

  worker:
    build:
      context: ./worker
      dockerfile: Dockerfile.dev
    volumes:
      - ./worker:/app
    depends_on:
      - postgres
      - redis
    environment:
      DATABASE_URL: postgres://powernode:powernode@postgres:5432/powernode_development
      REDIS_URL: redis://redis:6379/0

  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile.dev
    volumes:
      - ./frontend:/app
      - node_modules:/app/node_modules
    ports:
      - "3002:3000"
    environment:
      REACT_APP_API_URL: http://localhost:3000

volumes:
  postgres_data:
  redis_data:
  gem_cache:
  node_modules:
```

### Kubernetes Deployment
```yaml
# k8s/api-deployment.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-deployment
spec:
  replicas: 3
  selector:
    matchLabels:
      app: powernode-api
  template:
    metadata:
      labels:
        app: powernode-api
    spec:
      containers:
      - name: api
        image: powernode-api:latest
        ports:
        - containerPort: 3000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: db-secrets
              key: url
        - name: REDIS_URL
          valueFrom:
            configMapKeyRef:
              name: redis-config
              key: url
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        livenessProbe:
          httpGet:
            path: /health
            port: 3000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 3000
          initialDelaySeconds: 5
          periodSeconds: 5
```

## Monitoring & Alerting

### Application Monitoring
```ruby
# config/initializers/monitoring.rb
if Rails.env.production?
  # DataDog APM configuration
  Datadog.configure do |c|
    c.env = Rails.env
    c.service = 'powernode-api'
    c.version = ENV['APP_VERSION'] || 'unknown'
    
    # Enable tracing
    c.tracing.instrument :rails
    c.tracing.instrument :postgres
    c.tracing.instrument :redis
    c.tracing.instrument :sidekiq
  end
  
  # Custom metrics
  Rails.application.config.after_initialize do
    # Business metrics
    ActiveSupport::Notifications.subscribe('subscription.created') do |*args|
      StatsD.increment('subscription.created')
    end
    
    ActiveSupport::Notifications.subscribe('payment.succeeded') do |*args|
      StatsD.increment('payment.succeeded')
    end
    
    ActiveSupport::Notifications.subscribe('payment.failed') do |*args|
      StatsD.increment('payment.failed')
    end
  end
end
```

### Infrastructure Monitoring
```yaml
# monitoring/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'powernode-api'
    static_configs:
      - targets: ['api:3000']
    metrics_path: '/metrics'
    scrape_interval: 10s

  - job_name: 'powernode-worker'
    static_configs:
      - targets: ['worker:9394']
    metrics_path: '/metrics'
    scrape_interval: 30s

  - job_name: 'postgres'
    static_configs:
      - targets: ['postgres-exporter:9187']

  - job_name: 'redis'
    static_configs:
      - targets: ['redis-exporter:9121']
```

### Alert Configuration
```yaml
# monitoring/alerts.yml
groups:
- name: powernode.rules
  rules:
  - alert: HighErrorRate
    expr: rate(http_requests_total{status=~"5.."}[5m]) > 0.1
    for: 5m
    annotations:
      summary: "High error rate detected"
      description: "Error rate is {{ $value }} errors per second"

  - alert: DatabaseConnectionPool
    expr: postgres_connection_pool_size - postgres_connection_pool_active < 5
    for: 2m
    annotations:
      summary: "Database connection pool nearly exhausted"

  - alert: SidekiqQueueSize
    expr: sidekiq_queue_size > 1000
    for: 5m
    annotations:
      summary: "Sidekiq queue size is growing"
      description: "Queue {{ $labels.queue }} has {{ $value }} jobs"

  - alert: DiskSpaceUsage
    expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes > 0.8
    for: 5m
    annotations:
      summary: "Disk space usage high"
```

## Database Operations

### Backup Strategy
```bash
#!/bin/bash
# scripts/backup-database.sh

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="powernode_backup_${TIMESTAMP}.sql"

# Create backup
pg_dump $DATABASE_URL > "/backups/${BACKUP_FILE}"

# Compress backup
gzip "/backups/${BACKUP_FILE}"

# Upload to S3
aws s3 cp "/backups/${BACKUP_FILE}.gz" "s3://powernode-backups/database/"

# Cleanup old backups (keep 30 days)
find /backups -name "powernode_backup_*.sql.gz" -mtime +30 -delete

echo "Backup completed: ${BACKUP_FILE}.gz"
```

### Database Migration Pipeline
```bash
#!/bin/bash
# scripts/deploy-with-migrations.sh

set -e

echo "Starting deployment with migrations..."

# 1. Create database backup
./scripts/backup-database.sh

# 2. Run migrations in maintenance mode
kubectl patch deployment api-deployment -p '{"spec":{"replicas":0}}'
kubectl wait --for=delete pod -l app=powernode-api --timeout=60s

# 3. Run migrations
kubectl run migration-job --image=powernode-api:$1 --restart=Never \
  --env="DATABASE_URL=$DATABASE_URL" \
  -- bundle exec rails db:migrate

# 4. Verify migration success
kubectl wait --for=condition=complete job/migration-job --timeout=300s

# 5. Deploy new version
kubectl set image deployment/api-deployment api=powernode-api:$1
kubectl patch deployment api-deployment -p '{"spec":{"replicas":3}}'
kubectl rollout status deployment/api-deployment

# 6. Cleanup
kubectl delete job migration-job

echo "Deployment completed successfully"
```

## Performance Optimization

### Resource Management
```yaml
# k8s/resource-limits.yml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: powernode-quota
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
    services: "5"
    secrets: "10"
    configmaps: "10"
```

### Auto-scaling Configuration
```yaml
# k8s/hpa.yml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-deployment
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 15
```

## Security Infrastructure

### Network Policies
```yaml
# k8s/network-policy.yml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: powernode-network-policy
spec:
  podSelector:
    matchLabels:
      app: powernode-api
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: nginx-ingress
    ports:
    - protocol: TCP
      port: 3000
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432
  - to:
    - podSelector:
        matchLabels:
          app: redis
    ports:
    - protocol: TCP
      port: 6379
```

### Secret Management
```bash
# scripts/manage-secrets.sh
#!/bin/bash

# Create secrets from environment files
kubectl create secret generic api-secrets \
  --from-env-file=.env.production \
  --dry-run=client -o yaml | kubectl apply -f -

# Database credentials
kubectl create secret generic db-secrets \
  --from-literal=url="$DATABASE_URL" \
  --from-literal=password="$DB_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# JWT secrets
kubectl create secret generic jwt-secrets \
  --from-literal=secret="$JWT_SECRET_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

# Payment gateway secrets
kubectl create secret generic payment-secrets \
  --from-literal=stripe-secret="$STRIPE_SECRET_KEY" \
  --from-literal=paypal-secret="$PAYPAL_CLIENT_SECRET" \
  --dry-run=client -o yaml | kubectl apply -f -
```

## Development Workflow

### Process Management (CRITICAL)
**NEVER start servers manually** - Always use management scripts with screen sessions.

```bash
# Essential commands
$POWERNODE_ROOT/scripts/auto-dev.sh ensure    # Start all services
$POWERNODE_ROOT/scripts/auto-dev.sh status    # Health check

# Individual services
$POWERNODE_ROOT/scripts/backend-manager.sh start|stop|status|logs
$POWERNODE_ROOT/scripts/worker-manager.sh start|stop|status|start-web|stop-web  
$POWERNODE_ROOT/scripts/frontend-manager.sh start|stop|status|logs

# Service endpoints
# Backend: http://localhost:3000
# Worker Web: http://localhost:4567/sidekiq  
# Frontend: http://localhost:3002
```

**Claude Auto-Start**: Servers auto-start when user requests testing/development work.
**Startup Sequence**: Backend → Worker → Frontend → Health check

### Development Commands
```bash
# Database with automatic worker token update
cd $POWERNODE_ROOT/server && rails db:create db:migrate db:seed && rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); if worker && worker.token.present?; File.write('$POWERNODE_ROOT/worker/.env', File.read('$POWERNODE_ROOT/worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\")); puts \"✅ Updated worker token\"; end"

# Testing  
cd $POWERNODE_ROOT/server && bundle exec rspec        # Backend (203+ tests)
cd $POWERNODE_ROOT/frontend && npm test              # Frontend

# Project tracking
# Use ../TODO.md with: [ ] [🔄] [✅] [❌] [⚠️]
```

### Database Operations (Development)

**Database Schema (CONSOLIDATED)**
**CRITICAL**: Streamlined migrations with UUID strategy.

#### Current Structure
1. **20250101000001_create_powernode_schema.rb** - Core platform tables
2. **20250101000002_create_additional_features.rb** - Extended features

**UUID Strategy**: `string :id, limit: 36` (current), `gen_random_uuid()` (new tables)
**Extensions**: `pgcrypto`, `uuid-ossp` enabled

```bash
# Database reset commands (run from $POWERNODE_ROOT/server)
cd $POWERNODE_ROOT/server && rails db:drop db:create db:migrate db:seed
cd $POWERNODE_ROOT/server && rm -f db/schema.rb && rails db:migrate  # Fresh start

# CRITICAL: Always update worker token after database reset
cd $POWERNODE_ROOT/server && rails runner "worker = Worker.find_by(name: 'Powernode System Worker'); 
if worker && worker.token.present?
  File.write('$POWERNODE_ROOT/worker/.env', File.read('$POWERNODE_ROOT/worker/.env').gsub(/^WORKER_TOKEN=.*$/, \"WORKER_TOKEN=#{worker.token}\"))
  puts \"✅ Updated worker/.env with system worker token: #{worker.token[0..10]}...\"
else
  puts \"❌ No system worker token found - check seeds.rb\"
end"
```

**Core Tables**: accounts, users, plans/subscriptions, payments/invoices, workers/volumes, kb_articles, notifications/audit_logs

## Infrastructure Commands

### Infrastructure Setup
```bash
# Local development environment
docker-compose up -d                    # Start all services
docker-compose logs -f api             # View API logs
docker-compose exec api rails console  # Access Rails console

# Production deployment
kubectl apply -f k8s/                  # Deploy to Kubernetes
kubectl get pods -l app=powernode-api  # Check pod status
kubectl logs -f deployment/api-deployment  # View logs

# Database operations
kubectl exec -it postgres-pod -- pg_dump powernode_production > backup.sql
kubectl port-forward svc/postgres 5432:5432  # Local database access

# Monitoring
kubectl port-forward svc/prometheus 9090:9090  # Access Prometheus
kubectl port-forward svc/grafana 3000:3000     # Access Grafana
```

### CI/CD Management
```bash
# GitHub Actions
gh workflow run ci.yml --ref develop     # Trigger CI pipeline
gh run list --workflow=ci.yml            # List recent runs
gh run view 123456 --log                 # View run logs

# Manual deployment
./scripts/deploy.sh production v1.2.0    # Deploy specific version
./scripts/rollback.sh production v1.1.0  # Rollback deployment
```

### Monitoring Commands
```bash
# Application metrics
kubectl top pods                         # Resource usage
kubectl get hpa                         # Auto-scaler status
kubectl describe pod api-deployment-xxx # Pod details

# Database monitoring
kubectl exec postgres-pod -- psql -c "SELECT * FROM pg_stat_activity;"
kubectl exec redis-pod -- redis-cli info memory

# Log aggregation
kubectl logs -l app=powernode-api --tail=100 --since=1h
stern powernode-api  # Real-time log streaming
```

## Integration Points

### Platform Architect Coordination
- **Resource Planning**: Infrastructure capacity and scaling requirements
- **Architecture Decisions**: Technology stack and deployment strategies
- **Security Integration**: Coordinating security infrastructure with security specialist
- **Performance Coordination**: Working with performance optimizer on resource optimization

### Security Specialist Integration
- **Infrastructure Security**: Container security scanning and network policies
- **Secret Management**: Secure credential storage and rotation
- **Compliance Monitoring**: Automated compliance checking and reporting
- **Security Automation**: Integrating security tools into CI/CD pipeline

### Development Team Integration
- **Environment Provisioning**: Automated development and staging environments
- **Testing Infrastructure**: CI/CD pipeline integration with test suites
- **Deployment Coordination**: Managing deployments across all application components
- **Monitoring Integration**: Application performance monitoring and alerting

## Git Workflow & Release Management

### Git-Flow Model (MANDATORY)
**Current Version**: `0.0.1` → `0.1.0` (next release)

**Branch Structure**:
- `main` - Production releases only (2 PR reviews required)
- `develop` - Integration branch (1 PR review required)
- `feature/ISSUE-description` - New features
- `release/v1.2.0` - Release preparation
- `hotfix/v1.2.1-description` - Production fixes

**Git Configuration**:
- **IMPORTANT**: Clean commit messages without Claude attribution
- Use conventional commits: `feat:`, `fix:`, `docs:`, etc.
- Git-Flow enforced: `develop` → `feature/*` → `release/*` → `main`

```bash
# Git-flow commands
git flow feature start ISSUE-feature-name
git flow feature finish ISSUE-feature-name
git flow release start v1.2.0
git flow release finish v1.2.0
git flow hotfix start v1.2.1-critical-fix
git flow hotfix finish v1.2.1-critical-fix
```

### Semantic Versioning (SemVer 2.0.0)
**Format**: `MAJOR.MINOR.PATCH[-PRERELEASE]`

**Version Rules**:
- **MAJOR** (X.0.0): Breaking changes, API incompatibility
- **MINOR** (0.X.0): New features, backward compatible  
- **PATCH** (0.0.X): Bug fixes, backward compatible
- **PRERELEASE**: `alpha`, `beta`, `rc` tags

**Conventional Commits**:
- `feat:` → MINOR version bump
- `fix:` → PATCH version bump
- `feat!:` or `BREAKING CHANGE:` → MAJOR version bump
- `docs:`, `style:`, `refactor:`, `test:`, `chore:` → PATCH version bump

```bash
# Version management
git describe --tags --abbrev=0           # Check current version
npm version patch|minor|major            # Bump version
npm version prerelease --preid=alpha    # Pre-release version

# Examples
feat(auth): implement OAuth2 integration  # MINOR bump
fix(billing): resolve renewal bug         # PATCH bump
feat!: redesign authentication API       # MAJOR bump
```

### Release Process
**Pre-Release Checklist**:
- [ ] All features merged to develop
- [ ] All tests passing (backend + frontend)
- [ ] Security audit completed
- [ ] Performance benchmarks met
- [ ] Documentation updated

**Release Tagging**:
```bash
git tag -a v1.2.0 -m "Release v1.2.0

Features:
- New payment gateway integration
- Enhanced user management

Breaking Changes:
- API endpoint restructuring

Migration Guide:
- Update API calls to new endpoints"
```

**Deployment Strategy**:
- `main` → Production
- `develop` → Staging
- `feature/*` → Development/Preview
- `release/*` → Pre-production testing

**Quality Gates**: Tests pass → Security scans → Performance benchmarks → Manual approval

### Git Workflow & Cleanup
**Pre-Commit Cleanup (MANDATORY)**:
```bash
find $POWERNODE_ROOT -name "*.tmp" -o -name ".DS_Store" -o -name "Thumbs.db" -o -name "*.swp" -o -name "*.swo" -o -name "*~" | xargs rm -f 2>/dev/null; cd $POWERNODE_ROOT/frontend && rm -rf .next/ dist/ build/ coverage/ .nyc_output/ node_modules/.cache/ && cd $POWERNODE_ROOT/server && rm -rf tmp/cache/ tmp/pids/ tmp/sessions/ tmp/sockets/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd $POWERNODE_ROOT/worker && rm -rf tmp/ coverage/ && find log/ -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null; cd $POWERNODE_ROOT && git status --porcelain
```

**Commit Pattern**: Complete work → Run cleanup → Test/lint → Commit

### Commit Preparation Protocol (CRITICAL)
**MANDATORY BEHAVIOR**: When preparing git commits, follow this exact sequence:

1. **Analyze Changes**: Check git status and examine staged/unstaged changes
2. **Stage Appropriate Files**: Add relevant files to staging area using `git add`
3. **Draft Commit Message**: Prepare conventional commit message following project standards
4. **Present for Approval**: Show proposed commit message and staged changes to user
5. **Wait for Confirmation**: **NEVER execute `git commit` automatically**

**ABSOLUTE RULE**: When user says "prepare for git commit", do NOT automatically commit. Only execute `git commit` when explicitly asked to "commit" or "create the commit".

## Quick Reference

### Essential Commands
```bash
# Development Workflow
$POWERNODE_ROOT/scripts/auto-dev.sh ensure            # Start all services
cd $POWERNODE_ROOT/server && rails db:migrate db:seed # Database setup
cd $POWERNODE_ROOT/server && bundle exec rspec        # Backend tests
cd $POWERNODE_ROOT/frontend && npm test               # Frontend tests

# Infrastructure
docker-compose up -d                    # Local development
kubectl apply -f k8s/                  # Deploy to Kubernetes
helm upgrade powernode ./helm-chart    # Helm deployment

# Monitoring
kubectl get pods -o wide               # Pod status
kubectl top nodes                      # Node resources
kubectl describe hpa api-hpa           # Auto-scaler details

# Database
pg_dump $DATABASE_URL > backup.sql     # Manual backup
kubectl exec postgres-pod -- psql     # Database access

# Git Flow
git flow feature start ISSUE-description
git flow release start v1.2.0
npm version patch|minor|major
```

### Key Metrics
- **API Response Time**: < 200ms 95th percentile
- **Database Connection Pool**: < 80% utilization
- **Memory Usage**: < 80% of container limits
- **CPU Usage**: < 70% average, < 90% peak
- **Error Rate**: < 0.1% of total requests
- **Deployment Frequency**: Multiple times per day
- **Recovery Time**: < 15 minutes for production issues

### Emergency Procedures
- **Scale Up**: `kubectl scale deployment api-deployment --replicas=6`
- **Rollback**: `kubectl rollout undo deployment/api-deployment`
- **Maintenance Mode**: `kubectl patch deployment api-deployment -p '{"spec":{"replicas":0}}'`
- **Database Failover**: Automated with read replica promotion
- **Log Access**: `stern powernode` for real-time log streaming