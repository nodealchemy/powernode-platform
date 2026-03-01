# Security Quick Start Guide

## 🚨 IMMEDIATE ACTION REQUIRED

### Current Security Risk
- **CRITICAL**: Sensitive files (.env, keys, secrets) are tracked in git history
- **EXPOSURE**: JWT secrets, API keys, database passwords visible in all commits
- **IMPACT**: Development credentials compromised, production at risk

### Quick Execution Steps

#### 1. Run Security Cleanup Script (5 minutes)
```bash
# Execute the automated cleanup
./scripts/security-cleanup.sh

# This will:
# - Remove sensitive files from git index
# - Update .gitignore with comprehensive patterns
# - Create proper .env.example files
# - Commit the security improvements
```

#### 2. Rewrite Git History (10-30 minutes)
Choose one method:

**Method A: git-filter-repo (Recommended)**
```bash
# Install if needed
pip3 install git-filter-repo

# Remove sensitive files from entire history
git filter-repo --path server/.env --invert-paths
git filter-repo --path worker/.env --invert-paths
git filter-repo --path worker/.session.key --invert-paths
git filter-repo --path server/config/master.key --invert-paths
```

**Method B: BFG Repo-Cleaner (Alternative)**
```bash
# Download BFG
wget https://repo1.maven.org/maven2/com/madgag/bfg/1.14.0/bfg-1.14.0.jar

# Clean history
java -jar bfg-1.14.0.jar --delete-files ".env" .
java -jar bfg-1.14.0.jar --delete-files "*.key" .
java -jar bfg-1.14.0.jar --delete-files "*secret*" .

# Cleanup
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

#### 3. Force Push Changes (2 minutes)
```bash
# Push cleaned history (DESTRUCTIVE - coordinates with team first)
git push --force-with-lease origin main
git push --force-with-lease origin develop
```

#### 4. Regenerate All Secrets (10-15 minutes)
```bash
# Copy example files
cp server/.env.example server/.env
cp worker/.env.example worker/.env  
cp frontend/.env.example frontend/.env

# Edit with new values - NEVER reuse old secrets
```

**Generate Secure Secrets:**
```bash
# JWT Secret (256-bit)
openssl rand -hex 32

# Rails Master Key
rails secret

# Database Password  
openssl rand -base64 32 | tr -d "=+/" | cut -c1-25

# Session Key
openssl rand -hex 32
```

### Critical Security Actions

#### Must Regenerate (NEVER reuse exposed values):
- [ ] JWT_SECRET_KEY
- [ ] Rails config/master.key
- [ ] Database passwords
- [ ] Stripe API keys (test and live)
- [ ] PayPal credentials
- [ ] Worker authentication tokens
- [ ] Session encryption keys

#### Team Coordination:
1. **Notify team BEFORE history rewrite**
2. **All team members must re-clone after force push**
3. **Update CI/CD systems with new secrets**
4. **Verify production systems use different secrets**

### Verification Steps

```bash
# Verify sensitive files are ignored
echo "TEST_SECRET=123" > test.env
git add test.env  # Should be ignored
git status  # Should not show test.env
rm test.env

# Check history is clean
git log --all --grep="secret\|password\|key" --oneline
git log --all -S "JWT_SECRET_KEY" --oneline  # Should be empty

# Test application
sudo systemctl start powernode.target  # Should start normally
```

### Post-Cleanup Checklist

- [ ] Git history cleaned (no sensitive files in any commit)
- [ ] All secrets regenerated (never reuse exposed values)
- [ ] .env files created from .example templates
- [ ] Application starts and functions normally
- [ ] Team notified and repositories re-cloned
- [ ] CI/CD updated with new secrets
- [ ] Production deployment verified secure

## Documentation References

- **Complete Plan**: `docs/platform/SECURITY_CLEANUP_PLAN.md`
- **Automated Script**: `scripts/security-cleanup.sh`
- **Environment Setup**: Individual `.env.example` files

## Support

If you encounter issues:
1. Check backup created in `../powernode-platform-backup-*`
2. Review detailed plan in `SECURITY_CLEANUP_PLAN.md`
3. Verify all team coordination before force push

**Time Estimate**: 30-60 minutes total (depending on method chosen)
**Team Impact**: All members must re-clone after completion
**Risk Level After**: LOW (with proper secret regeneration)