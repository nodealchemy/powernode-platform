# frozen_string_literal: true

# AI DevOps Templates Seed Data
# Creates system-level AI DevOps workflow templates for common operations
# Uses find_or_create_by! to avoid overwriting existing customized templates

puts "  Loading AI DevOps Templates..."

admin_account = Account.find_by(name: "Powernode Admin")
unless admin_account
  puts "  ⚠️  Admin account not found - skipping AI DevOps templates"
  return
end

puts "  ✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"

# Template 1: Automated Code Review
Ai::DevopsTemplate.find_or_create_by!(slug: "automated-code-review") do |t|
  t.account = admin_account
  t.name = "Automated Code Review"
  t.description = "AI-powered code review that analyzes pull requests for quality, security, performance, and best practices. Provides structured feedback with severity ratings and line-level suggestions."
  t.category = "code_quality"
  t.template_type = "code_review"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.is_featured = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "PR Opened/Updated", "config" => { "event" => "pull_request" } },
      { "id" => "fetch_diff", "type" => "action", "label" => "Fetch PR Diff", "config" => { "tool" => "git_diff" } },
      { "id" => "analyze_quality", "type" => "ai", "label" => "Analyze Code Quality", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "analyze_security", "type" => "ai", "label" => "Security Review", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "post_review", "type" => "action", "label" => "Post Review Comments", "config" => { "tool" => "git_comment" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "fetch_diff" },
      { "source" => "fetch_diff", "target" => "analyze_quality" },
      { "source" => "fetch_diff", "target" => "analyze_security" },
      { "source" => "analyze_quality", "target" => "post_review" },
      { "source" => "analyze_security", "target" => "post_review" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["pull_request.opened", "pull_request.synchronize"],
    "filters" => { "base_branch" => ["main", "develop"] }
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "pr_number" => { "type" => "integer", "required" => true, "description" => "Pull request number" },
    "review_depth" => { "type" => "string", "default" => "standard", "enum" => ["quick", "standard", "thorough"], "description" => "Review depth level" }
  }
  t.output_schema = {
    "review_summary" => { "type" => "string" },
    "findings" => { "type" => "array" },
    "risk_level" => { "type" => "string", "enum" => ["low", "medium", "high", "critical"] },
    "approval_recommendation" => { "type" => "boolean" }
  }
  t.variables = [
    { "name" => "review_language", "default" => "en", "description" => "Language for review comments" },
    { "name" => "max_findings", "default" => "20", "description" => "Maximum number of findings to report" }
  ]
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["code-review", "quality", "security", "pull-request", "automation"]
  t.usage_guide = <<~GUIDE
    ## Automated Code Review Template

    ### Setup
    1. Connect your Git provider (GitHub, GitLab, Gitea, or Bitbucket)
    2. Configure the webhook trigger for pull request events
    3. Set the review depth based on your needs

    ### Review Depth Levels
    - **Quick**: Fast scan for obvious issues, typos, and formatting
    - **Standard**: Balanced review covering quality, security, and best practices
    - **Thorough**: Deep analysis including performance, architecture, and edge cases

    ### Output
    The review posts inline comments on the PR with severity-rated findings and an overall summary comment with approval recommendation.
  GUIDE
end

# Template 2: Security Vulnerability Scanner
Ai::DevopsTemplate.find_or_create_by!(slug: "security-vulnerability-scanner") do |t|
  t.account = admin_account
  t.name = "Security Vulnerability Scanner"
  t.description = "Comprehensive AI security analysis combining SAST scanning, dependency auditing, secret detection, and OWASP Top 10 checks. Generates structured vulnerability reports with remediation guidance."
  t.category = "security"
  t.template_type = "security_scan"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.is_featured = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Scan Triggered", "config" => { "event" => "manual_or_schedule" } },
      { "id" => "clone_repo", "type" => "action", "label" => "Clone Repository", "config" => { "tool" => "git_clone" } },
      { "id" => "sast_scan", "type" => "ai", "label" => "SAST Analysis", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "dependency_audit", "type" => "action", "label" => "Dependency Audit", "config" => { "tool" => "dependency_check" } },
      { "id" => "secret_scan", "type" => "ai", "label" => "Secret Detection", "config" => { "model" => "claude-haiku-4-5-20251001", "temperature" => 0.0 } },
      { "id" => "generate_report", "type" => "ai", "label" => "Generate Report", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "clone_repo" },
      { "source" => "clone_repo", "target" => "sast_scan" },
      { "source" => "clone_repo", "target" => "dependency_audit" },
      { "source" => "clone_repo", "target" => "secret_scan" },
      { "source" => "sast_scan", "target" => "generate_report" },
      { "source" => "dependency_audit", "target" => "generate_report" },
      { "source" => "secret_scan", "target" => "generate_report" }
    ]
  }
  t.trigger_config = {
    "type" => "schedule",
    "cron" => "0 2 * * 1",
    "description" => "Weekly Monday at 2 AM"
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL to scan" },
    "branch" => { "type" => "string", "default" => "main", "description" => "Branch to scan" },
    "scan_types" => { "type" => "array", "default" => ["sast", "dependencies", "secrets"], "description" => "Types of scans to run" },
    "severity_threshold" => { "type" => "string", "default" => "medium", "enum" => ["low", "medium", "high", "critical"], "description" => "Minimum severity to report" }
  }
  t.output_schema = {
    "vulnerabilities" => { "type" => "array" },
    "severity_counts" => { "type" => "object" },
    "risk_score" => { "type" => "number" },
    "remediation_plan" => { "type" => "array" },
    "compliance_status" => { "type" => "object" }
  }
  t.variables = []
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["security", "vulnerability", "sast", "dependencies", "owasp", "compliance"]
  t.usage_guide = <<~GUIDE
    ## Security Vulnerability Scanner

    ### What It Does
    Runs three parallel security scans on your codebase:
    1. **SAST Analysis** - AI-powered static analysis for code vulnerabilities
    2. **Dependency Audit** - Checks all dependencies against known CVE databases
    3. **Secret Detection** - Scans for hardcoded credentials, API keys, and tokens

    ### Severity Levels
    - **Critical**: Actively exploitable, immediate action required
    - **High**: Significant risk, fix within 24 hours
    - **Medium**: Moderate risk, fix within 1 week
    - **Low**: Minor risk, fix in next sprint

    ### Output
    A structured JSON report with all findings, severity counts, overall risk score, and a prioritized remediation plan.
  GUIDE
