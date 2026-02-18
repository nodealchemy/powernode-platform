# frozen_string_literal: true

# AI Governance Seed
# Creates compliance policies, approval chains, account credits, and A2A agent cards

puts "\n🛡️ Seeding AI Governance (Policies, Approvals, Credits, Agent Cards)..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping AI Governance"
  return
end

puts "  ✅ Using account: #{admin_account.name}"

# ---------------------------------------------------------------------------
# Compliance Policies (5)
# ---------------------------------------------------------------------------
puts "\n  📜 Creating compliance policies..."

policies_data = [
  {
    name: 'AI Output Content Filter',
    policy_type: 'output_filter',
    category: 'content_safety',
    description: 'Prevents AI outputs from containing PII, secrets, or sensitive data. Aligned with GDPR Article 22 and EU AI Act transparency requirements.',
    status: 'active',
    enforcement_level: 'block',
    priority: 10,
    is_required: true,
    conditions: {
      'patterns' => %w[credit_card ssn api_key private_key password_hash],
      'regex_rules' => [
        { 'name' => 'credit_card', 'pattern' => '\b\d{4}[\s-]?\d{4}[\s-]?\d{4}[\s-]?\d{4}\b' },
        { 'name' => 'ssn', 'pattern' => '\b\d{3}-\d{2}-\d{4}\b' },
        { 'name' => 'api_key', 'pattern' => '\b(sk|pk|api)[_-][a-zA-Z0-9]{20,}\b' }
      ]
    },
    actions: {
      'on_violation' => 'redact_and_block',
      'notify' => %w[admin security_team],
      'log_level' => 'warn'
    },
    applies_to: {
      'all_agents' => true,
      'all_workflows' => true,
      'environments' => %w[production staging development]
    }
  },
  {
    name: 'Model Usage Rate Limit',
    policy_type: 'rate_limit',
    category: 'cost_management',
    description: 'Enforces per-user rate limits to prevent runaway AI costs. 100 requests/hour, 1000 requests/day per user.',
    status: 'active',
    enforcement_level: 'block',
    priority: 20,
    is_required: false,
    conditions: {
      'limits' => {
        'per_user_per_hour' => 100,
        'per_user_per_day' => 1000,
        'per_account_per_hour' => 500,
        'per_account_per_day' => 5000
      },
      'window_type' => 'sliding'
    },
    actions: {
      'on_violation' => 'reject_request',
      'retry_after_seconds' => 60,
      'notify' => %w[user admin],
      'log_level' => 'info'
    },
    applies_to: {
      'all_agents' => true,
      'all_workflows' => true,
      'exclude_system_operations' => true
    }
  },
  {
    name: 'High-Risk AI Cost Cap',
    policy_type: 'cost_limit',
    category: 'financial_governance',
    description: 'Requires approval for AI operations exceeding $5 per workflow execution. Aligned with FinOps best practices.',
    status: 'active',
    enforcement_level: 'require_approval',
    priority: 15,
    is_required: false,
    conditions: {
      'cost_threshold_usd' => 5.0,
      'per' => 'workflow_execution',
      'model_cost_rates' => {
        'claude-sonnet-4-5-20250929' => { 'input_per_1k' => 0.003, 'output_per_1k' => 0.015 },
        'claude-opus-4-5-20251101' => { 'input_per_1k' => 0.015, 'output_per_1k' => 0.075 }
      }
    },
    actions: {
      'on_violation' => 'pause_and_request_approval',
      'approval_chain' => 'High-Cost AI Operation',
      'notify' => %w[admin finance],
      'log_level' => 'warn'
    },
    applies_to: {
      'all_workflows' => true,
      'environments' => %w[production staging]
    }
  },
  {
    name: 'Sensitive Data Access Policy',
    policy_type: 'data_access',
    category: 'data_protection',
    description: 'Warns when AI agents access datasets marked as sensitive. Aligned with SOC2 CC6.1 logical access controls.',
    status: 'draft',
    enforcement_level: 'warn',
    priority: 5,
    is_required: false,
    conditions: {
      'data_classifications' => %w[pii confidential restricted],
      'access_types' => %w[read write export],
      'require_justification' => true
    },
    actions: {
      'on_violation' => 'log_and_warn',
      'require_audit_note' => true,
      'notify' => %w[data_owner compliance_team],
      'log_level' => 'warn'
    },
    applies_to: {
      'all_agents' => true,
      'data_sources' => %w[database file_storage external_api]
    }
  },
  {
    name: 'Model Selection Governance',
    policy_type: 'model_usage',
    category: 'model_governance',
    description: 'Logs all model selection decisions for audit trail. Aligned with NIST AI RMF MAP function.',
    status: 'disabled',
    enforcement_level: 'log',
    priority: 1,
    is_required: false,
    conditions: {
      'track_model_changes' => true,
      'track_provider_changes' => true,
      'approved_models' => %w[claude-sonnet-4-5-20250929 claude-opus-4-5-20251101 gpt-4o text-embedding-3-large],
      'approved_providers' => %w[anthropic openai]
    },
    actions: {
      'on_violation' => 'log_only',
      'create_audit_entry' => true,
      'log_level' => 'info'
    },
    applies_to: {
      'all_agents' => true,
      'all_workflows' => true
    }
  }
]

