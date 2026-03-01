# frozen_string_literal: true

# DevOps Pipeline Showcase Seeds
# Creates 5 realistic example pipelines that demonstrate platform capabilities:
# 1. AI Code Review Pipeline - Automated PR review with Claude
# 2. CI/CD Build & Deploy - Full build, test, deploy workflow
# 3. Security Scanning Pipeline - AI-powered security analysis
# 4. Issue Implementation Pipeline - Automated issue to PR workflow
# 5. Release Automation Pipeline - Versioning and release process

puts "\n" + '=' * 80
puts 'DEVOPS PIPELINE SHOWCASE - Creating Example Pipelines'
puts '=' * 80

# Find admin account and user
account = Account.find_by(subdomain: 'admin') || Account.first
unless account
  puts '  Error: Admin account not found. Run main seeds first.'
  return
end

user = account.users.joins(:roles).where(roles: { name: 'super_admin' }).first ||
       account.users.first
unless user
  puts '  Error: Admin user not found. Run main seeds first.'
  return
end

puts "Using admin account: #{account.name} (#{user.email})"

# Find or create AI Provider for Claude-powered steps
ai_provider = account.ai_providers.find_by(provider_type: 'anthropic') ||
              account.ai_providers.first

unless ai_provider
  puts '  Warning: No AI provider found - AI-powered steps will use placeholder'
end

# Find or create Git Provider
git_provider = account.devops_providers.find_or_create_by!(name: 'GitHub') do |p|
  p.provider_type = 'github'
  p.base_url = 'https://api.github.com'
  p.api_version = 'v3'
  p.is_active = true
  p.is_default = true
  p.health_status = 'healthy'
  p.capabilities = %w[repositories pipelines webhooks pull_requests issues releases]
end

puts "Using Git Provider: #{git_provider.name}"

# Find or create prompt templates for AI steps
# Valid categories: review, implement, security, deploy, docs, custom, general, agent, workflow
def find_or_create_prompt_template(account, name, category, content, variables = {})
  Shared::PromptTemplate.find_or_create_by!(account: account, name: name) do |pt|
    pt.category = category
    pt.content = content
    pt.variables = variables
    pt.is_active = true
    pt.is_system = true
    pt.version = 1
  end
end

code_review_prompt = find_or_create_prompt_template(
  account,
  'AI Code Review',
  'review',
  <<~'PROMPT',
    Review the following code changes for:
    1. Code quality and best practices
    2. Potential bugs or issues
    3. Performance concerns
    4. Security vulnerabilities
    5. Documentation completeness

    Repository: {{repository}}
    Pull Request: #{{pr_number}}
    Changed Files: {{changed_files}}

    Provide structured feedback with severity levels (critical/high/medium/low).
  PROMPT
  { 'repository' => 'string', 'pr_number' => 'number', 'changed_files' => 'array' }
)

security_scan_prompt = find_or_create_prompt_template(
  account,
  'Security Vulnerability Scan',
  'security',
  <<~'PROMPT',
    Perform a comprehensive security analysis of the code changes:

    1. OWASP Top 10 vulnerabilities
    2. Dependency vulnerabilities
    3. Secrets/credentials exposure
    4. Input validation issues
    5. Authentication/authorization flaws

    Repository: {{repository}}
    Branch: {{branch}}

    Output a structured security report with CVE references where applicable.
  PROMPT
  { 'repository' => 'string', 'branch' => 'string' }
)

implementation_prompt = find_or_create_prompt_template(
  account,
  'Issue Implementation',
  'implement',
  <<~'PROMPT',
    Implement the following issue:

    Issue #{{issue_number}}: {{issue_title}}
    Description: {{issue_body}}

    Repository context: {{repository}}
    Target branch: {{target_branch}}

    Generate the necessary code changes following the project's coding standards.
  PROMPT
  { 'issue_number' => 'number', 'issue_title' => 'string', 'issue_body' => 'string',
    'repository' => 'string', 'target_branch' => 'string' }
)

test_generation_prompt = find_or_create_prompt_template(
  account,
  'AI Test Generation',
  'implement',
  <<~'PROMPT',
    Generate comprehensive unit tests for the following code changes:

    {{changes}}

    Requirements:
    1. Test all public functions and methods
    2. Include edge cases and error scenarios
    3. Use the project's existing test framework and patterns
    4. Ensure good code coverage

    Output the test files with proper imports and test structure.
  PROMPT
  { 'changes' => 'array' }
)

puts "Created/found prompt templates"

# =============================================================================
# PIPELINE 1: AI CODE REVIEW PIPELINE
# Demonstrates: PR triggers, AI analysis, comment posting, approval gates
# =============================================================================

puts "\n" + '-' * 60
puts '1. AI CODE REVIEW PIPELINE'
puts '-' * 60

