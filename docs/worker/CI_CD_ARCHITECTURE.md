# CI/CD Pipeline Architecture

## Overview

The Powernode CI/CD system is designed with an **API-driven architecture** that separates concerns between:

- **Git Provider Actions/Runners** (Gitea Actions, GitLab CI, GitHub Actions) - Handle code checkout, build operations, and test execution
- **Worker Service** - Orchestrates pipelines and interacts with git providers via their APIs
- **Backend API** - Stores pipeline definitions, runs, and artifacts

This architecture supports **multiple git providers** (Gitea, GitLab, GitHub) through a unified abstraction layer.

---

## Architecture Principles

### 1. API-Driven Operations

The worker service does **NOT**:
- Execute Docker operations directly
- SSH into servers to run commands
- Perform direct file system operations on remote hosts

The worker service **DOES**:
- Trigger workflows via git provider APIs
- Update commit statuses via provider APIs
- Create pull requests and comments via provider APIs
- Call deployment webhooks and APIs
- Orchestrate pipeline steps through API calls

### 2. Provider Agnostic

All git operations go through the `GitOperationsService` which abstracts provider-specific differences:

```ruby
# Same interface regardless of provider
git_ops = CiCd::GitOperationsService.new(provider_config: config)

# Works with Gitea, GitLab, or GitHub
git_ops.update_status(repo: "org/repo", sha: "abc123", state: "success", ...)
git_ops.create_pull_request(repo: "org/repo", title: "Feature", head: "feature", base: "main")
git_ops.post_comment(repo: "org/repo", number: 42, body: "Build passed!")
```

### 3. Webhook-Based Triggers

Pipelines are triggered by webhooks from git providers, normalized through `WebhookNormalizer`:

```ruby
normalizer = CiCd::GitProviders::WebhookNormalizer.new
payload = normalizer.normalize(raw_payload, headers)

# Returns standardized payload regardless of provider:
# {
#   provider: :gitea,
#   event_type: :push,
#   repository: "org/repo",
#   ref: "refs/heads/main",
#   ...
# }
```

---

## Component Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Git Provider (Gitea/GitLab/GitHub)           │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │
│  │   Webhooks  │  │   Actions   │  │     API     │                  │
│  └──────┬──────┘  └──────┬──────┘  └──────▲──────┘                  │
└─────────┼────────────────┼────────────────┼─────────────────────────┘
          │                │                │
          │ HTTP POST      │ Dispatch       │ API Calls
          ▼                │                │
┌─────────────────────┐    │                │
│   Backend Server    │    │                │
│  ┌───────────────┐  │    │                │
│  │ Webhook       │  │    │                │
│  │ Controller    │──┼────┼────────────────┤
│  └───────┬───────┘  │    │                │
│          │          │    │                │
│  ┌───────▼───────┐  │    │                │
│  │ Pipeline      │  │    │                │
│  │ Service       │  │    │                │
│  └───────┬───────┘  │    │                │
└──────────┼──────────┘    │                │
           │               │                │
           │ Enqueue Job   │                │
           ▼               │                │
┌──────────────────────────┼────────────────┼─────────────────────────┐
│   Worker Service         │                │                         │
│  ┌───────────────────┐   │                │                         │
│  │ PipelineRunJob    │   │                │                         │
│  └─────────┬─────────┘   │                │                         │
│            │             │                │                         │
│  ┌─────────▼─────────┐   │                │                         │
│  │ Step Handlers     │───┼────────────────┘                         │
│  │ ┌───────────────┐ │   │                                          │
│  │ │ Checkout      │ │   │  • Fetches repo data via provider API    │
│  │ ├───────────────┤ │   │  • Clones with token authentication      │
│  │ │ Claude        │ │   │                                          │
│  │ │ Execute       │ │   │  • Runs Claude CLI locally               │
│  │ ├───────────────┤ │   │  • Uses prompt templates                 │
│  │ │ Deploy        │─┼───┼──• Triggers workflows via API            │
│  │ │               │ │   │  • Calls webhooks for deployment         │
│  │ ├───────────────┤ │   │                                          │
│  │ │ Create PR     │─┼───┼──• Creates PR via provider API           │
│  │ ├───────────────┤ │   │                                          │
│  │ │ Post Comment  │─┼───┘  • Posts comments via provider API       │
│  │ └───────────────┘ │                                              │
│  └───────────────────┘                                              │
│                                                                     │
│  ┌───────────────────────────────────────────────────────────────┐  │
│  │ Git Provider Abstraction Layer                                │  │
│  │ ┌─────────────┐ ┌─────────────┐ ┌─────────────┐               │  │
│  │ │   Gitea     │ │   GitLab    │ │   GitHub    │               │  │
│  │ │  Provider   │ │  Provider   │ │  Provider   │               │  │
│  │ └─────────────┘ └─────────────┘ └─────────────┘               │  │
│  └───────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Git Provider Abstraction

### Directory Structure

