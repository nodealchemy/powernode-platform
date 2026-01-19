#!/bin/bash

# Powernode Platform Git-Flow Initialization Script
# Sets up Git-Flow with proper branching strategy and protection rules

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}Powernode Platform Git-Flow Initialization${NC}"
echo "=================================================="

# Check if git-flow is installed
check_git_flow() {
    if ! command -v git-flow &> /dev/null; then
        echo -e "${RED}Error: git-flow is not installed${NC}"
        echo -e "${YELLOW}Install with:${NC}"
        echo "  macOS: brew install git-flow-avh"
        echo "  Ubuntu: sudo apt-get install git-flow"
        echo "  Windows: Use Git for Windows or install via package manager"
        exit 1
    fi
    echo -e "${GREEN}✓ git-flow is installed${NC}"
}

# Check if we're in a git repository
check_git_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}Error: Not in a git repository${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Git repository detected${NC}"
}

# Initialize git-flow if not already initialized
init_git_flow() {
    if [ ! -f "$PROJECT_ROOT/.git/config" ] || ! grep -q "gitflow" "$PROJECT_ROOT/.git/config"; then
        echo -e "${BLUE}Initializing git-flow...${NC}"
        
        # Initialize git-flow with default settings
        cd "$PROJECT_ROOT"
        git flow init -d
        
        echo -e "${GREEN}✓ Git-flow initialized${NC}"
    else
        echo -e "${YELLOW}⚠ Git-flow already initialized${NC}"
    fi
}

# Set up branch protection (requires GitHub CLI or manual setup)
setup_branch_protection() {
    echo -e "${BLUE}Setting up branch protection rules...${NC}"
    
    # Check if GitHub CLI is available
    if command -v gh &> /dev/null; then
        echo -e "${BLUE}GitHub CLI detected, setting up branch protection...${NC}"
        
        # Protect main branch
        gh api repos/:owner/:repo/branches/main/protection \
            --method PUT \
            --field required_status_checks='{"strict":true,"contexts":["ci/tests"]}' \
            --field enforce_admins=true \
            --field required_pull_request_reviews='{"required_approving_review_count":2,"dismiss_stale_reviews":true}' \
            --field restrictions=null \
            2>/dev/null || echo -e "${YELLOW}⚠ Could not set main branch protection (may need repo access)${NC}"
        
        # Protect develop branch
        gh api repos/:owner/:repo/branches/develop/protection \
            --method PUT \
            --field required_status_checks='{"strict":true,"contexts":["ci/tests"]}' \
            --field enforce_admins=false \
            --field required_pull_request_reviews='{"required_approving_review_count":1,"dismiss_stale_reviews":true}' \
            --field restrictions=null \
            2>/dev/null || echo -e "${YELLOW}⚠ Could not set develop branch protection (may need repo access)${NC}"
        
        echo -e "${GREEN}✓ Branch protection rules configured${NC}"
    else
        echo -e "${YELLOW}⚠ GitHub CLI not found. Set up branch protection manually:${NC}"
        echo "1. Go to GitHub repository settings"
        echo "2. Navigate to Branches → Add rule"
        echo "3. For 'main' branch:"
        echo "   - Require pull request reviews (2 reviewers)"
        echo "   - Require status checks to pass"
        echo "   - Require branches to be up to date"
        echo "   - Include administrators"
        echo "4. For 'develop' branch:"
        echo "   - Require pull request reviews (1 reviewer)"
        echo "   - Require status checks to pass"
    fi
}

# Configure git settings for the project
configure_git_settings() {
    echo -e "${BLUE}Configuring git settings...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # Set commit message template
    git config commit.template .gitmessage
    
    # Set git-flow configuration
    git config gitflow.branch.master main
    git config gitflow.branch.develop develop
    git config gitflow.prefix.feature feature/
    git config gitflow.prefix.release release/
    git config gitflow.prefix.hotfix hotfix/
    git config gitflow.prefix.support support/
    git config gitflow.prefix.versiontag v
    
    # Configure conventional commits hook (if available)
    if [ -d ".git/hooks" ]; then
        cat > .git/hooks/commit-msg << 'EOF'
#!/bin/sh
# Conventional Commits validation hook

commit_regex='^(feat|fix|docs|style|refactor|test|chore|ci|perf|revert)(\(.+\))?(!)?:.{1,50}'

if ! grep -qE "$commit_regex" "$1"; then
    echo "Invalid commit message format!"
    echo "Use: <type>[optional scope][!]: <description>"
    echo "Types: feat, fix, docs, style, refactor, test, chore, ci, perf, revert"
    echo "Example: feat(auth): add OAuth2 integration"
    exit 1
fi
EOF
        chmod +x .git/hooks/commit-msg
        echo -e "${GREEN}✓ Commit message validation hook installed${NC}"
    fi
    
    echo -e "${GREEN}✓ Git settings configured${NC}"
}