review_pipeline = Devops::Pipeline.find_or_create_by!(
  account: account,
  name: 'AI Code Review Pipeline'
) do |p|
  p.slug = 'ai-code-review'
  p.pipeline_type = 'review'
  p.created_by = user
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.is_system = false
  p.allow_concurrent = true
  p.timeout_minutes = 30
  p.version = 1
  p.environment = 'review'
  p.triggers = {
    'pull_request' => {
      'enabled' => true,
      'events' => %w[opened synchronize reopened],
      'branches' => [ 'main', 'develop', 'release/*' ]
    }
  }
  p.features = {
    'ai_review' => true,
    'auto_approve' => false,
    'security_scan' => true
  }
  p.notification_settings = {
    'on_success' => true,
    'on_failure' => true,
    'channels' => [ 'slack', 'email' ]
  }
end

# Clear existing steps for clean recreation
review_pipeline.pipeline_steps.destroy_all

# Create pipeline steps
review_steps = [
  {
    name: 'Checkout Code',
    position: 1,
    step_type: 'checkout',
    inputs: { 'ref' => '{{trigger.sha}}', 'depth' => 1 },
    outputs: { 'workspace' => 'string' }
  },
  {
    name: 'AI Code Analysis',
    position: 2,
    step_type: 'claude_execute',
    prompt_template: code_review_prompt,
    inputs: {
      'repository' => '{{trigger.repository}}',
      'pr_number' => '{{trigger.pr_number}}',
      'changed_files' => '{{trigger.changed_files}}'
    },
    outputs: { 'review_comments' => 'array', 'severity_summary' => 'object', 'approval_recommendation' => 'string' }
  },
  {
    name: 'Security Check',
    position: 3,
    step_type: 'claude_execute',
    prompt_template: security_scan_prompt,
    inputs: {
      'repository' => '{{trigger.repository}}',
      'branch' => '{{trigger.branch}}'
    },
    outputs: { 'vulnerabilities' => 'array', 'security_score' => 'number' },
    condition: "steps.ai_code_analysis.outputs.severity_summary.critical == 0"
  },
  {
    name: 'Post Review Comments',
    position: 4,
    step_type: 'post_comment',
    inputs: {
      'pr_number' => '{{trigger.pr_number}}',
      'comments' => '{{steps.ai_code_analysis.outputs.review_comments}}',
      'summary' => '{{steps.security_check.outputs.security_score}}'
    },
    outputs: { 'comment_ids' => 'array' }
  },
  {
    name: 'Approval Gate',
    position: 5,
    step_type: 'custom',
    requires_approval: true,
    approval_settings: {
      'required_approvers' => 1,
      'timeout_hours' => 24,
      'auto_approve_if' => 'steps.ai_code_analysis.outputs.approval_recommendation == "approve"'
    },
    condition: "steps.security_check.outputs.security_score >= 80",
    inputs: { 'review_result' => '{{steps.ai_code_analysis.outputs}}' },
    outputs: { 'approved' => 'boolean', 'approver' => 'string' }
  },
  {
    name: 'Notify Team',
    position: 6,
    step_type: 'notify',
    inputs: {
      'channel' => 'slack',
      'message' => 'PR #' + '{{trigger.pr_number}} review complete. Score: {{steps.security_check.outputs.security_score}}/100',
      'status' => '{{pipeline.status}}'
    },
    outputs: { 'notification_sent' => 'boolean' }
  }
]

review_steps.each do |step_data|
  review_pipeline.pipeline_steps.create!(
    name: step_data[:name],
    position: step_data[:position],
    step_type: step_data[:step_type],
    shared_prompt_template: step_data[:prompt_template],
    inputs: step_data[:inputs] || {},
    outputs: step_data[:outputs] || {},
    condition: step_data[:condition],
    requires_approval: step_data[:requires_approval] || false,
    approval_settings: step_data[:approval_settings] || {},
    is_active: true,
    configuration: { 'timeout_seconds' => 300, 'retry_policy' => { 'max_attempts' => 2, 'backoff' => 'exponential' } }
  )
end

puts "Created AI Code Review Pipeline (#{review_pipeline.pipeline_steps.count} steps)"

# =============================================================================
# PIPELINE 2: CI/CD BUILD & DEPLOY PIPELINE
# Demonstrates: Full workflow, artifacts, tests, deployment, environments
# =============================================================================

puts "\n" + '-' * 60
puts '2. CI/CD BUILD & DEPLOY PIPELINE'
puts '-' * 60

