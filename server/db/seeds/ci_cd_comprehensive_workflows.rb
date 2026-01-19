# frozen_string_literal: true

# CI/CD Comprehensive Workflow Seeds
# Creates example pipelines demonstrating ALL CI/CD capabilities including:
# - All 11 step types (checkout, claude_execute, post_comment, create_pr, create_branch,
#   upload_artifact, download_artifact, run_tests, deploy, notify, custom)
# - All trigger types (manual, push, PR, schedule, webhook, issue_comment)
# - Step output chaining, conditional execution, approval gates
# - Multi-stage deployments with health checks
# - Artifact workflows (upload/download)
# - AI-powered automation with prompt templates

puts "=" * 60
puts "Seeding Comprehensive CI/CD Workflows..."
puts "=" * 60

# ============================================
# Setup: Get or create required records
# ============================================

# Find the best account to seed pipelines into
# Priority: Demo Company > Powernode Admin > First account
system_account = Account.find_by(name: "Demo Company") ||
                 Account.find_by(name: "Powernode Admin") ||
                 Account.first ||
                 Account.create!(name: "System", subdomain: "system")

admin_user = system_account.users.first ||
             User.create!(
               account: system_account,
               email: "admin@powernode.local",
               first_name: "Admin",
               last_name: "User",
               password: "password123",
               password_confirmation: "password123"
             )

# Get or create AI Provider for Claude
ai_provider = Ai::Provider.find_by(account: system_account, provider_type: "anthropic") ||
              Ai::Provider.create!(
                account: system_account,
                name: "Claude (Anthropic)",
                provider_type: "anthropic",
                model_id: "claude-sonnet-4-20250514",
                is_active: true,
                is_default: true,
                configuration: {
                  max_tokens: 8192,
                  temperature: 0.7
                }
              )

puts "  Using account: #{system_account.name}"
puts "  Using AI provider: #{ai_provider.name}"

# ============================================
# Create Git Provider
# ============================================

puts "\n  Creating Git Provider..."

git_provider = CiCd::Provider.find_or_create_by!(
  account: system_account,
  name: "GitHub Enterprise"
) do |p|
  p.provider_type = "github"
  p.base_url = "https://github.com"
  p.api_version = "v3"
  p.is_active = true
  p.is_default = true
  p.health_status = "healthy"
  p.capabilities = %w[repositories pull_requests issues webhooks runners actions]
  p.created_by = admin_user
end

puts "    ✓ Git Provider: #{git_provider.name}"

# ============================================
# Create Repository
# ============================================

puts "\n  Creating Repository..."

repository = CiCd::Repository.find_or_create_by!(
  account: system_account,
  full_name: "powernode/example-app"
) do |r|
  r.provider = git_provider
  r.name = "example-app"
  r.external_id = "repo-12345"
  r.default_branch = "main"
  r.is_active = true
  r.settings = {
    "clone_url" => "https://github.com/powernode/example-app.git",
    "ssh_clone_url" => "git@github.com:powernode/example-app.git",
    "web_url" => "https://github.com/powernode/example-app",
    "is_private" => false,
    "language" => "TypeScript",
    "topics" => %w[react typescript powernode],
    "stars" => 42,
    "forks" => 8
  }
end

puts "    ✓ Repository: #{repository.full_name}"

# ============================================
# Create Prompt Templates
# ============================================

puts "\n  Creating Prompt Templates..."

prompt_templates = {}

# 1. Comprehensive PR Review Template
prompt_templates[:pr_review] = Shared::PromptTemplate.find_or_create_by!(
  account: system_account,
  slug: "pr-review-comprehensive"
) do |t|
  t.name = "Comprehensive PR Review"
  t.description = "Full AI-powered PR review with security, quality, and performance analysis"
  t.category = "review"
  t.domain = "cicd"
  t.content = <<~'PROMPT'
    You are an expert code reviewer. Analyze this pull request thoroughly.

    ## Pull Request Details
    - **Title**: {{ pr_title }}
    - **Author**: {{ pr_author }}
    - **Branch**: {{ source_branch }} → {{ target_branch }}
    - **Files Changed**: {{ files_changed }}

    ## Diff Content
    ```diff
    {{ diff }}
    ```

    Provide a comprehensive review covering:
    1. Code Quality (Score: 0-100)
    2. Security Analysis (CRITICAL/HIGH/MEDIUM/LOW/NONE)
    3. Performance Impact
    4. Test Coverage

    Output as JSON:
    ```json
    {
      "quality_score": 85,
      "security_level": "LOW",
      "approval_status": "APPROVE",
      "risk_level": "LOW",
      "summary": "...",
      "issues": [...],
      "suggestions": [...]
    }
    ```
  PROMPT
  t.variables = [
    { "name" => "pr_title", "type" => "string", "required" => true },
    { "name" => "pr_author", "type" => "string", "required" => true },
    { "name" => "source_branch", "type" => "string", "required" => true },
    { "name" => "target_branch", "type" => "string", "required" => true, "default" => "main" },
    { "name" => "files_changed", "type" => "number", "required" => false },
    { "name" => "diff", "type" => "text", "required" => true }
  ]
  t.is_active = true
  t.created_by = admin_user
end

