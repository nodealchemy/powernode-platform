# frozen_string_literal: true

# DevOps Articles - Priority 1
# Creates comprehensive documentation for DevOps features

puts "  📦 Creating DevOps articles..."

devops_cat = KnowledgeBase::Category.find_by!(slug: "devops")
author = User.find_by!(email: "admin@powernode.org")

# Article 24: DevOps Overview (Featured)
devops_overview_content = <<~MARKDOWN
# DevOps Overview

Powernode's DevOps integration provides comprehensive tools for modern software development workflows, enabling teams to connect repositories, automate builds, and streamline deployments from a unified platform.

## What You'll Learn

- Core DevOps capabilities in Powernode
- Git provider integration options
- CI/CD pipeline fundamentals
- Webhook and automation patterns
- API key management for secure access

## Key Features

### Git Integration

Connect your code repositories from popular providers:

- **GitHub** - Full OAuth integration with repository sync
- **GitLab** - Self-hosted and cloud support
- **Gitea** - Lightweight self-hosted option
- **Bitbucket** - Atlassian ecosystem integration

### CI/CD Pipelines

Build, test, and deploy your applications automatically:

```yaml
# Example pipeline configuration
name: Production Deploy
stages:
  - build
  - test
  - deploy

jobs:
  build:
    stage: build
    script:
      - npm install
      - npm run build
    artifacts:
      paths:
        - dist/

  test:
    stage: test
    script:
      - npm run test:ci
    coverage: '/Coverage: (\\d+)%/'

  deploy:
    stage: deploy
    script:
      - ./scripts/deploy.sh
    environment: production
    when: manual
```

### Webhooks and Automation

Receive real-time notifications for repository events:

- Push events and commits
- Pull request creation and updates
- Issue tracking integration
- Release and tag creation
- Branch protection status changes

### API Keys

Secure programmatic access for CI/CD systems:

```bash
# Using API keys in CI/CD
curl -X POST https://api.powernode.org/api/v1/deployments \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"environment": "production", "commit_sha": "abc123"}'
```

## Getting Started Checklist

### Day 1: Repository Connection
- [ ] Navigate to DevOps > Git Providers
- [ ] Click "Connect Provider"
- [ ] Authorize OAuth access
- [ ] Select repositories to sync
- [ ] Configure sync frequency

### Week 1: Pipeline Setup
- [ ] Create your first CI/CD pipeline
- [ ] Configure build stages
- [ ] Add test automation
- [ ] Set up deployment targets
- [ ] Configure environment variables

### Week 2: Automation
- [ ] Set up webhook endpoints
- [ ] Configure build triggers
- [ ] Enable automatic deployments
- [ ] Set up notifications
- [ ] Review and optimize workflows

## Best Practices

### Repository Management

**Branch Protection**
- Require pull request reviews
- Enable status checks before merge
- Restrict force pushes to main branches
- Enable signed commits for security

**Code Quality**
- Integrate linting in pipelines
- Require passing tests before merge
- Track code coverage metrics
- Automate dependency updates

### Pipeline Optimization

**Caching**
```yaml
cache:
  key: ${CI_COMMIT_REF_SLUG}
  paths:
    - node_modules/
    - .npm/
```

**Parallel Execution**
```yaml
test:
  parallel:
    matrix:
      - NODE_VERSION: ['18', '20', '22']
```

**Artifacts Management**
- Keep only necessary build artifacts
- Set retention policies
- Use compression for large files
- Clean up old artifacts automatically

### Security

**Secrets Management**
- Never commit secrets to repositories
- Use environment variables for sensitive data
- Rotate API keys regularly
- Audit access permissions quarterly

**Pipeline Security**
- Pin dependency versions
- Scan for vulnerabilities
- Use signed container images
- Implement least privilege access

## Integration Examples

### GitHub Actions Trigger

```yaml
# .github/workflows/powernode.yml
name: Notify Powernode
on:
  push:
    branches: [main]

jobs:
  notify:
    runs-on: ubuntu-latest
    steps:
      - name: Trigger Powernode Pipeline
        run: |
          curl -X POST ${{ secrets.POWERNODE_WEBHOOK_URL }} \\
            -H "Content-Type: application/json" \\
            -d '{"event": "push", "ref": "${{ github.ref }}"}'
```

### GitLab CI Integration

```yaml
# .gitlab-ci.yml
stages:
  - notify

powernode_notify:
  stage: notify
  script:
    - >
      curl -X POST $POWERNODE_WEBHOOK_URL
      -H "Content-Type: application/json"
      -d '{"pipeline_id": "'$CI_PIPELINE_ID'", "status": "success"}'
  only:
    - main
```

## Monitoring and Analytics

### Pipeline Metrics

Track key performance indicators:

- **Build Success Rate** - Target > 95%
- **Average Build Time** - Optimize for speed
- **Deployment Frequency** - Measure delivery velocity
- **Mean Time to Recovery** - Track incident response

### Activity Dashboard

View real-time DevOps activity:

- Recent commits across repositories
- Pipeline execution status
- Deployment history
- Team activity timeline

## Troubleshooting

### Common Issues

**Provider Connection Failed**
1. Check OAuth token validity
2. Verify repository permissions
3. Confirm network connectivity
4. Review provider status page

**Pipeline Not Triggering**
1. Verify webhook configuration
2. Check trigger conditions
3. Review branch filters
4. Inspect webhook delivery logs

**Build Failures**
1. Check build logs for errors
2. Verify environment variables
3. Confirm dependency availability
4. Test locally with same configuration

## Next Steps

Ready to dive deeper? Explore these guides:

1. [Configuring Git Providers](/kb/configuring-git-providers) - Detailed provider setup
2. [Creating CI/CD Pipelines](/kb/creating-cicd-pipelines) - Advanced pipeline configuration
3. [Webhook Management](/kb/webhook-integration-management) - Automation deep dive

---

Need help? Contact support@powernode.org or visit our [community forum](https://community.powernode.org).
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "devops-overview") do |article|
  article.title = "DevOps Overview"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = true
  article.excerpt = "Comprehensive introduction to Powernode's DevOps capabilities including Git integration, CI/CD pipelines, webhooks, and automation patterns."
  article.content = devops_overview_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ DevOps Overview"

# Article 25: Configuring Git Providers
git_providers_content = <<~MARKDOWN
# Configuring Git Providers

Connect your code repositories to Powernode for seamless integration with CI/CD pipelines, activity tracking, and automated workflows.

## Supported Providers

### GitHub

GitHub is the most popular Git hosting service, offering extensive API support and OAuth integration.

**Features:**
- Repository sync and mirroring
- Pull request status checks
- Commit activity tracking
- GitHub Actions integration
- Issue and milestone sync