policies_count = 0
policies_data.each do |pd|
  Ai::CompliancePolicy.find_or_create_by!(account: admin_account, name: pd[:name]) do |p|
    p.created_by = admin_user
    p.policy_type = pd[:policy_type]
    p.category = pd[:category]
    p.description = pd[:description]
    p.status = pd[:status]
    p.enforcement_level = pd[:enforcement_level]
    p.priority = pd[:priority]
    p.is_required = pd[:is_required]
    p.conditions = pd[:conditions]
    p.actions = pd[:actions]
    p.applies_to = pd[:applies_to]
    p.activated_at = Time.current if pd[:status] == 'active'
  end
  policies_count += 1
end

puts "  ✅ #{policies_count} compliance policies created"

# ---------------------------------------------------------------------------
# Approval Chains (3)
# ---------------------------------------------------------------------------
puts "\n  ✅ Creating approval chains..."

chains_data = [
  {
    name: 'Production Deployment',
    description: 'Two-step approval chain for production deployments: team lead review followed by security sign-off',
    trigger_type: 'workflow_deploy',
    trigger_conditions: { 'environment' => 'production' },
    is_sequential: true,
    timeout_hours: 24,
    timeout_action: 'reject',
    steps: [
      {
        'step' => 1,
        'name' => 'Team Lead Review',
        'approver_type' => 'role',
        'approver_value' => 'team_lead',
        'required' => true,
        'timeout_hours' => 12
      },
      {
        'step' => 2,
        'name' => 'Security Sign-off',
        'approver_type' => 'role',
        'approver_value' => 'security_reviewer',
        'required' => true,
        'timeout_hours' => 12
      }
    ]
  },
  {
    name: 'High-Cost AI Operation',
    description: 'Single-step manager approval for AI operations exceeding $10 cost threshold',
    trigger_type: 'high_cost',
    trigger_conditions: { 'cost_threshold_usd' => 10.0, 'per' => 'operation' },
    is_sequential: true,
    timeout_hours: 4,
    timeout_action: 'reject',
    steps: [
      {
        'step' => 1,
        'name' => 'Manager Approval',
        'approver_type' => 'role',
        'approver_value' => 'manager',
        'required' => true,
        'timeout_hours' => 4
      }
    ]
  },
  {
    name: 'Sensitive Data Processing',
    description: 'Two-step approval for AI operations on sensitive data: data owner then compliance officer',
    trigger_type: 'sensitive_data',
    trigger_conditions: { 'data_classifications' => %w[pii confidential restricted] },
    is_sequential: true,
    timeout_hours: 48,
    timeout_action: 'escalate',
    steps: [
      {
        'step' => 1,
        'name' => 'Data Owner Review',
        'approver_type' => 'role',
        'approver_value' => 'data_owner',
        'required' => true,
        'timeout_hours' => 24
      },
      {
        'step' => 2,
        'name' => 'Compliance Review',
        'approver_type' => 'role',
        'approver_value' => 'compliance_officer',
        'required' => true,
        'timeout_hours' => 24
      }
    ]
  }
]

chains_count = 0
chains_data.each do |cd|
  Ai::ApprovalChain.find_or_create_by!(account: admin_account, name: cd[:name]) do |c|
    c.created_by = admin_user
    c.description = cd[:description]
    c.trigger_type = cd[:trigger_type]
    c.trigger_conditions = cd[:trigger_conditions]
    c.steps = cd[:steps]
    c.is_sequential = cd[:is_sequential]
    c.timeout_hours = cd[:timeout_hours]
    c.timeout_action = cd[:timeout_action]
    c.status = 'active'
  end
  chains_count += 1