cicd_pipeline = Devops::Pipeline.find_or_create_by!(
  account: account,
  name: 'CI/CD Build & Deploy'
) do |p|
  p.slug = 'cicd-build-deploy'
  p.pipeline_type = 'deploy'
  p.created_by = user
  p.provider = git_provider
  p.is_active = true
  p.is_system = false
  p.allow_concurrent = false
  p.timeout_minutes = 60
  p.version = 1
  p.environment = 'production'
  p.triggers = {
    'push' => {
      'enabled' => true,
      'branches' => [ 'main' ]
    },
    'manual' => {
      'enabled' => true,
      'inputs' => {
        'environment' => { 'type' => 'select', 'options' => %w[staging production], 'default' => 'staging' },
        'skip_tests' => { 'type' => 'boolean', 'default' => false }
      }
    }
  }
  p.features = {
    'build_cache' => true,
    'parallel_tests' => true,
    'blue_green_deploy' => true
  }
  p.runner_labels = [ 'linux', 'docker' ]
  p.notification_settings = {
    'on_success' => true,
    'on_failure' => true,
    'channels' => [ 'slack' ]
  }
end

cicd_pipeline.pipeline_steps.destroy_all

cicd_steps = [
  {
    name: 'Checkout',
    position: 1,
    step_type: 'checkout',
    inputs: { 'ref' => '{{trigger.sha}}', 'fetch_depth' => 0 },
    outputs: { 'workspace' => 'string', 'commit_sha' => 'string' }
  },
  {
    name: 'Install Dependencies',
    position: 2,
    step_type: 'custom',
    inputs: {
      'command' => 'npm ci --prefer-offline',
      'cache_key' => 'node-modules-{{hashFiles("package-lock.json")}}'
    },
    outputs: { 'cache_hit' => 'boolean' }
  },
  {
    name: 'Run Linting',
    position: 3,
    step_type: 'custom',
    inputs: { 'command' => 'npm run lint' },
    outputs: { 'lint_errors' => 'number' }
  },
  {
    name: 'Run Unit Tests',
    position: 4,
    step_type: 'run_tests',
    condition: "inputs.skip_tests != true",
    inputs: {
      'command' => 'npm run test:unit -- --coverage',
      'coverage_threshold' => 80
    },
    outputs: { 'test_results' => 'object', 'coverage_percent' => 'number' }
  },
  {
    name: 'Run Integration Tests',
    position: 5,
    step_type: 'run_tests',
    condition: "inputs.skip_tests != true && inputs.environment == 'production'",
    inputs: { 'command' => 'npm run test:integration' },
    outputs: { 'test_results' => 'object' }
  },
  {
    name: 'Build Application',
    position: 6,
    step_type: 'custom',
    inputs: {
      'command' => 'npm run build',
      'env' => { 'NODE_ENV' => 'production' }
    },
    outputs: { 'build_path' => 'string', 'build_size' => 'number' }
  },
  {
    name: 'Upload Build Artifacts',
    position: 7,
    step_type: 'upload_artifact',
    inputs: {
      'name' => 'build-{{trigger.sha}}',
      'path' => '{{steps.build_application.outputs.build_path}}',
      'retention_days' => 30
    },
    outputs: { 'artifact_id' => 'string', 'artifact_url' => 'string' }
  },
  {
    name: 'Deploy to Staging',
    position: 8,
    step_type: 'deploy',
    condition: "inputs.environment == 'staging' || inputs.environment == 'production'",
    inputs: {
      'environment' => 'staging',
      'artifact' => '{{steps.upload_build_artifacts.outputs.artifact_id}}',
      'strategy' => 'rolling'
    },
    outputs: { 'deployment_id' => 'string', 'url' => 'string' }
  },
  {
    name: 'Run Smoke Tests',
    position: 9,
    step_type: 'run_tests',
    inputs: {
      'command' => 'npm run test:smoke',
      'target_url' => '{{steps.deploy_to_staging.outputs.url}}'
    },
    outputs: { 'smoke_passed' => 'boolean' }
  },
  {
    name: 'Production Approval',
    position: 10,
    step_type: 'custom',
    requires_approval: true,
    condition: "inputs.environment == 'production'",
    approval_settings: {
      'required_approvers' => 2,
      'timeout_hours' => 4,
      'notify' => [ 'devops-team', 'tech-lead' ]
    },
    inputs: { 'staging_url' => '{{steps.deploy_to_staging.outputs.url}}' },
    outputs: { 'approved' => 'boolean' }
  },
  {
    name: 'Deploy to Production',
    position: 11,
    step_type: 'deploy',
    condition: "inputs.environment == 'production' && steps.production_approval.outputs.approved == true",
    inputs: {
      'environment' => 'production',
      'artifact' => '{{steps.upload_build_artifacts.outputs.artifact_id}}',
      'strategy' => 'blue_green',
      'rollback_on_failure' => true
    },
    outputs: { 'deployment_id' => 'string', 'url' => 'string', 'previous_version' => 'string' }
  },
  {
    name: 'Notify Deployment',
    position: 12,
    step_type: 'notify',
    inputs: {
      'channel' => 'slack',
      'message' => 'Deployed {{trigger.sha}} to {{inputs.environment}}. URL: {{steps.deploy_to_production.outputs.url || steps.deploy_to_staging.outputs.url}}'
    },
    outputs: { 'sent' => 'boolean' }
  }
]