```
worker/app/services/ci_cd/
├── git_providers/
│   ├── base_provider.rb       # Abstract base class
│   ├── gitea_provider.rb      # Gitea API implementation
│   ├── gitlab_provider.rb     # GitLab API implementation
│   ├── github_provider.rb     # GitHub API implementation
│   ├── provider_factory.rb    # Factory for creating providers
│   └── webhook_normalizer.rb  # Webhook payload normalization
├── git_operations_service.rb  # High-level git operations
├── deployment_service.rb      # Deployment orchestration
└── step_handlers/
    ├── base.rb                # Base handler class
    ├── checkout_handler.rb    # Repository checkout
    ├── claude_execute_handler.rb  # AI code generation
    ├── create_pr_handler.rb   # Pull request creation
    ├── deploy_handler.rb      # Deployment execution
    ├── post_comment_handler.rb    # Comment posting
    ├── run_command_handler.rb     # Shell command execution
    └── upload_artifact_handler.rb # Artifact management
```

### Provider Configuration

```ruby
provider_config = {
  type: :gitea,           # :gitea, :gitlab, or :github
  api_url: "https://git.example.com/api/v1",
  api_token: "token_xxx"
}

# Create provider via factory
provider = CiCd::GitProviders::ProviderFactory.create(
  type: :gitea,
  api_url: "https://git.example.com/api/v1",
  api_token: "token_xxx"
)

# Or from a GitProvider record
provider = CiCd::GitProviders::ProviderFactory.from_record(git_provider)
```

### Common Operations

```ruby
git_ops = CiCd::GitOperationsService.new(provider_config: config)

# Update commit status
git_ops.update_status(
  repo: "org/repo",
  sha: "abc123def456",
  state: "success",
  context: "ci/powernode",
  description: "All checks passed",
  target_url: "https://powernode.example.com/runs/123"
)

# Create pull request
git_ops.create_pull_request(
  repo: "org/repo",
  title: "feat: Add new feature",
  head: "feature/new-feature",
  base: "main",
  body: "## Summary\n\nThis PR adds..."
)

# Post or update comment
git_ops.upsert_comment(
  repo: "org/repo",
  number: 42,
  body: "Build status: ✅ Passed",
  marker: "powernode-ci-status"  # Used to find/update existing comment
)

# Trigger workflow (Gitea Actions, GitHub Actions, GitLab CI)
git_ops.trigger_workflow(
  repo: "org/repo",
  workflow: "deploy.yml",
  ref: "main",
  inputs: { environment: "production" }
)
```

---

## Deployment Strategies

The `DeploymentService` supports multiple deployment strategies:

### 1. Workflow Trigger (Default)

Triggers a git provider workflow/action for deployment:

```yaml
# Pipeline step configuration
- type: deploy
  config:
    strategy: workflow
    workflow: deploy.yml
    environment: production
    inputs:
      target: "production-cluster"
```

### 2. Webhook

Calls an external deployment webhook:

```yaml
- type: deploy
  config:
    strategy: webhook
    webhook_url: https://deploy.example.com/trigger
    webhook_secret: ${DEPLOY_SECRET}
    environment: staging
```

### 3. API

Calls a deployment API endpoint:

```yaml
- type: deploy
  config:
    strategy: api
    api_url: https://api.example.com/deployments
    api_token: ${DEPLOY_TOKEN}
    environment: production
```

### 4. Command (Legacy)

Executes a local deployment command (legacy fallback):

```yaml
- type: deploy
  config:
    strategy: command
    command: ./scripts/deploy.sh production
    timeout_minutes: 15
```

---

## Webhook Handling

### Supported Events

| Provider | Push | Pull Request | Issue | Comment |
|----------|------|--------------|-------|---------|
| Gitea    | ✅   | ✅           | ✅    | ✅      |
| GitLab   | ✅   | ✅ (MR)      | ✅    | ✅      |
| GitHub   | ✅   | ✅           | ✅    | ✅      |

### Webhook Signature Verification

```ruby
normalizer = CiCd::GitProviders::WebhookNormalizer.new

# Verify signature (provider-specific)
is_valid = normalizer.verify_signature(
  payload: raw_body,
  signature: request.headers["X-Gitea-Signature"],
  secret: webhook_secret,
  provider: :gitea
)
```

### Signature Header Mapping

| Provider | Signature Header |
|----------|------------------|
| Gitea    | `X-Gitea-Signature` |
| GitLab   | `X-Gitlab-Token` |
| GitHub   | `X-Hub-Signature-256` |

---

## Step Handlers

### Checkout Handler

Clones repository with provider-aware authentication:

```yaml
- type: checkout
  config:
    ref: ${head_sha}
    fetch_depth: 1  # Shallow clone
```

**Features:**
- Automatically detects provider from pipeline context
- Uses provider API to fetch repository metadata
- Authenticates clone URLs with provider tokens
- Supports shallow cloning for faster checkouts

