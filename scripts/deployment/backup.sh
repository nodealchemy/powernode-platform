#!/bin/bash
# Backup script for Powernode Platform
# Usage: ./backup.sh [environment] [backup-type]

set -euo pipefail

ENVIRONMENT=${1:-production}
BACKUP_TYPE=${2:-full}  # full, database, files, config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

# Configuration
STACK_NAME="powernode-${ENVIRONMENT}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_BASE_DIR="${BACKUP_BASE_DIR:-/backups/powernode}"
BACKUP_DIR="${BACKUP_BASE_DIR}/${ENVIRONMENT}/${TIMESTAMP}"

# Retention settings
DATABASE_RETENTION_DAYS=${DATABASE_RETENTION_DAYS:-30}
FILES_RETENTION_DAYS=${FILES_RETENTION_DAYS:-7}
CONFIG_RETENTION_DAYS=${CONFIG_RETENTION_DAYS:-365}

# Load environment variables
load_env_vars() {
    local env_file="${PROJECT_ROOT}/.env.${ENVIRONMENT}"
    
    if [[ -f "$env_file" ]]; then
        log_info "Loading environment variables from $env_file"
        set -a
        source "$env_file"
        set +a
    else
        log_warning "Environment file $env_file not found"
    fi
}

# Create backup directory
create_backup_dir() {
    log_info "Creating backup directory: $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    
    # Create metadata file
    cat > "${BACKUP_DIR}/backup_metadata.json" << EOF
{
  "timestamp": "$TIMESTAMP",
  "environment": "$ENVIRONMENT",
  "backup_type": "$BACKUP_TYPE",
  "stack_name": "$STACK_NAME",
  "git_commit": "$(git rev-parse HEAD 2>/dev/null || echo 'unknown')",
  "git_branch": "$(git branch --show-current 2>/dev/null || echo 'unknown')",
  "backup_version": "1.0",
  "retention_days": {
    "database": $DATABASE_RETENTION_DAYS,
    "files": $FILES_RETENTION_DAYS,
    "config": $CONFIG_RETENTION_DAYS
  }
}
EOF
}

# Backup PostgreSQL database
backup_database() {
    log_info "Starting database backup..."
    
    local db_container
    db_container=$(docker service ps "${STACK_NAME}_postgres" --filter "desired-state=running" --format "{{.Name}}.{{.ID}}" | head -1)
    
    if [[ -z "$db_container" ]]; then
        log_error "PostgreSQL container not found"
        return 1
    fi
    
    local backup_file="${BACKUP_DIR}/database_${TIMESTAMP}.sql"
    local compressed_file="${backup_file}.gz"
    
    log_info "Creating database dump..."
    if docker exec "$db_container" pg_dumpall -U postgres > "$backup_file"; then
        log_success "Database dump created: $backup_file"
        
        # Compress the dump
        gzip "$backup_file"
        log_success "Database dump compressed: $compressed_file"
        
        # Verify the backup
        if verify_database_backup "$compressed_file"; then
            log_success "Database backup verification passed"
            
            # Create checksums
            sha256sum "$compressed_file" > "${compressed_file}.sha256"
            log_info "Checksum created: ${compressed_file}.sha256"
        else
            log_error "Database backup verification failed"
            return 1
        fi
    else
        log_error "Database dump failed"
        return 1
    fi
}

# Verify database backup
verify_database_backup() {
    local backup_file=$1
    
    log_info "Verifying database backup..."
    
    # Check if file exists and has content
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file does not exist: $backup_file"
        return 1
    fi
    
    local file_size=$(stat -f%z "$backup_file" 2>/dev/null || stat -c%s "$backup_file" 2>/dev/null)
    if [[ $file_size -lt 1000 ]]; then
        log_error "Backup file is too small (${file_size} bytes)"
        return 1
    fi
    
    # Verify gzip integrity
    if ! gzip -t "$backup_file" >/dev/null 2>&1; then
        log_error "Backup file is corrupted (gzip test failed)"
        return 1
    fi
    
    # Check for SQL content
    if ! zcat "$backup_file" | head -20 | grep -q "PostgreSQL database dump"; then
        log_error "Backup file doesn't appear to contain PostgreSQL dump"
        return 1
    fi
    
    log_success "Database backup verification passed"
    return 0
}

