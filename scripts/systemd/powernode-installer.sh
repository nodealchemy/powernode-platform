#!/usr/bin/env bash
# Powernode Platform - Systemd Service Installer
# Manages installation, instances, and configuration of systemd services.
#
# Usage:
#   powernode-installer.sh install [--production]
#   powernode-installer.sh uninstall [--purge]
#   powernode-installer.sh add-instance <service> <name>
#   powernode-installer.sh remove-instance <service> <name>
#   powernode-installer.sh enable <service> [instance]
#   powernode-installer.sh disable <service> [instance]
#   powernode-installer.sh status
#   powernode-installer.sh generate-nginx <instance>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNITS_DIR="${SCRIPT_DIR}/units"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
NGINX_DIR="${SCRIPT_DIR}/nginx"

SYSTEMD_DIR="/etc/systemd/system"
CONFIG_DIR="/etc/powernode"

SERVICES=(backend worker worker-web frontend)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This command must be run as root (use sudo)"
        exit 1
    fi
}

# ──────────────────────────────────────────────────────────────────
# detect_environment - Auto-detect RVM, nvm, Ruby, Node versions
# ──────────────────────────────────────────────────────────────────
detect_rvm_path() {
    if [[ -n "${RVM_PATH:-}" ]]; then
        echo "${RVM_PATH}"
    elif [[ -d "/usr/local/rvm" ]]; then
        echo "/usr/local/rvm"
    elif [[ -d "${HOME}/.rvm" ]]; then
        echo "${HOME}/.rvm"
    elif [[ -d "${SUDO_USER:+/home/${SUDO_USER}/.rvm}" ]]; then
        echo "/home/${SUDO_USER}/.rvm"
    else
        echo ""
    fi
}

detect_ruby_version() {
    local rvm_path="$1"
    if [[ -n "${rvm_path}" ]] && [[ -s "${rvm_path}/scripts/rvm" ]]; then
        # Source RVM temporarily to detect the current default
        (source "${rvm_path}/scripts/rvm" 2>/dev/null && rvm current 2>/dev/null) || echo ""
    elif command -v ruby &>/dev/null; then
        ruby -e 'puts "ruby-#{RUBY_VERSION}"' 2>/dev/null || echo ""
    else
        echo ""
    fi
}

detect_nvm_dir() {
    if [[ -n "${NVM_DIR:-}" ]]; then
        echo "${NVM_DIR}"
    elif [[ -d "${HOME}/.nvm" ]]; then
        echo "${HOME}/.nvm"
    elif [[ -n "${SUDO_USER:-}" ]] && [[ -d "/home/${SUDO_USER}/.nvm" ]]; then
        echo "/home/${SUDO_USER}/.nvm"
    else
        echo ""
    fi
}

detect_node_version() {
    local nvm_dir="$1"
    if [[ -n "${nvm_dir}" ]] && [[ -s "${nvm_dir}/nvm.sh" ]]; then
        (source "${nvm_dir}/nvm.sh" 2>/dev/null && node --version 2>/dev/null | sed 's/^v//') || echo ""
    elif command -v node &>/dev/null; then
        node --version 2>/dev/null | sed 's/^v//' || echo ""
    else
        echo ""
    fi
}

detect_powernode_base() {
    # Walk up from script dir to find project root (contains server/, frontend/, worker/)
    local dir="${SCRIPT_DIR}"
    while [[ "${dir}" != "/" ]]; do
        if [[ -d "${dir}/server" ]] && [[ -d "${dir}/frontend" ]] && [[ -d "${dir}/worker" ]]; then
            echo "${dir}"
            return
        fi
        dir="$(dirname "${dir}")"
    done
    echo "/opt/powernode"
}