end

puts "  ✅ #{chains_count} approval chains created"

# ---------------------------------------------------------------------------
# Account Credits (1)
# ---------------------------------------------------------------------------
puts "\n  💰 Creating account credits..."

Ai::AccountCredit.find_or_create_by!(account: admin_account) do |credit|
  credit.balance = 10_000.0
  credit.lifetime_credits_purchased = 10_000.0
  credit.last_purchase_at = Time.current
  credit.settings = {
    'low_balance_threshold' => 500.0,
    'auto_recharge' => false,
    'notification_email' => 'admin@powernode.org'
  }
end

puts "  ✅ Account credits: #{Ai::AccountCredit.find_by(account: admin_account)&.balance} balance"

# ---------------------------------------------------------------------------
# Agent Cards — A2A Protocol v0.3 (5)
# ---------------------------------------------------------------------------
puts "\n  🃏 Creating A2A Agent Cards..."

agent_cards_data = [
  {
    agent_slug: 'claude-strategic-planner',
    name: 'Claude Strategic Planner',
    description: 'Strategic planning and task decomposition agent with advanced reasoning for complex goal-oriented workflows.',
    visibility: 'internal',
    capabilities: {
      'skills' => [
        { 'id' => 'strategic_planning', 'name' => 'Strategic Planning', 'description' => 'Develop comprehensive strategic plans and roadmaps', 'examples' => ['Create a Q3 product roadmap', 'Plan a phased migration strategy'] },
        { 'id' => 'task_decomposition', 'name' => 'Task Decomposition', 'description' => 'Break complex goals into actionable task hierarchies', 'examples' => ['Decompose feature implementation into subtasks', 'Create work breakdown structure for project'] },
        { 'id' => 'goal_setting', 'name' => 'Goal Setting', 'description' => 'Define measurable objectives and key results', 'examples' => ['Set OKRs for engineering team', 'Define success criteria for product launch'] }
      ],
      'input_schemas' => { 'strategic_planning' => { 'type' => 'object', 'properties' => { 'goal' => { 'type' => 'string' }, 'context' => { 'type' => 'string' }, 'constraints' => { 'type' => 'array' } } } }
    },
    authentication: { 'schemes' => ['bearer'], 'credentials' => 'required' },
    tags: %w[planning strategy orchestration reasoning],
    default_input_modes: ['application/json'],
    default_output_modes: ['application/json']
  },
  {
    agent_slug: 'claude-research-analyst',
    name: 'Claude Research Analyst',
    description: 'Comprehensive research and data analysis agent with source validation and evidence synthesis capabilities.',
    visibility: 'internal',
    capabilities: {
      'skills' => [
        { 'id' => 'data_analysis', 'name' => 'Data Analysis', 'description' => 'Perform statistical analysis and derive insights from datasets', 'examples' => ['Analyze user engagement trends', 'Compare performance metrics across releases'] },
        { 'id' => 'research_synthesis', 'name' => 'Research Synthesis', 'description' => 'Combine information from multiple sources into coherent findings', 'examples' => ['Synthesize competitor analysis from multiple reports', 'Create literature review on topic'] },
        { 'id' => 'fact_checking', 'name' => 'Fact Checking', 'description' => 'Verify claims against source data and provide confidence scores', 'examples' => ['Verify technical claims in documentation', 'Cross-reference statistics with primary sources'] }
      ]
    },
    authentication: { 'schemes' => ['bearer'], 'credentials' => 'required' },
    tags: %w[research analysis data evidence],
    default_input_modes: ['application/json'],
    default_output_modes: ['application/json']
  },
  {
    agent_slug: 'claude-content-creator',
    name: 'Claude Content Creator',
    description: 'Versatile content generation agent for documentation, reports, and creative writing with multi-format output.',
    visibility: 'public',
    capabilities: {
      'skills' => [
        { 'id' => 'content_generation', 'name' => 'Content Generation', 'description' => 'Generate high-quality written content in various formats and styles', 'examples' => ['Write a technical blog post', 'Create product release announcement'] },
        { 'id' => 'editing', 'name' => 'Editing & Refinement', 'description' => 'Edit content for clarity, grammar, tone, and engagement', 'examples' => ['Proofread and improve API documentation', 'Refine executive summary for clarity'] },
        { 'id' => 'summarization', 'name' => 'Summarization', 'description' => 'Condense lengthy content into concise summaries at various detail levels', 'examples' => ['Summarize meeting transcript', 'Create TL;DR for technical specification'] }
      ]
    },
    authentication: { 'schemes' => %w[bearer api_key], 'credentials' => 'required' },
    tags: %w[content writing documentation creative],
    default_input_modes: ['application/json', 'text/plain'],
    default_output_modes: ['application/json', 'text/plain', 'text/markdown']
  },
  {
    agent_slug: 'workflow-performance-monitor',
    name: 'Workflow Performance Monitor',
    description: 'Real-time performance monitoring agent with anomaly detection and alerting for workflow execution health.',
    visibility: 'private',
    capabilities: {
      'skills' => [
        { 'id' => 'performance_monitoring', 'name' => 'Performance Monitoring', 'description' => 'Track execution times, resource usage, and throughput in real-time', 'examples' => ['Monitor API response times', 'Track pipeline execution duration'] },
        { 'id' => 'anomaly_detection', 'name' => 'Anomaly Detection', 'description' => 'Identify unusual patterns and performance deviations automatically', 'examples' => ['Detect latency spikes', 'Flag unusual error rate increases'] },
        { 'id' => 'alerting', 'name' => 'Smart Alerting', 'description' => 'Generate context-aware alerts with severity classification', 'examples' => ['Alert on SLA breach risk', 'Notify on resource exhaustion trend'] }
      ]
    },
    authentication: { 'schemes' => ['api_key'], 'credentials' => 'required' },
    tags: %w[monitoring performance observability alerting],
    default_input_modes: ['application/json'],
    default_output_modes: ['application/json']
  },
  {
    agent_slug: 'workflow-analytics-intelligence',
    name: 'Workflow Analytics Intelligence',
    description: 'Advanced analytics agent providing trend analysis, predictive insights, and business intelligence from workflow data.',
    visibility: 'internal',
    capabilities: {
      'skills' => [
        { 'id' => 'analytics', 'name' => 'Advanced Analytics', 'description' => 'Perform deep statistical and business analytics on workflow data', 'examples' => ['Analyze workflow completion rates by category', 'Calculate efficiency metrics across teams'] },
        { 'id' => 'trend_analysis', 'name' => 'Trend Analysis', 'description' => 'Identify trends, seasonality, and patterns in time-series data', 'examples' => ['Detect weekly usage patterns', 'Forecast resource needs for next quarter'] },
        { 'id' => 'reporting', 'name' => 'Intelligence Reporting', 'description' => 'Generate comprehensive analytical reports with visualizations', 'examples' => ['Create monthly performance dashboard', 'Generate cost optimization report'] }
      ]
    },
    authentication: { 'schemes' => ['bearer'], 'credentials' => 'required' },
    tags: %w[analytics intelligence reporting trends],
    default_input_modes: ['application/json'],
    default_output_modes: ['application/json']
  }
]