**Setup Steps:**

1. Navigate to **DevOps > Git Providers**
2. Click **Connect Provider** > **GitHub**
3. Authorize Powernode OAuth application
4. Select organization or personal account
5. Choose repositories to sync

```bash
# Verify connection via API
curl -X GET https://api.powernode.org/api/v1/devops/providers \\
  -H "Authorization: Bearer YOUR_API_KEY"
```

**OAuth Scopes Required:**
- `repo` - Full repository access
- `read:org` - Organization membership
- `admin:repo_hook` - Webhook management
- `workflow` - GitHub Actions (optional)

### GitLab

GitLab offers both cloud and self-hosted options with comprehensive DevOps features.

**Features:**
- Self-hosted and GitLab.com support
- CI/CD pipeline integration
- Merge request workflows
- Container registry access
- Security scanning integration

**Setup Steps:**

1. Navigate to **DevOps > Git Providers**
2. Click **Connect Provider** > **GitLab**
3. Enter instance URL (for self-hosted)
4. Generate personal access token with required scopes
5. Configure repository access

**Required Token Scopes:**
- `api` - Full API access
- `read_repository` - Repository read access
- `write_repository` - Repository write access
- `read_registry` - Container registry access (optional)

**Self-Hosted Configuration:**
```yaml
GitLab Self-Hosted Setup:
  Instance URL: https://gitlab.yourcompany.com
  API Version: v4 (default)
  SSL Verification: true (recommended)
  Timeout: 30 seconds
```

### Gitea

Gitea is a lightweight, self-hosted Git service ideal for smaller teams.

**Features:**
- Minimal resource requirements
- Full Git compatibility
- Webhook support
- REST API access
- Organization management

**Setup Steps:**

1. Navigate to **DevOps > Git Providers**
2. Click **Connect Provider** > **Gitea**
3. Enter your Gitea instance URL
4. Create application token in Gitea settings
5. Configure organization access

**Token Generation:**
```
Gitea > Settings > Applications > Generate New Token
Required Permissions:
  - repo:read, repo:write
  - organization:read (if using orgs)
  - admin:repo_hook
```

### Bitbucket

Bitbucket integrates with the Atlassian ecosystem for comprehensive project management.

**Features:**
- Jira integration
- Pipelines compatibility
- Pull request automation
- Code review workflows
- Team collaboration

**Setup Steps:**

1. Navigate to **DevOps > Git Providers**
2. Click **Connect Provider** > **Bitbucket**
3. Authorize via OAuth 2.0
4. Select workspace
5. Choose repositories to sync

## Repository Synchronization

### Sync Configuration

Control how repositories sync with Powernode:

```yaml
Sync Settings:
  Frequency: Every 15 minutes (default)
  Options:
    - On webhook event (real-time)
    - Hourly
    - Daily
    - Manual only

  Include:
    - Branches: main, develop, release/*
    - Tags: v*, release-*
    - Commits: Last 100 per branch

  Exclude:
    - Branches: feature/*, hotfix/*
    - Files: *.log, node_modules/**
```

### Branch Management

Configure branch synchronization:

**Protected Branches**
- Sync status checks to Powernode
- Track merge requirements
- Monitor branch policies
- Report protection violations

**Branch Filters**
```yaml
Branch Patterns:
  Include:
    - main
    - develop
    - release/**
    - hotfix/**
  Exclude:
    - feature/**
    - experiment/**
```

### Commit Tracking

Track commit activity across repositories:

- Author information
- Commit messages and descriptions
- File changes summary
- Build status per commit
- Linked issues and PRs

## Webhook Configuration

### Automatic Webhooks

Powernode automatically configures webhooks when connecting providers:

```yaml
Webhook Events (Auto-configured):
  - push
  - pull_request
  - pull_request_review
  - create (branches/tags)
  - delete (branches/tags)
  - release
  - issues (optional)
```

### Manual Webhook Setup

For restricted environments, configure webhooks manually:

**Webhook URL Format:**
```
https://api.powernode.org/webhooks/git/{provider_id}/{secret_token}
```

**Security Settings:**
- Content type: `application/json`
- Secret: Auto-generated, visible in provider settings
- SSL verification: Required (recommended)

### Event Filtering

Control which events trigger actions:

```yaml
Event Filters:
  push:
    branches:
      - main
      - release/*
    paths:
      include:
        - src/**
        - package.json
      exclude:
        - docs/**
        - "*.md"
```

## Troubleshooting

### Connection Issues

**OAuth Authorization Failed**

```yaml
Possible Causes:
  - Expired OAuth token
  - Insufficient permissions
  - Organization restrictions
  - Third-party access blocked

Resolution Steps:
  1. Re-authorize from provider settings
  2. Check required OAuth scopes
  3. Verify organization allows third-party access
  4. Contact organization admin if restricted
```

**Repository Not Appearing**

```yaml
Checklist:
  - Verify repository permissions
  - Check organization membership
  - Confirm repository is not archived
  - Try manual repository refresh
  - Check API rate limits
```

**Webhook Delivery Failures**

```yaml
Common Issues:
  - Incorrect webhook URL
  - Invalid secret token
  - SSL certificate problems
  - Firewall blocking requests

Debugging:
  1. Check webhook delivery logs in provider
  2. Verify Powernode webhook endpoint status
  3. Test with webhook.site for debugging
  4. Review Powernode activity logs
```

### Sync Problems

**Commits Not Syncing**

1. Check sync frequency settings
2. Verify webhook is delivering events
3. Confirm branch is not excluded
4. Review provider API status
5. Trigger manual sync

**Branch Protection Not Reflecting**

1. Ensure admin permissions
2. Check branch protection API access
3. Verify sync includes protection rules
4. Wait for next sync cycle

## Best Practices

### Security

**Token Management**
- Use dedicated service accounts
- Apply minimum required permissions
- Rotate tokens quarterly
- Monitor token usage

**Access Control**
- Limit repository access to needed repos
- Use organization-level tokens when possible
- Audit connected repositories regularly
- Remove unused provider connections

### Performance

**Optimize Sync**
- Filter unnecessary branches
- Exclude large binary files
- Set appropriate sync frequency
- Use webhooks for real-time updates

## Related Articles

- [DevOps Overview](/kb/devops-overview)
- [Creating CI/CD Pipelines](/kb/creating-cicd-pipelines)
- [Webhook and Integration Management](/kb/webhook-integration-management)

---

Need help configuring your Git provider? Contact support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "configuring-git-providers") do |article|
  article.title = "Configuring Git Providers"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Step-by-step guide to connecting GitHub, GitLab, Gitea, and Bitbucket to Powernode for repository synchronization and CI/CD integration."
  article.content = git_providers_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Configuring Git Providers"