end

# Template 3: Test Generation Pipeline
Ai::DevopsTemplate.find_or_create_by!(slug: "ai-test-generation") do |t|
  t.account = admin_account
  t.name = "AI Test Generation Pipeline"
  t.description = "Automatically generates comprehensive test suites for new or modified code. Supports RSpec, Jest, pytest, and Go test frameworks with edge case coverage and mocking strategies."
  t.category = "testing"
  t.template_type = "test_generation"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Code Changed", "config" => { "event" => "push" } },
      { "id" => "detect_changes", "type" => "action", "label" => "Detect Changed Files", "config" => { "tool" => "git_diff" } },
      { "id" => "analyze_code", "type" => "ai", "label" => "Analyze Code Structure", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "generate_tests", "type" => "ai", "label" => "Generate Tests", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.3 } },
      { "id" => "validate_tests", "type" => "action", "label" => "Run Generated Tests", "config" => { "tool" => "test_runner" } },
      { "id" => "create_pr", "type" => "action", "label" => "Create Test PR", "config" => { "tool" => "git_pr" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "detect_changes" },
      { "source" => "detect_changes", "target" => "analyze_code" },
      { "source" => "analyze_code", "target" => "generate_tests" },
      { "source" => "generate_tests", "target" => "validate_tests" },
      { "source" => "validate_tests", "target" => "create_pr" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["push"],
    "filters" => { "branches" => ["develop", "feature/*"] }
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "branch" => { "type" => "string", "required" => true, "description" => "Branch with changes" },
    "test_framework" => { "type" => "string", "default" => "auto-detect", "enum" => ["auto-detect", "rspec", "jest", "pytest", "go-test"], "description" => "Test framework to use" },
    "coverage_target" => { "type" => "number", "default" => 80, "description" => "Target coverage percentage" }
  }
  t.output_schema = {
    "tests_generated" => { "type" => "integer" },
    "files_created" => { "type" => "array" },
    "coverage_estimate" => { "type" => "number" },
    "pr_url" => { "type" => "string" }
  }
  t.variables = [
    { "name" => "test_style", "default" => "descriptive", "description" => "Test naming style: descriptive or concise" },
    { "name" => "include_mocks", "default" => "true", "description" => "Generate mock/stub helpers" }
  ]
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["testing", "test-generation", "automation", "coverage", "ci-cd"]
end

# Template 4: Deployment Validation
Ai::DevopsTemplate.find_or_create_by!(slug: "deployment-validation") do |t|
  t.account = admin_account
  t.name = "Pre-Deployment Validation"
  t.description = "AI-powered pre-deployment risk assessment that analyzes code changes, database migrations, configuration diffs, and infrastructure impact before deploying to staging or production."
  t.category = "deployment"
  t.template_type = "deployment_validation"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.is_featured = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Deploy Requested", "config" => { "event" => "deployment" } },
      { "id" => "gather_changes", "type" => "action", "label" => "Gather Release Changes", "config" => { "tool" => "git_log" } },
      { "id" => "check_migrations", "type" => "ai", "label" => "Analyze Migrations", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "check_config", "type" => "ai", "label" => "Config Change Review", "config" => { "model" => "claude-haiku-4-5-20251001", "temperature" => 0.1 } },
      { "id" => "risk_assessment", "type" => "ai", "label" => "Risk Assessment", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "gate_decision", "type" => "condition", "label" => "Deploy Gate", "config" => { "condition" => "risk_level != 'critical'" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "gather_changes" },
      { "source" => "gather_changes", "target" => "check_migrations" },
      { "source" => "gather_changes", "target" => "check_config" },
      { "source" => "check_migrations", "target" => "risk_assessment" },
      { "source" => "check_config", "target" => "risk_assessment" },
      { "source" => "risk_assessment", "target" => "gate_decision" }
    ]
  }
  t.trigger_config = {
    "type" => "manual",
    "description" => "Triggered before deployment to staging or production"
  }
  t.input_schema = {
    "environment" => { "type" => "string", "required" => true, "enum" => ["staging", "production"], "description" => "Target deployment environment" },
    "release_tag" => { "type" => "string", "description" => "Release tag or commit SHA" },
    "previous_tag" => { "type" => "string", "description" => "Previous release tag for diff" },
    "rollback_plan_required" => { "type" => "boolean", "default" => true, "description" => "Require rollback plan in assessment" }
  }
  t.output_schema = {
    "approved" => { "type" => "boolean" },
    "risk_level" => { "type" => "string", "enum" => ["low", "medium", "high", "critical"] },
    "breaking_changes" => { "type" => "array" },
    "migration_risks" => { "type" => "array" },
    "rollback_plan" => { "type" => "string" },
    "recommended_actions" => { "type" => "array" }
  }
  t.variables = []
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["deployment", "validation", "risk-assessment", "ci-cd", "production"]
end