### Claude Execute Handler

Runs Claude CLI for AI-powered operations:

```yaml
- type: claude_execute
  config:
    prompt: "Review this PR and suggest improvements"
    prompt_template_id: "pr-review-template"
    model: "claude-3-sonnet"
    timeout_minutes: 10
```

**Features:**
- Template-based prompts with variable interpolation
- Access to trigger context (PR body, issue content, diffs)
- JSON output parsing for structured responses
- Session management for context continuity

### Create PR Handler

Creates pull requests via provider API:

```yaml
- type: create_pr
  config:
    title: "feat: {{ issue_title }}"
    body_from: claude_execute.raw_output
    base: develop
    branch_prefix: claude
```

**Features:**
- Provider-agnostic PR creation
- Automatic branch naming based on trigger
- Checks for existing PRs to avoid duplicates
- Template interpolation for title/body

### Deploy Handler

Orchestrates deployments through multiple strategies:

```yaml
- type: deploy
  config:
    environment: staging
    strategy: workflow
    workflow: deploy.yml
    health_check_url: https://staging.example.com/health
    health_check_retries: 3
```

**Features:**
- Multiple deployment strategies (workflow, webhook, API, command)
- Health check verification after deployment
- Smoke test execution
- Automatic commit status updates

### Post Comment Handler

Posts comments to issues/PRs:

```yaml
- type: post_comment
  config:
    body_from: claude_execute.raw_output
    header: "## 🤖 AI Analysis"
    footer: "---\n*Powered by Claude*"
```

**Features:**
- Provider-agnostic commenting
- Support for update-in-place (upsert) comments
- Template variable interpolation
- Header/footer customization

---

## Pipeline Definition Example

```yaml
name: AI Code Review
description: Automated code review with Claude

triggers:
  - type: pull_request
    events: [opened, synchronize]

steps:
  - name: checkout
    type: checkout
    config:
      fetch_depth: 50

  - name: get_diff
    type: run_command
    config:
      command: git diff origin/${base_branch}...HEAD

  - name: review
    type: claude_execute
    config:
      prompt_template_id: pr-review
      model: claude-3-sonnet

  - name: post_review
    type: post_comment
    config:
      body_from: review.raw_output
      marker: claude-review

  - name: update_status
    type: update_status
    config:
      state: success
      context: ai-review
      description: AI review completed
```

---

## Provider-Specific Notes

### Gitea

- API prefix: `/api/v1`
- Supports Gitea Actions (similar to GitHub Actions)
- Uses `Bearer` token authentication
- Workflow dispatch: `POST /repos/{owner}/{repo}/actions/workflows/{workflow}/dispatches`

### GitLab

- API prefix: `/api/v4`
- Uses URL-encoded project paths (`owner%2Frepo`)
- Uses `PRIVATE-TOKEN` header for authentication
- Merge Requests (not Pull Requests)
- Uses `iid` (internal ID) for MR operations
- Workflow dispatch: Trigger tokens or pipeline API

### GitHub

- API prefix: (none, uses `api.github.com` directly)
- Uses `Bearer` token with `X-GitHub-Api-Version` header
- Supports GitHub Actions and Check Runs API
- Workflow dispatch: `POST /repos/{owner}/{repo}/actions/workflows/{workflow}/dispatches`

---

## Error Handling

All provider operations may throw these errors:

```ruby
module CiCd::GitProviders
  class ApiError < StandardError; end
  class AuthenticationError < ApiError; end  # 401
  class ForbiddenError < ApiError; end       # 403
  class NotFoundError < ApiError; end        # 404
  class ValidationError < ApiError; end      # 422
  class RateLimitError < ApiError; end       # 429
end
```

Step handlers should catch and handle these appropriately:

```ruby
begin
  git_ops.create_pull_request(...)
rescue CiCd::GitProviders::ValidationError => e
  # PR might already exist, try to find it
  existing = git_ops.find_pull_request(...)
rescue CiCd::GitProviders::RateLimitError => e
  # Implement backoff/retry
end
```

---

## Testing

### Provider Mock

For testing, use the provider factory with mock credentials:

```ruby
# In tests
provider = CiCd::GitProviders::ProviderFactory.create(
  type: :gitea,
  api_url: "http://localhost:3000",
  api_token: "test_token"
)

# Stub HTTP requests with WebMock or VCR
stub_request(:post, "http://localhost:3000/api/v1/repos/org/repo/statuses/abc123")
  .to_return(status: 200, body: { status: "created" }.to_json)
```

### Integration Testing

Test pipeline execution with real providers in a test environment:

```ruby
RSpec.describe CiCd::GitOperationsService do
  let(:service) { described_class.new(provider_config: test_provider_config) }

  it "creates commit status" do
    result = service.update_status(
      repo: "test/repo",
      sha: "abc123",
      state: "pending",
      context: "test",
      description: "Running tests"
    )

    expect(result[:state]).to eq("pending")
  end
end
```
