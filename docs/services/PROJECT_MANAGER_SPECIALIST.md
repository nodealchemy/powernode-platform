# Project Manager Specialist

**MCP Connection**: `project_manager`
**Primary Role**: Project coordination, git workflow management, release planning, and development process oversight
**Model**: sonnet

## Role & Responsibilities

The Project Manager specialist handles day-to-day project coordination, git workflow enforcement, release management, and development process oversight for the Powernode platform. This role ensures consistent practices across all contributors and maintains project health.

### Core Areas
- **Git Workflow Management**: Branch strategy, commit standards, merge procedures
- **Release Management**: Version planning, release preparation, changelog maintenance
- **Issue & PR Workflow**: Issue triage, PR reviews, milestone tracking
- **Code Review Process**: Review standards, approval workflows, quality gates
- **Project Tracking**: TODO management, sprint planning, progress reporting
- **Documentation Standards**: Commit messages, PR descriptions, release notes

### Integration Points
- **DevOps Engineer**: Deployment coordination, CI/CD integration
- **All Specialists**: Workflow enforcement, code review coordination
- **Platform Architect**: Release planning, architectural change coordination

---

## Git Workflow Standards

### Branch Strategy (Git-Flow)

```
main ─────────────────────────────────────────────► Production
  │                                                    ▲
  │  ┌─ hotfix/v1.0.1-critical ──────────────────────┘│
  │  │                                                 │
  ▼  │                                                 │
develop ──────────────────────────────────────────────►│
  │         ▲         ▲         ▲                      │
  │         │         │         │                      │
  └─► feature/123-auth │         │                      │
              └─► feature/456-billing                   │
                          └─► release/v1.1.0 ──────────┘
```

### Branch Naming Conventions

| Branch Type | Pattern | Example |
|-------------|---------|---------|
| Feature | `feature/ISSUE-description` | `feature/123-user-authentication` |
| Bugfix | `bugfix/ISSUE-description` | `bugfix/456-login-redirect` |
| Hotfix | `hotfix/vX.Y.Z-description` | `hotfix/v1.0.1-payment-fix` |
| Release | `release/vX.Y.Z` | `release/v1.1.0` |
| Experiment | `experiment/description` | `experiment/new-caching-strategy` |

### Branch Rules

| Branch | Protection | Reviews Required | CI Required |
|--------|------------|------------------|-------------|
| `main` | Protected | 2 approvals | All checks pass |
| `develop` | Protected | 1 approval | All checks pass |
| `release/*` | Protected | 1 approval | All checks pass |
| `feature/*` | None | Optional | Recommended |
| `hotfix/*` | None | 1 approval | All checks pass |

### Git-Flow Commands

```bash
# Feature workflow
git flow feature start ISSUE-description      # Create feature branch
git flow feature finish ISSUE-description     # Merge to develop

# Release workflow
git flow release start v1.2.0                 # Create release branch
git flow release finish v1.2.0                # Merge to main and develop

# Hotfix workflow
git flow hotfix start v1.2.1-description      # Create hotfix from main
git flow hotfix finish v1.2.1-description     # Merge to main and develop

# Manual equivalents (if git-flow not installed)
git checkout develop && git checkout -b feature/ISSUE-description
git checkout develop && git merge --no-ff feature/ISSUE-description
```

---

## Conventional Commits

### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

### Commit Types

| Type | Description | Version Impact |
|------|-------------|----------------|
| `feat` | New feature | MINOR bump |
| `fix` | Bug fix | PATCH bump |
| `docs` | Documentation only | PATCH bump |
| `style` | Code style (formatting, semicolons) | PATCH bump |
| `refactor` | Code change (no feature/fix) | PATCH bump |
| `perf` | Performance improvement | PATCH bump |
| `test` | Adding/updating tests | PATCH bump |
| `chore` | Maintenance tasks | PATCH bump |
| `ci` | CI/CD changes | PATCH bump |
| `build` | Build system changes | PATCH bump |
| `revert` | Revert previous commit | PATCH bump |

### Breaking Changes

```bash
# Breaking change indicator (triggers MAJOR bump)
feat!: redesign authentication API

# Or with footer
feat(auth): redesign authentication API

BREAKING CHANGE: JWT token format changed from HS256 to RS256
```

### Scope Examples