# Template 5: Release Notes Generator
Ai::DevopsTemplate.find_or_create_by!(slug: "release-notes-generator") do |t|
  t.account = admin_account
  t.name = "Release Notes Generator"
  t.description = "Automatically generates structured release notes from git history, PR descriptions, and issue trackers. Produces user-facing changelogs categorized by feature, fix, and breaking change."
  t.category = "release"
  t.template_type = "release_notes"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Release Tagged", "config" => { "event" => "tag_push" } },
      { "id" => "fetch_commits", "type" => "action", "label" => "Fetch Commit History", "config" => { "tool" => "git_log" } },
      { "id" => "fetch_prs", "type" => "action", "label" => "Fetch Merged PRs", "config" => { "tool" => "git_prs" } },
      { "id" => "categorize", "type" => "ai", "label" => "Categorize Changes", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "generate_notes", "type" => "ai", "label" => "Write Release Notes", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.4 } },
      { "id" => "publish", "type" => "action", "label" => "Publish Release", "config" => { "tool" => "git_release" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "fetch_commits" },
      { "source" => "trigger", "target" => "fetch_prs" },
      { "source" => "fetch_commits", "target" => "categorize" },
      { "source" => "fetch_prs", "target" => "categorize" },
      { "source" => "categorize", "target" => "generate_notes" },
      { "source" => "generate_notes", "target" => "publish" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["tag_push"],
    "filters" => { "tag_pattern" => "[0-9]*.[0-9]*.[0-9]*" }
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "current_tag" => { "type" => "string", "required" => true, "description" => "Current release tag" },
    "previous_tag" => { "type" => "string", "description" => "Previous tag for comparison" },
    "include_contributors" => { "type" => "boolean", "default" => true, "description" => "List contributors in notes" },
    "format" => { "type" => "string", "default" => "markdown", "enum" => ["markdown", "html", "plain"], "description" => "Output format" }
  }
  t.output_schema = {
    "release_notes" => { "type" => "string" },
    "features" => { "type" => "array" },
    "bug_fixes" => { "type" => "array" },
    "breaking_changes" => { "type" => "array" },
    "contributors" => { "type" => "array" }
  }
  t.variables = [
    { "name" => "audience", "default" => "end-user", "description" => "Target audience: end-user, developer, or both" }
  ]
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["release", "changelog", "documentation", "automation"]
end

# Template 6: Changelog Updater
Ai::DevopsTemplate.find_or_create_by!(slug: "changelog-updater") do |t|
  t.account = admin_account
  t.name = "Changelog Updater"
  t.description = "Maintains a Keep a Changelog formatted CHANGELOG.md by analyzing merged PRs and commits. Automatically categorizes entries and updates the file with each release."
  t.category = "release"
  t.template_type = "changelog"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "PR Merged to Main", "config" => { "event" => "pull_request.merged" } },
      { "id" => "read_changelog", "type" => "action", "label" => "Read CHANGELOG.md", "config" => { "tool" => "file_read" } },
      { "id" => "analyze_pr", "type" => "ai", "label" => "Categorize PR", "config" => { "model" => "claude-haiku-4-5-20251001", "temperature" => 0.1 } },
      { "id" => "update_changelog", "type" => "ai", "label" => "Update Changelog", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "commit_changes", "type" => "action", "label" => "Commit Updated Changelog", "config" => { "tool" => "git_commit" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "read_changelog" },
      { "source" => "trigger", "target" => "analyze_pr" },
      { "source" => "read_changelog", "target" => "update_changelog" },
      { "source" => "analyze_pr", "target" => "update_changelog" },
      { "source" => "update_changelog", "target" => "commit_changes" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["pull_request.closed"],
    "filters" => { "merged" => true, "base_branch" => ["main", "master"] }
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "pr_number" => { "type" => "integer", "required" => true, "description" => "Merged PR number" },
    "changelog_path" => { "type" => "string", "default" => "CHANGELOG.md", "description" => "Path to changelog file" }
  }
  t.output_schema = {
    "entry_added" => { "type" => "string" },
    "category" => { "type" => "string", "enum" => ["added", "changed", "deprecated", "removed", "fixed", "security"] },
    "commit_sha" => { "type" => "string" }
  }
  t.variables = []
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["changelog", "release", "documentation", "automation", "keep-a-changelog"]
end

# Template 7: API Documentation Generator
Ai::DevopsTemplate.find_or_create_by!(slug: "api-docs-generator") do |t|
  t.account = admin_account
  t.name = "API Documentation Generator"
  t.description = "Scans API controllers, routes, and serializers to generate OpenAPI/Swagger documentation. Includes endpoint descriptions, request/response examples, and authentication details."
  t.category = "documentation"
  t.template_type = "api_docs"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Docs Requested", "config" => { "event" => "manual" } },
      { "id" => "scan_routes", "type" => "action", "label" => "Scan API Routes", "config" => { "tool" => "file_search" } },
      { "id" => "scan_controllers", "type" => "action", "label" => "Scan Controllers", "config" => { "tool" => "file_read" } },
      { "id" => "analyze_endpoints", "type" => "ai", "label" => "Analyze Endpoints", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "generate_openapi", "type" => "ai", "label" => "Generate OpenAPI Spec", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "write_docs", "type" => "action", "label" => "Write Documentation Files", "config" => { "tool" => "file_write" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "scan_routes" },
      { "source" => "trigger", "target" => "scan_controllers" },
      { "source" => "scan_routes", "target" => "analyze_endpoints" },
      { "source" => "scan_controllers", "target" => "analyze_endpoints" },
      { "source" => "analyze_endpoints", "target" => "generate_openapi" },
      { "source" => "generate_openapi", "target" => "write_docs" }
    ]
  }
  t.trigger_config = {
    "type" => "manual",
    "description" => "Manually triggered to regenerate API documentation"
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "branch" => { "type" => "string", "default" => "main", "description" => "Branch to document" },
    "api_prefix" => { "type" => "string", "default" => "/api/v1", "description" => "API route prefix" },
    "output_format" => { "type" => "string", "default" => "openapi3", "enum" => ["openapi3", "swagger2", "markdown"], "description" => "Documentation format" }
  }
  t.output_schema = {
    "spec_file" => { "type" => "string" },
    "endpoints_documented" => { "type" => "integer" },
    "schemas_generated" => { "type" => "integer" },
    "warnings" => { "type" => "array" }
  }
  t.variables = [
    { "name" => "include_examples", "default" => "true", "description" => "Generate request/response examples" },
    { "name" => "include_auth", "default" => "true", "description" => "Document authentication requirements" }
  ]
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["documentation", "api", "openapi", "swagger", "automation"]
end