# 2. Security Scan Template
prompt_templates[:security_scan] = Shared::PromptTemplate.find_or_create_by!(
  account: system_account,
  slug: "security-scan-deep"
) do |t|
  t.name = "Deep Security Analysis"
  t.description = "AI-powered security vulnerability scanning with CVSS scoring"
  t.category = "security"
  t.domain = "cicd"
  t.content = <<~'PROMPT'
    Perform a comprehensive security analysis of the codebase.

    ## Analysis Areas
    1. **Input Validation** - SQL injection, XSS, command injection
    2. **Authentication/Authorization** - Session management, access control
    3. **Data Protection** - Encryption, sensitive data exposure
    4. **Dependencies** - Known vulnerabilities in packages
    5. **Configuration** - Security misconfigurations

    Output as JSON:
    ```json
    {
      "findings": [
        {
          "severity": "HIGH",
          "category": "SQL Injection",
          "file": "src/api/users.ts",
          "line": 42,
          "description": "...",
          "recommendation": "..."
        }
      ],
      "severity_summary": {
        "critical": 0,
        "high": 1,
        "medium": 3,
        "low": 5
      },
      "overall_risk": "MEDIUM"
    }
    ```
  PROMPT
  t.variables = []
  t.is_active = true
  t.created_by = admin_user
end

# 3. Issue Implementation Template
prompt_templates[:issue_implementation] = Shared::PromptTemplate.find_or_create_by!(
  account: system_account,
  slug: "issue-to-implementation"
) do |t|
  t.name = "Issue to Implementation"
  t.description = "Automatically implement features or fix bugs from GitHub issues"
  t.category = "implement"
  t.domain = "cicd"
  t.content = <<~'PROMPT'
    You are implementing a solution for the following issue:

    ## Issue #{{ issue_number }}: {{ issue_title }}

    ### Description
    {{ issue_body }}

    ### Labels
    {{ labels }}

    ### Instructions
    1. Analyze the requirements
    2. Plan the implementation
    3. Write clean, maintainable code
    4. Add appropriate tests
    5. Update documentation if needed

    Provide a summary of changes made.
  PROMPT
  t.variables = [
    { "name" => "issue_number", "type" => "number", "required" => true },
    { "name" => "issue_title", "type" => "string", "required" => true },
    { "name" => "issue_body", "type" => "text", "required" => true },
    { "name" => "labels", "type" => "string", "required" => false, "default" => "enhancement" }
  ]
  t.is_active = true
  t.created_by = admin_user
end

# 4. Deployment Validation Template
prompt_templates[:deployment_validation] = Shared::PromptTemplate.find_or_create_by!(
  account: system_account,
  slug: "deployment-validation"
) do |t|
  t.name = "Post-Deployment Validation"
  t.description = "Validates deployment health and functionality"
  t.category = "deploy"
  t.domain = "cicd"
  t.content = <<~'PROMPT'
    Perform post-deployment validation for {{ environment }} environment.

    ## Deployment Details
    - **Application**: {{ app_name }}
    - **Version**: {{ version }}
    - **URL**: {{ deploy_url }}

    ## Validation Checklist
    - Health checks (HTTP 200)
    - Database connectivity
    - API endpoints responding
    - Performance baseline

    Output as JSON:
    ```json
    {
      "status": "HEALTHY",
      "checks": { "health": true, "db": true, "api": true },
      "metrics": { "response_time_ms": 150 },
      "issues": [],
      "recommendations": []
    }
    ```
  PROMPT
  t.variables = [
    { "name" => "app_name", "type" => "string", "required" => true },
    { "name" => "version", "type" => "string", "required" => true },
    { "name" => "environment", "type" => "string", "required" => true },
    { "name" => "deploy_url", "type" => "string", "required" => true }
  ]
  t.is_active = true
  t.created_by = admin_user
end

prompt_templates.each do |key, template|
  puts "    ✓ Prompt Template: #{template.name}"
end

# ============================================
# Pipeline 1: Full CI/CD with AI Review
# Demonstrates: checkout, claude_execute, run_tests, post_comment, notify, deploy
# ============================================

puts "\n  Creating Pipeline 1: Full CI/CD with AI Review..."

pipeline1 = CiCd::Pipeline.find_or_create_by!(
  account: system_account,
  slug: "full-cicd-ai-review"
) do |p|
  p.name = "Full CI/CD Pipeline with AI Review"
  p.description = "Comprehensive pipeline with AI code review, security scanning, human approval, and multi-stage deployment"
  p.pipeline_type = "deploy"
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.timeout_minutes = 60
  p.allow_concurrent = false
  p.runner_labels = ["ubuntu-latest"]
  p.environment = {
    "NODE_ENV" => "production",
    "CI" => "true"
  }
  p.triggers = {
    "pull_request" => ["opened", "synchronize", "reopened"],
    "push" => { "branches" => ["main", "release/*"] },
    "manual" => true,
    "workflow_dispatch" => true
  }
  p.features = {
    "auto_merge" => true,
    "slack_notifications" => true,
    "approval_required" => true
  }
  p.created_by = admin_user
end

pipeline1.steps.destroy_all

# Step 1: Checkout
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Checkout Repository",
  step_type: "checkout",
  position: 0,
  is_active: true,
  configuration: {
    "fetch_depth" => 0,
    "submodules" => true
  },
  inputs: {},
  outputs: [
    { "name" => "commit_sha", "type" => "string" },
    { "name" => "branch", "type" => "string" }
  ]
)

