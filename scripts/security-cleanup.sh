#!/bin/bash

# Security Cleanup Script for Powernode Platform
# This script removes sensitive files from git tracking and prepares for history cleanup

set -e  # Exit on any error

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🔒 Powernode Platform Security Cleanup"
echo "====================================="
echo

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Check if git-filter-repo is available
check_requirements() {
    print_step "Checking requirements..."
    
    if ! command -v git-filter-repo &> /dev/null; then
        print_warning "git-filter-repo not found. Install with: pip3 install git-filter-repo"
        echo "Alternatively, we can use git rm --cached for index removal only"
    fi
    
    if ! git status --porcelain | grep -q '^' && [ -z "$(git status --porcelain)" ]; then
        print_success "Working directory is clean"
    else
        print_error "Working directory has uncommitted changes. Please commit or stash them first."
        exit 1
    fi
}

# Create backup
create_backup() {
    print_step "Creating repository backup..."
    
    BACKUP_DIR="../powernode-platform-backup-$(date +%Y%m%d_%H%M%S)"
    git clone --mirror . "$BACKUP_DIR"
    print_success "Backup created at $BACKUP_DIR"
}

# Remove sensitive files from git index (but keep local copies)
remove_from_index() {
    print_step "Removing sensitive files from git index..."
    
    # List of sensitive files to remove from git tracking
    SENSITIVE_FILES=(
        "server/.env"
        "worker/.env"
        "worker/.session.key"
        "server/config/master.key"
        "frontend/.env"
        "frontend/.env.development"
        "server/.kamal/secrets"
        "server/tmp/local_secret.txt"
    )
    
    for file in "${SENSITIVE_FILES[@]}"; do
        if git ls-files --error-unmatch "$file" &> /dev/null; then
            print_step "Removing $file from git index..."
            git rm --cached "$file" 2>/dev/null || echo "  File not in index: $file"
        else
            echo "  File not tracked: $file"
        fi
    done
    
    print_success "Sensitive files removed from git index"
}

# Update .env.example files
update_env_examples() {
    print_step "Updating .env.example files..."
    
    # Server .env.example
    cat > server/.env.example << 'EOF'
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
EOF

    # Worker .env.example
    cat > worker/.env.example << 'EOF'
# Worker Authentication Token
# This is generated automatically by the Rails application
# Run: rails db:seed to generate system worker token
WORKER_TOKEN=generate_via_rails_db_seed
EOF

    # Frontend .env.example
    cat > frontend/.env.example << 'EOF'
# Application Version
REACT_APP_VERSION=0.0.2

# API Configuration
REACT_APP_API_BASE_URL=http://localhost:3000/api/v1
REACT_APP_WS_BASE_URL=ws://localhost:3000/cable

# Development Settings
REACT_APP_AUTO_DETECT_BACKEND=true
EOF

    print_success ".env.example files updated"
}

# Test .gitignore effectiveness
test_gitignore() {
    print_step "Testing .gitignore effectiveness..."
    
    # Create test files that should be ignored
    echo "test_secret_key=12345" > test.env
    echo "test_private_key" > test.key
    echo "test_secret" > secret.txt
    
    # Check if git tries to track them
    git add . 2>/dev/null || true
    
    if git status --porcelain | grep -E "(test\.env|test\.key|secret\.txt)"; then
        print_error ".gitignore is not working correctly for test files"
        rm -f test.env test.key secret.txt
        exit 1
    else
        print_success ".gitignore is working correctly"
        rm -f test.env test.key secret.txt
    fi
}

# Commit the .gitignore and removal changes
commit_changes() {
    print_step "Committing security changes..."
    
    git add .gitignore
    git add server/.env.example worker/.env.example frontend/.env.example 2>/dev/null || true
    
    git commit -m "security: remove sensitive files from git tracking

- Remove .env files containing API keys and secrets
- Remove session keys and master encryption keys  
- Remove deployment secrets and temporary files
- Update comprehensive .gitignore patterns
- Add updated .env.example files with placeholders
- Files now properly protected from future commits

CRITICAL: All exposed secrets must be regenerated before production use" || {
        print_warning "No changes to commit (files may already be handled)"
    }
    
    print_success "Security changes committed"
}

# Show next steps for history cleanup
show_next_steps() {
    print_step "Next Steps for Complete Security Cleanup"
    echo
    print_warning "CRITICAL: The following actions are REQUIRED for complete security:"
    echo
    echo "1. Git History Cleanup (Choose one method):"
    echo "   Method A - git-filter-repo (recommended):"
    echo "   git filter-repo --path server/.env --invert-paths"
    echo "   git filter-repo --path worker/.env --invert-paths"  
    echo "   git filter-repo --path worker/.session.key --invert-paths"
    echo "   git filter-repo --path server/config/master.key --invert-paths"
    echo
    echo "   Method B - BFG Repo-Cleaner:"
    echo "   java -jar bfg.jar --delete-files '.env' ."
    echo "   java -jar bfg.jar --delete-files '*.key' ."
    echo
    echo "2. Regenerate ALL Secrets (CRITICAL):"
    echo "   - Generate new JWT_SECRET_KEY"
    echo "   - Rotate all API keys (Stripe, PayPal, etc.)"
    echo "   - Generate new Rails master.key"
    echo "   - Generate new session keys"
    echo "   - Update production deployments"
    echo
    echo "3. Force Push (After history cleanup):"
    echo "   git push --force-with-lease origin main"
    echo "   git push --force-with-lease origin develop"
    echo
    print_error "WARNING: History rewriting will require all team members to re-clone"
    echo
    echo "4. Copy environment files:"
    echo "   cp server/.env.example server/.env"
    echo "   cp worker/.env.example worker/.env"
    echo "   cp frontend/.env.example frontend/.env"
    echo "   # Then edit with actual values"
    echo
    print_success "See docs/platform/SECURITY_CLEANUP_PLAN.md for complete details"
}

# Main execution
main() {
    echo "This script will remove sensitive files from git tracking."
    echo "It will NOT rewrite git history - that requires a separate step."
    echo
    read -p "Continue? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    
    check_requirements
    create_backup
    remove_from_index
    update_env_examples
    test_gitignore
    commit_changes
    show_next_steps
    
    print_success "Security cleanup (index removal) completed successfully!"
    print_warning "REMEMBER: Git history still contains secrets - follow next steps above"
}

# Run main function
main "$@"