# Article 26: Creating CI/CD Pipelines
cicd_pipelines_content = <<~MARKDOWN
# Creating CI/CD Pipelines

Build automated pipelines to continuously integrate, test, and deploy your applications with Powernode's visual pipeline builder and YAML configuration.

## Pipeline Concepts

### What is a Pipeline?

A CI/CD pipeline is an automated workflow that builds, tests, and deploys your code. Pipelines consist of:

- **Stages** - Major phases (build, test, deploy)
- **Jobs** - Individual tasks within stages
- **Steps** - Commands executed in jobs
- **Artifacts** - Files produced and shared between jobs

### Pipeline Lifecycle

```
Code Push → Trigger → Build → Test → Deploy → Monitor
    ↓         ↓        ↓       ↓        ↓         ↓
  Event   Webhook   Compile   Run    Release   Track
          Match     & Pack   Tests   to Env   Metrics
```

## Creating Your First Pipeline

### Using the Visual Builder

1. Navigate to **DevOps > Pipelines**
2. Click **Create Pipeline**
3. Select **Visual Builder**
4. Add stages and jobs using drag-and-drop
5. Configure triggers and conditions
6. Save and activate

### Using YAML Configuration

Create a `powernode-pipeline.yml` in your repository:

```yaml
# powernode-pipeline.yml
name: Application Pipeline
version: 1

trigger:
  branches:
    include:
      - main
      - release/*
  paths:
    include:
      - src/**
      - package.json

variables:
  NODE_VERSION: '20'
  DEPLOY_ENV: production

stages:
  - name: build
    jobs:
      - name: compile
        runner: ubuntu-latest
        steps:
          - checkout: self
          - run: npm ci
          - run: npm run build
          - artifact:
              name: dist
              paths:
                - dist/**
                - package.json

  - name: test
    dependsOn: build
    jobs:
      - name: unit-tests
        runner: ubuntu-latest
        steps:
          - checkout: self
          - artifact: dist
          - run: npm ci
          - run: npm run test:unit
          - coverage:
              format: lcov
              path: coverage/lcov.info

      - name: integration-tests
        runner: ubuntu-latest
        steps:
          - checkout: self
          - artifact: dist
          - run: npm ci
          - run: npm run test:integration

  - name: deploy
    dependsOn: test
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - name: deploy-production
        runner: ubuntu-latest
        environment: production
        steps:
          - artifact: dist
          - run: ./scripts/deploy.sh
        approvals:
          - type: manual
            approvers:
              - team-leads
```

## Pipeline Configuration

### Triggers

**Branch Triggers**
```yaml
trigger:
  branches:
    include:
      - main
      - develop
      - release/*
    exclude:
      - feature/*
```

**Path Triggers**
```yaml
trigger:
  paths:
    include:
      - src/**
      - tests/**
    exclude:
      - docs/**
      - "*.md"
```

**Schedule Triggers**
```yaml
schedules:
  - cron: "0 0 * * *"  # Daily at midnight
    branches:
      include:
        - main
    always: true  # Run even without changes
```

**Manual Triggers**
```yaml
trigger: none  # Only manual execution

parameters:
  - name: environment
    displayName: Deploy Environment
    type: string
    default: staging
    values:
      - staging
      - production
```

### Variables and Secrets

**Pipeline Variables**
```yaml
variables:
  # Inline variables
  APP_NAME: my-application
  NODE_VERSION: '20'

  # Variable groups (shared across pipelines)
  - group: common-variables
  - group: production-secrets

  # Conditional variables
  ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    DEPLOY_ENV: production
  ${{ else }}:
    DEPLOY_ENV: staging
```

**Secrets Management**
```yaml
# Reference secrets from secure storage
steps:
  - run: |
      echo "Deploying to ${{ secrets.DEPLOY_HOST }}"
      ./deploy.sh --key "${{ secrets.DEPLOY_KEY }}"
    env:
      DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

### Runners and Environments

**Runner Selection**
```yaml
jobs:
  build:
    runner: ubuntu-latest  # Hosted runner
    # Or self-hosted:
    # runner:
    #   labels: [self-hosted, linux, x64]
    steps:
      - run: echo "Building on $(uname -a)"
```

**Available Hosted Runners**
| Runner | Description | Use Case |
|--------|-------------|----------|
| `ubuntu-latest` | Ubuntu 22.04 | General purpose |
| `ubuntu-20.04` | Ubuntu 20.04 | Legacy compatibility |
| `macos-latest` | macOS 14 | iOS/macOS builds |
| `windows-latest` | Windows Server 2022 | Windows builds |

**Environment Configuration**
```yaml
jobs:
  deploy:
    environment:
      name: production
      url: https://myapp.com
    steps:
      - run: ./deploy.sh
```

## Advanced Features

### Parallel Execution

**Matrix Strategy**
```yaml
jobs:
  test:
    strategy:
      matrix:
        node: [18, 20, 22]
        os: [ubuntu-latest, macos-latest]
    runner: ${{ matrix.os }}
    steps:
      - uses: setup-node@v4
        with:
          node-version: ${{ matrix.node }}
      - run: npm test
```

**Fan-Out/Fan-In**
```yaml
stages:
  - name: test
    jobs:
      - name: unit-tests
      - name: integration-tests
      - name: e2e-tests

  - name: deploy
    dependsOn: test  # Waits for all test jobs