# Step 2: AI Code Review
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "AI Code Review",
  step_type: "claude_execute",
  position: 1,
  is_active: true,
  shared_prompt_template: prompt_templates[:pr_review],
  configuration: {
    "model" => "claude-sonnet-4-20250514",
    "timeout_seconds" => 300,
    "session_id" => "pr-review-{{ run_number }}",
    "parse_json" => true
  },
  inputs: {
    "pr_title" => "${{ trigger.pull_request.title }}",
    "pr_author" => "${{ trigger.pull_request.user.login }}",
    "source_branch" => "${{ trigger.pull_request.head.ref }}",
    "target_branch" => "${{ trigger.pull_request.base.ref }}",
    "diff" => "${{ trigger.pull_request.diff }}"
  },
  outputs: [
    { "name" => "quality_score", "type" => "number" },
    { "name" => "approval_status", "type" => "string" },
    { "name" => "risk_level", "type" => "string" },
    { "name" => "security_level", "type" => "string" }
  ],
  condition: "trigger.type == 'pull_request'"
)

# Step 3: Security Analysis
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Security Analysis",
  step_type: "claude_execute",
  position: 2,
  is_active: true,
  shared_prompt_template: prompt_templates[:security_scan],
  configuration: {
    "model" => "claude-sonnet-4-20250514",
    "timeout_seconds" => 600,
    "working_directory" => ".",
    "parse_json" => true
  },
  inputs: {},
  outputs: [
    { "name" => "findings", "type" => "array" },
    { "name" => "severity_summary", "type" => "object" },
    { "name" => "overall_risk", "type" => "string" }
  ]
)

# Step 4: Run Tests
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Run Test Suite",
  step_type: "run_tests",
  position: 3,
  is_active: true,
  configuration: {
    "framework" => "jest",
    "coverage" => true,
    "parallel" => true,
    "fail_fast" => false
  },
  inputs: {
    "command" => "npm run test:ci"
  },
  outputs: [
    { "name" => "passed", "type" => "boolean" },
    { "name" => "coverage", "type" => "number" },
    { "name" => "test_count", "type" => "number" },
    { "name" => "failed_count", "type" => "number" }
  ]
)

# Step 5: Post Review Comment
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Post Review Results",
  step_type: "post_comment",
  position: 4,
  is_active: true,
  configuration: {
    "target" => "pull_request"
  },
  inputs: {
    "body" => <<~'COMMENT'
      ## 🤖 AI Code Review Results

      **Quality Score**: ${{ steps.ai_code_review.outputs.quality_score }}/100
      **Risk Level**: ${{ steps.ai_code_review.outputs.risk_level }}
      **Security**: ${{ steps.security_analysis.outputs.overall_risk }}
      **Recommendation**: ${{ steps.ai_code_review.outputs.approval_status }}

      ### Test Results
      - **Tests**: ${{ steps.run_test_suite.outputs.test_count }} tests
      - **Coverage**: ${{ steps.run_test_suite.outputs.coverage }}%
      - **Status**: ${{ steps.run_test_suite.outputs.passed && '✅ Passed' || '❌ Failed' }}

      ---
      *Generated by Powernode AI Pipeline*
    COMMENT
  },
  outputs: [{ "name" => "comment_id", "type" => "string" }],
  condition: "trigger.type == 'pull_request'"
)

# Step 6: Human Approval Gate
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Request Human Approval",
  step_type: "notify",
  position: 5,
  is_active: true,
  configuration: {
    "type" => "approval_request",
    "channels" => ["slack", "email"],
    "approvers" => ["@devops-team", "@security-team"],
    "timeout_hours" => 24,
    "auto_approve_on" => {
      "risk_level" => "LOW",
      "quality_score_min" => 80
    }
  },
  inputs: {
    "title" => "Deployment Approval Required",
    "environment" => "production",
    "risk_level" => "${{ steps.ai_code_review.outputs.risk_level }}",
    "changes_summary" => "${{ steps.ai_code_review.outputs.summary }}"
  },
  outputs: [
    { "name" => "approved", "type" => "boolean" },
    { "name" => "approver", "type" => "string" },
    { "name" => "approval_time", "type" => "datetime" }
  ],
  condition: "trigger.ref == 'refs/heads/main' || startsWith(trigger.ref, 'refs/heads/release/')"
)

# Step 7: Deploy to Staging
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Deploy to Staging",
  step_type: "deploy",
  position: 6,
  is_active: true,
  configuration: {
    "environment" => "staging",
    "strategy" => "rolling",
    "health_check_url" => "https://staging.example.com/health",
    "timeout_seconds" => 300
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" }
  ],
  condition: "steps.request_human_approval.outputs.approved == true"
)

# Step 8: Validate Staging
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Validate Staging Deployment",
  step_type: "claude_execute",
  position: 7,
  is_active: true,
  shared_prompt_template: prompt_templates[:deployment_validation],
  configuration: {
    "model" => "claude-sonnet-4-20250514",
    "timeout_seconds" => 180,
    "parse_json" => true
  },
  inputs: {
    "app_name" => "Example App",
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}",
    "environment" => "staging",
    "deploy_url" => "${{ steps.deploy_to_staging.outputs.deployment_url }}"
  },
  outputs: [
    { "name" => "status", "type" => "string" },
    { "name" => "metrics", "type" => "object" }
  ],
  condition: "steps.deploy_to_staging.outputs.deployed == true"
)

# Step 9: Deploy to Production
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Deploy to Production",
  step_type: "deploy",
  position: 8,
  is_active: true,
  configuration: {
    "environment" => "production",
    "strategy" => "blue_green",
    "health_check_url" => "https://example.com/health",
    "timeout_seconds" => 600,
    "rollback_on_failure" => true,
    "smoke_test_command" => "curl -f https://example.com/api/status"
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" }
  ],
  condition: "steps.validate_staging_deployment.outputs.status == 'HEALTHY'"
)

