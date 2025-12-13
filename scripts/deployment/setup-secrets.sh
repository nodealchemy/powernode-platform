#!/bin/bash
# Docker secrets setup for remote deployment
# Usage: ./setup-secrets.sh [environment]

set -euo pipefail

ENVIRONMENT=${1:-production}
SECRET_PREFIX="${ENVIRONMENT}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

create_secret() {
    local secret_name="$1"
    local secret_value="$2"
    local description="${3:-}"
    
    if docker secret inspect "$secret_name" >/dev/null 2>&1; then
        log_info "Secret $secret_name already exists, skipping..."
        return 0
    fi
    
    if [[ -z "$secret_value" ]]; then
        log_warning "Empty value for secret $secret_name, skipping..."
        return 0
    fi
    
    if echo "$secret_value" | docker secret create "$secret_name" - >/dev/null 2>&1; then
        log_success "Created secret: $secret_name ${description:+($description)}"
        return 0
    else
        log_error "Failed to create secret: $secret_name"
        return 1
    fi
}

prompt_secret() {
    local prompt_text="$1"
    local secret_var="$2"
    local is_password="${3:-true}"
    
    if [[ "$is_password" == "true" ]]; then
        read -rsp "$prompt_text: " value
        echo >&2  # New line after password input
    else
        read -rp "$prompt_text: " value
    fi
    
    eval "$secret_var='$value'"
}

generate_password() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-25
}

generate_hex_secret() {
    local length=${1:-64}
    openssl rand -hex "$((length / 2))"
}

log_info "Setting up Docker secrets for environment: $ENVIRONMENT"

# Database secrets
log_info "Creating database secrets..."
create_secret "${SECRET_PREFIX}_db_name" "powernode_${ENVIRONMENT}" "database name"
create_secret "${SECRET_PREFIX}_db_user" "powernode" "database user"

# Generate or prompt for database password
if [[ "${AUTO_GENERATE_PASSWORDS:-true}" == "true" ]]; then
    db_password=$(generate_password)
    log_info "Auto-generated database password"
else
    prompt_secret "Enter database password for $ENVIRONMENT" db_password
fi
create_secret "${SECRET_PREFIX}_db_password" "$db_password" "database password"

# Redis secrets  
log_info "Creating Redis secrets..."
if [[ "${AUTO_GENERATE_PASSWORDS:-true}" == "true" ]]; then
    redis_password=$(generate_password)
    log_info "Auto-generated Redis password"
else
    prompt_secret "Enter Redis password for $ENVIRONMENT" redis_password
fi
create_secret "${SECRET_PREFIX}_redis_password" "$redis_password" "Redis password"

# Application secrets
log_info "Creating application secrets..."

# Rails master key
rails_master_key=""
if [[ -f "server/config/master.key" ]]; then
    rails_master_key=$(cat server/config/master.key)
    create_secret "${SECRET_PREFIX}_rails_master_key" "$rails_master_key" "Rails master key"
elif [[ -f "server/config/credentials/${ENVIRONMENT}.key" ]]; then
    rails_master_key=$(cat "server/config/credentials/${ENVIRONMENT}.key")
    create_secret "${SECRET_PREFIX}_rails_master_key" "$rails_master_key" "Rails environment key"
else
    log_warning "Rails master key not found at server/config/master.key"
    log_warning "You may need to create this secret manually"
fi

# JWT secret
jwt_secret=$(generate_hex_secret 64)
create_secret "${SECRET_PREFIX}_jwt_secret" "$jwt_secret" "JWT secret"

# Payment gateway secrets
log_info "Setting up payment gateway secrets..."

# Stripe
if [[ "${SKIP_PAYMENT_SECRETS:-false}" != "true" ]]; then
    stripe_secret=""
    if [[ -n "${STRIPE_SECRET_KEY:-}" ]]; then
        stripe_secret="$STRIPE_SECRET_KEY"
        log_info "Using Stripe secret from environment variable"
    else
        log_info "Enter Stripe secret key for $ENVIRONMENT"
        log_warning "This should be your live secret key for production (sk_live_...)"
        prompt_secret "Stripe Secret Key" stripe_secret
    fi
    create_secret "${SECRET_PREFIX}_stripe_secret_key" "$stripe_secret" "Stripe secret key"
    
    # PayPal
    paypal_secret=""
    if [[ -n "${PAYPAL_CLIENT_SECRET:-}" ]]; then
        paypal_secret="$PAYPAL_CLIENT_SECRET"
        log_info "Using PayPal secret from environment variable"
    else
        prompt_secret "PayPal Client Secret" paypal_secret
    fi
    create_secret "${SECRET_PREFIX}_paypal_client_secret" "$paypal_secret" "PayPal client secret"