```

### Artifacts and Caching

**Artifact Upload**
```yaml
steps:
  - run: npm run build
  - artifact:
      name: build-output
      paths:
        - dist/**
      retention: 30 days
```

**Artifact Download**
```yaml
steps:
  - artifact:
      name: build-output
      path: ./dist
  - run: ls -la dist/
```

**Caching**
```yaml
steps:
  - cache:
      key: npm-${{ hashFiles('package-lock.json') }}
      paths:
        - ~/.npm
        - node_modules
  - run: npm ci
```

### Conditions and Dependencies

**Conditional Execution**
```yaml
jobs:
  deploy:
    condition: |
      and(
        succeeded(),
        eq(variables['Build.SourceBranch'], 'refs/heads/main'),
        ne(variables['Build.Reason'], 'PullRequest')
      )
```

**Job Dependencies**
```yaml
stages:
  - name: build
  - name: test
    dependsOn: build
  - name: deploy
    dependsOn:
      - build
      - test
    condition: succeeded('test')
```

### Approvals and Gates

**Manual Approval**
```yaml
jobs:
  deploy-production:
    environment: production
    approvals:
      - type: manual
        approvers:
          - user:admin@company.com
          - team:release-managers
        timeout: 24h
        instructions: "Review changes before production deployment"
```

**Automated Gates**
```yaml
jobs:
  deploy:
    gates:
      - type: quality-gate
        conditions:
          - coverage: ">= 80%"
          - critical-issues: 0
      - type: time-window
        allowed:
          - weekdays: true
          - hours: 9-17
```

## Pipeline Templates

### Reusable Templates

Create shared pipeline templates:

```yaml
# templates/node-build.yml
parameters:
  - name: nodeVersion
    default: '20'

steps:
  - uses: setup-node@v4
    with:
      node-version: ${{ parameters.nodeVersion }}
  - run: npm ci
  - run: npm run build
```

**Using Templates**
```yaml
# Main pipeline
stages:
  - name: build
    jobs:
      - name: build-app
        steps:
          - template: templates/node-build.yml
            parameters:
              nodeVersion: '22'
```

### Common Pipeline Patterns

**Node.js Application**
```yaml
name: Node.js CI/CD

trigger:
  branches: [main]

stages:
  - name: ci
    jobs:
      - name: build-and-test
        runner: ubuntu-latest
        steps:
          - checkout: self
          - uses: setup-node@v4
            with:
              node-version: '20'
              cache: 'npm'
          - run: npm ci
          - run: npm run lint
          - run: npm run test:ci
          - run: npm run build
          - artifact:
              name: dist
              paths: [dist/**]

  - name: cd
    dependsOn: ci
    jobs:
      - name: deploy
        runner: ubuntu-latest
        environment: production
        steps:
          - artifact: dist
          - run: ./deploy.sh
```

## Monitoring and Debugging

### Pipeline Logs

Access detailed logs for each step:

1. Navigate to pipeline run
2. Click on failed job
3. Expand step logs
4. Download full logs if needed

### Debug Mode

Enable verbose logging:

```yaml
variables:
  SYSTEM_DEBUG: true
  ACTIONS_STEP_DEBUG: true

steps:
  - run: |
      set -x  # Enable bash debug
      npm run build
```

### Notifications

Configure pipeline notifications:

```yaml
notifications:
  - type: email
    recipients:
      - team@company.com
    on:
      - failure
      - success-after-failure

  - type: slack
    webhook: ${{ secrets.SLACK_WEBHOOK }}
    on:
      - failure
```

## Troubleshooting

### Common Issues

**Pipeline Not Triggering**
- Check branch filter matches
- Verify webhook is configured
- Review trigger conditions
- Check for syntax errors in YAML

**Job Failing**
- Review step logs for errors
- Check runner availability
- Verify environment variables
- Test commands locally

**Slow Pipelines**
- Enable caching
- Parallelize independent jobs
- Optimize artifact sizes
- Use appropriate runners

## Related Articles

- [DevOps Overview](/kb/devops-overview)
- [Configuring Git Providers](/kb/configuring-git-providers)
- [Webhook and Integration Management](/kb/webhook-integration-management)

---

Need help with pipeline configuration? Contact support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "creating-cicd-pipelines") do |article|
  article.title = "Creating CI/CD Pipelines"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Complete guide to building automated CI/CD pipelines in Powernode with visual builder, YAML configuration, and advanced features."
  article.content = cicd_pipelines_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Creating CI/CD Pipelines"

# Article 27: Webhook and Integration Management
webhook_content = <<~MARKDOWN
# Webhook and Integration Management

Configure webhook endpoints to receive real-time events and integrate Powernode with external services for automated workflows.

## Understanding Webhooks

### What Are Webhooks?

Webhooks are HTTP callbacks that notify your applications when events occur in Powernode. Instead of polling for changes, webhooks push data to your endpoints in real-time.

### Webhook Architecture

```
Event Occurs → Powernode → HTTP POST → Your Endpoint → Process Event
     ↓              ↓              ↓            ↓
  (Push,        Generate      Delivery     Handle &
   Deploy,      Payload       + Retry      Respond
   etc.)
```

## Creating Webhook Endpoints

### In the Dashboard

1. Navigate to **DevOps > Webhooks**
2. Click **Add Webhook**
3. Configure endpoint details:
   - Name: Descriptive identifier
   - URL: Your HTTPS endpoint
   - Events: Select events to receive
   - Secret: Auto-generated or custom
4. Save and test

### Via API

```bash
curl -X POST https://api.powernode.org/api/v1/webhooks \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "Production Notifications",
    "url": "https://api.myapp.com/webhooks/powernode",
    "events": ["pipeline.completed", "deployment.finished"],
    "secret": "your-webhook-secret",
    "active": true
  }'
```

## Available Events

### Pipeline Events

| Event | Description | Payload |
|-------|-------------|---------|
| `pipeline.started` | Pipeline execution began | Pipeline details, trigger info |
| `pipeline.completed` | Pipeline finished (success/failure) | Final status, duration, artifacts |
| `pipeline.failed` | Pipeline failed | Error details, failed job |
| `job.started` | Individual job started | Job details, runner info |
| `job.completed` | Individual job finished | Job status, logs location |

### Deployment Events

| Event | Description | Payload |
|-------|-------------|---------|
| `deployment.started` | Deployment initiated | Environment, version |
| `deployment.finished` | Deployment completed | Status, deployment URL |
| `deployment.rolled_back` | Rollback executed | Previous version, reason |
| `approval.requested` | Manual approval needed | Approvers, deadline |
| `approval.received` | Approval granted | Approver, timestamp |

### Repository Events

| Event | Description | Payload |
|-------|-------------|---------|
| `repository.synced` | Repository sync completed | Commit count, branch info |
| `commit.received` | New commit detected | Commit details, author |
| `branch.created` | New branch created | Branch name, base |
| `branch.deleted` | Branch removed | Branch name |
| `tag.created` | New tag created | Tag name, commit |

## Webhook Payload Structure

### Standard Payload Format

```json
{
  "id": "evt_01HQ7EXAMPLE",
  "type": "pipeline.completed",
  "created_at": "2024-01-15T10:30:00Z",
  "data": {
    "pipeline": {
      "id": "pipe_01HQ7EXAMPLE",
      "name": "Production Deploy",
      "status": "success",
      "duration_seconds": 245,
      "trigger": {
        "type": "push",
        "branch": "main",
        "commit": "abc123def456"
      }
    }
  },
  "account": {
    "id": "acc_01HQ7EXAMPLE",
    "name": "Acme Corp"
  }
}
```

### Event-Specific Payloads

**Pipeline Completed**
```json
{
  "type": "pipeline.completed",
  "data": {
    "pipeline": {
      "id": "pipe_01HQ7EXAMPLE",
      "name": "Main Pipeline",
      "status": "success",
      "started_at": "2024-01-15T10:25:00Z",
      "finished_at": "2024-01-15T10:30:00Z",
      "duration_seconds": 300,
      "stages": [
        {"name": "build", "status": "success", "duration": 120},
        {"name": "test", "status": "success", "duration": 150},
        {"name": "deploy", "status": "success", "duration": 30}
      ],
      "artifacts": [
        {"name": "dist", "size_bytes": 1048576}
      ]
    },
    "commit": {
      "sha": "abc123def456",
      "message": "feat: add new feature",
      "author": "developer@company.com"
    }
  }
}
```

## Webhook Security

### Signature Verification

Powernode signs all webhook payloads using HMAC-SHA256:

```
X-Powernode-Signature: sha256=abc123...
X-Powernode-Timestamp: 1705312200
```

**Verification Implementation (Node.js):**
```javascript
const crypto = require('crypto');

function verifyWebhookSignature(payload, signature, timestamp, secret) {
  const signedPayload = `${timestamp}.${payload}`;
  const expectedSignature = crypto
    .createHmac('sha256', secret)
    .update(signedPayload)
    .digest('hex');

  const receivedSignature = signature.replace('sha256=', '');

  // Timing-safe comparison
  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature),
    Buffer.from(receivedSignature)
  );
}

// Express middleware
app.post('/webhooks/powernode', express.raw({type: 'application/json'}), (req, res) => {
  const signature = req.headers['x-powernode-signature'];
  const timestamp = req.headers['x-powernode-timestamp'];
  const payload = req.body.toString();

  if (!verifyWebhookSignature(payload, signature, timestamp, WEBHOOK_SECRET)) {
    return res.status(401).send('Invalid signature');
  }

  // Process valid webhook
  const event = JSON.parse(payload);
  handleEvent(event);

  res.status(200).send('OK');
});
```

**Verification Implementation (Python):**
```python
import hmac
import hashlib
from flask import Flask, request, abort

def verify_webhook_signature(payload, signature, timestamp, secret):
    signed_payload = f"{timestamp}.{payload}"
    expected_signature = hmac.new(
        secret.encode(),
        signed_payload.encode(),
        hashlib.sha256
    ).hexdigest()

    received_signature = signature.replace('sha256=', '')
    return hmac.compare_digest(expected_signature, received_signature)

@app.route('/webhooks/powernode', methods=['POST'])
def handle_webhook():
    signature = request.headers.get('X-Powernode-Signature')
    timestamp = request.headers.get('X-Powernode-Timestamp')
    payload = request.get_data(as_text=True)

    if not verify_webhook_signature(payload, signature, timestamp, WEBHOOK_SECRET):
        abort(401)

    event = request.get_json()
    process_event(event)
    return 'OK', 200
```

### Timestamp Validation

Prevent replay attacks by validating timestamp freshness:

```javascript
const MAX_AGE_SECONDS = 300; // 5 minutes

function isTimestampValid(timestamp) {
  const now = Math.floor(Date.now() / 1000);
  const eventTime = parseInt(timestamp);
  return Math.abs(now - eventTime) <= MAX_AGE_SECONDS;
}
```

## Retry Logic

### Automatic Retries

Powernode automatically retries failed webhook deliveries:

```yaml
Retry Schedule:
  Attempt 1: Immediate
  Attempt 2: 1 minute delay
  Attempt 3: 5 minutes delay
  Attempt 4: 30 minutes delay
  Attempt 5: 2 hours delay
  Maximum: 5 attempts over 24 hours

Success Criteria:
  - HTTP 2xx response
  - Response within 30 seconds
  - Valid response body (optional)
```

### Handling Failures

When processing might fail:

```javascript
app.post('/webhooks/powernode', async (req, res) => {
  // Always respond quickly to acknowledge receipt
  res.status(200).send('Received');

  // Process asynchronously
  try {
    await processEventAsync(req.body);
  } catch (error) {
    // Log for manual review
    logger.error('Webhook processing failed', {
      eventId: req.body.id,
      error: error.message
    });
    // Don't throw - we already acknowledged
  }
});
```

## Integration Patterns

### Slack Notifications

```javascript
async function notifySlack(event) {
  if (event.type !== 'pipeline.completed') return;

  const pipeline = event.data.pipeline;
  const status = pipeline.status === 'success' ? '✅' : '❌';

  await fetch(SLACK_WEBHOOK_URL, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      text: `${status} Pipeline "${pipeline.name}" ${pipeline.status}`,
      attachments: [{
        color: pipeline.status === 'success' ? 'good' : 'danger',
        fields: [
          {title: 'Duration', value: `${pipeline.duration_seconds}s`, short: true},
          {title: 'Trigger', value: pipeline.trigger.type, short: true}
        ]
      }]
    })
  });
}
```

### Database Logging

```javascript
async function logToDatabase(event) {
  await db.webhookEvents.create({
    event_id: event.id,
    event_type: event.type,
    payload: event.data,
    received_at: new Date(),
    processed: false
  });
}
```

### Third-Party Integrations

**PagerDuty Alert:**
```javascript
async function triggerPagerDuty(event) {
  if (event.type !== 'pipeline.failed') return;

  await fetch('https://events.pagerduty.com/v2/enqueue', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
      routing_key: PAGERDUTY_KEY,
      event_action: 'trigger',
      payload: {
        summary: `Pipeline ${event.data.pipeline.name} failed`,
        severity: 'error',
        source: 'powernode',
        custom_details: event.data
      }
    })
  });
}
```

## Debugging Webhooks

### Webhook Logs

View delivery logs in dashboard:

1. Navigate to **DevOps > Webhooks**
2. Select webhook endpoint
3. Click **Delivery Logs**
4. Review request/response details

### Test Mode

Test webhooks before deployment:

```bash
# Send test event
curl -X POST https://api.powernode.org/api/v1/webhooks/{id}/test \\
  -H "Authorization: Bearer YOUR_API_KEY" \\
  -d '{"event_type": "pipeline.completed"}'
```

### Local Development

Use ngrok or similar for local testing:

```bash
# Start ngrok tunnel
ngrok http 3000

# Update webhook URL to ngrok URL
# https://abc123.ngrok.io/webhooks/powernode
```

## Troubleshooting

### Common Issues

**Webhook Not Delivered**
- Verify endpoint is publicly accessible
- Check SSL certificate validity
- Confirm correct event subscription
- Review firewall rules

**Signature Verification Failed**
- Ensure using raw request body
- Verify secret matches configuration
- Check timestamp is included
- Confirm algorithm matches

**Timeouts**
- Respond quickly (< 30s)
- Process asynchronously
- Increase endpoint resources
- Implement queue-based processing

## Related Articles

- [DevOps Overview](/kb/devops-overview)
- [Configuring Git Providers](/kb/configuring-git-providers)
- [Creating CI/CD Pipelines](/kb/creating-cicd-pipelines)

---

Need help with webhook configuration? Contact support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "webhook-integration-management") do |article|
  article.title = "Webhook and Integration Management"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure webhooks to receive real-time events from Powernode and integrate with external services like Slack, PagerDuty, and custom applications."
  article.content = webhook_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Webhook and Integration Management"

# Article 28: Managing Pipeline Runners
runners_content = <<~MARKDOWN
# Managing Pipeline Runners

Configure and manage self-hosted runners for CI/CD pipeline execution with full control over your build environment.

## What Are Runners?

### Runner Overview

Runners are agents that execute CI/CD pipeline jobs:

- **Hosted Runners** - Managed by Powernode, ready to use
- **Self-Hosted Runners** - Your infrastructure, your control

### Why Self-Hosted?

| Benefit | Description |
|---------|-------------|
| **Security** | Keep builds in your network |
| **Compliance** | Meet data residency requirements |
| **Performance** | Dedicated resources |
| **Customization** | Custom software and tools |
| **Cost** | Reduce usage-based costs |

## Accessing Runners

Navigate to **DevOps > Runners** to:
- View registered runners
- Add new runners
- Monitor runner status
- Configure runner settings

## Runner Dashboard

```
┌─────────────────────────────────────────────────────┐
│  Pipeline Runners                    [Add Runner]   │
├─────────────────────────────────────────────────────┤
│  Runner           │ Status │ Jobs │ Labels         │
├───────────────────┼────────┼──────┼────────────────┤
│  linux-build-01   │ ✅ Idle │  234 │ linux, docker  │
│  linux-build-02   │ 🔄 Busy │  189 │ linux, docker  │
│  macos-build-01   │ ✅ Idle │   45 │ macos, ios     │
│  windows-build    │ ⚠️ Offline │ 67 │ windows, .net │
│  gpu-runner-01    │ ✅ Idle │   12 │ linux, gpu     │
└───────────────────┴────────┴──────┴────────────────┘
```

## Setting Up Self-Hosted Runners

### Prerequisites

Before setting up a runner:

```yaml
System Requirements:
  OS: Linux, macOS, or Windows
  CPU: 2+ cores recommended
  RAM: 4GB minimum, 8GB recommended
  Storage: 20GB+ free space
  Network: Outbound HTTPS access

Software:
  - Docker (recommended)
  - Git
  - Required build tools
```

### Installation Steps

#### 1. Generate Registration Token

```bash
# Via Dashboard
1. Navigate to DevOps > Runners
2. Click "Add Runner"
3. Copy the registration token

# Via API
curl -X POST https://api.powernode.org/api/v1/devops/runners/token \\
  -H "Authorization: Bearer YOUR_API_KEY"
```

#### 2. Download Runner Agent

```bash
# Linux/macOS
curl -L https://powernode.org/runner/download/linux-amd64 -o powernode-runner
chmod +x powernode-runner

# Windows (PowerShell)
Invoke-WebRequest -Uri https://powernode.org/runner/download/windows-amd64 \\
  -OutFile powernode-runner.exe
```

#### 3. Register Runner

```bash
./powernode-runner register \\
  --url https://api.powernode.org \\
  --token YOUR_REGISTRATION_TOKEN \\
  --name "linux-build-01" \\
  --labels "linux,docker,nodejs" \\
  --executor docker
```

#### 4. Start Runner

```bash
# Interactive mode
./powernode-runner run

# As a service (Linux)
sudo ./powernode-runner service install
sudo ./powernode-runner service start
```

### Docker Installation

Run runner as Docker container:

```bash
docker run -d \\
  --name powernode-runner \\
  --restart unless-stopped \\
  -v /var/run/docker.sock:/var/run/docker.sock \\
  -e POWERNODE_URL=https://api.powernode.org \\
  -e POWERNODE_TOKEN=YOUR_TOKEN \\
  -e RUNNER_NAME=docker-runner-01 \\
  -e RUNNER_LABELS=docker,linux \\
  powernode/runner:latest
```

### Kubernetes Installation

Deploy runners in Kubernetes:

```yaml
# runner-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: powernode-runner
spec:
  replicas: 3
  selector:
    matchLabels:
      app: powernode-runner
  template:
    metadata:
      labels:
        app: powernode-runner
    spec:
      containers:
        - name: runner
          image: powernode/runner:latest
          env:
            - name: POWERNODE_URL
              value: "https://api.powernode.org"
            - name: POWERNODE_TOKEN
              valueFrom:
                secretKeyRef:
                  name: runner-secrets
                  key: token
            - name: RUNNER_LABELS
              value: "kubernetes,docker"
```

## Runner Configuration

### Configuration File

```yaml
# config.yaml
runner:
  name: linux-build-01
  url: https://api.powernode.org
  token: ${RUNNER_TOKEN}

  labels:
    - linux
    - docker
    - nodejs

  executor: docker
  docker:
    image: node:20
    privileged: false
    volumes:
      - /cache:/cache

  concurrency: 4
  check_interval: 5s

  cache:
    path: /cache
    max_size: 10GB
```

### Executor Types

| Executor | Description | Use Case |
|----------|-------------|----------|
| **docker** | Run jobs in containers | Most workloads |
| **shell** | Run directly on host | Custom environments |
| **kubernetes** | Run in K8s pods | Scalable builds |
| **virtualbox** | Run in VMs | Isolation needs |

### Docker Executor Options

```yaml
docker:
  image: ubuntu:22.04
  privileged: false
  cap_add:
    - NET_ADMIN
  volumes:
    - /cache:/cache:rw
    - /certs:/certs:ro
  network_mode: bridge
  dns:
    - 8.8.8.8
  extra_hosts:
    - "internal.server:10.0.0.1"
  memory: 4g
  cpus: 2
```

## Runner Labels

### Using Labels

Labels help route jobs to specific runners:

```yaml
# Pipeline configuration
jobs:
  build:
    runner:
      labels: [linux, docker, nodejs]
    steps:
      - run: npm build

  ios-build:
    runner:
      labels: [macos, ios, xcode]
    steps:
      - run: xcodebuild
```

### Common Labels

| Label | Purpose |
|-------|---------|
| `linux`, `macos`, `windows` | Operating system |
| `docker` | Docker available |
| `gpu`, `cuda` | GPU computing |
| `nodejs`, `python`, `java` | Language runtime |
| `high-mem`, `high-cpu` | Resource specs |

## Monitoring Runners

### Status Monitoring

```yaml
Runner Status:
  Name: linux-build-01
  Status: Online
  Last Seen: 2 seconds ago

  Current Job: pipeline-123 / build
  Queue: 0 jobs waiting

  System:
    CPU: 45%
    Memory: 6.2GB / 16GB
    Disk: 45GB / 100GB

  Statistics (24h):
    Jobs Completed: 156
    Jobs Failed: 3
    Avg Duration: 4m 32s
```

### Health Checks

```yaml
Health Check Configuration:
  interval: 30s
  timeout: 10s
  unhealthy_threshold: 3

  Checks:
    - type: disk_space
      min_percent: 10

    - type: docker
      enabled: true

    - type: connectivity
      url: https://api.powernode.org
```

### Alerts

Configure runner alerts:

```yaml
Alert Rules:
  - name: Runner Offline
    condition: status == offline
    duration: 5m
    notify: ops-team

  - name: High Queue
    condition: queue_length > 10
    duration: 15m
    notify: devops-team

  - name: Disk Space Low
    condition: disk_free < 20%
    notify: ops-team
```

## Security

### Runner Security

```yaml
Security Configuration:
  Token Rotation:
    Interval: 30 days
    Auto-rotate: true

  Network:
    Allowed IPs: [internal only]
    TLS: required
    Verify Certs: true

  Execution:
    Privileged Mode: disabled
    Root User: disabled
    Secrets Masking: enabled
```

### Secret Management

```yaml
Secrets Available to Runners:
  Environment Variables:
    - Injected at job start
    - Masked in logs

  Files:
    - Mounted as volumes
    - Cleaned after job

  Best Practices:
    - Never log secrets
    - Use short-lived tokens
    - Rotate regularly
```

## Troubleshooting

### Common Issues

**Runner Not Connecting**
```yaml
Checklist:
  - Verify token is valid
  - Check network connectivity
  - Confirm firewall rules
  - Review runner logs
```

**Jobs Stuck in Queue**
```yaml
Checklist:
  - Check runner status
  - Verify label matching
  - Review runner capacity
  - Check for resource constraints
```

**Build Failures**
```yaml
Checklist:
  - Review job logs
  - Check Docker image availability
  - Verify environment setup
  - Test commands locally
```

### Runner Logs

```bash
# View runner logs
./powernode-runner --log-level debug run

# Docker logs
docker logs -f powernode-runner

# Service logs (Linux)
journalctl -u powernode-runner -f
```

## Best Practices

### Setup

1. **Right-Size Resources**
   - Match to workload needs
   - Plan for peak usage
   - Monitor and adjust

2. **Use Labels Effectively**
   - Meaningful categorization
   - Avoid over-labeling
   - Document label meanings

3. **Implement Redundancy**
   - Multiple runners per label
   - Geographic distribution
   - Auto-scaling where possible

### Operations

1. **Regular Maintenance**
   - Update runner software
   - Clean up disk space
   - Rotate tokens

2. **Monitoring**
   - Track performance metrics
   - Set up alerts
   - Review logs regularly

## Related Articles

- [DevOps Overview](/kb/devops-overview)
- [Creating CI/CD Pipelines](/kb/creating-cicd-pipelines)
- [API Key Management](/kb/api-key-management)

---

Need help with runners? Contact devops-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "managing-pipeline-runners") do |article|
  article.title = "Managing Pipeline Runners"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Configure self-hosted runners for CI/CD pipeline execution with Docker, Kubernetes, labels, monitoring, and security best practices."
  article.content = runners_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ Managing Pipeline Runners"

# Article 29: API Key Management
api_keys_content = <<~MARKDOWN
# API Key Management

Create, manage, and secure API keys for programmatic access to Powernode's features and integrations.

## API Keys Overview

### What Are API Keys?

API keys provide:
- **Authentication** for API requests
- **Authorization** scoped to specific permissions
- **Tracking** of API usage
- **Security** controls for access

### Accessing API Keys

Navigate to **DevOps > API Keys** to:
- View existing keys
- Create new keys
- Manage permissions
- Monitor usage

## API Keys Dashboard

```
┌─────────────────────────────────────────────────────┐
│  API Keys                            [Create Key]   │
├─────────────────────────────────────────────────────┤
│  Name           │ Permissions │ Last Used │ Status  │
├─────────────────┼─────────────┼───────────┼─────────┤
│  CI/CD Key      │ 5 scopes    │ 2 min ago │ Active  │
│  Integration    │ 3 scopes    │ 1 hour    │ Active  │
│  Read Only      │ 2 scopes    │ 3 days    │ Active  │
│  Legacy Key     │ Full Access │ 30 days   │ ⚠️ Review│
└─────────────────┴─────────────┴───────────┴─────────┘
```

## Creating API Keys

### Via Dashboard

1. Navigate to **DevOps > API Keys**
2. Click **Create Key**
3. Configure key settings:

```yaml
Key Configuration:
  Name: CI/CD Pipeline Key
  Description: Key for GitHub Actions integration

  Permissions:
    ✅ pipelines.trigger
    ✅ pipelines.read
    ✅ deployments.create
    ✅ artifacts.read
    ⬜ admin.settings

  Restrictions:
    IP Allowlist:
      - 192.30.252.0/22  # GitHub Actions
      - 185.199.108.0/22
    Expires: 90 days
    Rate Limit: 1000/hour

  Environment: Production
```

4. Click **Create**
5. **Copy the key immediately** (shown only once)

### Via API

```bash
curl -X POST https://api.powernode.org/api/v1/api-keys \\
  -H "Authorization: Bearer YOUR_ADMIN_KEY" \\
  -H "Content-Type: application/json" \\
  -d '{
    "name": "CI/CD Pipeline Key",
    "description": "Key for GitHub Actions",
    "permissions": [
      "pipelines.trigger",
      "pipelines.read",
      "deployments.create"
    ],
    "expires_in_days": 90,
    "ip_allowlist": ["192.30.252.0/22"]
  }'
```

## Key Permissions

### Permission Scopes

| Scope | Description | Use Case |
|-------|-------------|----------|
| `api.read` | Read API resources | Read-only integrations |
| `api.write` | Write API resources | Full integrations |
| `pipelines.*` | Pipeline operations | CI/CD systems |
| `deployments.*` | Deployment operations | Release automation |
| `webhooks.*` | Webhook management | Event subscriptions |
| `ai.*` | AI operations | AI integrations |
| `admin.*` | Administrative access | Management tools |

### Scope Hierarchy

```yaml
Scope Hierarchy:
  api.read:
    - Read all non-admin resources

  api.write:
    - Includes api.read
    - Create/update resources

  pipelines.trigger:
    - Start pipeline runs

  pipelines.read:
    - View pipeline status
    - Download artifacts

  admin.settings:
    - Modify system settings
    - Manage other keys
```

### Minimum Permissions

Follow least-privilege principle:

```yaml
# Good: Specific permissions
permissions:
  - pipelines.trigger
  - pipelines.read

# Avoid: Broad permissions
permissions:
  - api.write  # Too broad
  - admin.*    # Too powerful
```

## Key Security

### Best Practices

1. **Use Meaningful Names**
   ```yaml
   Good: "GitHub Actions - Production Deploy"
   Bad: "API Key 1"
   ```

2. **Set Expiration**
   ```yaml
   Recommended Expiration:
     Development: 30 days
     CI/CD: 90 days
     Production: 180 days
     Maximum: 365 days
   ```

3. **Restrict IP Addresses**
   ```yaml
   IP Allowlist:
     # GitHub Actions
     - 192.30.252.0/22
     - 185.199.108.0/22
     # Your CI servers
     - 10.0.0.0/8
   ```

4. **Minimum Permissions**
   - Only grant needed scopes
   - Review periodically
   - Remove unused permissions

### Storing Keys Securely

```yaml
DO:
  - Use secret management (Vault, AWS Secrets)
  - Store in CI/CD secrets
  - Encrypt at rest
  - Rotate regularly

DON'T:
  - Commit to version control
  - Share via email/chat
  - Log in applications
  - Embed in client code
```

### Environment Variables

```bash
# Set as environment variable
export POWERNODE_API_KEY="pk_live_abc123..."

# Use in applications
api_key = os.environ.get('POWERNODE_API_KEY')
```

## Using API Keys

### Request Authentication

```bash
# Header authentication (recommended)
curl -X GET https://api.powernode.org/api/v1/pipelines \\
  -H "Authorization: Bearer pk_live_abc123..."

# Query parameter (use only when necessary)
curl "https://api.powernode.org/api/v1/pipelines?api_key=pk_live_abc123..."
```

### SDK Usage

```javascript
// JavaScript SDK
const powernode = require('@powernode/sdk');

const client = new powernode.Client({
  apiKey: process.env.POWERNODE_API_KEY
});

const pipelines = await client.pipelines.list();
```

```python
# Python SDK
import powernode

client = powernode.Client(api_key=os.environ['POWERNODE_API_KEY'])
pipelines = client.pipelines.list()
```

## Key Rotation

### Why Rotate?

- Limit exposure from compromised keys
- Meet compliance requirements
- Maintain security hygiene

### Rotation Process

1. **Create New Key**
   - Same permissions as old key
   - Add descriptive name with date

2. **Update Applications**
   - Deploy with new key
   - Verify functionality

3. **Monitor Old Key**
   - Watch for any remaining usage
   - Identify missed updates

4. **Revoke Old Key**
   - Disable after transition
   - Delete after confirmation

### Automated Rotation

```yaml
Rotation Policy:
  Interval: 90 days
  Warning: 14 days before expiry
  Grace Period: 7 days
  Auto-create: true

Notifications:
  - Email key owner
  - Slack #security
  - Create ticket
```

## Monitoring Usage

### Usage Dashboard

```yaml
Key Usage: CI/CD Pipeline Key

Last 24 Hours:
  Requests: 1,234
  Success Rate: 99.8%
  Avg Latency: 145ms

By Endpoint:
  /pipelines/trigger: 450
  /pipelines/status: 680
  /artifacts/download: 104

By IP:
  192.30.252.45: 800
  192.30.252.46: 434

Rate Limit:
  Current: 450/hour
  Limit: 1000/hour
```

### Usage Alerts

```yaml
Alert Rules:
  - name: High Usage
    condition: requests > 800/hour
    notify: devops-team

  - name: Failed Requests
    condition: error_rate > 5%
    notify: security-team

  - name: New IP Detected
    condition: ip NOT IN allowlist
    notify: security-team
```

## Troubleshooting

### Common Errors

**401 Unauthorized**
```yaml
Causes:
  - Invalid or expired key
  - Key revoked
  - Wrong key for environment

Solution:
  - Verify key is correct
  - Check key status in dashboard
  - Ensure using right environment
```

**403 Forbidden**
```yaml
Causes:
  - Insufficient permissions
  - IP not in allowlist
  - Resource access denied

Solution:
  - Review key permissions
  - Check IP restrictions
  - Verify resource ownership
```

**429 Rate Limited**
```yaml
Causes:
  - Exceeded rate limit

Solution:
  - Implement backoff
  - Request limit increase
  - Optimize request patterns
```

### Debug Mode

```bash
# Enable debug headers
curl -X GET https://api.powernode.org/api/v1/pipelines \\
  -H "Authorization: Bearer pk_live_abc123..." \\
  -H "X-Debug: true" \\
  -v

# Response headers include:
# X-RateLimit-Remaining: 950
# X-RateLimit-Reset: 1642345678
# X-Request-Id: req_abc123
```

## Administrative Actions

### Revoking Keys

```yaml
Revoke Scenarios:
  - Employee departure
  - Suspected compromise
  - Project completion
  - Key rotation

Process:
  1. Navigate to API Keys
  2. Select key to revoke
  3. Click "Revoke"
  4. Confirm action
  5. Monitor for failed requests
```

### Bulk Management

```bash
# List all keys via API
curl -X GET https://api.powernode.org/api/v1/api-keys \\
  -H "Authorization: Bearer ADMIN_KEY"

# Revoke expired keys
curl -X POST https://api.powernode.org/api/v1/api-keys/revoke-expired \\
  -H "Authorization: Bearer ADMIN_KEY"
```

## Related Articles

- [DevOps Overview](/kb/devops-overview)
- [Managing Pipeline Runners](/kb/managing-pipeline-runners)
- [API & Integrations Overview](/kb/api-overview)

---

Need help with API keys? Contact devops-support@powernode.org
MARKDOWN

KnowledgeBase::Article.find_or_create_by!(slug: "api-key-management") do |article|
  article.title = "API Key Management"
  article.category = devops_cat
  article.author = author
  article.status = "published"
  article.is_public = true
  article.is_featured = false
  article.excerpt = "Create, manage, and secure API keys with scoped permissions, IP restrictions, rotation policies, and usage monitoring."
  article.content = api_keys_content
  article.views_count = 0
  article.likes_count = 0
  article.published_at = Time.current
end

puts "    ✅ API Key Management"

puts "  ✅ DevOps articles created (6 articles)"