cicd_steps.each do |step_data|
  cicd_pipeline.pipeline_steps.create!(
    name: step_data[:name],
    position: step_data[:position],
    step_type: step_data[:step_type],
    inputs: step_data[:inputs] || {},
    outputs: step_data[:outputs] || {},
    condition: step_data[:condition],
    requires_approval: step_data[:requires_approval] || false,
    approval_settings: step_data[:approval_settings] || {},
    is_active: true,
    configuration: { 'timeout_seconds' => (step_data[:step_type] == 'deploy' ? 600 : 300), 'retry_policy' => { 'max_attempts' => 3, 'backoff' => 'exponential' } }
  )
end

puts "Created CI/CD Build & Deploy Pipeline (#{cicd_pipeline.pipeline_steps.count} steps)"

# =============================================================================
# PIPELINE 3: SECURITY SCANNING PIPELINE
# Demonstrates: Scheduled runs, comprehensive security analysis, reporting
# =============================================================================

puts "\n" + '-' * 60
puts '3. SECURITY SCANNING PIPELINE'
puts '-' * 60

security_pipeline = Devops::Pipeline.find_or_create_by!(
  account: account,
  name: 'Security Scanning Pipeline'
) do |p|
  p.slug = 'security-scanning'
  p.pipeline_type = 'security'
  p.created_by = user
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.is_system = false
  p.allow_concurrent = false
  p.timeout_minutes = 45
  p.version = 1
  p.environment = 'security'
  p.triggers = {
    'schedule' => {
      'enabled' => true,
      'cron' => '0 2 * * *',
      'timezone' => 'UTC'
    },
    'pull_request' => {
      'enabled' => true,
      'events' => [ 'opened', 'synchronize' ]
    },
    'manual' => {
      'enabled' => true,
      'inputs' => {
        'scan_type' => { 'type' => 'select', 'options' => %w[quick full deep], 'default' => 'full' },
        'branch' => { 'type' => 'string', 'default' => 'main' }
      }
    }
  }
  p.features = {
    'sast' => true,
    'dast' => true,
    'dependency_scan' => true,
    'secret_detection' => true,
    'container_scan' => true
  }
  p.notification_settings = {
    'on_critical' => true,
    'on_high' => true,
    'channels' => [ 'security-team', 'slack' ]
  }
end

security_pipeline.pipeline_steps.destroy_all