cards_count = 0
agent_cards_data.each do |acd|
  agent = Ai::Agent.find_by(account: admin_account, slug: acd[:agent_slug])
  unless agent
    puts "    ⚠️  Agent '#{acd[:agent_slug]}' not found — skipping card"
    next
  end

  Ai::AgentCard.find_or_create_by!(account: admin_account, name: acd[:name]) do |card|
    card.ai_agent_id = agent.id
    card.description = acd[:description]
    card.protocol_version = '0.3'
    card.capabilities = acd[:capabilities]
    card.authentication = acd[:authentication]
    card.default_input_modes = acd[:default_input_modes]
    card.default_output_modes = acd[:default_output_modes]
    card.visibility = acd[:visibility]
    card.provider_name = 'Powernode'
    card.tags = acd[:tags]
    card.status = 'active'
    card.card_version = '1.0.0'
    card.published_at = Time.current
  end
  cards_count += 1
end

puts "  ✅ #{cards_count} agent cards created"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n📊 AI Governance Summary:"
puts "   Compliance Policies: #{Ai::CompliancePolicy.where(account: admin_account).count}"
puts "   Approval Chains: #{Ai::ApprovalChain.where(account: admin_account).count}"
puts "   Account Credits Balance: #{Ai::AccountCredit.find_by(account: admin_account)&.balance}"
puts "   Agent Cards: #{Ai::AgentCard.where(account: admin_account).count}"
puts "✅ AI Governance seeding completed!"