# Template 8: Coverage Analysis Report
Ai::DevopsTemplate.find_or_create_by!(slug: "coverage-analysis-report") do |t|
  t.account = admin_account
  t.name = "Coverage Analysis Report"
  t.description = "Analyzes test coverage data to identify uncovered code paths, suggest priority areas for testing, and track coverage trends over time. Integrates with SimpleCov, Istanbul, and coverage.py."
  t.category = "testing"
  t.template_type = "coverage_analysis"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Tests Completed", "config" => { "event" => "ci_complete" } },
      { "id" => "collect_coverage", "type" => "action", "label" => "Collect Coverage Data", "config" => { "tool" => "artifact_download" } },
      { "id" => "analyze_gaps", "type" => "ai", "label" => "Analyze Coverage Gaps", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "prioritize", "type" => "ai", "label" => "Prioritize Test Targets", "config" => { "model" => "claude-haiku-4-5-20251001", "temperature" => 0.1 } },
      { "id" => "generate_report", "type" => "ai", "label" => "Generate Report", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.3 } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "collect_coverage" },
      { "source" => "collect_coverage", "target" => "analyze_gaps" },
      { "source" => "analyze_gaps", "target" => "prioritize" },
      { "source" => "prioritize", "target" => "generate_report" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["ci.completed"],
    "filters" => { "status" => "success" }
  }
  t.input_schema = {
    "coverage_file" => { "type" => "string", "required" => true, "description" => "Path to coverage report file" },
    "coverage_format" => { "type" => "string", "default" => "auto-detect", "enum" => ["auto-detect", "simplecov", "istanbul", "coverage-py", "lcov"], "description" => "Coverage report format" },
    "target_coverage" => { "type" => "number", "default" => 80, "description" => "Target coverage percentage" },
    "compare_with_previous" => { "type" => "boolean", "default" => true, "description" => "Compare with previous run" }
  }
  t.output_schema = {
    "total_coverage" => { "type" => "number" },
    "coverage_delta" => { "type" => "number" },
    "uncovered_files" => { "type" => "array" },
    "priority_targets" => { "type" => "array" },
    "trend" => { "type" => "string", "enum" => ["improving", "stable", "declining"] }
  }
  t.variables = []
  t.secrets_required = []
  t.integrations_required = []
  t.tags = ["testing", "coverage", "quality", "analysis", "ci-cd"]