security_steps = [
  {
    name: 'Checkout Repository',
    position: 1,
    step_type: 'checkout',
    inputs: { 'ref' => '{{inputs.branch || trigger.sha}}', 'depth' => 0 },
    outputs: { 'workspace' => 'string' }
  },
  {
    name: 'Dependency Vulnerability Scan',
    position: 2,
    step_type: 'custom',
    inputs: {
      'command' => 'npm audit --json > audit-report.json && snyk test --json > snyk-report.json',
      'continue_on_error' => true
    },
    outputs: { 'vulnerabilities' => 'array', 'critical_count' => 'number', 'high_count' => 'number' }
  },
  {
    name: 'Secret Detection',
    position: 3,
    step_type: 'custom',
    inputs: {
      'command' => 'trufflehog filesystem . --json > secrets-report.json',
      'excluded_paths' => [ 'node_modules', '.git', 'dist' ]
    },
    outputs: { 'secrets_found' => 'array', 'secrets_count' => 'number' }
  },
  {
    name: 'SAST Analysis',
    position: 4,
    step_type: 'custom',
    inputs: {
      'command' => 'semgrep --config auto --json > sast-report.json',
      'rules' => [ 'security', 'best-practices' ]
    },
    outputs: { 'findings' => 'array', 'severity_breakdown' => 'object' }
  },
  {
    name: 'AI Security Review',
    position: 5,
    step_type: 'claude_execute',
    prompt_template: security_scan_prompt,
    inputs: {
      'repository' => '{{trigger.repository}}',
      'branch' => '{{inputs.branch || trigger.branch}}',
      'scan_results' => {
        'dependencies' => '{{steps.dependency_vulnerability_scan.outputs}}',
        'secrets' => '{{steps.secret_detection.outputs}}',
        'sast' => '{{steps.sast_analysis.outputs}}'
      }
    },
    outputs: { 'ai_analysis' => 'object', 'risk_score' => 'number', 'recommendations' => 'array' }
  },
  {
    name: 'Container Image Scan',
    position: 6,
    step_type: 'custom',
    condition: "inputs.scan_type == 'full' || inputs.scan_type == 'deep'",
    inputs: {
      'command' => 'trivy image --format json --output container-report.json {{docker_image}}',
      'severity' => 'CRITICAL,HIGH'
    },
    outputs: { 'container_vulnerabilities' => 'array' }
  },
  {
    name: 'Generate Security Report',
    position: 7,
    step_type: 'custom',
    inputs: {
      'template' => 'security-report',
      'data' => {
        'dependency_scan' => '{{steps.dependency_vulnerability_scan.outputs}}',
        'secrets' => '{{steps.secret_detection.outputs}}',
        'sast' => '{{steps.sast_analysis.outputs}}',
        'ai_analysis' => '{{steps.ai_security_review.outputs}}',
        'container' => '{{steps.container_image_scan.outputs}}'
      }
    },
    outputs: { 'report_url' => 'string', 'summary' => 'object' }
  },
  {
    name: 'Upload Security Report',
    position: 8,
    step_type: 'upload_artifact',
    inputs: {
      'name' => 'security-report-{{trigger.sha}}-{{timestamp}}',
      'path' => './security-reports/',
      'retention_days' => 90
    },
    outputs: { 'artifact_id' => 'string' }
  },
  {
    name: 'Notify Security Team',
    position: 9,
    step_type: 'notify',
    condition: "steps.ai_security_review.outputs.risk_score < 70 || steps.dependency_vulnerability_scan.outputs.critical_count > 0",
    inputs: {
      'channel' => 'security-team',
      'priority' => 'high',
      'message' => 'Security scan completed with risk score: {{steps.ai_security_review.outputs.risk_score}}/100. Critical issues: {{steps.dependency_vulnerability_scan.outputs.critical_count}}',
      'report_link' => '{{steps.generate_security_report.outputs.report_url}}'
    },
    outputs: { 'notified' => 'boolean' }
  },
  {
    name: 'Block PR on Critical',
    position: 10,
    step_type: 'post_comment',
    condition: "trigger.type == 'pull_request' && steps.dependency_vulnerability_scan.outputs.critical_count > 0",
    inputs: {
      'pr_number' => '{{trigger.pr_number}}',
      'comment' => 'Security scan found {{steps.dependency_vulnerability_scan.outputs.critical_count}} critical vulnerabilities. Please address before merging.',
      'block_merge' => true
    },
    outputs: { 'blocked' => 'boolean' }
  }
]

security_steps.each do |step_data|
  security_pipeline.pipeline_steps.create!(
    name: step_data[:name],
    position: step_data[:position],
    step_type: step_data[:step_type],
    shared_prompt_template: step_data[:prompt_template],
    inputs: step_data[:inputs] || {},
    outputs: step_data[:outputs] || {},
    condition: step_data[:condition],
    requires_approval: step_data[:requires_approval] || false,
    is_active: true,
    configuration: { 'timeout_seconds' => 600, 'retry_policy' => { 'max_attempts' => 2, 'backoff' => 'linear' } }
  )
end

# Create schedule for nightly scans
security_pipeline.schedules.find_or_create_by!(name: 'Nightly Security Scan') do |s|
  s.cron_expression = '0 2 * * *'
  s.timezone = 'UTC'
  s.is_active = true
  s.inputs = { 'scan_type' => 'full', 'branch' => 'main' }
  s.created_by = user
end

puts "Created Security Scanning Pipeline (#{security_pipeline.pipeline_steps.count} steps, 1 schedule)"

# =============================================================================
# PIPELINE 4: ISSUE IMPLEMENTATION PIPELINE
# Demonstrates: Issue triggers, AI implementation, branch/PR creation
# =============================================================================

puts "\n" + '-' * 60
puts '4. ISSUE IMPLEMENTATION PIPELINE'
puts '-' * 60

issue_pipeline = Devops::Pipeline.find_or_create_by!(
  account: account,
  name: 'AI Issue Implementation'
) do |p|
  p.slug = 'ai-issue-implementation'
  p.pipeline_type = 'implement'
  p.created_by = user
  p.provider = git_provider
  p.ai_provider = ai_provider
  p.is_active = true
  p.is_system = false
  p.allow_concurrent = true
  p.timeout_minutes = 45
  p.version = 1
  p.environment = 'development'
  p.triggers = {
    'issue' => {
      'enabled' => true,
      'events' => [ 'labeled' ],
      'labels' => [ 'ai-implement', 'auto-fix' ]
    },
    'issue_comment' => {
      'enabled' => true,
      'pattern' => '/implement'
    },
    'manual' => {
      'enabled' => true,
      'inputs' => {
        'issue_number' => { 'type' => 'number', 'required' => true },
        'target_branch' => { 'type' => 'string', 'default' => 'develop' }
      }
    }
  }
  p.features = {
    'ai_implementation' => true,
    'auto_tests' => true,
    'auto_pr' => true,
    'ai_model' => 'claude-sonnet-4-5-20250514',
    'ai_temperature' => 0.3,
    'ai_max_tokens' => 8000
  }
