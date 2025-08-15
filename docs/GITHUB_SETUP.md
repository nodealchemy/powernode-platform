# GitHub Configuration Guide for Powernode

## 1. Create GitHub Repository

### Option A: Using GitHub Web Interface
1. Go to https://github.com/new
2. Repository name: `powernode-platform`
3. Description: `Subscription lifecycle management platform with Rails 8 API, React TypeScript frontend, and Sidekiq worker service`
4. Choose **Private** or **Public** based on your needs
5. **DO NOT** initialize with README, .gitignore, or license (we already have these)
6. Click "Create repository"

### Option B: Using GitHub CLI (if available)
```bash
gh repo create powernode-platform --private --description "Subscription lifecycle management platform"
```

## 2. Configure Git Remote

After creating the repository, add the remote:

```bash
# Replace YOUR_USERNAME with your GitHub username
git remote add origin https://github.com/YOUR_USERNAME/powernode-platform.git

# Verify remote was added
git remote -v
```

## 3. Push Initial Code

```bash
# Push master branch and all tags
git push -u origin master --tags

# Push develop branch
git checkout develop
git push -u origin develop

# Set develop as default branch for Git-Flow
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop
```

## 4. GitHub Repository Settings

### Branch Protection Rules

Navigate to **Settings > Branches** and add these protection rules:

#### For `master` branch:
- ✅ Require a pull request before merging
- ✅ Require approvals (1)
- ✅ Dismiss stale PR approvals when new commits are pushed
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ✅ Require conversation resolution before merging
- ✅ Restrict pushes that create files larger than 100MB
- ✅ Do not allow bypassing the above settings

#### For `develop` branch:
- ✅ Require a pull request before merging
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- ✅ Allow force pushes (for Git-Flow)

### Repository Settings

In **Settings > General**:

#### Features
- ✅ Wikis (for documentation)
- ✅ Issues (for bug tracking)
- ✅ Projects (for project management)
- ✅ Discussions (for community)

#### Pull Requests
- ✅ Allow merge commits
- ✅ Allow squash merging
- ✅ Allow rebase merging
- ✅ Always suggest updating pull request branches
- ✅ Automatically delete head branches

## 5. GitHub Actions Configuration

The repository already includes GitHub Actions workflows:

### Semantic Release Workflow
- **File**: `.github/workflows/semantic-release.yml`
- **Triggers**: Push to master, pull requests
- **Features**: Testing, security audits, automated releases

### Required Secrets

Add these secrets in **Settings > Secrets and variables > Actions**:

```bash
# For npm packages (if publishing)
NPM_TOKEN=your_npm_token

# For semantic-release GitHub integration  
GITHUB_TOKEN=automatically_provided

# For deployment (optional)
DEPLOY_KEY=your_deploy_key
```

## 6. Issue Templates

Create `.github/ISSUE_TEMPLATE/` directory with templates:

### Bug Report Template
```yaml
name: Bug Report
about: Create a report to help us improve
title: '[BUG] '
labels: ['bug', 'needs-triage']
assignees: ''
```

### Feature Request Template
```yaml
name: Feature Request
about: Suggest an idea for this project
title: '[FEATURE] '
labels: ['enhancement', 'needs-triage']
assignees: ''
```

## 7. Pull Request Template

Create `.github/pull_request_template.md`:

```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update

## Testing
- [ ] Tests pass locally
- [ ] New tests added for new functionality
- [ ] Manual testing completed

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated
- [ ] No breaking changes without version bump
```

## 8. GitHub Pages (Optional)

For documentation hosting:

1. Go to **Settings > Pages**
2. Source: **Deploy from a branch**
3. Branch: **master** or **gh-pages**
4. Folder: **/ (root)** or **/docs**

## 9. Security Configuration

### Security Policies

Create `.github/SECURITY.md`:

```markdown
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |
| 0.0.x   | :white_check_mark: |

## Reporting a Vulnerability

Please report security vulnerabilities via email to security@your-domain.com
```

### Dependabot Configuration

The repository includes `.github/dependabot.yml` for automated dependency updates.

## 10. Git-Flow GitHub Integration

### Release Process with GitHub

1. **Create Release Branch**:
   ```bash
   git flow release start v0.1.0
   ```

2. **Complete Release**:
   ```bash
   git flow release finish v0.1.0
   ```

3. **Push to GitHub**:
   ```bash
   git push origin master --tags
   git push origin develop
   ```

4. **Create GitHub Release**:
   - Go to **Releases > Create a new release**
   - Tag: `v0.1.0`
   - Title: `Release v0.1.0`
   - Description: Copy from CHANGELOG.md
   - Attach binaries if applicable

## 11. Team Collaboration

### Branch Naming Convention
- Feature branches: `feature/description-of-feature`
- Hotfix branches: `hotfix/description-of-fix`
- Release branches: `release/v0.1.0`

### Commit Message Convention
Following Conventional Commits:
```
type(scope): description

feat(auth): add OAuth2 integration
fix(billing): resolve subscription renewal issue
docs(api): update endpoint documentation
```

## Quick Setup Commands

```bash
# 1. Add GitHub remote (replace YOUR_USERNAME)
git remote add origin https://github.com/YOUR_USERNAME/powernode-platform.git

# 2. Push all branches and tags
git push -u origin master --tags
git checkout develop
git push -u origin develop

# 3. Set develop as default branch
git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/develop

# 4. Verify setup
git remote -v
git branch -a
```

## Troubleshooting

### Authentication Issues
- Use personal access token instead of password
- Configure SSH keys for seamless authentication
- Enable 2FA for enhanced security

### Large File Issues
- Use Git LFS for files > 100MB
- Add binary files to .gitignore
- Consider external storage for large assets

### Branch Protection Bypassing
- Use organization rules for stricter enforcement
- Require admin approval for protection rule changes
- Enable audit logging for compliance