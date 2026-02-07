#!/usr/bin/env bash
# Powernode Docker Package Manager
# Creates versioned release packages with all artifacts needed for deployment.
#
# Usage:
#   powernode-package.sh create [--version <ver>]  # Build images + create package
#   powernode-package.sh export [--version <ver>]  # Export images to tar archives
#   powernode-package.sh import <package-dir>      # Import images from tar archives
#   powernode-package.sh list                      # List local powernode images
#   powernode-package.sh clean [--keep <n>]        # Remove old images (keep latest n)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY="${POWERNODE_REGISTRY:-docker.io/powernode}"
SERVICES=(backend worker frontend)
PACKAGE_DIR="${PROJECT_ROOT}/packages"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[PKG]${NC}    $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

get_version() {
    local version="${1:-}"
    if [[ -z "${version}" ]] && [[ -f "${PROJECT_ROOT}/frontend/VERSION" ]]; then
        version="$(cat "${PROJECT_ROOT}/frontend/VERSION")"
    fi
    if [[ -z "${version}" ]]; then
        version="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "dev")"
    fi
    echo "${version}"
}

# ──────────────────────────────────────────────────────────────────
# create - Build all images and create a deployment package
# ──────────────────────────────────────────────────────────────────
cmd_create() {
    local version=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    version="$(get_version "${version}")"

    log_info "Creating release package v${version}..."

    # Build all images
    "${SCRIPT_DIR}/powernode-build.sh" --tag "${version}" --latest

    # Create package directory
    local pkg_dir="${PACKAGE_DIR}/${version}"
    mkdir -p "${pkg_dir}"

    # Copy deployment files
    log_info "Packaging deployment files..."
    cp "${PROJECT_ROOT}/docker-compose.prod.yml" "${pkg_dir}/docker-compose.yml"
    cp -r "${PROJECT_ROOT}/docker/swarm" "${pkg_dir}/swarm" 2>/dev/null || true
    cp "${PROJECT_ROOT}/scripts/deployment/deploy.sh" "${pkg_dir}/" 2>/dev/null || true
    cp "${PROJECT_ROOT}/scripts/deployment/health-check.sh" "${pkg_dir}/" 2>/dev/null || true

    # Create .env template
    cat > "${pkg_dir}/.env.template" <<'ENVEOF'
# Powernode Deployment Configuration
# Copy to .env and fill in values before deploying.

# Domain
DOMAIN=example.com
ACME_EMAIL=admin@example.com

# Database
POSTGRES_USER=powernode
POSTGRES_PASSWORD=CHANGE_ME
POSTGRES_DB=powernode_production

# Redis
REDIS_PASSWORD=CHANGE_ME

# Application Secrets
SECRET_KEY_BASE=CHANGE_ME
JWT_SECRET=CHANGE_ME
WORKER_API_KEY=CHANGE_ME

# Payments (optional)
STRIPE_API_KEY=
STRIPE_WEBHOOK_SECRET=
PAYPAL_CLIENT_ID=
PAYPAL_CLIENT_SECRET=

# Traefik Dashboard Auth (htpasswd format)
TRAEFIK_AUTH=admin:$$apr1$$...
ENVEOF

    # Write manifest
    cat > "${pkg_dir}/manifest.json" <<MANIFEST
{
  "name": "powernode",
  "version": "${version}",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "git_commit": "$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)",
  "git_branch": "$(git -C "${PROJECT_ROOT}" branch --show-current 2>/dev/null || echo unknown)",
  "images": {
    "backend": "${REGISTRY}/backend:${version}",
    "worker": "${REGISTRY}/worker:${version}",
    "frontend": "${REGISTRY}/frontend:${version}"
  }
}
MANIFEST

    log_ok "Package created: ${pkg_dir}/"
    echo ""
    echo "  Contents:"
    ls -1 "${pkg_dir}" | while read -r f; do echo "    ${f}"; done
    echo ""
    echo "  Deploy with:"
    echo "    cd ${pkg_dir}"
    echo "    cp .env.template .env  # fill in secrets"
    echo "    docker compose up -d"
}