# Step 10: Completion Notification
CiCd::PipelineStep.create!(
  pipeline: pipeline1,
  name: "Send Completion Notification",
  step_type: "notify",
  position: 9,
  is_active: true,
  continue_on_error: true,
  configuration: {
    "type" => "completion",
    "channels" => ["slack"],
    "always_run" => true
  },
  inputs: {
    "status" => "${{ pipeline.status }}",
    "duration" => "${{ pipeline.duration_seconds }}"
  },
  outputs: []
)

puts "    ✓ Pipeline: #{pipeline1.name} (#{pipeline1.steps.count} steps)"

CiCd::PipelineRepository.find_or_create_by!(pipeline: pipeline1, repository: repository)

# ============================================
# Pipeline 2: AI Issue Auto-Implementation
# Demonstrates: checkout, create_branch, claude_execute, run_tests, create_pr, post_comment
# ============================================

puts "\n  Creating Pipeline 2: AI Issue Auto-Implementation..."

pipeline2 = CiCd::Pipeline.find_or_create_by!(
  account: system_account,
  slug: "issue-auto-implementation"
) do |p|
  p.name = "AI Issue Auto-Implementation"
  p.description = "Automatically implements features and bug fixes from GitHub issues using AI"
  p.pipeline_type = "implement"
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.timeout_minutes = 30
  p.allow_concurrent = true
  p.runner_labels = ["ubuntu-latest"]
  p.triggers = {
    "issue_comment" => ["created"],
    "manual" => true
  }
  p.features = {
    "auto_pr" => true,
    "mention_trigger" => "@claude implement"
  }
  p.created_by = admin_user
end

pipeline2.steps.destroy_all

# Step 1: Checkout
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "Checkout Repository",
  step_type: "checkout",
  position: 0,
  is_active: true,
  configuration: { "fetch_depth" => 0 },
  inputs: {},
  outputs: [{ "name" => "commit_sha", "type" => "string" }]
)

# Step 2: Create Feature Branch
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "Create Feature Branch",
  step_type: "create_branch",
  position: 1,
  is_active: true,
  configuration: {},
  inputs: {
    "branch_name" => "ai/issue-${{ trigger.issue.number }}-${{ trigger.issue.title | slugify }}",
    "base_branch" => "main"
  },
  outputs: [{ "name" => "branch_name", "type" => "string" }]
)

# Step 3: AI Implementation
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "AI Implementation",
  step_type: "claude_execute",
  position: 2,
  is_active: true,
  shared_prompt_template: prompt_templates[:issue_implementation],
  configuration: {
    "model" => "claude-sonnet-4-20250514",
    "timeout_seconds" => 900,
    "session_id" => "issue-${{ trigger.issue.number }}"
  },
  inputs: {
    "issue_number" => "${{ trigger.issue.number }}",
    "issue_title" => "${{ trigger.issue.title }}",
    "issue_body" => "${{ trigger.issue.body }}",
    "labels" => "${{ trigger.issue.labels | map: 'name' | join: ', ' }}"
  },
  outputs: [
    { "name" => "changes_made", "type" => "array" },
    { "name" => "summary", "type" => "string" }
  ]
)

# Step 4: Verify Changes
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "Verify Changes",
  step_type: "run_tests",
  position: 3,
  is_active: true,
  configuration: {
    "framework" => "jest",
    "fail_fast" => true
  },
  inputs: {
    "command" => "npm run test"
  },
  outputs: [{ "name" => "passed", "type" => "boolean" }]
)

# Step 5: Create Pull Request
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "Create Pull Request",
  step_type: "create_pr",
  position: 4,
  is_active: true,
  configuration: {
    "draft" => false,
    "labels" => ["ai-generated", "auto-implementation"]
  },
  inputs: {
    "title" => "AI: Implement #${{ trigger.issue.number }} - ${{ trigger.issue.title }}",
    "body" => <<~BODY,
      ## AI-Generated Implementation

      This PR was automatically generated by Powernode AI to address issue #${{ trigger.issue.number }}.

      ### Changes Made
      ${{ steps.ai_implementation.outputs.summary }}

      ### Test Status
      ${{ steps.verify_changes.outputs.passed && '✅ All tests passing' || '⚠️ Tests need attention' }}

      ---
      Closes #${{ trigger.issue.number }}

      *Generated by Powernode AI Pipeline*
    BODY
    "head" => "${{ steps.create_feature_branch.outputs.branch_name }}",
    "base" => "main"
  },
  outputs: [
    { "name" => "pr_number", "type" => "number" },
    { "name" => "pr_url", "type" => "string" }
  ],
  condition: "steps.verify_changes.outputs.passed == true"
)

# Step 6: Update Issue
CiCd::PipelineStep.create!(
  pipeline: pipeline2,
  name: "Update Issue",
  step_type: "post_comment",
  position: 5,
  is_active: true,
  configuration: { "target" => "issue" },
  inputs: {
    "body" => <<~'COMMENT'
      ## 🤖 AI Implementation Complete

      I've created a pull request to address this issue:
      **PR**: #${{ steps.create_pull_request.outputs.pr_number }}
      **Link**: ${{ steps.create_pull_request.outputs.pr_url }}

      ### Summary
      ${{ steps.ai_implementation.outputs.summary }}

      Please review the changes and provide feedback!
    COMMENT
  },
  outputs: []
)

