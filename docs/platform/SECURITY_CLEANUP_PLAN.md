# Security Cleanup Plan: Complete Removal of Secrets from Git History

## Overview
This document outlines the comprehensive plan to remove all sensitive files and secrets from git history, ensure proper .gitignore configuration, and establish security best practices.

## Current Security Risk Assessment

### Critical Files Currently Tracked in Git History
1. **`server/.env`** - Contains:
   - JWT_SECRET_KEY (development key)
   - Database passwords
   - Stripe test API keys
   - PayPal test credentials
   - Background job tokens

2. **`worker/.env`** - Contains:
   - WORKER_TOKEN (system authentication)

3. **`worker/.session.key`** - Contains:
   - Session encryption key (hexadecimal)

4. **`server/config/master.key`** - Contains:
   - Rails master encryption key

5. **Additional Risk Files:**
   - `server/.kamal/secrets` - Deployment secrets
   - `server/tmp/local_secret.txt` - Temporary secrets
   - `frontend/.env*` - API endpoints (lower risk)

### Git History Exposure
- These files have been committed multiple times since project inception
- All sensitive values are exposed in commit history
- Risk extends to all branches and tags

## Removal Strategy

### Phase 1: Immediate Protection (Pre-History Cleanup)

#### 1.1 Update .gitignore (Comprehensive Patterns)
```gitignore
# === SECURITY: Environment and Secret Files ===
# Environment files
.env
.env.*
!.env.example
!.env.sample
!.env.template

# Rails secrets and keys
config/master.key
config/credentials.yml.enc
config/credentials/
*.key
*.pem
*.p12
*.jks
*.keystore

# Session and encryption keys
.session.key
session.key
encryption.key

# API keys and tokens
*secret*
*private*
*.token
api_keys.yml
credentials.json

# Kamal deployment secrets
.kamal/secrets
.kamal/.env
kamal.env

# Temporary secret files
tmp/*secret*
tmp/*key*
tmp/*credential*

# Database dumps with potential secrets
*.sql
*.dump
backup/
dumps/

# SSL/TLS certificates
*.crt
*.cert
*.ca-bundle
ssl/
certificates/

# Cloud provider credentials
.aws/
.gcp/
.azure/
*-credentials.json
service-account.json

# IDE files that might contain secrets
.vscode/settings.json
.idea/workspace.xml
```

#### 1.2 Remove Files from Git Index
```bash
# Remove sensitive files from git index (keep local copies)
git rm --cached server/.env
git rm --cached worker/.env
git rm --cached worker/.session.key
git rm --cached server/config/master.key
git rm --cached frontend/.env
git rm --cached frontend/.env.development
git rm --cached server/.kamal/secrets
git rm --cached server/tmp/local_secret.txt

# Commit the removal
git commit -m "security: remove sensitive files from git tracking

- Remove .env files containing API keys and secrets
- Remove session keys and master encryption keys
- Remove deployment secrets and temporary files
- Files moved to .gitignore for future protection"
```

### Phase 2: Git History Rewriting

#### 2.1 Use git-filter-repo (Recommended Method)
```bash
# Install git-filter-repo if not available
pip3 install git-filter-repo

# Create backup of repository
git clone --mirror . ../powernode-platform-backup.git

# Remove sensitive files from entire history
git filter-repo --path server/.env --invert-paths
git filter-repo --path worker/.env --invert-paths
git filter-repo --path worker/.session.key --invert-paths
git filter-repo --path server/config/master.key --invert-paths
git filter-repo --path frontend/.env --invert-paths
git filter-repo --path frontend/.env.development --invert-paths
git filter-repo --path server/.kamal/secrets --invert-paths
git filter-repo --path server/tmp/local_secret.txt --invert-paths

# Alternative: Remove files matching patterns
git filter-repo --glob '*.env' --invert-paths --force
git filter-repo --glob '*.key' --invert-paths --force
git filter-repo --glob '*secret*' --invert-paths --force
```

#### 2.2 Alternative: BFG Repo-Cleaner
```bash
# Download BFG Repo-Cleaner
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar

# Remove files by name
java -jar bfg-1.14.0.jar --delete-files ".env" .
java -jar bfg-1.14.0.jar --delete-files "*.key" .
java -jar bfg-1.14.0.jar --delete-files "*secret*" .

# Clean up the repository
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

### Phase 3: .env.example Files Update

#### 3.1 Create Comprehensive .env.example Files

**`server/.env.example`:**
```env
# Database Configuration
POWERNODE_DATABASE_PASSWORD=your_secure_database_password