# Backup Redis data
backup_redis() {
    log_info "Starting Redis backup..."
    
    local redis_container
    redis_container=$(docker service ps "${STACK_NAME}_redis" --filter "desired-state=running" --format "{{.Name}}.{{.ID}}" | head -1)
    
    if [[ -z "$redis_container" ]]; then
        log_error "Redis container not found"
        return 1
    fi
    
    local backup_file="${BACKUP_DIR}/redis_${TIMESTAMP}.rdb"
    
    # Trigger Redis BGSAVE
    docker exec "$redis_container" redis-cli BGSAVE
    
    # Wait for backup to complete
    log_info "Waiting for Redis BGSAVE to complete..."
    while docker exec "$redis_container" redis-cli LASTSAVE | grep -q "$(docker exec "$redis_container" redis-cli LASTSAVE)"; do
        sleep 2
    done
    
    # Copy the RDB file
    if docker cp "${redis_container}:/data/dump.rdb" "$backup_file"; then
        log_success "Redis backup completed: $backup_file"
        
        # Compress and checksum
        gzip "$backup_file"
        sha256sum "${backup_file}.gz" > "${backup_file}.gz.sha256"
    else
        log_error "Redis backup failed"
        return 1
    fi
}

# Backup configuration files
backup_configuration() {
    log_info "Starting configuration backup..."
    
    local config_dir="${BACKUP_DIR}/configuration"
    mkdir -p "$config_dir"
    
    # Backup Docker stack configurations
    if [[ -d "${PROJECT_ROOT}/docker" ]]; then
        cp -r "${PROJECT_ROOT}/docker" "$config_dir/"
        log_info "Docker configurations backed up"
    fi
    
    # Backup monitoring configurations
    if [[ -d "${PROJECT_ROOT}/configs" ]]; then
        cp -r "${PROJECT_ROOT}/configs" "$config_dir/"
        log_info "Monitoring configurations backed up"
    fi
    
    # Backup deployment scripts
    if [[ -d "${PROJECT_ROOT}/scripts" ]]; then
        cp -r "${PROJECT_ROOT}/scripts" "$config_dir/"
        log_info "Deployment scripts backed up"
    fi
    
    # Backup environment files (without secrets)
    for env_file in "${PROJECT_ROOT}"/.env.*.example; do
        if [[ -f "$env_file" ]]; then
            cp "$env_file" "$config_dir/"
        fi
    done
    
    # Create archive
    local config_archive="${BACKUP_DIR}/configuration_${TIMESTAMP}.tar.gz"
    tar -czf "$config_archive" -C "$config_dir" .
    rm -rf "$config_dir"
    
    # Create checksum
    sha256sum "$config_archive" > "${config_archive}.sha256"
    
    log_success "Configuration backup completed: $config_archive"
}

# Backup Docker secrets (metadata only - not actual secrets)
backup_secrets_metadata() {
    log_info "Backing up secrets metadata..."
    
    local secrets_file="${BACKUP_DIR}/secrets_metadata_${TIMESTAMP}.json"
    
    # Get list of secrets (not their values)
    docker secret ls --format "json" > "$secrets_file"
    
    log_success "Secrets metadata backed up: $secrets_file"
}

# Backup service configurations
backup_service_state() {
    log_info "Backing up service configurations..."
    
    local services_dir="${BACKUP_DIR}/services"
    mkdir -p "$services_dir"
    
    # Get all services in the stack
    local services
    services=$(docker service ls --filter name="$STACK_NAME" --format "{{.Name}}")
    
    for service in $services; do
        log_info "Backing up service: $service"
        docker service inspect "$service" > "${services_dir}/${service}.json"
    done
    
    # Backup stack information
    docker stack ps "$STACK_NAME" --format "json" > "${services_dir}/stack_tasks.json"
    
    log_success "Service configurations backed up"
}

# Backup application files (volumes)
backup_volumes() {
    log_info "Starting volume backup..."
    
    local volumes_dir="${BACKUP_DIR}/volumes"
    mkdir -p "$volumes_dir"
    
    # Get list of volumes used by the stack
    local volumes
    volumes=$(docker volume ls --filter name="${STACK_NAME}" --format "{{.Name}}")
    
    for volume in $volumes; do
        log_info "Backing up volume: $volume"
        local volume_backup="${volumes_dir}/${volume}_${TIMESTAMP}.tar.gz"
        
        # Create a temporary container to access the volume
        docker run --rm \
            -v "${volume}:/backup-source:ro" \
            -v "$(dirname "$volume_backup"):/backup-dest" \
            alpine:latest \
            tar -czf "/backup-dest/$(basename "$volume_backup")" -C /backup-source .
        
        # Create checksum
        sha256sum "$volume_backup" > "${volume_backup}.sha256"
    done
    
    log_success "Volume backup completed"
}

# Upload backup to remote storage (if configured)
upload_backup() {
    if [[ -n "${BACKUP_STORAGE_URL:-}" ]]; then
        log_info "Uploading backup to remote storage..."
        
        case "$BACKUP_STORAGE_URL" in
            s3://*)
                aws s3 sync "$BACKUP_DIR" "$BACKUP_STORAGE_URL/$ENVIRONMENT/$TIMESTAMP/" --delete
                log_success "Backup uploaded to S3"
                ;;
            gs://*)
                gsutil -m rsync -r -d "$BACKUP_DIR" "$BACKUP_STORAGE_URL/$ENVIRONMENT/$TIMESTAMP/"
                log_success "Backup uploaded to Google Cloud Storage"
                ;;
            *)
                log_warning "Unsupported backup storage URL: $BACKUP_STORAGE_URL"
                ;;
        esac
    else
        log_info "No remote storage configured, backup stored locally only"
    fi
}