# ──────────────────────────────────────────────────────────────────
# install - Install systemd units and configuration
# ──────────────────────────────────────────────────────────────────
cmd_install() {
    require_root

    local production=false
    local run_user="${SUDO_USER:-$(whoami)}"
    local run_group="$(id -gn "${run_user}" 2>/dev/null || echo "${run_user}")"

    if [[ "${1:-}" == "--production" ]]; then
        production=true
    fi

    log_info "Installing Powernode systemd services..."

    # Production: create system user
    if [[ "${production}" == true ]]; then
        if ! id -u powernode &>/dev/null; then
            log_info "Creating system user 'powernode'..."
            useradd --system --shell /usr/sbin/nologin --home-dir /opt/powernode --create-home powernode
            log_ok "System user 'powernode' created"
        else
            log_ok "System user 'powernode' already exists"
        fi
        run_user="powernode"
        run_group="powernode"
    fi

    # Create config directory
    log_info "Setting up ${CONFIG_DIR}..."
    mkdir -p "${CONFIG_DIR}"
    if [[ "${production}" == true ]]; then
        chown root:powernode "${CONFIG_DIR}"
    else
        chown "root:${run_group}" "${CONFIG_DIR}"
    fi
    chmod 750 "${CONFIG_DIR}"
    log_ok "Config directory ready"

    # Auto-detect environment
    local detected_rvm_path detected_ruby detected_nvm_dir detected_node detected_base
    detected_rvm_path="$(detect_rvm_path)"
    detected_ruby="$(detect_ruby_version "${detected_rvm_path}")"
    detected_nvm_dir="$(detect_nvm_dir)"
    detected_node="$(detect_node_version "${detected_nvm_dir}")"
    detected_base="$(detect_powernode_base)"

    log_info "Detected environment:"
    log_info "  Base path:     ${detected_base}"
    log_info "  RVM path:      ${detected_rvm_path:-not found}"
    log_info "  Ruby version:  ${detected_ruby:-not found}"
    log_info "  nvm dir:       ${detected_nvm_dir:-not found}"
    log_info "  Node version:  ${detected_node:-not found}"
    log_info "  Run as:        ${run_user}:${run_group}"

    # Install config templates (never overwrite existing)
    log_info "Installing config templates..."
    for conf_file in "${CONFIGS_DIR}"/*.conf; do
        local basename="$(basename "${conf_file}")"
        local dest="${CONFIG_DIR}/${basename}"
        if [[ -f "${dest}" ]]; then
            log_warn "Skipping ${basename} (already exists)"
        else
            cp "${conf_file}" "${dest}"

            # Patch auto-detected values into powernode.conf
            if [[ "${basename}" == "powernode.conf" ]]; then
                sed -i "s|^POWERNODE_BASE=.*|POWERNODE_BASE=${detected_base}|" "${dest}"
                [[ -n "${detected_rvm_path}" ]] && sed -i "s|^RVM_PATH=.*|RVM_PATH=${detected_rvm_path}|" "${dest}"
                [[ -n "${detected_ruby}" ]] && sed -i "s|^POWERNODE_RUBY_VERSION=.*|POWERNODE_RUBY_VERSION=${detected_ruby}|" "${dest}"
                [[ -n "${detected_nvm_dir}" ]] && sed -i "s|^NVM_DIR=.*|NVM_DIR=${detected_nvm_dir}|" "${dest}"
                [[ -n "${detected_node}" ]] && sed -i "s|^NODE_VERSION=.*|NODE_VERSION=${detected_node}|" "${dest}"

                if [[ "${production}" == true ]]; then
                    sed -i "s|^POWERNODE_MODE=.*|POWERNODE_MODE=production|" "${dest}"
                fi
            fi

            chown "root:${run_group}" "${dest}"
            chmod 640 "${dest}"
            log_ok "Installed ${basename}"
        fi
    done

    # Install unit files with User/Group injection
    log_info "Installing systemd unit files..."
    for unit_file in "${UNITS_DIR}"/*; do
        local basename="$(basename "${unit_file}")"
        local dest="${SYSTEMD_DIR}/${basename}"

        # For .service files, inject User= and Group= into [Service] section
        if [[ "${basename}" == *.service ]]; then
            sed -e "/^\[Service\]/a User=${run_user}\nGroup=${run_group}" \
                "${unit_file}" > "${dest}"
        else
            cp "${unit_file}" "${dest}"
        fi
        chmod 644 "${dest}"
        log_ok "Installed ${basename}"
    done

    # Make wrapper scripts executable
    log_info "Setting wrapper script permissions..."
    chmod +x "${SCRIPT_DIR}"/powernode-*.sh
    log_ok "Wrapper scripts are executable"

    # Ensure WorkingDirectory paths reference detected base
    log_info "Patching unit file paths to ${detected_base}..."
    for dest in "${SYSTEMD_DIR}"/powernode-*.service; do
        sed -i "s|/opt/powernode|${detected_base}|g" "${dest}"
    done
    log_ok "Paths updated"

    # Production: enable security hardening directives
    if [[ "${production}" == true ]]; then
        log_info "Enabling security hardening for production..."
        for dest in "${SYSTEMD_DIR}"/powernode-*.service; do
            sed -i 's|^# \(NoNewPrivileges=\)|\1|' "${dest}"
            sed -i 's|^# \(ProtectSystem=\)|\1|' "${dest}"
            sed -i 's|^# \(PrivateTmp=\)|\1|' "${dest}"
            sed -i 's|^# \(ReadWritePaths=\)|\1|' "${dest}"
        done
        log_ok "Security hardening enabled"
    fi

    # Production: create flag file to disable frontend dev server
    if [[ "${production}" == true ]]; then
        touch "${CONFIG_DIR}/no-frontend"
        log_ok "Frontend dev server disabled (production mode)"
    else
        rm -f "${CONFIG_DIR}/no-frontend"
    fi

    # Reload systemd
    systemctl daemon-reload
    log_ok "systemd daemon reloaded"

    # Enable default instances
    log_info "Enabling default service instances..."
    systemctl enable powernode.target 2>/dev/null || true
    for svc in "${SERVICES[@]}"; do
        systemctl enable "powernode-${svc}@default.service" 2>/dev/null || true
        log_ok "Enabled powernode-${svc}@default"
    done

    echo ""
    log_ok "Installation complete!"
    echo ""
    echo "  Start all services:   sudo systemctl start powernode.target"
    echo "  Check status:         sudo systemctl status 'powernode-*'"
    echo "  View logs:            journalctl -u powernode-backend@default -f"
    echo ""
    echo "  Config files:         ${CONFIG_DIR}/"
    echo "  Unit files:           ${SYSTEMD_DIR}/powernode-*"
    echo ""
    if [[ "${production}" == true ]]; then
        echo "  Production mode enabled. Frontend service will not start."
        echo "  Build frontend:       cd ${detected_base}/frontend && npm run build"
        echo "  Generate nginx:       sudo ${SCRIPT_DIR}/powernode-installer.sh generate-nginx default"
    fi
}

# ──────────────────────────────────────────────────────────────────
# uninstall - Remove systemd units and optionally configs
# ──────────────────────────────────────────────────────────────────
cmd_uninstall() {
    require_root

    local purge=false
    if [[ "${1:-}" == "--purge" ]]; then
        purge=true
    fi

    log_info "Uninstalling Powernode systemd services..."

    # Stop all services
    log_info "Stopping all Powernode services..."
    systemctl stop powernode.target 2>/dev/null || true
    for svc in "${SERVICES[@]}"; do
        # Stop all instances of each service type
        for unit in $(systemctl list-units --all --no-legend "powernode-${svc}@*" 2>/dev/null | awk '{print $1}'); do
            systemctl stop "${unit}" 2>/dev/null || true
            systemctl disable "${unit}" 2>/dev/null || true
        done
    done
    systemctl disable powernode.target 2>/dev/null || true

    # Remove unit files
    log_info "Removing unit files..."
    rm -f "${SYSTEMD_DIR}"/powernode-backend@.service
    rm -f "${SYSTEMD_DIR}"/powernode-worker@.service
    rm -f "${SYSTEMD_DIR}"/powernode-worker-web@.service
    rm -f "${SYSTEMD_DIR}"/powernode-frontend@.service
    rm -f "${SYSTEMD_DIR}"/powernode.target
    log_ok "Unit files removed"

    systemctl daemon-reload
    log_ok "systemd daemon reloaded"

    if [[ "${purge}" == true ]]; then
        log_info "Purging configuration..."
        rm -rf "${CONFIG_DIR}"
        log_ok "Config directory ${CONFIG_DIR} removed"
    else
        log_info "Config files preserved at ${CONFIG_DIR}/ (use --purge to remove)"
    fi

    echo ""
    log_ok "Uninstall complete"
}

# ──────────────────────────────────────────────────────────────────
# add-instance - Create a new service instance
# ──────────────────────────────────────────────────────────────────
cmd_add_instance() {
    require_root

    local service="${1:-}"
    local name="${2:-}"

    if [[ -z "${service}" ]] || [[ -z "${name}" ]]; then
        log_error "Usage: powernode-installer.sh add-instance <service> <name>"
        log_error "Services: ${SERVICES[*]}"
        exit 1
    fi

    # Validate service name
    local valid=false
    for svc in "${SERVICES[@]}"; do
        if [[ "${svc}" == "${service}" ]]; then
            valid=true
            break
        fi
    done
    if [[ "${valid}" != true ]]; then
        log_error "Unknown service '${service}'. Valid: ${SERVICES[*]}"
        exit 1
    fi

    # Validate instance name (alphanumeric + hyphens)
    if [[ ! "${name}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
        log_error "Instance name must be alphanumeric with hyphens (e.g., 'api2', 'ai-heavy')"
        exit 1
    fi

    local config_file="${CONFIG_DIR}/${service}-${name}.conf"
    local default_config="${CONFIG_DIR}/${service}-default.conf"

    if [[ -f "${config_file}" ]]; then
        log_error "Instance config already exists: ${config_file}"
        exit 1
    fi

    if [[ ! -f "${default_config}" ]]; then
        log_error "Default config not found: ${default_config}"
        log_error "Run 'install' first"
        exit 1
    fi

    # Copy default config as template
    cp "${default_config}" "${config_file}"

    # Update the instance header comment
    sed -i "s/^# Instance: default/# Instance: ${name}/" "${config_file}"

    # Preserve ownership/permissions from default
    local owner group
    owner="$(stat -c '%U' "${default_config}")"
    group="$(stat -c '%G' "${default_config}")"
    chown "${owner}:${group}" "${config_file}"
    chmod 640 "${config_file}"

    log_ok "Created instance config: ${config_file}"
    echo ""
    echo "  Next steps:"
    echo "    1. Edit the config:    sudo nano ${config_file}"
    echo "       (at minimum, change the PORT to avoid conflicts)"
    echo "    2. Enable and start:   sudo systemctl enable --now powernode-${service}@${name}"
    echo "    3. Check status:       sudo systemctl status powernode-${service}@${name}"
}

# ──────────────────────────────────────────────────────────────────
# remove-instance - Remove a service instance
# ──────────────────────────────────────────────────────────────────
cmd_remove_instance() {
    require_root

    local service="${1:-}"
    local name="${2:-}"

    if [[ -z "${service}" ]] || [[ -z "${name}" ]]; then
        log_error "Usage: powernode-installer.sh remove-instance <service> <name>"
        exit 1
    fi

    if [[ "${name}" == "default" ]]; then
        log_error "Cannot remove the default instance. Use 'uninstall' instead."
        exit 1
    fi

    local unit="powernode-${service}@${name}.service"
    local config_file="${CONFIG_DIR}/${service}-${name}.conf"

    # Stop and disable the instance
    if systemctl is-active "${unit}" &>/dev/null; then
        log_info "Stopping ${unit}..."
        systemctl stop "${unit}"
    fi
    if systemctl is-enabled "${unit}" &>/dev/null; then
        log_info "Disabling ${unit}..."
        systemctl disable "${unit}"
    fi

    # Remove config
    if [[ -f "${config_file}" ]]; then
        rm -f "${config_file}"
        log_ok "Removed config: ${config_file}"
    fi

    log_ok "Instance '${name}' of '${service}' removed"
}

# ──────────────────────────────────────────────────────────────────
# enable / disable - Enable or disable a service instance
# ──────────────────────────────────────────────────────────────────
cmd_enable() {
    require_root
    local service="${1:-}"
    local instance="${2:-default}"

    if [[ -z "${service}" ]]; then
        log_error "Usage: powernode-installer.sh enable <service> [instance]"
        exit 1
    fi

    local unit="powernode-${service}@${instance}.service"
    systemctl enable "${unit}"
    log_ok "Enabled ${unit}"
    echo "  Start with: sudo systemctl start ${unit}"
}

cmd_disable() {
    require_root
    local service="${1:-}"
    local instance="${2:-default}"

    if [[ -z "${service}" ]]; then
        log_error "Usage: powernode-installer.sh disable <service> [instance]"
        exit 1
    fi

    local unit="powernode-${service}@${instance}.service"
    systemctl disable "${unit}"
    log_ok "Disabled ${unit}"
}

# ──────────────────────────────────────────────────────────────────
# status - Show status of all Powernode services
# ──────────────────────────────────────────────────────────────────
cmd_status() {
    echo ""
    echo "Powernode Platform Service Status"
    echo "================================="
    echo ""

    # Target status
    local target_status
    target_status="$(systemctl is-active powernode.target 2>/dev/null || echo "inactive")"
    printf "  %-40s %s\n" "powernode.target" "${target_status}"
    echo ""

    # Per-service status
    for svc in "${SERVICES[@]}"; do
        local found=false
        # Find all instances of this service type
        while IFS= read -r unit; do
            [[ -z "${unit}" ]] && continue
            found=true
            local state active_state sub_state
            active_state="$(systemctl show -p ActiveState --value "${unit}" 2>/dev/null || echo "unknown")"
            sub_state="$(systemctl show -p SubState --value "${unit}" 2>/dev/null || echo "")"

            local color="${NC}"
            case "${active_state}" in
                active)   color="${GREEN}" ;;
                failed)   color="${RED}" ;;
                inactive) color="${YELLOW}" ;;
            esac

            printf "  %-40s ${color}%s${NC}" "${unit}" "${active_state}"
            [[ -n "${sub_state}" ]] && printf " (%s)" "${sub_state}"
            echo ""
        done < <(systemctl list-units --all --no-legend "powernode-${svc}@*" 2>/dev/null | awk '{print $1}')

        # Also check for enabled-but-not-loaded instances via config files
        if [[ -d "${CONFIG_DIR}" ]]; then
            for conf in "${CONFIG_DIR}/${svc}"-*.conf; do
                [[ -f "${conf}" ]] || continue
                local basename_conf instance_name
                basename_conf="$(basename "${conf}" .conf)"
                # Skip false matches (e.g. worker-web-* matching worker-*)
                # Verify the prefix is exactly "${svc}-" not a longer service name
                instance_name="${basename_conf#"${svc}-"}"
                if [[ "${svc}-${instance_name}" != "${basename_conf}" ]]; then
                    continue
                fi
                # Also skip if instance_name itself starts with a known service suffix
                # e.g. "web-default" when svc=worker (that belongs to worker-web)
                local is_other_svc=false
                for other in "${SERVICES[@]}"; do
                    if [[ "${other}" != "${svc}" ]] && [[ "${other}" == "${svc}-"* ]]; then
                        local suffix="${other#"${svc}-"}"
                        if [[ "${instance_name}" == "${suffix}-"* ]] || [[ "${instance_name}" == "${suffix}" ]]; then
                            is_other_svc=true
                            break
                        fi
                    fi
                done
                [[ "${is_other_svc}" == true ]] && continue

                local unit_name="powernode-${svc}@${instance_name}.service"
                # Skip if already listed
                if ! systemctl list-units --all --no-legend "${unit_name}" 2>/dev/null | grep -q "${unit_name}"; then
                    printf "  %-40s ${YELLOW}not loaded${NC} (config exists)\n" "${unit_name}"
                    found=true
                fi
            done
        fi

        if [[ "${found}" != true ]]; then
            printf "  %-40s ${YELLOW}no instances${NC}\n" "powernode-${svc}@*"
        fi
    done

    echo ""

    # Show config files
    if [[ -d "${CONFIG_DIR}" ]]; then
        echo "Configuration files:"
        for conf in "${CONFIG_DIR}"/*.conf; do
            [[ -f "${conf}" ]] || continue
            echo "  ${conf}"
        done
        echo ""
    fi
}

# ──────────────────────────────────────────────────────────────────
# generate-nginx - Generate nginx config for production frontend
# ──────────────────────────────────────────────────────────────────
cmd_generate_nginx() {
    local instance="${1:-default}"
    local template="${NGINX_DIR}/powernode-frontend.conf.template"

    if [[ ! -f "${template}" ]]; then
        log_error "Nginx template not found: ${template}"
        exit 1
    fi

    # Read backend port from instance config
    local backend_config="${CONFIG_DIR}/backend-${instance}.conf"
    local backend_port="3000"
    if [[ -f "${backend_config}" ]]; then
        backend_port="$(grep -E '^PORT=' "${backend_config}" | cut -d= -f2 || echo "3000")"
    fi

    # Read base path
    local base_path="/opt/powernode"
    if [[ -f "${CONFIG_DIR}/powernode.conf" ]]; then
        base_path="$(grep -E '^POWERNODE_BASE=' "${CONFIG_DIR}/powernode.conf" | cut -d= -f2 || echo "/opt/powernode")"
    fi

    local build_path="${base_path}/frontend/build"
    local domain="localhost"
    local output="/tmp/powernode-frontend-${instance}.conf"

    sed -e "s|__INSTANCE__|${instance}|g" \
        -e "s|__DOMAIN__|${domain}|g" \
        -e "s|__BACKEND_PORT__|${backend_port}|g" \
        -e "s|__BUILD_PATH__|${build_path}|g" \
        "${template}" > "${output}"

    log_ok "Nginx config generated: ${output}"
    echo ""
    echo "  Review:    cat ${output}"
    echo "  Install:   sudo cp ${output} /etc/nginx/sites-available/powernode-${instance}"
    echo "  Enable:    sudo ln -sf /etc/nginx/sites-available/powernode-${instance} /etc/nginx/sites-enabled/"
    echo "  Test:      sudo nginx -t"
    echo "  Reload:    sudo systemctl reload nginx"
    echo ""
    echo "  Edit ${output} to set the correct server_name (domain) before installing."
}

# ──────────────────────────────────────────────────────────────────
# Main dispatcher
# ──────────────────────────────────────────────────────────────────
usage() {
    echo "Powernode Platform - Systemd Service Installer"
    echo ""
    echo "Usage: $(basename "$0") <command> [options]"
    echo ""
    echo "Commands:"
    echo "  install [--production]           Install units, configs, optionally create system user"
    echo "  uninstall [--purge]              Remove units, optionally purge configs"
    echo "  add-instance <service> <name>    Create a new instance config"
    echo "  remove-instance <service> <name> Remove an instance"
    echo "  enable <service> [instance]      Enable a service instance (default: 'default')"
    echo "  disable <service> [instance]     Disable a service instance"
    echo "  status                           Show all service instances status"
    echo "  generate-nginx <instance>        Generate nginx config for production"
    echo ""
    echo "Services: ${SERVICES[*]}"
    echo ""
    echo "Examples:"
    echo "  sudo $(basename "$0") install"
    echo "  sudo $(basename "$0") install --production"
    echo "  sudo $(basename "$0") add-instance backend api2"
    echo "  sudo $(basename "$0") status"
    echo "  sudo $(basename "$0") generate-nginx default"
}

command="${1:-}"
shift || true

case "${command}" in
    install)          cmd_install "$@" ;;
    uninstall)        cmd_uninstall "$@" ;;
    add-instance)     cmd_add_instance "$@" ;;
    remove-instance)  cmd_remove_instance "$@" ;;
    enable)           cmd_enable "$@" ;;
    disable)          cmd_disable "$@" ;;
    status)           cmd_status ;;
    generate-nginx)   cmd_generate_nginx "$@" ;;
    help|--help|-h)   usage ;;
    *)
        if [[ -n "${command}" ]]; then
            log_error "Unknown command: ${command}"
        fi
        usage
        exit 1
        ;;
esac