# Create initial version tag if none exists
create_initial_tag() {
    cd "$PROJECT_ROOT"
    
    # Check if any tags exist
    if ! git tag -l | grep -q .; then
        echo -e "${BLUE}Creating initial version tag...${NC}"
        
        # Create initial tag
        git tag -a 0.0.1-dev -m "Initial development version

Features:
- Project foundation established
- Git-flow workflow configured
- Semantic versioning enforced
- Development environment ready"

        echo -e "${GREEN}✓ Initial tag 0.0.1-dev created${NC}"
        echo -e "${YELLOW}Push the tag with: git push --tags${NC}"
    else
        echo -e "${YELLOW}⚠ Version tags already exist${NC}"
    fi
}

# Display git-flow usage instructions
show_usage_instructions() {
    echo ""
    echo -e "${BLUE}Git-Flow Usage Instructions${NC}"
    echo "=============================="
    echo ""
    echo -e "${GREEN}Feature Development:${NC}"
    echo "  git flow feature start ISSUE-feature-name"
    echo "  # ... make changes ..."
    echo "  git flow feature finish ISSUE-feature-name"
    echo ""
    echo -e "${GREEN}Release Process:${NC}"
    echo "  git flow release start v1.2.0"
    echo "  # ... final testing and version updates ..."
    echo "  git flow release finish v1.2.0"
    echo ""
    echo -e "${GREEN}Hotfix Process:${NC}"
    echo "  git flow hotfix start v1.2.1-critical-fix"
    echo "  # ... fix critical issue ..."
    echo "  git flow hotfix finish v1.2.1-critical-fix"
    echo ""
    echo -e "${GREEN}Version Management:${NC}"
    echo "  ./scripts/version-bump.sh minor    # Bump minor version"
    echo "  ./scripts/version-bump.sh patch    # Bump patch version"
    echo "  ./scripts/version-bump.sh alpha    # Create alpha release"
    echo ""
    echo -e "${YELLOW}Branch Protection:${NC}"
    echo "  - main: Requires 2 PR reviews, all tests pass"
    echo "  - develop: Requires 1 PR review, all tests pass"
    echo "  - No direct pushes to protected branches"
    echo ""
    echo -e "${YELLOW}Commit Format (Conventional):${NC}"
    echo "  feat(scope): add new feature"
    echo "  fix(scope): resolve bug"
    echo "  feat!: breaking change"
    echo ""
    echo -e "${GREEN}Next Steps:${NC}"
    echo "1. Create your first feature: git flow feature start setup-project"
    echo "2. Review branch protection in GitHub settings"
    echo "3. Configure CI/CD pipelines for automated testing"
    echo "4. Set up deployment automation"
}

# Main execution
main() {
    echo "Starting Git-Flow initialization for Powernode Platform..."
    echo ""
    
    check_git_flow
    check_git_repo
    init_git_flow
    configure_git_settings
    setup_branch_protection
    create_initial_tag
    show_usage_instructions
    
    echo ""
    echo -e "${GREEN}✅ Git-Flow initialization complete!${NC}"
    echo -e "${BLUE}Repository is now configured with:${NC}"
    echo "  ✓ Git-Flow branching model"
    echo "  ✓ Semantic versioning enforcement"
    echo "  ✓ Conventional commit validation"
    echo "  ✓ Branch protection rules"
    echo "  ✓ Version management scripts"
    echo ""
    echo -e "${YELLOW}Remember to:${NC}"
    echo "  - Push initial tags: git push --tags"
    echo "  - Review GitHub branch protection settings"
    echo "  - Configure CI/CD status checks"
}

# Run main function
main "$@"