# Clean up old backups
cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    local base_dir="${BACKUP_BASE_DIR}/${ENVIRONMENT}"
    
    if [[ ! -d "$base_dir" ]]; then
        log_info "No old backups to clean up"
        return
    fi
    
    # Clean up based on backup type and retention policy
    case "$BACKUP_TYPE" in
        database)
            find "$base_dir" -name "database_*.sql.gz" -type f -mtime +$DATABASE_RETENTION_DAYS -delete
            ;;
        config)
            find "$base_dir" -name "configuration_*.tar.gz" -type f -mtime +$CONFIG_RETENTION_DAYS -delete
            ;;
        full)
            # For full backups, clean up entire directories older than the shortest retention
            local min_retention=$((DATABASE_RETENTION_DAYS < FILES_RETENTION_DAYS ? DATABASE_RETENTION_DAYS : FILES_RETENTION_DAYS))
            find "$base_dir" -maxdepth 1 -type d -mtime +$min_retention -exec rm -rf {} \; 2>/dev/null || true
            ;;
    esac
    
    log_success "Old backups cleaned up"
}

# Generate backup report
generate_backup_report() {
    log_info "Generating backup report..."
    
    local report_file="${BACKUP_DIR}/backup_report.json"
    local total_size=$(du -sb "$BACKUP_DIR" | cut -f1)
    local file_count=$(find "$BACKUP_DIR" -type f | wc -l)
    
    cat > "$report_file" << EOF
{
  "backup_info": {
    "timestamp": "$TIMESTAMP",
    "environment": "$ENVIRONMENT",
    "backup_type": "$BACKUP_TYPE",
    "status": "completed",
    "total_size_bytes": $total_size,
    "file_count": $file_count,
    "backup_dir": "$BACKUP_DIR"
  },
  "components": {
    "database": $(test -f "${BACKUP_DIR}/database_${TIMESTAMP}.sql.gz" && echo "true" || echo "false"),
    "redis": $(test -f "${BACKUP_DIR}/redis_${TIMESTAMP}.rdb.gz" && echo "true" || echo "false"),
    "configuration": $(test -f "${BACKUP_DIR}/configuration_${TIMESTAMP}.tar.gz" && echo "true" || echo "false"),
    "services": $(test -d "${BACKUP_DIR}/services" && echo "true" || echo "false"),
    "volumes": $(test -d "${BACKUP_DIR}/volumes" && echo "true" || echo "false")
  },
  "files": [
$(find "$BACKUP_DIR" -type f -exec basename {} \; | sed 's/^/    "/' | sed 's/$/"/' | paste -sd, -)
  ]
}
EOF
    
    log_success "Backup report generated: $report_file"
}

# Main backup function
main() {
    log_info "Starting Powernode Platform backup"
    log_info "Environment: $ENVIRONMENT"
    log_info "Backup type: $BACKUP_TYPE"
    log_info "Timestamp: $TIMESTAMP"
    
    # Validate environment
    case $ENVIRONMENT in
        staging|production)
            log_info "Valid environment: $ENVIRONMENT"
            ;;
        *)
            log_error "Invalid environment: $ENVIRONMENT. Must be 'staging' or 'production'"
            exit 1
            ;;
    esac
    
    # Load configuration
    load_env_vars
    
    # Check if stack exists
    if ! docker stack ps "$STACK_NAME" >/dev/null 2>&1; then
        log_error "Stack $STACK_NAME not found"
        exit 1
    fi
    
    # Create backup directory
    create_backup_dir
    
    # Perform backup based on type
    case "$BACKUP_TYPE" in
        full)
            backup_database
            backup_redis
            backup_configuration
            backup_secrets_metadata
            backup_service_state
            backup_volumes
            ;;
        database)
            backup_database
            backup_redis
            ;;
        files)
            backup_volumes
            ;;
        config)
            backup_configuration
            backup_secrets_metadata
            backup_service_state
            ;;
        *)
            log_error "Invalid backup type: $BACKUP_TYPE"
            log_error "Valid types: full, database, files, config"
            exit 1
            ;;
    esac
    
    # Upload to remote storage
    upload_backup
    
    # Generate report
    generate_backup_report
    
    # Clean up old backups
    cleanup_old_backups
    
    # Final summary
    local backup_size=$(du -sh "$BACKUP_DIR" | cut -f1)
    log_success "Backup completed successfully!"
    log_info "Backup location: $BACKUP_DIR"
    log_info "Backup size: $backup_size"
    log_info "Files created: $(find "$BACKUP_DIR" -type f | wc -l)"
    
    return 0
}

# Execute main function
main "$@"