puts "    ✓ Pipeline: #{pipeline2.name} (#{pipeline2.steps.count} steps)"

CiCd::PipelineRepository.find_or_create_by!(pipeline: pipeline2, repository: repository)

# ============================================
# Pipeline 3: Nightly Security Scan
# Demonstrates: checkout, claude_execute, custom, notify with schedule trigger
# ============================================

puts "\n  Creating Pipeline 3: Nightly Security Scan..."

pipeline3 = CiCd::Pipeline.find_or_create_by!(
  account: system_account,
  slug: "scheduled-security-scan"
) do |p|
  p.name = "Nightly Security Scan"
  p.description = "Scheduled AI-powered security analysis of the entire codebase"
  p.pipeline_type = "security"
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.timeout_minutes = 45
  p.triggers = {
    "schedule" => ["0 2 * * *"],
    "manual" => true
  }
  p.created_by = admin_user
end

pipeline3.steps.destroy_all

# Step 1: Checkout
CiCd::PipelineStep.create!(
  pipeline: pipeline3,
  name: "Checkout Repository",
  step_type: "checkout",
  position: 0,
  is_active: true,
  configuration: { "fetch_depth" => 0 },
  inputs: {},
  outputs: []
)

# Step 2: Deep Security Analysis
CiCd::PipelineStep.create!(
  pipeline: pipeline3,
  name: "Deep Security Analysis",
  step_type: "claude_execute",
  position: 1,
  is_active: true,
  shared_prompt_template: prompt_templates[:security_scan],
  configuration: {
    "model" => "claude-sonnet-4-20250514",
    "timeout_seconds" => 1800,
    "working_directory" => ".",
    "parse_json" => true
  },
  inputs: {},
  outputs: [
    { "name" => "findings", "type" => "array" },
    { "name" => "severity_summary", "type" => "object" },
    { "name" => "overall_risk", "type" => "string" }
  ]
)

# Step 3: Create Security Report (custom step)
CiCd::PipelineStep.create!(
  pipeline: pipeline3,
  name: "Create Security Report Issue",
  step_type: "custom",
  position: 2,
  is_active: true,
  configuration: {
    "action" => "create_issue",
    "shell" => "bash"
  },
  inputs: {
    "title" => "🔒 Security Scan Report - ${{ date.today }}",
    "body" => <<~BODY,
      ## Automated Security Scan Results

      **Scan Date**: ${{ date.today }}
      **Repository**: ${{ repository.full_name }}

      ### Summary
      - **Critical**: ${{ steps.deep_security_analysis.outputs.severity_summary.critical || 0 }}
      - **High**: ${{ steps.deep_security_analysis.outputs.severity_summary.high || 0 }}
      - **Medium**: ${{ steps.deep_security_analysis.outputs.severity_summary.medium || 0 }}
      - **Low**: ${{ steps.deep_security_analysis.outputs.severity_summary.low || 0 }}

      ---
      *Generated by Powernode AI Security Pipeline*
    BODY
    "labels" => "security,automated"
  },
  outputs: [{ "name" => "issue_number", "type" => "number" }],
  condition: "steps.deep_security_analysis.outputs.findings.length > 0"
)

# Step 4: Alert on Critical
CiCd::PipelineStep.create!(
  pipeline: pipeline3,
  name: "Alert on Critical Findings",
  step_type: "notify",
  position: 3,
  is_active: true,
  configuration: {
    "type" => "alert",
    "channels" => ["slack", "pagerduty"],
    "severity" => "critical"
  },
  inputs: {
    "message" => "🚨 Critical security vulnerabilities found in ${{ repository.full_name }}",
    "findings_count" => "${{ steps.deep_security_analysis.outputs.severity_summary.critical }}"
  },
  outputs: [],
  condition: "steps.deep_security_analysis.outputs.severity_summary.critical > 0"
)

puts "    ✓ Pipeline: #{pipeline3.name} (#{pipeline3.steps.count} steps)"

CiCd::PipelineRepository.find_or_create_by!(pipeline: pipeline3, repository: repository)

# Create schedule for Pipeline 3
CiCd::Schedule.find_or_create_by!(pipeline: pipeline3, name: "Nightly Run") do |s|
  s.cron_expression = "0 2 * * *"
  s.timezone = "UTC"
  s.is_active = true
  s.created_by = admin_user
  s.inputs = {}
end

# ============================================
# Pipeline 4: Build & Release (NEW)
# Demonstrates: checkout, run_tests, custom, upload_artifact, download_artifact, deploy
# ============================================

puts "\n  Creating Pipeline 4: Build & Release..."

pipeline4 = CiCd::Pipeline.find_or_create_by!(
  account: system_account,
  slug: "build-and-release"
) do |p|
  p.name = "Build & Release Pipeline"
  p.description = "Build application, store artifacts, and deploy to production with artifact workflows"
  p.pipeline_type = "deploy"
  p.provider = git_provider
  p.is_active = true
  p.timeout_minutes = 30
  p.allow_concurrent = false
  p.runner_labels = ["ubuntu-latest"]
  p.environment = {
    "NODE_ENV" => "production",
    "CI" => "true"
  }
  p.triggers = {
    "push" => { "branches" => ["main"] },
    "release" => ["published"],
    "manual" => true
  }
  p.created_by = admin_user
end

