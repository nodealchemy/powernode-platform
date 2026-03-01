#!/bin/bash

# Powernode Platform Version Bump Script
# Enforces semantic versioning and updates all version files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Flags
AUTO_YES=false

# Current version detection
get_current_version() {
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        grep '"version"' "$PROJECT_ROOT/package.json" | head -1 | sed 's/.*"version": "\(.*\)".*/\1/'
    else
        echo "0.0.1-dev"
    fi
}

# Validate version format (SemVer)
validate_version() {
    local version=$1
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9\.-]+)?(\+[a-zA-Z0-9\.-]+)?$ ]]; then
        echo -e "${RED}Error: Invalid version format. Must follow SemVer (e.g., 1.2.3, 2.0.0-alpha.1)${NC}"
        exit 1
    fi
}

# Update version in a JSON file's top-level "version" field
update_json_version() {
    local file="$1"
    local new_version="$2"
    local label="$3"

    if [ -f "$file" ]; then
        # Use node for safe JSON editing, fall back to sed
        if command -v node &>/dev/null; then
            node -e "
                const fs = require('fs');
                const pkg = JSON.parse(fs.readFileSync('$file', 'utf8'));
                pkg.version = '$new_version';
                fs.writeFileSync('$file', JSON.stringify(pkg, null, 2) + '\n');
            "
        else
            sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$new_version\"/" "$file"
        fi
        echo -e "  ${GREEN}✓${NC} $label"
    fi
}

# Update version in all relevant files
update_version_files() {
    local new_version=$1

    echo -e "${BLUE}Updating version to $new_version in all files...${NC}"

    # Root package.json
    update_json_version "$PROJECT_ROOT/package.json" "$new_version" "package.json"

    # Frontend package.json
    update_json_version "$PROJECT_ROOT/frontend/package.json" "$new_version" "frontend/package.json"

    # Update frontend package-lock.json
    if [ -f "$PROJECT_ROOT/frontend/package-lock.json" ]; then
        (cd "$PROJECT_ROOT/frontend" && npm install --package-lock-only --silent 2>/dev/null) || true
        echo -e "  ${GREEN}✓${NC} frontend/package-lock.json"
    fi

    # Update VERSION files
    for vfile in VERSION frontend/VERSION server/VERSION worker/VERSION; do
        if [ -f "$PROJECT_ROOT/$vfile" ]; then
            echo -n "$new_version" > "$PROJECT_ROOT/$vfile"
            echo -e "  ${GREEN}✓${NC} $vfile"
        fi
    done
}

# Main version bump function
bump_version() {
    local bump_type=$1
    local current_version
    current_version=$(get_current_version)

    echo -e "${BLUE}Current version: $current_version${NC}"

    # Parse current version
    local major minor patch prerelease
    if [[ $current_version =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-(.+))?$ ]]; then
        major=${BASH_REMATCH[1]}
        minor=${BASH_REMATCH[2]}
        patch=${BASH_REMATCH[3]}
        prerelease=${BASH_REMATCH[5]}
    else
        echo -e "${RED}Error: Cannot parse current version: $current_version${NC}"
        exit 1
    fi

    # Calculate new version based on bump type
    local new_version
    case $bump_type in
        major)
            new_version="$((major + 1)).0.0"
            ;;
        minor)
            new_version="$major.$((minor + 1)).0"
            ;;
        patch)
            new_version="$major.$minor.$((patch + 1))"
            ;;
        alpha)
            if [[ $current_version =~ alpha\.([0-9]+)$ ]]; then
                local alpha_num=${BASH_REMATCH[1]}
                new_version="$major.$minor.$patch-alpha.$((alpha_num + 1))"
            else
                new_version="$major.$minor.$((patch + 1))-alpha.0"
            fi
            ;;
        beta)
            if [[ $current_version =~ beta\.([0-9]+)$ ]]; then
                local beta_num=${BASH_REMATCH[1]}
                new_version="$major.$minor.$patch-beta.$((beta_num + 1))"
            else
                new_version="$major.$minor.$((patch + 1))-beta.0"
            fi
            ;;
        rc)
            if [[ $current_version =~ rc\.([0-9]+)$ ]]; then
                local rc_num=${BASH_REMATCH[1]}
                new_version="$major.$minor.$patch-rc.$((rc_num + 1))"
            else
                new_version="$major.$minor.$((patch + 1))-rc.0"
            fi
            ;;
        *)
            echo -e "${RED}Error: Invalid bump type. Use: major, minor, patch, alpha, beta, rc${NC}"
            exit 1
            ;;
    esac

    validate_version "$new_version"

    echo -e "${GREEN}Bumping version: $current_version → $new_version${NC}"

    # Confirm with user (skip if --yes)
    if [ "$AUTO_YES" = false ]; then
        read -p "Continue with version bump? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Version bump cancelled."
            exit 0
        fi
    fi

    # Update version files
    update_version_files "$new_version"

    echo ""
    echo -e "${GREEN}✓ Version bumped to $new_version${NC}"
    echo -e "${YELLOW}Files updated — review with: git diff${NC}"
}

# Usage help
show_help() {
    echo "Powernode Platform Version Bump Script"
    echo ""
    echo "Usage: $0 [options] <bump_type>"
    echo ""
    echo "Options:"
    echo "  -y, --yes      Skip confirmation prompt"
    echo "  -h, --help     Show this help message"
    echo ""
    echo "Bump types:"
    echo "  major    - Bump major version (X.0.0) - breaking changes"
    echo "  minor    - Bump minor version (0.X.0) - new features"
    echo "  patch    - Bump patch version (0.0.X) - bug fixes"
    echo "  alpha    - Bump to next alpha version (0.0.X-alpha.Y)"
    echo "  beta     - Bump to next beta version (0.0.X-beta.Y)"
    echo "  rc       - Bump to next release candidate (0.0.X-rc.Y)"
    echo ""
    echo "Examples:"
    echo "  $0 patch        # 1.0.0 → 1.0.1"
    echo "  $0 minor        # 1.0.0 → 1.1.0"
    echo "  $0 -y patch     # 1.0.0 → 1.0.1 (no prompt)"
    echo ""
    echo "Current version: $(get_current_version)"
}

# Parse arguments
BUMP_TYPE=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        major|minor|patch|alpha|beta|rc)
            BUMP_TYPE="$1"
            shift
            ;;
        *)
            echo -e "${RED}Error: Invalid argument '$1'${NC}"
            echo ""
            show_help
            exit 1
            ;;
    esac
done

if [ -z "$BUMP_TYPE" ]; then
    show_help
    exit 1
fi

bump_version "$BUMP_TYPE"