else
    log_info "Skipping payment gateway secrets (SKIP_PAYMENT_SECRETS=true)"
fi

# Monitoring secrets
log_info "Creating monitoring secrets..."

# Grafana admin password
grafana_password=""
if [[ "${AUTO_GENERATE_PASSWORDS:-true}" == "true" ]]; then
    grafana_password=$(generate_password)
    log_info "Auto-generated Grafana admin password: $grafana_password"
    log_warning "Save this password! You'll need it to access Grafana"
else
    prompt_secret "Enter Grafana admin password" grafana_password
fi
create_secret "grafana_admin_password" "$grafana_password" "Grafana admin password"

# Additional secrets based on environment
case "$ENVIRONMENT" in
    production)
        log_info "Setting up production-specific secrets..."
        
        # SMTP secrets for production notifications
        if [[ "${SKIP_SMTP_SECRETS:-false}" != "true" ]]; then
            smtp_password=""
            if [[ -n "${SMTP_PASSWORD:-}" ]]; then
                smtp_password="$SMTP_PASSWORD"
            else
                prompt_secret "SMTP Password for production notifications" smtp_password
            fi
            create_secret "${SECRET_PREFIX}_smtp_password" "$smtp_password" "SMTP password"
        fi
        
        # SSL certificate secrets (if using custom certificates)
        if [[ "${CUSTOM_SSL_CERTS:-false}" == "true" ]]; then
            if [[ -f "certs/${ENVIRONMENT}/tls.crt" ]] && [[ -f "certs/${ENVIRONMENT}/tls.key" ]]; then
                create_secret "${SECRET_PREFIX}_tls_cert" "$(cat certs/${ENVIRONMENT}/tls.crt)" "TLS certificate"
                create_secret "${SECRET_PREFIX}_tls_key" "$(cat certs/${ENVIRONMENT}/tls.key)" "TLS private key"
            else
                log_warning "Custom SSL certificates not found in certs/${ENVIRONMENT}/"
            fi
        fi
        ;;
        
    staging)
        log_info "Setting up staging-specific secrets..."
        # Staging might use different credentials or test credentials
        ;;
esac

# Verify secrets were created
log_info "Verifying created secrets..."
created_secrets=$(docker secret ls --format "{{.Name}}" | grep "^${SECRET_PREFIX}_\|^grafana_" | wc -l)
log_success "Successfully created/verified $created_secrets secrets for environment: $ENVIRONMENT"

# List created secrets (without values)
echo
log_info "Created secrets for $ENVIRONMENT:"
docker secret ls --format "table {{.Name}}\t{{.CreatedAt}}" | grep -E "^(${SECRET_PREFIX}_|grafana_|NAME)"

echo
log_success "Secret setup completed for environment: $ENVIRONMENT"

# Provide helpful information
echo
log_info "=== Important Notes ==="
log_warning "• Secrets are stored securely in Docker Swarm"
log_warning "• Secret values cannot be retrieved once created"
log_warning "• To update a secret, you must remove and recreate it"
log_warning "• Always backup your secret values securely"

if [[ "${AUTO_GENERATE_PASSWORDS:-true}" == "true" ]]; then
    echo
    log_info "=== Auto-Generated Passwords ==="
    log_warning "Database Password: $db_password"
    log_warning "Redis Password: $redis_password"  
    log_warning "Grafana Admin Password: $grafana_password"
    log_warning "SAVE THESE PASSWORDS! They cannot be retrieved later."
fi

echo
log_info "=== Next Steps ==="
log_info "1. Verify all secrets are correct for your environment"
log_info "2. Proceed with deployment using: ./scripts/deploy-remote.sh $ENVIRONMENT"
log_info "3. Test the deployment thoroughly"

# Optional: Save passwords to a secure file
if [[ "${SAVE_PASSWORDS_TO_FILE:-false}" == "true" ]] && [[ "${AUTO_GENERATE_PASSWORDS:-true}" == "true" ]]; then
    password_file="secrets-${ENVIRONMENT}-$(date +%Y%m%d_%H%M%S).txt"
    cat > "$password_file" << EOF
# Powernode $ENVIRONMENT Environment - Generated Passwords
# Generated: $(date)
# WARNING: This file contains sensitive information. Store securely and delete after use.

Database Password: $db_password
Redis Password: $redis_password
Grafana Admin Password: $grafana_password
EOF
    
    chmod 600 "$password_file"
    log_info "Passwords saved to: $password_file"
    log_warning "Remember to store this file securely and delete it after recording the passwords!"
fi