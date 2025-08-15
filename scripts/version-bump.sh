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

# Current version detection
get_current_version() {
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        grep '"version"' "$PROJECT_ROOT/package.json" | sed 's/.*"version": "\(.*\)".*/\1/'
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

# Update version in all relevant files
update_version_files() {
    local new_version=$1
    
    echo -e "${BLUE}Updating version to $new_version in all files...${NC}"
    
    # Update package.json (frontend)
    if [ -f "$PROJECT_ROOT/frontend/package.json" ]; then
        sed -i.bak "s/\"version\": \".*\"/\"version\": \"$new_version\"/" "$PROJECT_ROOT/frontend/package.json"
        rm "$PROJECT_ROOT/frontend/package.json.bak"
        echo "✓ Updated frontend/package.json"
    fi
    
    # Update server version (if Gemfile or version file exists)
    if [ -f "$PROJECT_ROOT/server/Gemfile" ]; then
        # Update version comment in Gemfile
        sed -i.bak "s/# Version: .*/# Version: $new_version/" "$PROJECT_ROOT/server/Gemfile"
        rm "$PROJECT_ROOT/server/Gemfile.bak" 2>/dev/null || true
        echo "✓ Updated server/Gemfile version comment"
    fi
    
    # Update worker version
    if [ -f "$PROJECT_ROOT/worker/Gemfile" ]; then
        sed -i.bak "s/# Version: .*/# Version: $new_version/" "$PROJECT_ROOT/worker/Gemfile"
        rm "$PROJECT_ROOT/worker/Gemfile.bak" 2>/dev/null || true
        echo "✓ Updated worker/Gemfile version comment"
    fi
    
    # Update CLAUDE.md current version
    sed -i.bak "s/- \*\*Current\*\*: \`.*\`/- **Current**: \`$new_version\`/" "$PROJECT_ROOT/CLAUDE.md"
    rm "$PROJECT_ROOT/CLAUDE.md.bak"
    echo "✓ Updated CLAUDE.md"
    
    # Update root package.json if it exists
    if [ -f "$PROJECT_ROOT/package.json" ]; then
        sed -i.bak "s/\"version\": \".*\"/\"version\": \"$new_version\"/" "$PROJECT_ROOT/package.json"
        rm "$PROJECT_ROOT/package.json.bak"
        echo "✓ Updated root package.json"
    fi
}

# Generate changelog entry
update_changelog() {
    local version=$1
    local date=$(date +%Y-%m-%d)
    
    # Create changelog entry
    local temp_file=$(mktemp)
    echo "## [$version] - $date" > "$temp_file"
    echo "" >> "$temp_file"
    echo "### Added" >> "$temp_file"
    echo "- " >> "$temp_file"
    echo "" >> "$temp_file"
    echo "### Changed" >> "$temp_file"
    echo "- " >> "$temp_file"
    echo "" >> "$temp_file"
    echo "### Fixed" >> "$temp_file"
    echo "- " >> "$temp_file"
    echo "" >> "$temp_file"
    
    # Insert at the top of CHANGELOG.md after the header
    if [ -f "$PROJECT_ROOT/CHANGELOG.md" ]; then
        # Find line number after "## [Unreleased]" section
        local insert_line=$(grep -n "^## \[Unreleased\]" "$PROJECT_ROOT/CHANGELOG.md" | cut -d: -f1)
        if [ -n "$insert_line" ]; then
            # Find the next ## section or end of unreleased section
            local next_section=$(tail -n +$((insert_line + 1)) "$PROJECT_ROOT/CHANGELOG.md" | grep -n "^## " | head -1 | cut -d: -f1)
            if [ -n "$next_section" ]; then
                insert_line=$((insert_line + next_section))
            else
                insert_line=$(($(wc -l < "$PROJECT_ROOT/CHANGELOG.md") + 1))
            fi
            
            # Insert the new version section
            head -n $((insert_line - 1)) "$PROJECT_ROOT/CHANGELOG.md" > "${temp_file}.full"
            cat "$temp_file" >> "${temp_file}.full"
            tail -n +$insert_line "$PROJECT_ROOT/CHANGELOG.md" >> "${temp_file}.full"
            mv "${temp_file}.full" "$PROJECT_ROOT/CHANGELOG.md"
        fi
    fi
    
    rm "$temp_file"
    echo "✓ Updated CHANGELOG.md"
}

# Main version bump function
bump_version() {
    local bump_type=$1
    local current_version=$(get_current_version)
    
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
    
    # Confirm with user
    read -p "Continue with version bump? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Version bump cancelled."
        exit 0
    fi
    
    # Update version files
    update_version_files "$new_version"
    
    # Update changelog
    update_changelog "$new_version"
    
    # Stage changes
    git add "$PROJECT_ROOT/CHANGELOG.md" "$PROJECT_ROOT/CLAUDE.md"
    [ -f "$PROJECT_ROOT/package.json" ] && git add "$PROJECT_ROOT/package.json"
    [ -f "$PROJECT_ROOT/frontend/package.json" ] && git add "$PROJECT_ROOT/frontend/package.json"
    [ -f "$PROJECT_ROOT/server/Gemfile" ] && git add "$PROJECT_ROOT/server/Gemfile"
    [ -f "$PROJECT_ROOT/worker/Gemfile" ] && git add "$PROJECT_ROOT/worker/Gemfile"
    
    echo -e "${GREEN}✓ Version bumped to $new_version${NC}"
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Edit CHANGELOG.md to add release notes"
    echo "2. Commit changes: git commit -m \"chore: bump version to $new_version\""
    echo "3. Create git tag: git tag -a v$new_version -m \"Release $new_version\""
    echo "4. Push changes: git push && git push --tags"
}

# Usage help
show_help() {
    echo "Powernode Platform Version Bump Script"
    echo ""
    echo "Usage: $0 <bump_type>"
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
    echo "  $0 minor     # 1.0.0 → 1.1.0"
    echo "  $0 patch     # 1.0.0 → 1.0.1"
    echo "  $0 alpha     # 1.0.0 → 1.0.1-alpha.0"
    echo ""
    echo "Current version: $(get_current_version)"
}

# Main script
if [ $# -eq 0 ]; then
    show_help
    exit 1
fi

case $1 in
    -h|--help)
        show_help
        ;;
    major|minor|patch|alpha|beta|rc)
        bump_version "$1"
        ;;
    *)
        echo -e "${RED}Error: Invalid bump type '$1'${NC}"
        show_help
        exit 1
        ;;
esac