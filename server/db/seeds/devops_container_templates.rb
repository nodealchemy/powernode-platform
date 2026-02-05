# frozen_string_literal: true

# Seed practical container templates (system-level, account_id: nil)
# These leverage the platform's Gitea act_runner infrastructure with powernode-ai-agent label

puts "  Loading DevOps Container Templates..."

# Template 1: Git Repository Test Runner
Devops::ContainerTemplate.find_or_create_by!(name: "Git Repository Test Runner", account_id: nil) do |t|
  t.description = "Clone repo from any connected git provider, install dependencies, run test suite, and report results. Supports Node.js, Python, and Ruby projects."
  t.image_name = "node"
  t.image_tag = "20-alpine"
  t.category = "ci-cd"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 600
  t.memory_mb = 1024
  t.cpu_millicores = 1000
  t.sandbox_mode = false
  t.network_access = true
  t.allowed_egress_domains = ["github.com", "registry.npmjs.org", "pypi.org", "rubygems.org", "gitlab.com"]
  t.environment_variables = { "CI" => "true", "NODE_ENV" => "test" }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Git repository URL" },
    "branch" => { "type" => "string", "default" => "main", "description" => "Branch to test" },
    "test_command" => { "type" => "string", "default" => "npm test", "description" => "Test command to execute" },
    "setup_command" => { "type" => "string", "description" => "Optional setup command (e.g., npm install)" }
  }
  t.output_schema = {
    "exit_code" => { "type" => "integer" },
    "test_output" => { "type" => "string" },
    "tests_passed" => { "type" => "integer" },
    "tests_failed" => { "type" => "integer" },
    "duration_ms" => { "type" => "integer" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "ci" }
end

# Template 2: AI Coding Agent
Devops::ContainerTemplate.find_or_create_by!(name: "AI Coding Agent", account_id: nil) do |t|
  t.description = "Run an autonomous AI coding agent in isolation for code generation, review, and refactoring tasks."
  t.image_name = "python"
  t.image_tag = "3.12-slim"
  t.category = "ai-agent"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 300
  t.memory_mb = 2048
  t.cpu_millicores = 1000
  t.sandbox_mode = true
  t.network_access = true
  t.allowed_egress_domains = ["api.openai.com", "api.anthropic.com", "api.together.xyz"]
  t.environment_variables = { "PYTHONUNBUFFERED" => "1" }
  t.input_schema = {
    "agent_script" => { "type" => "string", "description" => "Python script for the agent to execute" },
    "prompt" => { "type" => "string", "required" => true, "description" => "Task prompt for the AI agent" },
    "model" => { "type" => "string", "default" => "claude-sonnet-4-20250514", "description" => "AI model to use" },
    "provider_api_key" => { "type" => "string", "description" => "API key for the AI provider" },
    "max_tokens" => { "type" => "integer", "default" => 4096, "description" => "Max tokens for generation" }
  }
  t.output_schema = {
    "result" => { "type" => "string" },
    "tokens_used" => { "type" => "integer" },
    "files_modified" => { "type" => "array" },
    "execution_time_ms" => { "type" => "integer" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "ai-agent" }
end

# Template 3: Multi-Agent DevOps Pipeline
Devops::ContainerTemplate.find_or_create_by!(name: "Multi-Agent DevOps Pipeline", account_id: nil) do |t|
  t.description = "Orchestrate multiple AI agents (planner, coder, reviewer, deployer) for end-to-end feature development."
  t.image_name = "python"
  t.image_tag = "3.12-slim"
  t.category = "devops"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 900
  t.memory_mb = 4096
  t.cpu_millicores = 2000
  t.sandbox_mode = false
  t.network_access = true
  t.allowed_egress_domains = ["github.com", "gitlab.com", "api.openai.com", "api.anthropic.com"]
  t.environment_variables = { "PYTHONUNBUFFERED" => "1", "LOG_LEVEL" => "info" }
  t.input_schema = {
    "task_description" => { "type" => "string", "required" => true, "description" => "Feature or task to implement" },
    "repo_url" => { "type" => "string", "description" => "Target repository URL" },
    "branch" => { "type" => "string", "default" => "main", "description" => "Base branch" },
    "agents" => { "type" => "array", "default" => ["planner", "coder", "reviewer"], "description" => "Agent roles to activate" },
    "auto_merge" => { "type" => "boolean", "default" => false, "description" => "Auto-merge PR if review passes" }
  }
  t.output_schema = {
    "plan" => { "type" => "string" },
    "code_changes" => { "type" => "array" },
    "review_notes" => { "type" => "string" },
    "pr_url" => { "type" => "string" },
    "deployment_status" => { "type" => "string" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "multi-agent" }
end

# Template 4: Gitea/GitHub Actions Workflow Runner
Devops::ContainerTemplate.find_or_create_by!(name: "GitHub Actions Workflow Runner", account_id: nil) do |t|
  t.description = "Execute GitHub Actions-compatible workflows locally via act runner. Test workflows before pushing to remote."
  t.image_name = "catthehacker/ubuntu"
  t.image_tag = "act-latest"
  t.category = "ci-cd"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 600
  t.memory_mb = 2048
  t.cpu_millicores = 2000
  t.sandbox_mode = false
  t.network_access = true
  t.allowed_egress_domains = []
  t.environment_variables = { "ACT" => "true" }
  t.input_schema = {
    "workflow_yaml" => { "type" => "string", "required" => true, "description" => "GitHub Actions workflow YAML content" },
    "repo_url" => { "type" => "string", "description" => "Repository URL to clone" },
    "event_type" => { "type" => "string", "default" => "push", "description" => "Event type to simulate" },
    "event_payload" => { "type" => "object", "description" => "Event payload JSON" }
  }
  t.output_schema = {
    "workflow_result" => { "type" => "string" },
    "job_statuses" => { "type" => "object" },
    "logs" => { "type" => "string" },
    "artifacts" => { "type" => "array" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "workflow-runner" }
end

# Template 5: Code Quality & Security Scanner
Devops::ContainerTemplate.find_or_create_by!(name: "Code Quality & Security Scanner", account_id: nil) do |t|
  t.description = "Run linting (ESLint, Ruff, RuboCop), SAST scanning (Semgrep, Bandit), dependency audit, and complexity analysis."
  t.image_name = "python"
  t.image_tag = "3.12-slim"
  t.category = "security"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 300
  t.memory_mb = 1024
  t.cpu_millicores = 500
  t.sandbox_mode = true
  t.network_access = true
  t.allowed_egress_domains = ["pypi.org", "registry.npmjs.org", "github.com"]
  t.environment_variables = { "PYTHONUNBUFFERED" => "1" }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL to scan" },
    "branch" => { "type" => "string", "default" => "main", "description" => "Branch to scan" },
    "language" => { "type" => "string", "default" => "auto-detect", "description" => "Language: auto-detect, javascript, python, ruby" },
    "scan_types" => { "type" => "array", "default" => ["lint", "sast", "dependencies"], "description" => "Scan types: lint, sast, dependencies, complexity" }
  }
  t.output_schema = {
    "findings" => { "type" => "array" },
    "severity_counts" => { "type" => "object" },
    "score" => { "type" => "number" },
    "recommendations" => { "type" => "array" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "security" }
end

# Template 6: Database Migration Runner
Devops::ContainerTemplate.find_or_create_by!(name: "Database Migration Runner", account_id: nil) do |t|
  t.description = "Execute database migrations safely with dry-run, backup, and auto-rollback on failure."
  t.image_name = "postgres"
  t.image_tag = "16-alpine"
  t.category = "devops"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 300
  t.memory_mb = 512
  t.cpu_millicores = 500
  t.sandbox_mode = false
  t.network_access = true
  t.allowed_egress_domains = []
  t.environment_variables = {}
  t.input_schema = {
    "database_url" => { "type" => "string", "required" => true, "description" => "PostgreSQL connection string" },
    "migration_command" => { "type" => "string", "description" => "Migration command to run" },
    "direction" => { "type" => "string", "default" => "up", "description" => "Migration direction: up or down" },
    "dry_run" => { "type" => "boolean", "default" => false, "description" => "Preview changes without applying" },
    "backup_first" => { "type" => "boolean", "default" => true, "description" => "Create backup before migration" }
  }
  t.output_schema = {
    "migrations_run" => { "type" => "array" },
    "status" => { "type" => "string" },
    "backup_path" => { "type" => "string" },
    "rollback_performed" => { "type" => "boolean" },
    "duration_ms" => { "type" => "integer" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "database" }
end

# Template 7: API Integration Tester
Devops::ContainerTemplate.find_or_create_by!(name: "API Integration Tester", account_id: nil) do |t|
  t.description = "Run API endpoint tests with configurable requests, assertions, response validation, and load testing."
  t.image_name = "node"
  t.image_tag = "20-alpine"
  t.category = "testing"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 180
  t.memory_mb = 512
  t.cpu_millicores = 500
  t.sandbox_mode = true
  t.network_access = true
  t.allowed_egress_domains = []
  t.environment_variables = { "NODE_ENV" => "test" }
  t.input_schema = {
    "test_suite" => { "type" => "array", "required" => true, "description" => "JSON array of test case definitions" },
    "base_url" => { "type" => "string", "description" => "Base URL for all requests" },
    "auth_token" => { "type" => "string", "description" => "Authorization token" },
    "concurrency" => { "type" => "integer", "default" => 1, "description" => "Concurrent request count" },
    "iterations" => { "type" => "integer", "default" => 1, "description" => "Number of iterations per test" }
  }
  t.output_schema = {
    "results" => { "type" => "array" },
    "passed" => { "type" => "integer" },
    "failed" => { "type" => "integer" },
    "avg_latency_ms" => { "type" => "number" },
    "p95_latency_ms" => { "type" => "number" },
    "errors" => { "type" => "array" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "testing" }
end

# Template 8: Container Build & Registry Push
Devops::ContainerTemplate.find_or_create_by!(name: "Container Build & Registry Push", account_id: nil) do |t|
  t.description = "Build Docker image from Dockerfile, tag, and push to container registry (GHCR, Docker Hub, Gitea registry)."
  t.image_name = "docker"
  t.image_tag = "24-dind"
  t.category = "ci-cd"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 900
  t.memory_mb = 2048
  t.cpu_millicores = 2000
  t.sandbox_mode = false
  t.network_access = true
  t.allowed_egress_domains = []
  t.environment_variables = { "DOCKER_BUILDKIT" => "1" }
  t.input_schema = {
    "repo_url" => { "type" => "string", "required" => true, "description" => "Repository URL containing Dockerfile" },
    "dockerfile_path" => { "type" => "string", "default" => "Dockerfile", "description" => "Path to Dockerfile" },
    "registry_url" => { "type" => "string", "description" => "Container registry URL" },
    "image_name" => { "type" => "string", "required" => true, "description" => "Target image name" },
    "image_tag" => { "type" => "string", "default" => "latest", "description" => "Image tag" },
    "build_args" => { "type" => "object", "description" => "Docker build arguments" },
    "push" => { "type" => "boolean", "default" => true, "description" => "Push image to registry after build" }
  }
  t.output_schema = {
    "image_digest" => { "type" => "string" },
    "image_size" => { "type" => "string" },
    "build_duration_ms" => { "type" => "integer" },
    "push_status" => { "type" => "string" },
    "registry_url" => { "type" => "string" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "build" }
end

# Template 9: Infrastructure Health Monitor
Devops::ContainerTemplate.find_or_create_by!(name: "Infrastructure Health Monitor", account_id: nil) do |t|
  t.description = "Check health of services, ports, SSL certificates, DNS, and connectivity across infrastructure."
  t.image_name = "alpine"
  t.image_tag = "3.19"
  t.category = "monitoring"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 120
  t.memory_mb = 256
  t.cpu_millicores = 250
  t.sandbox_mode = true
  t.network_access = true
  t.allowed_egress_domains = []
  t.environment_variables = {}
  t.input_schema = {
    "targets" => { "type" => "array", "required" => true, "description" => "Array of URLs or host:port targets to check" },
    "check_type" => { "type" => "string", "default" => "http", "description" => "Check type: http, tcp, dns, ssl" },
    "timeout_per_check" => { "type" => "integer", "default" => 10, "description" => "Timeout per individual check in seconds" },
    "alert_webhook" => { "type" => "string", "description" => "Webhook URL to send alerts to" }
  }
  t.output_schema = {
    "results" => { "type" => "array" },
    "healthy_count" => { "type" => "integer" },
    "unhealthy_count" => { "type" => "integer" },
    "ssl_expiry_days" => { "type" => "object" },
    "response_times" => { "type" => "object" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "monitoring" }
end

# Template 10: Log Analyzer with AI
Devops::ContainerTemplate.find_or_create_by!(name: "Log Analyzer with AI", account_id: nil) do |t|
  t.description = "Analyze log files with pattern matching, anomaly detection, and AI-powered summarization."
  t.image_name = "python"
  t.image_tag = "3.12-slim"
  t.category = "data-processing"
  t.visibility = "public"
  t.status = "active"
  t.timeout_seconds = 180
  t.memory_mb = 1024
  t.cpu_millicores = 500
  t.sandbox_mode = true
  t.network_access = true
  t.allowed_egress_domains = ["api.openai.com", "api.anthropic.com"]
  t.environment_variables = { "PYTHONUNBUFFERED" => "1" }
  t.input_schema = {
    "log_source" => { "type" => "string", "required" => true, "description" => "Log source URL or path" },
    "analysis_type" => { "type" => "string", "default" => "all", "description" => "Analysis type: patterns, anomalies, summary, all" },
    "time_range" => { "type" => "string", "description" => "Time range filter (e.g., last 24h)" },
    "ai_model" => { "type" => "string", "description" => "AI model for summarization" }
  }
  t.output_schema = {
    "summary" => { "type" => "string" },
    "anomalies" => { "type" => "array" },
    "patterns" => { "type" => "array" },
    "error_rate" => { "type" => "number" },
    "recommendations" => { "type" => "array" }
  }
  t.labels = { "runner" => "powernode-ai-agent", "type" => "analysis" }
end

puts "  ✅ Created #{Devops::ContainerTemplate.system_templates.count} system container templates"