| Scope | Description |
|-------|-------------|
| `auth` | Authentication system |
| `billing` | Billing and payments |
| `api` | API endpoints |
| `ui` | User interface |
| `db` | Database/migrations |
| `worker` | Background jobs |
| `ci` | CI/CD pipeline |
| `deps` | Dependencies |

### Commit Message Examples

```bash
# Feature
feat(auth): implement OAuth2 login with Google

# Bug fix
fix(billing): resolve duplicate charge on renewal

# Documentation
docs(api): add authentication endpoint examples

# Refactor
refactor(subscriptions): extract billing logic to service class

# Performance
perf(queries): add index for subscription lookups

# Breaking change
feat!(api): restructure user endpoints

BREAKING CHANGE: /api/v1/users now returns paginated results by default
```

### Commit Message Rules

1. **Subject line**: Max 72 characters, imperative mood ("add" not "added")
2. **Body**: Wrap at 72 characters, explain what and why (not how)
3. **Footer**: Reference issues, breaking changes
4. **No Claude attribution**: Never include "Co-Authored-By: Claude" or similar

---

## Semantic Versioning

### Version Format

```
MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]

Examples:
1.0.0           # Stable release
1.1.0           # New features added
1.1.1           # Bug fixes
2.0.0-alpha.1   # Alpha pre-release
2.0.0-beta.2    # Beta pre-release
2.0.0-rc.1      # Release candidate
```

### Version Bump Rules

| Change Type | Version Impact | Example |
|-------------|----------------|---------|
| Breaking API change | MAJOR | 1.0.0 → 2.0.0 |
| New backward-compatible feature | MINOR | 1.0.0 → 1.1.0 |
| Backward-compatible bug fix | PATCH | 1.0.0 → 1.0.1 |
| Pre-release | Append tag | 1.0.0 → 1.1.0-alpha.1 |

### Version Commands

```bash
# Check current version
git describe --tags --abbrev=0
cat package.json | jq '.version'

# Bump version (npm)
npm version patch    # 1.0.0 → 1.0.1
npm version minor    # 1.0.0 → 1.1.0
npm version major    # 1.0.0 → 2.0.0

# Pre-release versions
npm version prerelease --preid=alpha    # 1.0.0 → 1.0.1-alpha.0
npm version prerelease --preid=beta     # 1.0.0-alpha.0 → 1.0.0-beta.0
npm version prerelease --preid=rc       # 1.0.0-beta.0 → 1.0.0-rc.0

# Manual tagging
git tag -a v1.2.0 -m "Release v1.2.0: Feature description"
git push origin v1.2.0
```

---

## Release Management

### Release Checklist

#### Pre-Release
- [ ] All features for release merged to `develop`
- [ ] All tests passing (backend + frontend + E2E)
- [ ] Security audit completed (`bundle audit`, `npm audit`)
- [ ] Performance benchmarks met
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Version bumped in package files

#### Release Process
- [ ] Create release branch from `develop`
- [ ] Final testing on release branch
- [ ] Fix any release blockers
- [ ] Update version numbers
- [ ] Create release tag with notes
- [ ] Merge to `main`
- [ ] Deploy to production
- [ ] Merge back to `develop`
- [ ] Announce release

#### Post-Release
- [ ] Monitor production metrics
- [ ] Address any immediate issues
- [ ] Archive release branch
- [ ] Update project roadmap

### Release Branch Workflow

```bash
# 1. Create release branch
git checkout develop
git pull origin develop
git flow release start v1.2.0

# 2. Update version and changelog
npm version minor --no-git-tag-version
# Edit CHANGELOG.md

# 3. Final fixes on release branch
git commit -m "chore(release): prepare v1.2.0"

# 4. Finish release (merges to main and develop, creates tag)
git flow release finish v1.2.0

# 5. Push everything
git push origin main develop --tags
```

### Changelog Format

```markdown
# Changelog

## [1.2.0] - 2025-01-17

### Added
- OAuth2 authentication with Google and GitHub (#123)
- Bulk user import functionality (#145)

### Changed
- Improved subscription renewal performance (#156)
- Updated payment gateway to Stripe API v2024-12 (#167)

### Fixed
- Resolved duplicate email notifications (#134)
- Fixed timezone handling in billing cycles (#178)

### Security
- Patched XSS vulnerability in user profiles (#189)

### Deprecated
- Legacy API v1 endpoints (removal in v2.0.0)

### Removed
- Dropped support for IE11 (#190)
```

