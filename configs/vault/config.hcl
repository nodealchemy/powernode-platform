# HashiCorp Vault Server Configuration
# Powernode AI Agent Community Platform

# Storage backend - Raft for single-node or HA cluster
storage "raft" {
  path    = "/vault/data"
  node_id = "vault-1"

  # Performance tuning
  performance_multiplier = 1
}

# API listener
listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"

  # TLS Configuration - uncomment for production
  # tls_disable = false
  # tls_cert_file = "/vault/config/tls/cert.pem"
  # tls_key_file = "/vault/config/tls/key.pem"
  # tls_min_version = "tls12"

  # For development only - disable in production
  tls_disable = true
}

# API address for clients
api_addr = "http://vault:8200"
cluster_addr = "https://vault:8201"

# Enable UI
ui = true

# Telemetry for Prometheus
telemetry {
  prometheus_retention_time = "30s"
  disable_hostname = true
}

# Audit logging
# Enable via CLI: vault audit enable file file_path=/vault/logs/audit.log

# Maximum lease TTL
max_lease_ttl = "768h"
default_lease_ttl = "768h"

# Disable memory locking if running in container without IPC_LOCK
disable_mlock = false

# Logging
log_level = "info"
log_format = "json"