# ──────────────────────────────────────────────────────────────────
# export - Save Docker images as tar archives for offline transfer
# ──────────────────────────────────────────────────────────────────
cmd_export() {
    local version=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --version) version="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    version="$(get_version "${version}")"

    local export_dir="${PACKAGE_DIR}/${version}/images"
    mkdir -p "${export_dir}"

    log_info "Exporting images for v${version}..."

    for service in "${SERVICES[@]}"; do
        local image="${REGISTRY}/${service}:${version}"
        local archive="${export_dir}/${service}.tar.gz"

        if docker image inspect "${image}" &>/dev/null; then
            log_info "Exporting ${image}..."
            docker save "${image}" | gzip > "${archive}"
            local size
            size="$(du -h "${archive}" | cut -f1)"
            log_ok "${service} exported (${size})"
        else
            log_warn "${image} not found locally, skipping"
        fi
    done

    log_ok "Images exported to: ${export_dir}/"
}

# ──────────────────────────────────────────────────────────────────
# import - Load Docker images from tar archives
# ──────────────────────────────────────────────────────────────────
cmd_import() {
    local pkg_dir="${1:-}"
    if [[ -z "${pkg_dir}" ]]; then
        log_error "Usage: powernode-package.sh import <package-dir>"
        exit 1
    fi

    local images_dir="${pkg_dir}/images"
    if [[ ! -d "${images_dir}" ]]; then
        # Try looking for images directly in the package dir
        images_dir="${pkg_dir}"
    fi

    log_info "Importing images from ${images_dir}..."

    for archive in "${images_dir}"/*.tar.gz; do
        [[ -f "${archive}" ]] || continue
        local name
        name="$(basename "${archive}" .tar.gz)"
        log_info "Loading ${name}..."
        docker load -i "${archive}"
        log_ok "${name} loaded"
    done

    log_ok "Import complete"
}

# ──────────────────────────────────────────────────────────────────
# list - Show local powernode images
# ──────────────────────────────────────────────────────────────────
cmd_list() {
    echo ""
    echo "Powernode Docker Images"
    echo "======================"
    echo ""

    for service in "${SERVICES[@]}"; do
        echo "  ${service}:"
        docker images "${REGISTRY}/${service}" --format "    {{.Tag}}\t{{.Size}}\t{{.CreatedSince}}" 2>/dev/null | head -10
        echo ""
    done

    # Also show any packages
    if [[ -d "${PACKAGE_DIR}" ]]; then
        echo "  Local packages:"
        for pkg in "${PACKAGE_DIR}"/*/manifest.json; do
            [[ -f "${pkg}" ]] || continue
            local ver
            ver="$(dirname "${pkg}")"
            ver="$(basename "${ver}")"
            echo "    ${ver}"
        done
        echo ""
    fi
}

# ──────────────────────────────────────────────────────────────────
# clean - Remove old images, keeping the latest n versions
# ──────────────────────────────────────────────────────────────────
cmd_clean() {
    local keep=3
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep) keep="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    log_info "Cleaning old images (keeping latest ${keep})..."

    for service in "${SERVICES[@]}"; do
        local image="${REGISTRY}/${service}"
        local tags
        tags="$(docker images "${image}" --format '{{.Tag}}' 2>/dev/null | grep -v '<none>' | grep -v 'latest' | sort -rV)"

        local count=0
        while IFS= read -r tag; do
            [[ -z "${tag}" ]] && continue
            count=$((count + 1))
            if [[ ${count} -gt ${keep} ]]; then
                log_info "Removing ${image}:${tag}"
                docker rmi "${image}:${tag}" 2>/dev/null || true
            fi
        done <<< "${tags}"
    done

    # Prune dangling images
    docker image prune -f --filter "label=org.opencontainers.image.title=powernode-*" 2>/dev/null || true

    log_ok "Cleanup complete"
}

# ──────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────
usage() {
    echo "Powernode Docker Package Manager"
    echo ""
    echo "Usage: $(basename "$0") <command> [options]"
    echo ""
    echo "Commands:"
    echo "  create [--version <ver>]    Build images and create deployment package"
    echo "  export [--version <ver>]    Export images as tar archives"
    echo "  import <package-dir>        Import images from tar archives"
    echo "  list                        List local powernode images"
    echo "  clean [--keep <n>]          Remove old images (default: keep 3)"
}

command="${1:-}"
shift || true

case "${command}" in
    create)  cmd_create "$@" ;;
    export)  cmd_export "$@" ;;
    import)  cmd_import "$@" ;;
    list)    cmd_list ;;
    clean)   cmd_clean "$@" ;;
    help|--help|-h) usage ;;
    *)
        if [[ -n "${command}" ]]; then
            log_error "Unknown command: ${command}"
        fi
        usage
        exit 1
        ;;
esac