---

## Issue & PR Workflow

### Issue Labels

| Label | Description | Color |
|-------|-------------|-------|
| `bug` | Something isn't working | Red |
| `feature` | New feature request | Green |
| `enhancement` | Improvement to existing feature | Blue |
| `documentation` | Documentation updates | Yellow |
| `security` | Security-related issue | Purple |
| `performance` | Performance improvement | Orange |
| `breaking` | Breaking change | Dark Red |
| `priority:high` | High priority | Red |
| `priority:medium` | Medium priority | Yellow |
| `priority:low` | Low priority | Gray |

### Issue Template

```markdown
## Description
[Clear description of the issue or feature]

## Expected Behavior
[What should happen]

## Actual Behavior
[What actually happens - for bugs]

## Steps to Reproduce
1. Step one
2. Step two
3. Step three

## Environment
- Browser/OS:
- Version:

## Additional Context
[Screenshots, logs, etc.]
```

### Pull Request Process

#### PR Title Format
```
<type>(<scope>): <description> (#issue)

Examples:
feat(auth): implement OAuth2 login (#123)
fix(billing): resolve duplicate charges (#456)
```

#### PR Description Template

```markdown
## Summary
[1-3 bullet points describing the change]

## Related Issues
Closes #123
Related to #456

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing Done
- [ ] Unit tests added/updated
- [ ] Integration tests pass
- [ ] Manual testing completed

## Screenshots (if UI changes)
[Before/After screenshots]

## Checklist
- [ ] Code follows project conventions
- [ ] Tests pass locally
- [ ] Documentation updated
- [ ] No console.log statements
- [ ] No hardcoded values
```

#### PR Review Guidelines

**Reviewer Responsibilities**:
1. Check code quality and patterns compliance
2. Verify tests are adequate
3. Review security implications
4. Check performance impact
5. Validate documentation updates

**Review Response Times**:
- High priority: Within 4 hours
- Normal priority: Within 24 hours
- Low priority: Within 48 hours

**Approval Requirements**:
- `main` branch: 2 approving reviews
- `develop` branch: 1 approving review
- All CI checks must pass

---

## Project Tracking

### TODO.md Management

**Location**: `docs/TODO.md`

**Status Indicators**:
| Symbol | Meaning |
|--------|---------|
| `[ ]` | Not started |
| `[🔄]` | In progress |
| `[✅]` | Completed |
| `[❌]` | Blocked/Cancelled |
| `[⚠️]` | Needs attention |

**TODO Format**:
```markdown
## Phase 1: Core Features

### Authentication
- [✅] JWT token implementation
- [🔄] OAuth2 integration (#123)
- [ ] Two-factor authentication (#145)
- [❌] LDAP integration (descoped)

### Billing
- [✅] Stripe integration
- [⚠️] PayPal webhooks (needs review)
- [ ] Invoice PDF generation
```

### Sprint Planning

**Sprint Duration**: 2 weeks

**Sprint Ceremonies**:
1. **Planning**: First day of sprint
2. **Daily Standup**: 15 minutes daily
3. **Review**: Last day of sprint
4. **Retrospective**: After review

**Capacity Planning**:
- Story points per developer: 8-10 per sprint
- Buffer for bugs/maintenance: 20%
- Technical debt allocation: 10%

### Milestone Tracking

```markdown
## Milestone: v1.0.0 - MVP Release

**Target Date**: 2025-02-01
**Status**: In Progress (75% complete)

### Deliverables
- [✅] User authentication
- [✅] Subscription management
- [🔄] Payment processing
- [ ] Admin dashboard
- [ ] Email notifications

### Blockers
- None currently

### Risks
- Payment gateway certification pending
```

---

## Code Review Standards

### Review Checklist

#### Functionality
- [ ] Code accomplishes the stated objective
- [ ] Edge cases are handled
- [ ] Error handling is appropriate

#### Code Quality
- [ ] Follows project conventions (CLAUDE.md)
- [ ] No code duplication
- [ ] Functions are single-purpose
- [ ] Names are descriptive

#### Testing
- [ ] Unit tests cover new code
- [ ] Integration tests for API changes
- [ ] Edge cases are tested