# JWT Configuration (CRITICAL: Generate secure keys for production)
JWT_SECRET_KEY=your_256_bit_jwt_secret_key_replace_this_value
JWT_EXPIRATION_TIME=24h

# Payment Gateway Configuration
# Stripe (use test keys for development, live keys for production)
STRIPE_SECRET_KEY=sk_test_your_stripe_secret_key
STRIPE_PUBLISHABLE_KEY=pk_test_your_stripe_publishable_key
STRIPE_WEBHOOK_SECRET=whsec_your_stripe_webhook_secret

# PayPal (use sandbox for development, live for production)
PAYPAL_CLIENT_ID=your_paypal_client_id
PAYPAL_CLIENT_SECRET=your_paypal_client_secret
PAYPAL_WEBHOOK_ID=your_paypal_webhook_id

# Application Configuration
RAILS_ENV=development
RAILS_LOG_LEVEL=info
RAILS_MAX_THREADS=5

# Frontend Configuration
FRONTEND_URL=http://localhost:3002

# Background Job Configuration
BACKGROUND_JOBS_API_URL=http://localhost:3000
BACKGROUND_JOBS_API_TOKEN=your_secure_service_token
```

**`worker/.env.example`:**
```env
# Worker Authentication Token
# This is generated automatically by the Rails application
# Run: rails db:seed to generate system worker token
WORKER_TOKEN=generate_via_rails_db_seed
```

**`frontend/.env.example`:**
```env
# Application Version
REACT_APP_VERSION=0.0.2

# API Configuration
REACT_APP_API_BASE_URL=http://localhost:3000/api/v1
REACT_APP_WS_BASE_URL=ws://localhost:3000/cable

# Development Settings
REACT_APP_AUTO_DETECT_BACKEND=true
```

### Phase 4: Security Documentation

#### 4.1 Create Security Guidelines
- Environment variable management
- Secret rotation procedures
- Development vs production configurations
- Key generation best practices

#### 4.2 Update Development Setup
- Modify setup scripts to copy .env.example files
- Add secret generation utilities
- Update documentation with security requirements

### Phase 5: Verification and Testing

#### 5.1 Verify Cleanup
```bash
# Check git history for sensitive patterns
git log --all --grep="password\|secret\|key" --oneline
git log --all -S "JWT_SECRET_KEY" --oneline
git log --all -S "STRIPE_SECRET_KEY" --oneline

# Verify .gitignore effectiveness
echo "test_secret_key" > test.env
git add test.env  # Should be ignored
git status  # Should not show test.env
rm test.env
```

#### 5.2 Test Application Functionality
- Ensure all services start correctly
- Verify authentication works
- Test payment gateway connections
- Confirm worker communication

## Post-Cleanup Actions

### Immediate Actions Required
1. **Regenerate All Secrets**: All exposed secrets must be considered compromised
2. **Rotate API Keys**: Update all Stripe, PayPal, and other service keys
3. **Update Production Deployments**: Ensure production uses new secrets
4. **Review Access Logs**: Check for any unauthorized access using old secrets

### Long-term Security Measures
1. **Secret Management Service**: Consider using HashiCorp Vault, AWS Secrets Manager, or similar
2. **Pre-commit Hooks**: Add hooks to prevent secret commits
3. **Regular Security Audits**: Periodic scans for exposed secrets
4. **Team Training**: Educate team on secret management best practices

## Risk Assessment

### Before Cleanup
- **Risk Level**: CRITICAL
- **Exposure**: Complete development credentials exposed
- **Impact**: Potential unauthorized access to development systems

### After Cleanup
- **Risk Level**: LOW
- **Exposure**: Historical exposure eliminated
- **Impact**: Minimal risk with proper secret rotation

## Timeline
- **Phase 1**: Immediate (< 1 hour)
- **Phase 2**: Same day (2-4 hours)
- **Phase 3**: Same day (1-2 hours)
- **Phase 4**: Within week (ongoing)
- **Phase 5**: Same day (1 hour)

## Notes
- **Backup Critical**: Always backup repository before history rewriting
- **Team Coordination**: Coordinate with team before rewriting shared history
- **Remote Impact**: History rewriting affects all team members and CI/CD systems
- **Force Push Required**: History rewriting requires force push to remote repositories

---

**CRITICAL WARNING**: Once git history is rewritten, all team members must re-clone the repository. All existing checkouts will be incompatible with the new history.