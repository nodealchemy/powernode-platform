#!/bin/bash

# Version Manager Script for Powernode Platform
# Manages semantic versioning across frontend and backend
# Usage: ./scripts/version-manager.sh [command] [args]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project paths
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$PROJECT_ROOT/VERSION"
FRONTEND_PACKAGE="$PROJECT_ROOT/frontend/package.json"
BACKEND_VERSION="$PROJECT_ROOT/server/config/version.rb"

# Helper functions
print_usage() {
    echo -e "${BLUE}Powernode Version Manager${NC}"
    echo ""
    echo "Usage: $0 [command] [args]"
    echo ""
    echo "Commands:"
    echo "  current                 Show current version"
    echo "  set <version>          Set version across all components"
    echo "  bump <type>            Bump version (major|minor|patch)"
    echo "  prerelease <type>      Add/update prerelease (alpha|beta|rc|dev)"
    echo "  release                Remove prerelease suffix"
    echo "  sync                   Sync versions between components"
    echo "  info                   Show detailed version information"
    echo "  validate               Validate version format"
    echo ""
    echo "Examples:"
    echo "  $0 current"
    echo "  $0 set 1.0.0"
    echo "  $0 bump minor"
    echo "  $0 prerelease alpha"
    echo "  $0 release"
}

get_current_version() {
    if [[ -f "$VERSION_FILE" ]]; then
        cat "$VERSION_FILE"
    else
        echo "0.0.1-dev"
    fi
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\-(alpha|beta|rc|dev)(\.[0-9]+)?)?$ ]]; then
        echo -e "${RED}Error: Invalid version format '$version'${NC}" >&2
        echo "Expected format: MAJOR.MINOR.PATCH[-PRERELEASE[.NUMBER]]" >&2
        exit 1
    fi
}

parse_version() {
    local version="$1"
    local base_version prerelease
    
    if [[ "$version" =~ ^([0-9]+\.[0-9]+\.[0-9]+)(\-(.+))?$ ]]; then
        base_version="${BASH_REMATCH[1]}"
        prerelease="${BASH_REMATCH[3]}"
        
        IFS='.' read -ra VERSION_PARTS <<< "$base_version"
        MAJOR="${VERSION_PARTS[0]}"
        MINOR="${VERSION_PARTS[1]}"
        PATCH="${VERSION_PARTS[2]}"
        PRERELEASE="$prerelease"
    else
        echo -e "${RED}Error: Failed to parse version '$version'${NC}" >&2
        exit 1
    fi
}

set_version() {
    local new_version="$1"
    validate_version "$new_version"
    
    echo -e "${BLUE}Setting version to: ${GREEN}$new_version${NC}"
    
    # Update VERSION file
    echo "$new_version" > "$VERSION_FILE"
    
    # Update frontend package.json
    if [[ -f "$FRONTEND_PACKAGE" ]]; then
        if command -v jq >/dev/null 2>&1; then
            jq ".version = \"$new_version\"" "$FRONTEND_PACKAGE" > "${FRONTEND_PACKAGE}.tmp" && \
            mv "${FRONTEND_PACKAGE}.tmp" "$FRONTEND_PACKAGE"
        else
            # Fallback to sed if jq is not available
            sed -i.bak "s/\"version\": \"[^\"]*\"/\"version\": \"$new_version\"/" "$FRONTEND_PACKAGE" && \
            rm "${FRONTEND_PACKAGE}.bak" 2>/dev/null || true
        fi
        echo -e "${GREEN}✓${NC} Updated frontend package.json"
    fi
    
    # Update backend version file (regenerate if needed)
    update_backend_version_file
    echo -e "${GREEN}✓${NC} Updated backend version file"
    
    # Update environment files
    update_env_files "$new_version"
    
    echo -e "${GREEN}✓ Version updated successfully!${NC}"
}

update_backend_version_file() {
    # The backend version file reads from VERSION file, so we don't need to update it
    # But we can touch it to trigger any watchers
    touch "$BACKEND_VERSION" 2>/dev/null || true
}

update_env_files() {
    local version="$1"
    local env_file="$PROJECT_ROOT/frontend/.env"
    
    # Update or create .env file for frontend
    if [[ -f "$env_file" ]]; then
        # Update existing REACT_APP_VERSION or add it
        if grep -q "REACT_APP_VERSION=" "$env_file"; then
            sed -i.bak "s/REACT_APP_VERSION=.*/REACT_APP_VERSION=$version/" "$env_file" && \
            rm "${env_file}.bak" 2>/dev/null || true
        else
            echo "REACT_APP_VERSION=$version" >> "$env_file"
        fi
    else
        echo "REACT_APP_VERSION=$version" > "$env_file"
    fi
    echo -e "${GREEN}✓${NC} Updated environment files"
}