#### Security
- [ ] No hardcoded secrets
- [ ] Input validation present
- [ ] Permission checks in place
- [ ] No SQL injection vulnerabilities

#### Performance
- [ ] No N+1 queries
- [ ] Appropriate indexing
- [ ] No memory leaks

#### Documentation
- [ ] Complex logic is commented
- [ ] API changes documented
- [ ] README updated if needed

### Review Comments

**Comment Types**:
- `[BLOCKER]`: Must fix before merge
- `[SUGGESTION]`: Recommended improvement
- `[QUESTION]`: Needs clarification
- `[NITPICK]`: Minor style issue
- `[PRAISE]`: Good work acknowledgment

**Example**:
```
[BLOCKER] This query will cause N+1 issues. Consider using `includes(:user)`.

[SUGGESTION] This logic could be extracted to a service class for better testability.

[QUESTION] What happens if the user doesn't have a subscription?
```

---

## Commit Preparation Protocol

### Before Committing

```bash
# 1. Check status
git status

# 2. Review changes
git diff
git diff --staged

# 3. Run pre-commit cleanup
find . -name "*.tmp" -o -name ".DS_Store" | xargs rm -f 2>/dev/null

# 4. Run tests
cd server && bundle exec rspec
cd frontend && CI=true npm test

# 5. Run linting
cd frontend && npm run lint
cd server && bundle exec rubocop

# 6. Stage changes
git add -p  # Interactive staging (recommended)
```

### Commit Workflow

```bash
# Stage specific files
git add path/to/file.rb
git add -p  # Interactive: review each hunk

# Review staged changes
git diff --staged

# Commit with conventional message
git commit -m "feat(auth): implement password reset flow

- Add password reset token generation
- Create reset email template
- Add expiration validation

Closes #123"

# Push to remote
git push origin feature/123-password-reset
```

### Pre-Commit Hooks

**Automated checks** (via `scripts/pre-commit-quality-check.sh`):
1. No `console.log` in production code
2. No hardcoded colors (theme classes required)
3. No `puts`/`print` in Ruby code
4. All Ruby files have `frozen_string_literal` pragma
5. TypeScript `any` type warnings

```bash
# Install hooks
./scripts/install-git-hooks.sh

# Bypass (not recommended)
git commit --no-verify
```

---

## Quick Reference

### Daily Workflow

```bash
# Start of day
git checkout develop
git pull origin develop

# Start feature
git flow feature start ISSUE-description
# or: git checkout -b feature/ISSUE-description

# During development
git add -p
git commit -m "feat(scope): description"

# End of feature
git push origin feature/ISSUE-description
# Create PR via GitHub

# After PR approved
git flow feature finish ISSUE-description
# or: git checkout develop && git merge --no-ff feature/ISSUE-description
```

### Release Workflow

```bash
# Create release
git flow release start v1.2.0

# Finalize
npm version minor
# Update CHANGELOG.md
git commit -m "chore(release): prepare v1.2.0"

# Complete release
git flow release finish v1.2.0
git push origin main develop --tags
```

### Hotfix Workflow

```bash
# Create hotfix from main
git flow hotfix start v1.2.1-critical-fix

# Fix and commit
git commit -m "fix(billing): resolve duplicate charge"

# Complete hotfix
git flow hotfix finish v1.2.1-critical-fix
git push origin main develop --tags
```

### Useful Git Commands

```bash
# View recent commits
git log --oneline -20

# View commit history for file
git log --follow -p path/to/file

# Find commit that introduced bug
git bisect start
git bisect bad HEAD
git bisect good v1.0.0

# Undo last commit (keep changes)
git reset --soft HEAD~1

# Amend last commit message
git commit --amend -m "new message"

# Cherry-pick commit to current branch
git cherry-pick abc123

# Stash changes
git stash
git stash pop
git stash list

# Clean untracked files
git clean -fd

# View branch relationships
git log --oneline --graph --all
```

---

## Integration with Other Specialists

### DevOps Engineer
- CI/CD pipeline configuration
- Deployment automation
- Environment management

### Security Specialist
- Security review requirements
- Vulnerability disclosure process
- Compliance checkpoints

### All Development Specialists
- Code review assignments
- PR workflow enforcement
- Convention compliance
