# frozen_string_literal: true

# AI DevOps Configs Seed
# Installs 5 DevOps templates and creates 4 AI model configurations for pipelines

puts "\n🔧 Seeding AI DevOps Configs (Template Installations + AI Configs)..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping AI DevOps configs"
  return
end

puts "  ✅ Using account: #{admin_account.name}"

# ---------------------------------------------------------------------------
# Template Installations (5 of 10 existing templates)
# ---------------------------------------------------------------------------
puts "\n  📦 Installing DevOps templates..."

template_configs = [
  {
    slug: 'automated-code-review',
    variable_values: { 'review_language' => 'en', 'max_findings' => '30' },
    custom_config: {
      'notifications' => { 'slack_channel' => '#code-reviews', 'email_on_critical' => true },
      'targets' => { 'branches' => %w[main develop], 'file_patterns' => %w[*.rb *.ts *.tsx] }
    }
  },
  {
    slug: 'security-vulnerability-scanner',
    variable_values: {},
    custom_config: {
      'notifications' => { 'slack_channel' => '#security-alerts', 'email_on_critical' => true },
      'targets' => { 'scan_dependencies' => true, 'scan_code' => true, 'severity_threshold' => 'medium' }
    }
  },
  {
    slug: 'ai-test-generation',
    variable_values: { 'test_style' => 'descriptive', 'include_mocks' => 'true' },
    custom_config: {
      'targets' => { 'frameworks' => %w[rspec jest], 'coverage_goal' => 80 }
    }
  },
  {
    slug: 'deployment-validation',
    variable_values: {},
    custom_config: {
      'targets' => { 'environments' => %w[staging production], 'require_approval_for' => %w[production] },
      'notifications' => { 'slack_channel' => '#deployments' }
    }
  },
  {
    slug: 'release-notes-generator',
    variable_values: { 'audience' => 'both' },
    custom_config: {
      'targets' => { 'include_commits' => true, 'include_prs' => true, 'format' => 'markdown' }
    }
  }
]

installed_count = 0
template_configs.each do |tc|
  template = Ai::DevopsTemplate.find_by(slug: tc[:slug])
  unless template
    puts "    ⚠️  Template '#{tc[:slug]}' not found — skipping"
    next
  end

  Ai::DevopsTemplateInstallation.find_or_create_by!(
    account: admin_account,
    devops_template: template
  ) do |inst|
    inst.installed_by = admin_user
    inst.status = 'active'
    inst.installed_version = template.version
    inst.variable_values = tc[:variable_values]
    inst.custom_config = tc[:custom_config]
  end
  installed_count += 1
end

puts "  ✅ #{installed_count} template installations created"

# ---------------------------------------------------------------------------
# DevOps AI Configs (4)
# ---------------------------------------------------------------------------
puts "\n  🤖 Creating DevOps AI configurations..."

ai_configs = [
  {
    name: 'Code Review Analysis',
    description: 'Primary AI configuration for automated code review and analysis',
    config_type: 'code_review',
    provider: 'anthropic',
    model: 'claude-sonnet-4-5-20250929',
    temperature: 0.2,
    max_tokens: 8192,
    timeout_seconds: 60,
    is_default: true,
    system_prompt: {
      'content' => 'You are a senior code reviewer. Analyze code changes for correctness, security, performance, and maintainability. Provide specific, actionable feedback with line references. Prioritize findings by severity.'
    },
    rate_limits: { 'requests_per_minute' => 30, 'requests_per_hour' => 500, 'tokens_per_minute' => 100_000 },
    settings: { 'response_format' => 'structured_json', 'stream' => false }
  },
  {
    name: 'Code Generation',
    description: 'AI configuration for generating code, tests, and documentation',
    config_type: 'code_generation',
    provider: 'anthropic',
    model: 'claude-sonnet-4-5-20250929',
    temperature: 0.4,
    max_tokens: 16_384,
    timeout_seconds: 90,
    is_default: false,
    system_prompt: {
      'content' => 'You are an expert software engineer. Generate clean, well-tested, production-ready code following established project conventions. Include appropriate error handling and documentation.'
    },
    rate_limits: { 'requests_per_minute' => 20, 'requests_per_hour' => 300, 'tokens_per_minute' => 200_000 },
    settings: { 'response_format' => 'code', 'stream' => true }
  },
  {
    name: 'Embedding & Search',
    description: 'Configuration for code embedding and semantic search operations',
    config_type: 'embedding',
    provider: 'openai',
    model: 'text-embedding-3-large',
    temperature: 0.0,
    max_tokens: 8191,
    timeout_seconds: 30,
    is_default: false,
    system_prompt: {},
    rate_limits: { 'requests_per_minute' => 100, 'requests_per_hour' => 3000, 'tokens_per_minute' => 1_000_000 },
    settings: { 'dimensions' => 3072, 'batch_size' => 100 }
  },
  {
    name: 'Security Analysis',
    description: 'Specialized AI configuration for security vulnerability analysis',
    config_type: 'custom',
    provider: 'anthropic',
    model: 'claude-sonnet-4-5-20250929',
    temperature: 0.1,
    max_tokens: 8192,
    timeout_seconds: 60,
    is_default: false,
    system_prompt: {
      'content' => 'You are a security engineer specializing in application security. Identify vulnerabilities following OWASP Top 10, CWE classifications, and NIST guidelines. For each finding provide severity, CWE ID, exploitation risk, and remediation steps.'
    },
    rate_limits: { 'requests_per_minute' => 20, 'requests_per_hour' => 200, 'tokens_per_minute' => 80_000 },
    settings: { 'response_format' => 'structured_json', 'stream' => false }
  }
]

configs_count = 0
ai_configs.each do |cfg|
  Devops::AiConfig.find_or_create_by!(account: admin_account, name: cfg[:name]) do |c|
    c.created_by = admin_user
    c.description = cfg[:description]
    c.config_type = cfg[:config_type]
    c.provider = cfg[:provider]
    c.model = cfg[:model]
    c.temperature = cfg[:temperature]
    c.max_tokens = cfg[:max_tokens]
    c.timeout_seconds = cfg[:timeout_seconds]
    c.is_default = cfg[:is_default]
    c.is_active = true
    c.system_prompt = cfg[:system_prompt]
    c.rate_limits = cfg[:rate_limits]
    c.settings = cfg[:settings]
  end
  configs_count += 1
end

puts "  ✅ #{configs_count} AI configurations created"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n📊 AI DevOps Configs Summary:"
puts "   Template Installations: #{Ai::DevopsTemplateInstallation.where(account: admin_account).count}"
puts "   DevOps AI Configs: #{Devops::AiConfig.where(account: admin_account).count}"
puts "✅ AI DevOps configs seeding completed!"