end

# Template 9: Performance Check
Ai::DevopsTemplate.find_or_create_by!(slug: "performance-check") do |t|
  t.account = admin_account
  t.name = "Performance Regression Check"
  t.description = "Detects performance regressions by analyzing code changes for N+1 queries, memory leaks, slow algorithms, and missing indexes. Compares against baseline benchmarks."
  t.category = "monitoring"
  t.template_type = "performance_check"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "PR Opened", "config" => { "event" => "pull_request" } },
      { "id" => "fetch_changes", "type" => "action", "label" => "Fetch Code Changes", "config" => { "tool" => "git_diff" } },
      { "id" => "query_analysis", "type" => "ai", "label" => "N+1 Query Detection", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "complexity_analysis", "type" => "ai", "label" => "Complexity Analysis", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "memory_analysis", "type" => "ai", "label" => "Memory Pattern Check", "config" => { "model" => "claude-haiku-4-5-20251001", "temperature" => 0.1 } },
      { "id" => "summary", "type" => "ai", "label" => "Performance Summary", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "fetch_changes" },
      { "source" => "fetch_changes", "target" => "query_analysis" },
      { "source" => "fetch_changes", "target" => "complexity_analysis" },
      { "source" => "fetch_changes", "target" => "memory_analysis" },
      { "source" => "query_analysis", "target" => "summary" },
      { "source" => "complexity_analysis", "target" => "summary" },
      { "source" => "memory_analysis", "target" => "summary" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["pull_request.opened", "pull_request.synchronize"]
  }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL" },
    "pr_number" => { "type" => "integer", "required" => true, "description" => "Pull request number" },
    "language" => { "type" => "string", "default" => "auto-detect", "enum" => ["auto-detect", "ruby", "javascript", "python", "go"], "description" => "Primary language" },
    "baseline_metrics" => { "type" => "object", "description" => "Previous performance baseline for comparison" }
  }
  t.output_schema = {
    "performance_issues" => { "type" => "array" },
    "n_plus_one_queries" => { "type" => "array" },
    "complexity_warnings" => { "type" => "array" },
    "memory_concerns" => { "type" => "array" },
    "impact_level" => { "type" => "string", "enum" => ["none", "low", "medium", "high"] }
  }
  t.variables = []
  t.secrets_required = ["git_provider_token"]
  t.integrations_required = ["git_provider"]
  t.tags = ["performance", "optimization", "n+1", "monitoring", "pull-request"]