pipeline4.steps.destroy_all

# Step 1: Checkout
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Checkout Repository",
  step_type: "checkout",
  position: 0,
  is_active: true,
  configuration: { "fetch_depth" => 0 },
  inputs: {},
  outputs: [
    { "name" => "commit_sha", "type" => "string" },
    { "name" => "version", "type" => "string" }
  ]
)

# Step 2: Run Tests
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Run Full Test Suite",
  step_type: "run_tests",
  position: 1,
  is_active: true,
  configuration: {
    "framework" => "jest",
    "coverage" => true,
    "parallel" => true
  },
  inputs: {
    "command" => "npm run test:ci -- --coverage"
  },
  outputs: [
    { "name" => "passed", "type" => "boolean" },
    { "name" => "coverage", "type" => "number" }
  ]
)

# Step 3: Build Application (custom)
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Build Application",
  step_type: "custom",
  position: 2,
  is_active: true,
  configuration: {
    "shell" => "bash",
    "working_directory" => "."
  },
  inputs: {
    "run" => <<~SCRIPT
      echo "Installing dependencies..."
      npm ci
      echo "Building application..."
      npm run build
      echo "Build complete!"
      ls -la dist/
    SCRIPT
  },
  outputs: [
    { "name" => "build_size", "type" => "string" },
    { "name" => "build_time", "type" => "number" }
  ],
  condition: "steps.run_full_test_suite.outputs.passed == true"
)

# Step 4: Upload Artifact
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Upload Build Artifact",
  step_type: "upload_artifact",
  position: 3,
  is_active: true,
  configuration: {
    "artifact_name" => "build-${{ steps.checkout_repository.outputs.commit_sha }}",
    "retention_days" => 30
  },
  inputs: {
    "path" => "dist/**/*"
  },
  outputs: [
    { "name" => "artifact_id", "type" => "string" },
    { "name" => "artifact_url", "type" => "string" },
    { "name" => "artifact_size", "type" => "number" }
  ]
)

# Step 5: Download Artifact (for deploy step)
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Download Build Artifact",
  step_type: "download_artifact",
  position: 4,
  is_active: true,
  configuration: {},
  inputs: {
    "artifact_name" => "build-${{ steps.checkout_repository.outputs.commit_sha }}",
    "path" => "./deploy"
  },
  outputs: [
    { "name" => "downloaded", "type" => "boolean" },
    { "name" => "path", "type" => "string" }
  ]
)

# Step 6: Deploy to CDN
CiCd::PipelineStep.create!(
  pipeline: pipeline4,
  name: "Deploy to CDN",
  step_type: "deploy",
  position: 5,
  is_active: true,
  configuration: {
    "environment" => "production",
    "strategy" => "rolling",
    "health_check_url" => "https://cdn.example.com/health",
    "timeout_seconds" => 300
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}",
    "source_path" => "${{ steps.download_build_artifact.outputs.path }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" }
  ]
)

puts "    ✓ Pipeline: #{pipeline4.name} (#{pipeline4.steps.count} steps)"

CiCd::PipelineRepository.find_or_create_by!(pipeline: pipeline4, repository: repository)

# ============================================
# Pipeline 5: Multi-Environment Deploy (NEW)
# Demonstrates: checkout, download_artifact, deploy (multiple), custom, notify (multiple)
# ============================================

puts "\n  Creating Pipeline 5: Multi-Environment Deploy..."

pipeline5 = CiCd::Pipeline.find_or_create_by!(
  account: system_account,
  slug: "multi-environment-deploy"
) do |p|
  p.name = "Multi-Environment Deployment"
  p.description = "Progressive deployment through dev → staging → production with approval gates and health checks"
  p.pipeline_type = "deploy"
  p.provider = git_provider
  p.is_active = true
  p.timeout_minutes = 90
  p.allow_concurrent = false
  p.runner_labels = ["ubuntu-latest"]
  p.triggers = {
    "workflow_dispatch" => {
      "inputs" => {
        "version" => { "type" => "string", "required" => true, "description" => "Version to deploy" },
        "skip_dev" => { "type" => "boolean", "default" => false, "description" => "Skip development deployment" }
      }
    },
    "manual" => true
  }
  p.environment = {
    "DEPLOY_ENV" => "multi"
  }
  p.created_by = admin_user
end

pipeline5.steps.destroy_all

# Step 1: Checkout
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Checkout Repository",
  step_type: "checkout",
  position: 0,
  is_active: true,
  configuration: {
    "fetch_depth" => 1,
    "ref" => "${{ inputs.version || trigger.ref }}"
  },
  inputs: {},
  outputs: [{ "name" => "commit_sha", "type" => "string" }]
)

# Step 2: Download Artifact
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Download Pre-built Artifact",
  step_type: "download_artifact",
  position: 1,
  is_active: true,
  configuration: {},
  inputs: {
    "artifact_name" => "build-${{ steps.checkout_repository.outputs.commit_sha }}",
    "path" => "./deploy"
  },
  outputs: [
    { "name" => "downloaded", "type" => "boolean" },
    { "name" => "path", "type" => "string" }
  ]
)

# Step 3: Deploy to Development
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Deploy to Development",
  step_type: "deploy",
  position: 2,
  is_active: true,
  configuration: {
    "environment" => "development",
    "strategy" => "rolling",
    "health_check_url" => "https://dev.example.com/health",
    "timeout_seconds" => 180
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" }
  ],
  condition: "inputs.skip_dev != true"
)