bump_version() {
    local bump_type="$1"
    local current_version
    current_version=$(get_current_version)
    
    parse_version "$current_version"
    
    case "$bump_type" in
        major)
            new_version="$((MAJOR + 1)).0.0"
            ;;
        minor)
            new_version="$MAJOR.$((MINOR + 1)).0"
            ;;
        patch)
            new_version="$MAJOR.$MINOR.$((PATCH + 1))"
            ;;
        *)
            echo -e "${RED}Error: Invalid bump type '$bump_type'${NC}" >&2
            echo "Valid types: major, minor, patch" >&2
            exit 1
            ;;
    esac
    
    # Preserve prerelease if it exists
    if [[ -n "$PRERELEASE" ]]; then
        new_version="$new_version-$PRERELEASE"
    fi
    
    set_version "$new_version"
}

add_prerelease() {
    local prerelease_type="$1"
    local current_version
    current_version=$(get_current_version)
    
    parse_version "$current_version"
    local base_version="$MAJOR.$MINOR.$PATCH"
    
    case "$prerelease_type" in
        alpha|beta|rc|dev)
            new_version="$base_version-$prerelease_type"
            ;;
        *)
            echo -e "${RED}Error: Invalid prerelease type '$prerelease_type'${NC}" >&2
            echo "Valid types: alpha, beta, rc, dev" >&2
            exit 1
            ;;
    esac
    
    set_version "$new_version"
}

release_version() {
    local current_version
    current_version=$(get_current_version)
    
    parse_version "$current_version"
    local base_version="$MAJOR.$MINOR.$PATCH"
    
    if [[ -z "$PRERELEASE" ]]; then
        echo -e "${YELLOW}Version $current_version is already a release version${NC}"
        return
    fi
    
    set_version "$base_version"
}

sync_versions() {
    local master_version
    master_version=$(get_current_version)
    
    echo -e "${BLUE}Syncing all components to version: ${GREEN}$master_version${NC}"
    set_version "$master_version"
}

show_info() {
    local current_version git_branch git_commit build_date
    current_version=$(get_current_version)
    git_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    git_commit=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    build_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    
    echo -e "${BLUE}Powernode Platform Version Information${NC}"
    echo -e "======================================"
    echo -e "Current Version: ${GREEN}$current_version${NC}"
    echo -e "Git Branch:      ${YELLOW}$git_branch${NC}"
    echo -e "Git Commit:      ${YELLOW}$git_commit${NC}"
    echo -e "Build Date:      ${YELLOW}$build_date${NC}"
    echo ""
    
    parse_version "$current_version"
    echo -e "Version Components:"
    echo -e "  Major:      $MAJOR"
    echo -e "  Minor:      $MINOR"
    echo -e "  Patch:      $PATCH"
    [[ -n "$PRERELEASE" ]] && echo -e "  Prerelease: $PRERELEASE"
    echo ""
    
    # Check if files exist and show their status
    echo -e "File Status:"
    [[ -f "$VERSION_FILE" ]] && echo -e "  ✓ VERSION file exists" || echo -e "  ✗ VERSION file missing"
    [[ -f "$FRONTEND_PACKAGE" ]] && echo -e "  ✓ Frontend package.json exists" || echo -e "  ✗ Frontend package.json missing"
    [[ -f "$BACKEND_VERSION" ]] && echo -e "  ✓ Backend version.rb exists" || echo -e "  ✗ Backend version.rb missing"
}

# Main command processing
case "${1:-}" in
    current)
        get_current_version
        ;;
    set)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error: Version required${NC}" >&2
            echo "Usage: $0 set <version>" >&2
            exit 1
        fi
        set_version "$2"
        ;;
    bump)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error: Bump type required${NC}" >&2
            echo "Usage: $0 bump <major|minor|patch>" >&2
            exit 1
        fi
        bump_version "$2"
        ;;
    prerelease)
        if [[ -z "${2:-}" ]]; then
            echo -e "${RED}Error: Prerelease type required${NC}" >&2
            echo "Usage: $0 prerelease <alpha|beta|rc|dev>" >&2
            exit 1
        fi
        add_prerelease "$2"
        ;;
    release)
        release_version
        ;;
    sync)
        sync_versions
        ;;
    info)
        show_info
        ;;
    validate)
        version=$(get_current_version)
        validate_version "$version"
        echo -e "${GREEN}✓ Version '$version' is valid${NC}"
        ;;
    help|--help|-h)
        print_usage
        ;;
    "")
        print_usage
        ;;
    *)
        echo -e "${RED}Error: Unknown command '$1'${NC}" >&2
        print_usage
        exit 1
        ;;
esac