end

# Template 10: Incident Response Runbook
Ai::DevopsTemplate.find_or_create_by!(slug: "incident-response-runbook") do |t|
  t.account = admin_account
  t.name = "Incident Response Runbook"
  t.description = "AI-assisted incident response that analyzes error logs, correlates events, suggests root causes, and generates incident reports. Integrates with monitoring and alerting systems."
  t.category = "monitoring"
  t.template_type = "custom"
  t.status = "published"
  t.visibility = "public"
  t.version = "1.0.0"
  t.is_system = true
  t.published_at = Time.current
  t.workflow_definition = {
    "nodes" => [
      { "id" => "trigger", "type" => "trigger", "label" => "Alert Received", "config" => { "event" => "webhook" } },
      { "id" => "collect_logs", "type" => "action", "label" => "Collect Recent Logs", "config" => { "tool" => "log_query" } },
      { "id" => "collect_metrics", "type" => "action", "label" => "Collect Metrics", "config" => { "tool" => "metrics_query" } },
      { "id" => "correlate_events", "type" => "ai", "label" => "Correlate Events", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.1 } },
      { "id" => "root_cause", "type" => "ai", "label" => "Root Cause Analysis", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.2 } },
      { "id" => "generate_runbook", "type" => "ai", "label" => "Generate Response Steps", "config" => { "model" => "claude-sonnet-4-5-20250929", "temperature" => 0.3 } },
      { "id" => "notify_team", "type" => "action", "label" => "Notify On-Call Team", "config" => { "tool" => "notification" } }
    ],
    "edges" => [
      { "source" => "trigger", "target" => "collect_logs" },
      { "source" => "trigger", "target" => "collect_metrics" },
      { "source" => "collect_logs", "target" => "correlate_events" },
      { "source" => "collect_metrics", "target" => "correlate_events" },
      { "source" => "correlate_events", "target" => "root_cause" },
      { "source" => "root_cause", "target" => "generate_runbook" },
      { "source" => "generate_runbook", "target" => "notify_team" }
    ]
  }
  t.trigger_config = {
    "type" => "webhook",
    "events" => ["alert.firing"],
    "filters" => { "severity" => ["critical", "high"] }
  }
  t.input_schema = {
    "alert_name" => { "type" => "string", "required" => true, "description" => "Name of the triggered alert" },
    "alert_severity" => { "type" => "string", "required" => true, "enum" => ["critical", "high", "medium", "low"], "description" => "Alert severity level" },
    "service_name" => { "type" => "string", "description" => "Affected service name" },
    "error_message" => { "type" => "string", "description" => "Error message from the alert" },
    "time_range" => { "type" => "string", "default" => "1h", "description" => "Time range for log collection" }
  }
  t.output_schema = {
    "incident_id" => { "type" => "string" },
    "root_cause" => { "type" => "string" },
    "impact_assessment" => { "type" => "string" },
    "response_steps" => { "type" => "array" },
    "related_incidents" => { "type" => "array" },
    "post_mortem_template" => { "type" => "string" }
  }
  t.variables = [
    { "name" => "escalation_threshold_minutes", "default" => "30", "description" => "Minutes before auto-escalation" },
    { "name" => "notification_channel", "default" => "slack", "description" => "Notification channel: slack, email, pagerduty" }
  ]
  t.secrets_required = ["monitoring_api_key", "notification_webhook_url"]
  t.integrations_required = ["monitoring", "notification"]
  t.tags = ["incident-response", "monitoring", "alerting", "runbook", "on-call"]
  t.usage_guide = <<~GUIDE
    ## Incident Response Runbook

    ### How It Works
    1. Receives alerts from your monitoring system (Prometheus, Datadog, etc.)
    2. Collects relevant logs and metrics from the affected time window
    3. AI correlates events across services to identify patterns
    4. Performs root cause analysis based on collected evidence
    5. Generates step-by-step response instructions
    6. Notifies the on-call team with full context

    ### Integration
    Configure your alerting system to send webhooks to this template's trigger endpoint. The template supports Prometheus AlertManager, Datadog, PagerDuty, and custom webhook formats.

    ### Escalation
    If the incident is not acknowledged within the configured threshold, the template automatically escalates to the next responder.
  GUIDE
end

# Ensure all system templates belong to admin account (fixes templates created before account assignment)
updated = Ai::DevopsTemplate.where(is_system: true, account_id: nil).update_all(account_id: admin_account.id)
puts "  Updated #{updated} existing templates to admin account" if updated > 0

puts "  Created #{Ai::DevopsTemplate.where(is_system: true).count} system AI DevOps templates (all owned by #{admin_account.name})"