end

issue_pipeline.pipeline_steps.destroy_all

issue_steps = [
  {
    name: 'Checkout Repository',
    position: 1,
    step_type: 'checkout',
    inputs: { 'ref' => '{{inputs.target_branch || "develop"}}' },
    outputs: { 'workspace' => 'string' }
  },
  {
    name: 'Fetch Issue Details',
    position: 2,
    step_type: 'custom',
    inputs: {
      'api_call' => 'GET /repos/{{trigger.repository}}/issues/{{trigger.issue_number || inputs.issue_number}}',
      'parse_response' => true
    },
    outputs: { 'issue_title' => 'string', 'issue_body' => 'string', 'labels' => 'array' }
  },
  {
    name: 'Create Feature Branch',
    position: 3,
    step_type: 'create_branch',
    inputs: {
      'branch_name' => 'ai/issue-{{trigger.issue_number || inputs.issue_number}}-{{slugify(steps.fetch_issue_details.outputs.issue_title)}}',
      'base_branch' => '{{inputs.target_branch || "develop"}}'
    },
    outputs: { 'branch_name' => 'string', 'branch_sha' => 'string' }
  },
  {
    name: 'AI Implementation',
    position: 4,
    step_type: 'claude_execute',
    prompt_template: implementation_prompt,
    inputs: {
      'issue_number' => '{{trigger.issue_number || inputs.issue_number}}',
      'issue_title' => '{{steps.fetch_issue_details.outputs.issue_title}}',
      'issue_body' => '{{steps.fetch_issue_details.outputs.issue_body}}',
      'repository' => '{{trigger.repository}}',
      'target_branch' => '{{steps.create_feature_branch.outputs.branch_name}}'
    },
    outputs: { 'changes' => 'array', 'files_modified' => 'array', 'implementation_summary' => 'string' }
  },
  {
    name: 'Apply Code Changes',
    position: 5,
    step_type: 'custom',
    inputs: {
      'changes' => '{{steps.ai_implementation.outputs.changes}}',
      'commit_message' => 'feat: implement #' + '{{trigger.issue_number || inputs.issue_number}} - {{steps.fetch_issue_details.outputs.issue_title}}'
    },
    outputs: { 'commit_sha' => 'string', 'files_changed' => 'number' }
  },
  {
    name: 'Generate Tests',
    position: 6,
    step_type: 'claude_execute',
    prompt_template: test_generation_prompt,
    inputs: {
      'changes' => '{{steps.ai_implementation.outputs.changes}}',
      'output_format' => 'code'
    },
    outputs: { 'test_files' => 'array' }
  },
  {
    name: 'Run Tests',
    position: 7,
    step_type: 'run_tests',
    inputs: { 'command' => 'npm run test -- --coverage' },
    outputs: { 'passed' => 'boolean', 'coverage' => 'number' }
  },
  {
    name: 'Create Pull Request',
    position: 8,
    step_type: 'create_pr',
    condition: "steps.run_tests.outputs.passed == true",
    inputs: {
      'title' => 'feat: #' + '{{trigger.issue_number || inputs.issue_number}} - {{steps.fetch_issue_details.outputs.issue_title}}',
      'body' => '## Summary\n{{steps.ai_implementation.outputs.implementation_summary}}\n\n## Changes\n{{steps.ai_implementation.outputs.files_modified}}\n\nCloses #' + '{{trigger.issue_number || inputs.issue_number}}\n\n---\n*This PR was automatically generated by AI.*',
      'head' => '{{steps.create_feature_branch.outputs.branch_name}}',
      'base' => '{{inputs.target_branch || "develop"}}',
      'draft' => false,
      'labels' => [ 'ai-generated', 'auto-review' ]
    },
    outputs: { 'pr_number' => 'number', 'pr_url' => 'string' }
  },
  {
    name: 'Link Issue to PR',
    position: 9,
    step_type: 'post_comment',
    inputs: {
      'issue_number' => '{{trigger.issue_number || inputs.issue_number}}',
      'comment' => 'AI implementation complete! See PR #' + '{{steps.create_pull_request.outputs.pr_number}} for the proposed changes.'
    },
    outputs: { 'comment_id' => 'string' }
  },
  {
    name: 'Notify on Failure',
    position: 10,
    step_type: 'notify',
    condition: "steps.run_tests.outputs.passed != true",
    inputs: {
      'channel' => 'slack',
      'message' => 'AI implementation for issue #' + '{{trigger.issue_number || inputs.issue_number}} failed tests. Manual intervention required.'
    },
    outputs: { 'sent' => 'boolean' }
  }
]