# Step 4: Run Smoke Tests (custom)
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Run Smoke Tests",
  step_type: "custom",
  position: 3,
  is_active: true,
  configuration: {
    "shell" => "bash",
    "working_directory" => "."
  },
  inputs: {
    "run" => <<~SCRIPT
      echo "Running smoke tests..."
      curl -f https://dev.example.com/api/health || exit 1
      curl -f https://dev.example.com/api/status || exit 1
      echo "Smoke tests passed!"
    SCRIPT
  },
  outputs: [{ "name" => "passed", "type" => "boolean" }],
  condition: "steps.deploy_to_development.outputs.deployed == true"
)

# Step 5: Deploy to Staging
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Deploy to Staging",
  step_type: "deploy",
  position: 4,
  is_active: true,
  configuration: {
    "environment" => "staging",
    "strategy" => "rolling",
    "health_check_url" => "https://staging.example.com/health",
    "timeout_seconds" => 300,
    "health_check_retries" => 3,
    "health_check_delay" => 10
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" }
  ]
)

# Step 6: Request Production Approval
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Request Production Approval",
  step_type: "notify",
  position: 5,
  is_active: true,
  configuration: {
    "type" => "approval_request",
    "channels" => ["slack", "email"],
    "approvers" => ["@release-managers", "@engineering-leads"],
    "timeout_hours" => 48
  },
  inputs: {
    "title" => "🚀 Production Deployment Approval",
    "message" => "Version ${{ steps.checkout_repository.outputs.commit_sha }} ready for production",
    "staging_url" => "${{ steps.deploy_to_staging.outputs.deployment_url }}"
  },
  outputs: [
    { "name" => "approved", "type" => "boolean" },
    { "name" => "approver", "type" => "string" }
  ],
  condition: "steps.deploy_to_staging.outputs.deployed == true"
)

# Step 7: Deploy to Production
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Deploy to Production",
  step_type: "deploy",
  position: 6,
  is_active: true,
  configuration: {
    "environment" => "production",
    "strategy" => "blue_green",
    "health_check_url" => "https://example.com/health",
    "timeout_seconds" => 600,
    "rollback_on_failure" => true,
    "smoke_test_command" => "curl -f https://example.com/api/status"
  },
  inputs: {
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}"
  },
  outputs: [
    { "name" => "deployed", "type" => "boolean" },
    { "name" => "deployment_url", "type" => "string" },
    { "name" => "previous_version", "type" => "string" }
  ],
  condition: "steps.request_production_approval.outputs.approved == true"
)

# Step 8: Send Completion Notification
CiCd::PipelineStep.create!(
  pipeline: pipeline5,
  name: "Send Deployment Notification",
  step_type: "notify",
  position: 7,
  is_active: true,
  continue_on_error: true,
  configuration: {
    "type" => "completion",
    "channels" => ["slack", "email"],
    "always_run" => true
  },
  inputs: {
    "status" => "${{ pipeline.status }}",
    "version" => "${{ steps.checkout_repository.outputs.commit_sha }}",
    "deployment_url" => "${{ steps.deploy_to_production.outputs.deployment_url }}",
    "approver" => "${{ steps.request_production_approval.outputs.approver }}"
  },
  outputs: []
)

puts "    ✓ Pipeline: #{pipeline5.name} (#{pipeline5.steps.count} steps)"

CiCd::PipelineRepository.find_or_create_by!(pipeline: pipeline5, repository: repository)

# ============================================
# Create Example Pipeline Runs
# ============================================

puts "\n  Creating Example Pipeline Runs..."

# Run 1: Successful PR Review
run1 = CiCd::PipelineRun.find_or_create_by!(
  pipeline: pipeline1,
  run_number: "full-cicd-ai-review-1"
) do |r|
  r.status = "success"
  r.trigger_type = "pull_request"
  r.trigger_context = {
    "pull_request" => {
      "number" => 42,
      "title" => "Add user authentication feature",
      "user" => { "login" => "developer" },
      "head" => { "ref" => "feature/auth" },
      "base" => { "ref" => "main" }
    }
  }
  r.triggered_by = admin_user
  r.started_at = 2.hours.ago
  r.completed_at = 1.hour.ago
  r.outputs = {
    "quality_score" => 92,
    "security_findings" => 0,
    "deployment_url" => "https://example.com"
  }
end
puts "    ✓ Run: #{run1.run_number} (#{run1.status})"

# Run 2: Running Deploy
run2 = CiCd::PipelineRun.find_or_create_by!(
  pipeline: pipeline1,
  run_number: "full-cicd-ai-review-2"
) do |r|
  r.status = "running"
  r.trigger_type = "push"
  r.trigger_context = {
    "ref" => "refs/heads/main",
    "commit" => { "sha" => "abc123def456" }
  }
  r.triggered_by = admin_user
  r.started_at = 30.minutes.ago
end
puts "    ✓ Run: #{run2.run_number} (#{run2.status})"

# Run 3: Failed Tests
run3 = CiCd::PipelineRun.find_or_create_by!(
  pipeline: pipeline2,
  run_number: "issue-auto-implementation-1"
) do |r|
  r.status = "failure"
  r.trigger_type = "issue_comment"
  r.trigger_context = {
    "issue" => {
      "number" => 15,
      "title" => "Fix login redirect bug",
      "body" => "Users are not redirected properly after login",
      "labels" => [{ "name" => "bug" }]
    },
    "comment" => {
      "body" => "@claude implement"
    }
  }
  r.triggered_by = admin_user
  r.started_at = 1.day.ago
  r.completed_at = 1.day.ago + 15.minutes
  r.error_message = "Test suite failed: 2 tests did not pass"
