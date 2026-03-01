#!/usr/bin/env bash
# Powernode Docker Image Builder
# Builds, tags, and optionally pushes Docker images for all services.
#
# Usage:
#   powernode-build.sh [options] [service...]
#
# Options:
#   --registry <url>     Container registry (default: docker.io/powernode)
#   --tag <tag>          Image tag (default: git short SHA)
#   --latest             Also tag as :latest
#   --push               Push images after building
#   --no-cache           Build without Docker cache
#   --platform <p>       Target platform (default: linux/amd64)
#   --env <environment>  Build environment: production|staging (default: production)
#
# Services: backend, worker, frontend (default: all)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Defaults
REGISTRY="${POWERNODE_REGISTRY:-docker.io/powernode}"
TAG=""
TAG_LATEST=false
PUSH=false
NO_CACHE=false
PLATFORM="linux/amd64"
BUILD_ENV="production"
SERVICES=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[BUILD]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}     $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --registry)  REGISTRY="$2"; shift 2 ;;
        --tag)       TAG="$2"; shift 2 ;;
        --latest)    TAG_LATEST=true; shift ;;
        --push)      PUSH=true; shift ;;
        --no-cache)  NO_CACHE=true; shift ;;
        --platform)  PLATFORM="$2"; shift 2 ;;
        --env)       BUILD_ENV="$2"; shift 2 ;;
        --help|-h)
            head -16 "$0" | tail -15
            exit 0
            ;;
        backend|worker|frontend)
            SERVICES+=("$1"); shift ;;
        *)
            log_error "Unknown argument: $1"
            exit 1 ;;
    esac
done

# Default to all services
if [[ ${#SERVICES[@]} -eq 0 ]]; then
    SERVICES=(backend worker frontend)
fi

# Auto-detect tag from git
if [[ -z "${TAG}" ]]; then
    TAG="$(git -C "${PROJECT_ROOT}" rev-parse --short HEAD 2>/dev/null || echo "dev")"
fi

# Read version
VERSION=""
if [[ -f "${PROJECT_ROOT}/frontend/VERSION" ]]; then
    VERSION="$(cat "${PROJECT_ROOT}/frontend/VERSION")"
fi

log_info "Build Configuration"
log_info "  Registry:    ${REGISTRY}"
log_info "  Tag:         ${TAG}"
log_info "  Version:     ${VERSION:-unknown}"
log_info "  Environment: ${BUILD_ENV}"
log_info "  Platform:    ${PLATFORM}"
log_info "  Services:    ${SERVICES[*]}"
log_info "  Push:        ${PUSH}"
echo ""

# Service build configurations
declare -A SERVICE_CONTEXT=(
    [backend]="server"
    [worker]="worker"
    [frontend]="frontend"
)

declare -A SERVICE_DOCKERFILE=(
    [backend]="Dockerfile"
    [worker]="Dockerfile"
    [frontend]="Dockerfile"
)

declare -A SERVICE_TARGET=(
    [backend]="production"
    [worker]="production"
    [frontend]=""
)

build_service() {
    local service="$1"
    local context="${PROJECT_ROOT}/${SERVICE_CONTEXT[$service]}"
    local dockerfile="${SERVICE_DOCKERFILE[$service]}"
    local target="${SERVICE_TARGET[$service]}"
    local image="${REGISTRY}/${service}"
    local full_tag="${image}:${TAG}"

    log_info "Building ${service}..."

    # Build args
    local build_args=()
    build_args+=(--file "${context}/${dockerfile}")
    build_args+=(--platform "${PLATFORM}")
    build_args+=(--tag "${full_tag}")

    if [[ -n "${VERSION}" ]]; then
        build_args+=(--tag "${image}:${VERSION}")
    fi

    if [[ "${TAG_LATEST}" == true ]]; then
        build_args+=(--tag "${image}:latest")
    fi

    if [[ -n "${target}" ]]; then
        build_args+=(--target "${target}")
    fi

    if [[ "${NO_CACHE}" == true ]]; then
        build_args+=(--no-cache)
    fi

    # Service-specific build args
    if [[ "${service}" == "frontend" ]]; then
        local api_domain="${POWERNODE_DOMAIN:-localhost}"
        if [[ "${BUILD_ENV}" == "production" ]]; then
            build_args+=(--build-arg "VITE_API_URL=https://api.${api_domain}")
            build_args+=(--build-arg "VITE_WS_URL=wss://api.${api_domain}")
        else
            build_args+=(--build-arg "VITE_API_URL=https://api-staging.${api_domain}")
            build_args+=(--build-arg "VITE_WS_URL=wss://api-staging.${api_domain}")
        fi
    fi

    # Labels
    build_args+=(--label "org.opencontainers.image.source=https://github.com/powernode/platform")
    build_args+=(--label "org.opencontainers.image.version=${VERSION:-${TAG}}")
    build_args+=(--label "org.opencontainers.image.revision=$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)")
    build_args+=(--label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)")
    build_args+=(--label "org.opencontainers.image.title=powernode-${service}")

    docker build "${build_args[@]}" "${context}"

    log_ok "${service} built: ${full_tag}"

    # Push if requested
    if [[ "${PUSH}" == true ]]; then
        log_info "Pushing ${full_tag}..."
        docker push "${full_tag}"

        if [[ -n "${VERSION}" ]]; then
            docker push "${image}:${VERSION}"
        fi

        if [[ "${TAG_LATEST}" == true ]]; then
            docker push "${image}:latest"
        fi

        log_ok "${service} pushed"
    fi
}

# Build each service
FAILED=()
for service in "${SERVICES[@]}"; do
    if build_service "${service}"; then
        log_ok "${service} complete"
    else
        log_error "${service} build failed"
        FAILED+=("${service}")
    fi
    echo ""
done

# Summary
echo ""
log_info "Build Summary"
log_info "============="
for service in "${SERVICES[@]}"; do
    local image="${REGISTRY}/${service}:${TAG}"
    if [[ " ${FAILED[*]} " =~ " ${service} " ]]; then
        echo -e "  ${RED}FAIL${NC}  ${image}"
    else
        echo -e "  ${GREEN}OK${NC}    ${image}"
    fi
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    log_error "Failed services: ${FAILED[*]}"
    exit 1
fi

log_ok "All images built successfully"