issue_steps.each do |step_data|
  issue_pipeline.pipeline_steps.create!(
    name: step_data[:name],
    position: step_data[:position],
    step_type: step_data[:step_type],
    shared_prompt_template: step_data[:prompt_template],
    inputs: step_data[:inputs] || {},
    outputs: step_data[:outputs] || {},
    condition: step_data[:condition],
    is_active: true,
    configuration: { 'timeout_seconds' => (step_data[:step_type] == 'claude_execute' ? 900 : 300), 'retry_policy' => { 'max_attempts' => 2 } }
  )
end

puts "Created AI Issue Implementation Pipeline (#{issue_pipeline.pipeline_steps.count} steps)"

# =============================================================================
# PIPELINE 5: RELEASE AUTOMATION PIPELINE
# Demonstrates: Release triggers, versioning, changelog, deployment
# =============================================================================

puts "\n" + '-' * 60
puts '5. RELEASE AUTOMATION PIPELINE'
puts '-' * 60

release_pipeline = Devops::Pipeline.find_or_create_by!(
  account: account,
  name: 'Release Automation Pipeline'
) do |p|
  p.slug = 'release-automation'
  p.pipeline_type = 'deploy'
  p.created_by = user
  p.provider = git_provider
  p.is_active = true
  p.is_system = false
  p.allow_concurrent = false
  p.timeout_minutes = 90
  p.version = 1
  p.environment = 'release'
  p.triggers = {
    'push' => {
      'enabled' => true,
      'tags' => [ 'v*.*.*' ]
    },
    'manual' => {
      'enabled' => true,
      'inputs' => {
        'version' => { 'type' => 'string', 'required' => true, 'pattern' => '^[0-9]+\\.[0-9]+\\.[0-9]+$' },
        'release_type' => { 'type' => 'select', 'options' => %w[major minor patch], 'default' => 'patch' },
        'prerelease' => { 'type' => 'boolean', 'default' => false }
      }
    }
  }
  p.features = {
    'semantic_versioning' => true,
    'auto_changelog' => true,
    'github_release' => true,
    'npm_publish' => true,
    'docker_publish' => true
  }
  p.notification_settings = {
    'on_success' => true,
    'on_failure' => true,
    'channels' => [ 'releases', 'slack' ]
  }
end

release_pipeline.pipeline_steps.destroy_all

release_steps = [
  {
    name: 'Checkout',
    position: 1,
    step_type: 'checkout',
    inputs: { 'ref' => '{{trigger.ref || "main"}}', 'fetch_depth' => 0, 'fetch_tags' => true },
    outputs: { 'workspace' => 'string' }
  },
  {
    name: 'Determine Version',
    position: 2,
    step_type: 'custom',
    inputs: {
      'command' => 'git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0"',
      'new_version' => '{{inputs.version || trigger.tag}}'
    },
    outputs: { 'current_version' => 'string', 'new_version' => 'string' }
  },
  {
    name: 'Generate Changelog',
    position: 3,
    step_type: 'custom',
    inputs: {
      'command' => 'git log {{steps.determine_version.outputs.current_version}}..HEAD --pretty=format:"- %s (%h)" --no-merges',
      'output_file' => 'CHANGELOG_ENTRY.md'
    },
    outputs: { 'changelog' => 'string', 'commit_count' => 'number' }
  },
  {
    name: 'Update Package Version',
    position: 4,
    step_type: 'custom',
    inputs: {
      'command' => 'npm version {{steps.determine_version.outputs.new_version}} --no-git-tag-version',
      'files' => [ 'package.json', 'package-lock.json' ]
    },
    outputs: { 'updated_files' => 'array' }
  },
  {
    name: 'Build Release',
    position: 5,
    step_type: 'custom',
    inputs: {
      'command' => 'npm run build:production',
      'env' => { 'VERSION' => '{{steps.determine_version.outputs.new_version}}' }
    },
    outputs: { 'build_path' => 'string' }
  },
  {
    name: 'Run Release Tests',
    position: 6,
    step_type: 'run_tests',
    inputs: { 'command' => 'npm run test:release' },
    outputs: { 'passed' => 'boolean' }
  },
  {
    name: 'Build Docker Image',
    position: 7,
    step_type: 'custom',
    inputs: {
      'command' => 'docker build -t {{docker_registry}}/{{app_name}}:{{steps.determine_version.outputs.new_version}} .',
      'tags' => [ '{{steps.determine_version.outputs.new_version}}', 'latest' ]
    },
    outputs: { 'image_tag' => 'string', 'image_digest' => 'string' }
  },
  {
    name: 'Push Docker Image',
    position: 8,
    step_type: 'custom',
    inputs: {
      'command' => 'docker push {{docker_registry}}/{{app_name}}:{{steps.determine_version.outputs.new_version}}'
    },
    outputs: { 'pushed' => 'boolean' }
  },
  {
    name: 'Publish to NPM',
    position: 9,
    step_type: 'custom',
    condition: "features.npm_publish == true",
    inputs: {
      'command' => 'npm publish --access public',
      'registry' => 'https://registry.npmjs.org'
    },
    outputs: { 'published' => 'boolean', 'package_url' => 'string' }
  },
  {
    name: 'Create GitHub Release',
    position: 10,
    step_type: 'custom',
    inputs: {
      'api_call' => 'POST /repos/{{trigger.repository}}/releases',
      'body' => {
        'tag_name' => 'v{{steps.determine_version.outputs.new_version}}',
        'name' => 'Release v{{steps.determine_version.outputs.new_version}}',
        'body' => '{{steps.generate_changelog.outputs.changelog}}',
        'prerelease' => '{{inputs.prerelease || false}}',
        'generate_release_notes' => true
      }
    },
    outputs: { 'release_id' => 'string', 'release_url' => 'string' }
  },
  {
    name: 'Upload Release Artifacts',
    position: 11,
    step_type: 'upload_artifact',
    inputs: {
      'release_id' => '{{steps.create_github_release.outputs.release_id}}',
      'files' => [ 'dist/*.zip', 'dist/*.tar.gz' ]
    },
    outputs: { 'uploaded_files' => 'array' }
  },
  {
    name: 'Deploy to Production',
    position: 12,
    step_type: 'deploy',
    requires_approval: true,
    approval_settings: {
      'required_approvers' => 2,
      'timeout_hours' => 8,
      'notify' => [ 'release-managers' ]
    },
    inputs: {
      'environment' => 'production',
      'image' => '{{steps.build_docker_image.outputs.image_tag}}',
      'strategy' => 'blue_green',
      'health_check_path' => '/health'
    },
    outputs: { 'deployment_id' => 'string', 'url' => 'string' }
  },
  {
    name: 'Notify Release Complete',
    position: 13,
    step_type: 'notify',
    inputs: {
      'channels' => [ 'releases', 'slack', 'email' ],
      'message' => 'Release v{{steps.determine_version.outputs.new_version}} deployed successfully!\n\nChanges:\n{{steps.generate_changelog.outputs.changelog}}\n\nRelease: {{steps.create_github_release.outputs.release_url}}',
      'priority' => 'normal'
    },
    outputs: { 'notified' => 'boolean' }
  }
]