end
puts "    ✓ Run: #{run3.run_number} (#{run3.status})"

# Run 4: Pending Approval
run4 = CiCd::PipelineRun.find_or_create_by!(
  pipeline: pipeline5,
  run_number: "multi-environment-deploy-1"
) do |r|
  r.status = "pending"
  r.trigger_type = "workflow_dispatch"
  r.trigger_context = {
    "inputs" => {
      "version" => "v1.2.3",
      "skip_dev" => false
    },
    "requested_by" => "developer@example.com"
  }
  r.triggered_by = admin_user
  r.started_at = 2.hours.ago
end
puts "    ✓ Run: #{run4.run_number} (#{run4.status})"

# Run 5: Cancelled
run5 = CiCd::PipelineRun.find_or_create_by!(
  pipeline: pipeline4,
  run_number: "build-and-release-1"
) do |r|
  r.status = "cancelled"
  r.trigger_type = "push"
  r.trigger_context = {
    "ref" => "refs/heads/main",
    "commit" => { "sha" => "xyz789" }
  }
  r.triggered_by = admin_user
  r.started_at = 3.hours.ago
  r.completed_at = 3.hours.ago + 5.minutes
end
puts "    ✓ Run: #{run5.run_number} (#{run5.status})"

# Create step executions for successful run
puts "\n  Creating Step Executions..."

pipeline1.steps.ordered.each_with_index do |step, index|
  CiCd::StepExecution.find_or_create_by!(
    pipeline_run: run1,
    pipeline_step: step
  ) do |e|
    e.status = "success"
    e.started_at = run1.started_at + (index * 5).minutes
    e.completed_at = run1.started_at + ((index + 1) * 5).minutes
    e.outputs = case step.step_type
                when "checkout"
                  { "commit_sha" => "abc123", "branch" => "feature/auth" }
                when "claude_execute"
                  { "quality_score" => 92, "approval_status" => "APPROVE", "risk_level" => "LOW" }
                when "run_tests"
                  { "passed" => true, "coverage" => 87, "test_count" => 156 }
                when "deploy"
                  { "deployed" => true, "deployment_url" => "https://staging.example.com" }
                when "notify"
                  { "approved" => true, "approver" => "admin@example.com" }
                else
                  {}
                end
    e.logs = "[#{e.started_at}] Starting #{step.name}...\n[#{e.completed_at}] #{step.name} completed successfully."
  end
end

puts "    ✓ Created #{run1.step_executions.count} step executions for successful run"

# ============================================
# Summary
# ============================================

puts "\n" + "=" * 60
puts "CI/CD Comprehensive Workflow Seeding Complete!"
puts "=" * 60
puts "\nCreated:"
puts "  • 1 Git Provider (#{git_provider.name})"
puts "  • 1 Repository (#{repository.full_name})"
puts "  • #{prompt_templates.count} Prompt Templates"
puts "  • 5 Pipelines:"
puts "    - #{pipeline1.name} (#{pipeline1.steps.count} steps)"
puts "    - #{pipeline2.name} (#{pipeline2.steps.count} steps)"
puts "    - #{pipeline3.name} (#{pipeline3.steps.count} steps)"
puts "    - #{pipeline4.name} (#{pipeline4.steps.count} steps)"
puts "    - #{pipeline5.name} (#{pipeline5.steps.count} steps)"
puts "  • 5 Example Pipeline Runs (success, running, failure, pending, cancelled)"
puts "  • #{CiCd::Schedule.count} Schedule(s)"

total_steps = pipeline1.steps.count + pipeline2.steps.count + pipeline3.steps.count +
              pipeline4.steps.count + pipeline5.steps.count
puts "\nTotal Steps: #{total_steps}"

puts "\nStep Types Demonstrated:"
all_steps = CiCd::PipelineStep.where(pipeline: [pipeline1, pipeline2, pipeline3, pipeline4, pipeline5])
step_types = all_steps.pluck(:step_type).uniq.sort
step_types.each do |st|
  count = all_steps.where(step_type: st).count
  puts "  ✓ #{st} (#{count}x)"
end

puts "\nTrigger Types Demonstrated:"
puts "  ✓ manual (all pipelines)"
puts "  ✓ pull_request (Pipeline 1)"
puts "  ✓ push (Pipelines 1, 4)"
puts "  ✓ schedule (Pipeline 3)"
puts "  ✓ workflow_dispatch (Pipelines 1, 5)"
puts "  ✓ issue_comment (Pipeline 2)"
puts "  ✓ release (Pipeline 4)"

puts "\nFeatures Demonstrated:"
puts "  ✓ AI-powered code review with quality scoring"
puts "  ✓ Security vulnerability scanning"
puts "  ✓ Human approval gates with auto-approve conditions"
puts "  ✓ Multi-stage deployment (dev → staging → production)"
puts "  ✓ Artifact upload/download workflows"
puts "  ✓ Auto-implementation from GitHub issues"
puts "  ✓ Scheduled/cron-based execution"
puts "  ✓ Step output chaining and conditions"
puts "  ✓ Health checks and rollback on failure"
puts "  ✓ Notification integrations (Slack, email, PagerDuty)"
puts "  ✓ Blue/green and rolling deployment strategies"
puts "=" * 60