release_steps.each do |step_data|
  release_pipeline.pipeline_steps.create!(
    name: step_data[:name],
    position: step_data[:position],
    step_type: step_data[:step_type],
    inputs: step_data[:inputs] || {},
    outputs: step_data[:outputs] || {},
    condition: step_data[:condition],
    requires_approval: step_data[:requires_approval] || false,
    approval_settings: step_data[:approval_settings] || {},
    is_active: true,
    configuration: { 'timeout_seconds' => 600, 'retry_policy' => { 'max_attempts' => 2 } }
  )
end

puts "Created Release Automation Pipeline (#{release_pipeline.pipeline_steps.count} steps)"

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + '=' * 80
puts 'DEVOPS PIPELINE SHOWCASE - COMPLETE'
puts '=' * 80

puts "\n  Summary:"
puts "   Total Pipelines: 5"
puts "   Total Steps: #{Devops::Pipeline.where(account: account, name: [
  'AI Code Review Pipeline',
  'CI/CD Build & Deploy',
  'Security Scanning Pipeline',
  'AI Issue Implementation',
  'Release Automation Pipeline'
]).joins(:steps).count}"

puts "\n  Pipelines Created:"

[
  [ review_pipeline, 'AI-powered code review on PRs', 'PR triggers, AI analysis, approval gates' ],
  [ cicd_pipeline, 'Full build, test, deploy workflow', 'Artifacts, multi-environment, blue-green deploy' ],
  [ security_pipeline, 'Comprehensive security scanning', 'SAST, dependency scan, AI analysis, scheduled' ],
  [ issue_pipeline, 'Automated issue to PR workflow', 'Issue triggers, AI implementation, auto-PR' ],
  [ release_pipeline, 'Versioning and release process', 'Changelog, Docker, NPM, GitHub releases' ]
].each_with_index do |(pipeline, purpose, features), i|
  puts "\n   #{i + 1}. #{pipeline.name}"
  puts "      Purpose: #{purpose}"
  puts "      Features: #{features}"
  puts "      Steps: #{pipeline.pipeline_steps.count}"
end

puts "\n  Step Types Demonstrated:"
puts "     checkout, claude_execute, post_comment, custom"
puts "     create_branch, create_pr, upload_artifact, download_artifact"
puts "     run_tests, deploy, notify"

puts "\n  Trigger Types Demonstrated:"
puts "     pull_request, push, issue, issue_comment"
puts "     schedule, manual, release/tags"

puts "\n" + '=' * 80
