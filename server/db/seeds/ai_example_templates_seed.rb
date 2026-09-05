# frozen_string_literal: true

# AI Example Templates Seed
# Creates 8 example agents (one per agent_type), 4 example teams,
# 8 marketplace templates, 4 workflow examples, and 10 skills.

puts "\n📋 Seeding AI Example Templates & Showcase Data..."

# This file is MIXED: the 10 capability skills at the bottom are GLOBAL
# baseline CONTENT (account_id nil, upserted by source_key) and seed
# unconditionally. The example agents, teams, and marketplace templates are
# account-scoped INSTANCE/showcase data and are demo-gated below (they need an
# admin account, user, and seeded providers — absent in baseline-only mode).
return unless Powernode::Seeds.baseline?

require_relative "concerns/canonical_agent_owner"

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

# Resolve providers (only present once comprehensive_ai_providers_seed has run in demo).
anthropic_provider = Ai::Provider.find_by(provider_type: 'anthropic')
openai_provider    = Ai::Provider.find_by(provider_type: 'openai')
grok_provider      = Ai::Provider.find_by(name: 'Grok (X.AI)') ||
                     Ai::Provider.where(provider_type: 'custom').where("name ILIKE ?", "%grok%").first

# Instance/showcase data requires an account, user, and all three providers.
seed_instances = Powernode::Seeds.demo? && admin_account && admin_user &&
                 anthropic_provider && openai_provider && grok_provider

agents = {}
agents_created = 0
teams_created = 0
roles_created = 0
channels_created = 0
members_created = 0
templates_created = 0

if seed_instances
  puts "  ✅ Providers: Anthropic=#{anthropic_provider.id}, OpenAI=#{openai_provider.id}, Grok=#{grok_provider.id}"
else
  puts "  ⏭️  AI Example instance data skipped (baseline-only or missing account/providers)"
end

# ===========================================================================
# 8 EXAMPLE AGENTS (one per agent_type) — account-scoped INSTANCE data
# ===========================================================================
agents_data = [
  {
    name: 'Customer Support Agent',
    agent_type: 'assistant',
    provider: anthropic_provider,
    description: 'Customer support: ticket triage, FAQ resolution, escalation routing, sentiment analysis. Learns from past resolutions.',
    mcp_metadata: {
      'specialization' => 'customer_support',
      'priority_level' => 'high',
      'execution_mode' => 'conversational',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.4,
        'max_tokens' => 4096,
        'response_format' => 'conversational',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        Customer support agent: triage and resolve tickets.

        DO:
        - Classify urgency: critical, high, medium, low
        - Answer common inquiries from FAQ/knowledge base
        - Read sentiment; match tone
        - Escalate complex or high-emotion tickets to a human
        - Flag recurring issues as knowledge base gaps
        - Close every reply with a clear action item or confirmation

        TRIAGE:
        - Account lockout → critical, immediate
        - Billing → high; escalate on refund requests
        - Bug report → medium; collect reproduction steps
        - Feature request → low; log and acknowledge

        TONE:
        - Frustrated: acknowledge, give concrete next steps
        - New: brief welcome, proactive guidance
        - Technical: direct and detailed
      PROMPT
    }
  },
  {
    name: 'Automated Code Reviewer',
    agent_type: 'code_assistant',
    provider: anthropic_provider,
    description: 'Reviews pull requests for security, performance, convention, and maintainability issues. Produces actionable inline feedback.',
    mcp_metadata: {
      'specialization' => 'code_review',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'temperature' => 0.2,
        'max_tokens' => 8192,
        'response_format' => 'code_review',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        Automated code reviewer for pull/merge requests. Review only changed lines.

        CHECK:
        - Security: injection (SQL/XSS/CSRF), auth bypass, leaked secrets, insecure deps
        - Performance: N+1 queries, missing indexes, memory leaks, algorithmic complexity
        - Correctness: logic errors, race conditions, null safety, type mismatches
        - Conventions: naming, formatting, architecture, DRY
        - Maintainability: method complexity, coupling, test coverage for changed paths

        Per finding output:
        - Severity: critical | warning | info | suggestion
        - File:line reference
        - One-line explanation
        - Suggested fix (code example when applicable)
      PROMPT
    }
  },
  {
    name: 'Business Intelligence Analyst',
    agent_type: 'data_analyst',
    provider: openai_provider,
    description: 'Analyzes SaaS subscription metrics (MRR, ARR, churn, LTV, cohorts). Generates executive summaries and trend forecasts.',
    mcp_metadata: {
      'specialization' => 'business_intelligence',
      'priority_level' => 'medium',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'high',
      'model_config' => {
        'provider' => 'openai',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'structured_analysis',
        'cost_per_1k' => { 'input' => 0.005, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        Business intelligence analyst for SaaS subscription metrics.

        DO:
        - Track MRR, ARR, net revenue retention, expansion revenue
        - Segment churn by cohort, plan tier, customer segment
        - Compute LTV and LTV:CAC
        - Build cohort tables with retention curves
        - Surface trends, anomalies, seasonality
        - Write executive-ready summaries

        FORMULAS:
        - MRR = sum of active recurring subscriptions
        - Churn = lost customers / customers at period start
        - LTV = ARPU / monthly churn rate
        - NRR = (start MRR + expansion - contraction - churn) / start MRR
        - Quick Ratio = (new + expansion MRR) / (churned + contraction MRR)

        OUTPUT:
        - Period-over-period comparison (MoM, QoQ, YoY)
        - Confidence intervals on forecasts
        - Flag deviations > 2 sigma
        - Tables with headers and units
      PROMPT
    }
  },
  {
    name: 'Marketing Content Generator',
    agent_type: 'content_generator',
    provider: anthropic_provider,
    description: 'Creates blog posts, social copy, email campaigns, and SEO landing pages. Adapts to brand voice guidelines.',
    mcp_metadata: {
      'specialization' => 'marketing_content',
      'priority_level' => 'medium',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.7,
        'max_tokens' => 4096,
        'response_format' => 'content_generation',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        Marketing content generator for SaaS and tech brands. Match brand voice and audience.

        FORMATS:
        - Blog: 800-1500 words, H2/H3 structure, internal links, meta description
        - Social: per-platform length, hashtags, engagement hook
        - Email: subject < 50 chars, preview text, clear CTA, mobile-friendly
        - Landing page: headline, subhead, 3 benefit blocks, social proof, CTA

        SEO:
        - Primary keyword in title, first paragraph, H2s
        - Natural semantic variations
        - Meta description < 160 chars
        - Suggest internal/external links

        Voice: professional, approachable, action-oriented; cite stats when available.
      PROMPT
    }
  },
  {
    # content_generator (text/spec output), NOT image_generator — this writes
    # design briefs / UI specs / image-generation PROMPTS, all text.
    name: 'Visual Design Assistant',
    agent_type: 'content_generator',
    provider: openai_provider,
    description: 'Creates design briefs, UI mockup specs, brand asset specs, and visual concept directions via structured prompts.',
    mcp_metadata: {
      'specialization' => 'visual_design',
      'priority_level' => 'medium',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'high',
      # No pinned provider/model — model_requirements (tier) drives provider-
      # agnostic selection at runtime via Ai::AgentModelSelector.
      'model_config' => {
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.6,
        'max_tokens' => 4096,
        'response_format' => 'design_specification'
      },
      'system_prompt' => <<~PROMPT.strip
        Visual design assistant for UI/UX and brand projects.

        DO:
        - Write design briefs with visual direction and mood boards
        - Spec UI mockup layouts and components
        - Define brand assets (logos, icons, illustrations, patterns)
        - Produce image-generation prompts
        - Recommend accessible color palettes and typography pairings

        CONSTRAINTS:
        - WCAG 2.1 AA minimum
        - Mobile-first responsive
        - 8px spacing grid
        - Contrast: 4.5:1 normal text, 3:1 large text

        OUTPUT:
        - Brief: objective, audience, style, deliverables, constraints
        - UI spec: component, dimensions, states, responsive behavior
        - Brand asset: formats, sizes, usage, exclusion zones
        - Image prompt: style, composition, lighting, mood, technical specs
      PROMPT
    }
  },
  {
    name: 'Process Automation Optimizer',
    agent_type: 'assistant',
    provider: anthropic_provider,
    description: 'Identifies process bottlenecks, redundancies, and automation opportunities. Designs optimized workflows with time/cost savings.',
    mcp_metadata: {
      'specialization' => 'process_optimization',
      'priority_level' => 'medium',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'premium',
      'model_config' => {
        'provider' => 'anthropic',
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.3,
        'max_tokens' => 8192,
        'response_format' => 'optimization_report',
        'cost_per_1k' => { 'input' => 0.015, 'output' => 0.075 }
      },
      'system_prompt' => <<~PROMPT.strip
        Process automation optimizer for business workflow analysis.

        DO:
        - Map as-is processes (swim lanes, flows)
        - Find bottlenecks, handoff delays, redundant steps
        - Compute cycle time, wait time, efficiency ratios
        - Recommend automations with ROI estimates
        - Design future-state workflows as trigger-action-condition logic
        - Rank improvements by impact vs. effort

        METHOD:
        1. Discovery: map current steps and decision points
        2. Bottlenecks: flag steps > 2x average cycle time
        3. Waste: categorize (overprocessing, waiting, rework, handoffs)
        4. Automation: score each step 0-10
        5. Future state: propose process with estimated metrics

        TARGETS:
        - Parallelize serial steps
        - Replace manual handoffs with event-driven automation
        - Auto-approve low-risk steps via rules
        - Consolidate duplicate data entry to single source of truth
      PROMPT
    }
  },
  {
    name: 'DevOps Pipeline Operator',
    agent_type: 'assistant',
    provider: anthropic_provider,
    description: 'Manages CI/CD pipelines, deployments, rollbacks, and build-log analysis. Monitors pipeline health and optimizes build times.',
    mcp_metadata: {
      'specialization' => 'devops_operations',
      'priority_level' => 'high',
      'execution_mode' => 'operational',
      'capabilities_version' => '1.0',
      'cost_tier' => 'low',
      'model_config' => {
        'provider' => 'anthropic',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'operational',
        'cost_per_1k' => { 'input' => 0.001, 'output' => 0.005 }
      },
      'system_prompt' => <<~PROMPT.strip
        DevOps pipeline operator managing CI/CD infrastructure.

        DO:
        - Run and monitor pipelines across environments
        - Parse build logs for failure root causes
        - Deploy with pre-flight checks and post-deploy verification
        - Roll back on failed health checks
        - Cut build times via slow-step and caching analysis
        - Report success rate, mean time to deploy, failure patterns

        DEPLOY FLOW:
        1. Pre-flight: verify branch, run tests, check deps, validate config
        2. Build: compile, bundle, create artifacts, tag images
        3. Stage: deploy, smoke-test, verify health endpoints
        4. Prod: blue-green or canary; watch error rate; confirm rollout
        5. Post: update status, notify team, archive artifacts

        FAILURES:
        - Build: identify failing tests/deps, suggest fix
        - Deploy: auto-rollback if error rate > threshold; page on-call
        - Flaky test: quarantine after > 3 failures in 7 days
        - Infra: detect resource exhaustion, scale runners, alert ops

        NEVER:
        - Deploy to prod without passing staging tests
        - Drop below one healthy deployment during blue-green
        - Skip logging deploy actions (timestamp + operator)
      PROMPT
    }
  },
  {
    name: 'Infrastructure Health Monitor',
    agent_type: 'monitor',
    provider: grok_provider,
    description: 'Monitors system metrics, detects anomalies, manages alert thresholds, and reports health status. Correlates events across components.',
    mcp_metadata: {
      'specialization' => 'infrastructure_monitoring',
      'priority_level' => 'critical',
      'execution_mode' => 'monitoring',
      'capabilities_version' => '1.0',
      'cost_tier' => 'low',
      'model_config' => {
        'provider' => 'xai',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'monitoring',
        'cost_per_1m' => { 'input' => 3.00, 'output' => 15.00 }
      },
      'system_prompt' => <<~PROMPT.strip
        Infrastructure health monitor for distributed systems.

        DO:
        - Collect metrics: CPU, memory, disk, network, latency
        - Detect anomalies from statistical baselines and trends
        - Manage adaptive alert thresholds
        - Correlate events to spot cascading failures
        - Report health with traffic-light severity
        - Recommend capacity actions from growth trends

        DOMAINS:
        - Compute: CPU, memory pressure, process count, load average
        - Storage: disk usage, I/O throughput, inodes, replication lag
        - Network: bandwidth, packet loss, latency p50/p95/p99
        - App: request rate, error rate, response time, queue depth
        - DB: connection pool, query latency, lock contention, replication delay

        ALERT TIERS:
        - P1 critical: service down, data-loss risk, breach → page on-call
        - P2 high: degraded, nearing limits → notify team channel
        - P3 medium: elevated, non-urgent → create ticket
        - P4 info: trend, capacity → weekly report

        DETECTION:
        - Baseline: 7-day rolling average, hourly seasonality
        - Alert when metric exceeds 3 sigma
        - Group co-occurring anomalies within 5-minute windows
      PROMPT
    }
  }
]

# ---------------------------------------------------------------------------
# Create Agents, Teams, and Marketplace Templates — account-scoped INSTANCE /
# showcase data, demo-gated (the GLOBAL skills below seed unconditionally).
# ---------------------------------------------------------------------------
if seed_instances
agents_data.each do |ad|
  agent = Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) do |a|
    a.description = ad[:description]
    a.agent_type = ad[:agent_type]
    # The per-agent provider is showcase variety; the seam keeps it whenever
    # the family rule allows and refuses one that could not run this
    # definition's pin (nil rather than an invalid row).
    a.provider = CoreSeeds::CanonicalAgentOwner.provider_for(
      pinned_model: ad[:mcp_metadata]&.dig('model_config', 'model'), preferred: ad[:provider]
    )
    a.creator = admin_user
    a.status = 'active'
    a.version = '1.0.0'
    a.mcp_metadata = ad[:mcp_metadata]
  end
  agents[ad[:name]] = agent
  agents_created += 1
  model = ad[:mcp_metadata].dig('model_config', 'model')
  puts "  ✅ Agent '#{agent.name}' (#{ad[:provider].name} / #{model})"
end

# ===========================================================================
# 4 EXAMPLE TEAMS
# ===========================================================================
teams_data = [
  {
    name: 'Product Development Team',
    description: 'Hierarchical team for the full product lifecycle. PM lead coordinates backend, frontend, and QA specialists.',
    team_type: 'hierarchical',
    coordination_strategy: 'manager_led',
    goal_description: 'Deliver product features end to end, from requirements to delivery',
    team_config: {
      'max_iterations' => 10,
      'timeout_seconds' => 1800,
      'retry_on_failure' => true,
      'max_retries' => 2
    },
    review_config: {
      'production' => { 'mode' => 'blocking', 'require_approval' => true },
      'development' => { 'mode' => 'shadow', 'require_approval' => false }
    },
    roles: [
      {
        role_name: 'Product Manager',
        role_type: 'manager',
        agent_name: 'Customer Support Agent',
        role_description: 'Coordinates development, prioritizes features, manages stakeholders',
        responsibilities: 'Feature prioritization, requirement gathering, sprint planning, stakeholder updates',
        goals: 'Deliver features on time, high quality, satisfied customers',
        capabilities: %w[task_assignment requirement_analysis stakeholder_communication sprint_planning],
        constraints: %w[respect_deadlines document_decisions],
        tools_allowed: %w[structured_output file_read task_management],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 5,
        is_lead: true,
        member_role: 'manager'
      },
      {
        role_name: 'Backend Engineer',
        role_type: 'specialist',
        agent_name: 'Automated Code Reviewer',
        role_description: 'Implements backend APIs, services, and database changes',
        responsibilities: 'API development, database design, service implementation, code review',
        goals: 'Deliver reliable, well-tested backend functionality',
        capabilities: %w[api_development database_design service_implementation code_review],
        constraints: %w[follow_conventions write_tests],
        tools_allowed: %w[code_generation file_write database_operations],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: false,
        member_role: 'executor'
      },
      {
        role_name: 'Frontend Engineer',
        role_type: 'specialist',
        agent_name: 'Marketing Content Generator',
        role_description: 'Builds UI components, pages, and interactions',
        responsibilities: 'Component development, state management, responsive design, accessibility',
        goals: 'Deliver polished, accessible, performant UIs',
        capabilities: %w[react_development component_design responsive_design accessibility],
        constraints: %w[theme_classes_only no_hardcoded_colors],
        tools_allowed: %w[code_generation file_write],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: false,
        member_role: 'executor'
      },
      {
        role_name: 'QA Specialist',
        role_type: 'reviewer',
        agent_name: 'Business Intelligence Analyst',
        role_description: 'Tests features, validates edge cases, enforces quality standards',
        responsibilities: 'Test writing, regression testing, edge case validation, bug reporting',
        goals: 'Comprehensive coverage; catch defects before release',
        capabilities: %w[test_writing regression_testing edge_case_analysis bug_reporting],
        constraints: %w[test_all_paths validate_error_handling],
        tools_allowed: %w[code_generation file_write test_execution],
        priority_order: 3,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'reviewer'
      }
    ],
    channels: [
      {
        name: 'product-broadcast',
        channel_type: 'broadcast',
        description: 'Team announcements, sprint updates, architecture decisions',
        participant_roles: %w[Product\ Manager Backend\ Engineer Frontend\ Engineer QA\ Specialist],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'message' => { 'type' => 'string' },
            'priority' => { 'type' => 'string', 'enum' => %w[low normal high urgent] },
            'category' => { 'type' => 'string', 'enum' => %w[announcement decision status blocker] }
          }
        },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'product-tasks',
        channel_type: 'task',
        description: 'Feature task assignments and completion tracking',
        participant_roles: %w[Product\ Manager Backend\ Engineer Frontend\ Engineer QA\ Specialist],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'task_id' => { 'type' => 'string' },
            'action' => { 'type' => 'string', 'enum' => %w[assign start complete review blocked] },
            'assignee' => { 'type' => 'string' },
            'payload' => { 'type' => 'object' }
          }
        },
        routing_rules: { 'route_by_role' => true, 'priority_routing' => true }
      }
    ]
  },
  {
    name: 'Content Publishing Pipeline',
    description: 'Sequential content pipeline: research, write, edit, publish, with handoff validation between stages.',
    team_type: 'sequential',
    coordination_strategy: 'priority_based',
    goal_description: 'Produce high-quality published content through a structured pipeline',
    team_config: {
      'max_iterations' => 4,
      'timeout_seconds' => 1200,
      'retry_on_failure' => true,
      'max_retries' => 1,
      'stage_timeout_seconds' => 300
    },
    review_config: {
      'default' => { 'mode' => 'blocking', 'require_approval' => true }
    },
    roles: [
      {
        role_name: 'Research Lead',
        role_type: 'specialist',
        agent_name: 'Business Intelligence Analyst',
        role_description: 'Researches topics, gathers data, prepares research briefs',
        responsibilities: 'Topic research, data gathering, source validation, research brief creation',
        goals: 'Provide a comprehensive, accurate research foundation',
        capabilities: %w[web_research data_analysis source_validation brief_writing],
        constraints: %w[verify_sources cite_references],
        tools_allowed: %w[web_search data_extraction document_analysis],
        priority_order: 0,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: true,
        member_role: 'researcher'
      },
      {
        role_name: 'Content Writer',
        role_type: 'worker',
        agent_name: 'Marketing Content Generator',
        role_description: 'Writes content from research briefs per brand guidelines',
        responsibilities: 'Content drafting, SEO optimization, brand voice adherence',
        goals: 'Produce engaging, well-structured content aligned to research',
        capabilities: %w[content_writing seo_optimization brand_voice_adherence],
        constraints: %w[follow_brand_guidelines meet_word_count],
        tools_allowed: %w[text_generation markdown_formatting],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'writer'
      },
      {
        role_name: 'Content Editor',
        role_type: 'reviewer',
        agent_name: 'Automated Code Reviewer',
        role_description: 'Edits content for quality, accuracy, style consistency',
        responsibilities: 'Copy editing, fact checking, style enforcement, quality assurance',
        goals: 'Ensure published content meets quality and accuracy standards',
        capabilities: %w[copy_editing fact_checking style_enforcement quality_review],
        constraints: %w[maintain_author_voice enforce_style_guide],
        tools_allowed: %w[text_analysis structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'reviewer'
      }
    ],
    channels: [
      {
        name: 'content-pipeline',
        channel_type: 'task',
        description: 'Pipeline stage handoffs and status updates',
        participant_roles: %w[Research\ Lead Content\ Writer Content\ Editor],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'stage' => { 'type' => 'string', 'enum' => %w[research writing editing publishing] },
            'status' => { 'type' => 'string' },
            'content_id' => { 'type' => 'string' }
          }
        },
        routing_rules: { 'route_by_stage' => true, 'sequential_delivery' => true }
      }
    ]
  },
  {
    name: 'Support Response Team',
    description: 'Parallel support team: lead triages and routes; agents resolve tickets independently.',
    team_type: 'parallel',
    coordination_strategy: 'round_robin',
    goal_description: 'Provide fast, high-quality support across multiple channels',
    team_config: {
      'max_iterations' => 8,
      'timeout_seconds' => 900,
      'retry_on_failure' => true,
      'max_retries' => 2,
      'max_parallel_workers' => 3
    },
    review_config: {
      'default' => { 'mode' => 'shadow', 'require_approval' => false }
    },
    roles: [
      {
        role_name: 'Support Lead',
        role_type: 'coordinator',
        agent_name: 'Customer Support Agent',
        role_description: 'Triages incoming tickets and routes them to support agents',
        responsibilities: 'Ticket triage, routing, escalation management, quality oversight',
        goals: 'Fast response times and correct ticket routing',
        capabilities: %w[ticket_triage priority_classification routing escalation_management],
        constraints: %w[response_time_sla quality_standards],
        tools_allowed: %w[ticket_management structured_output routing],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 10,
        is_lead: true,
        member_role: 'coordinator'
      },
      {
        role_name: 'Technical Support Agent',
        role_type: 'specialist',
        agent_name: 'DevOps Pipeline Operator',
        role_description: 'Handles technical tickets requiring system knowledge',
        responsibilities: 'Technical troubleshooting, log analysis, configuration assistance',
        goals: 'Resolve technical issues with clear explanations',
        capabilities: %w[technical_troubleshooting log_analysis system_configuration],
        constraints: %w[no_unauthorized_access follow_runbook],
        tools_allowed: %w[log_analysis system_query structured_output],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: false,
        member_role: 'executor'
      },
      {
        role_name: 'Billing Support Agent',
        role_type: 'specialist',
        agent_name: 'Business Intelligence Analyst',
        role_description: 'Handles billing, payment, and subscription tickets',
        responsibilities: 'Billing inquiries, payment issues, subscription changes, refund processing',
        goals: 'Resolve billing issues accurately; keep customers satisfied',
        capabilities: %w[billing_analysis payment_troubleshooting subscription_management],
        constraints: %w[pci_compliance refund_limits],
        tools_allowed: %w[billing_query payment_processing structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: false,
        member_role: 'executor'
      }
    ],
    channels: [
      {
        name: 'support-broadcast',
        channel_type: 'broadcast',
        description: 'Support team announcements and status updates',
        participant_roles: %w[Support\ Lead Technical\ Support\ Agent Billing\ Support\ Agent],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'message' => { 'type' => 'string' },
            'priority' => { 'type' => 'string' }
          }
        },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'support-tickets',
        channel_type: 'task',
        description: 'Ticket routing and assignment channel',
        participant_roles: %w[Support\ Lead Technical\ Support\ Agent Billing\ Support\ Agent],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'ticket_id' => { 'type' => 'string' },
            'action' => { 'type' => 'string' },
            'category' => { 'type' => 'string' }
          }
        },
        routing_rules: { 'round_robin' => true, 'category_routing' => true }
      }
    ]
  },
  {
    name: 'Architecture Review Board',
    description: 'Mesh team for collaborative architecture reviews. Peers evaluate proposals on security, performance, and design via auction-based task claiming.',
    team_type: 'mesh',
    coordination_strategy: 'auction',
    goal_description: 'Review architectures for security, performance, and design quality',
    team_config: {
      'max_iterations' => 6,
      'timeout_seconds' => 1200,
      'retry_on_failure' => true,
      'max_retries' => 1,
      'auction_timeout_seconds' => 60,
      'consensus_threshold' => 0.7
    },
    review_config: {
      'default' => { 'mode' => 'blocking', 'require_approval' => true }
    },
    roles: [
      {
        role_name: 'Lead Architect',
        role_type: 'coordinator',
        agent_name: 'Process Automation Optimizer',
        role_description: 'Coordinates reviews and synthesizes findings into decisions',
        responsibilities: 'Review coordination, decision synthesis, trade-off analysis, documentation',
        goals: 'Sound architecture decisions with documented rationale',
        capabilities: %w[architecture_analysis trade_off_evaluation decision_synthesis documentation],
        constraints: %w[document_all_decisions consider_all_perspectives],
        tools_allowed: %w[diagram_analysis structured_output document_generation],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: true,
        member_role: 'coordinator'
      },
      {
        role_name: 'Security Reviewer',
        role_type: 'reviewer',
        agent_name: 'Infrastructure Health Monitor',
        role_description: 'Evaluates proposals for security risk and threat modeling',
        responsibilities: 'Threat modeling, security pattern review, compliance validation, risk assessment',
        goals: 'Identify and mitigate security risks in proposed architectures',
        capabilities: %w[threat_modeling security_analysis compliance_review risk_assessment],
        constraints: %w[owasp_top_10 zero_trust_principles],
        tools_allowed: %w[security_scanning code_analysis structured_output],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'reviewer'
      },
      {
        role_name: 'Performance Reviewer',
        role_type: 'reviewer',
        agent_name: 'DevOps Pipeline Operator',
        role_description: 'Evaluates proposals for scalability, performance, resource efficiency',
        responsibilities: 'Performance modeling, scalability analysis, resource estimation, bottleneck identification',
        goals: 'Ensure architectures meet performance targets at projected scale',
        capabilities: %w[performance_modeling scalability_analysis capacity_planning bottleneck_detection],
        constraints: %w[load_testing_required sla_compliance],
        tools_allowed: %w[performance_analysis metric_collection structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'reviewer'
      }
    ],
    channels: [
      {
        name: 'arb-discussion',
        channel_type: 'topic',
        description: 'Review discussions and proposal analysis',
        participant_roles: %w[Lead\ Architect Security\ Reviewer Performance\ Reviewer],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'topic' => { 'type' => 'string' },
            'review_type' => { 'type' => 'string' },
            'message' => { 'type' => 'string' }
          }
        },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'arb-decisions',
        channel_type: 'broadcast',
        description: 'Final architecture decisions and ADR announcements',
        participant_roles: %w[Lead\ Architect Security\ Reviewer Performance\ Reviewer],
        message_schema: {
          'type' => 'object',
          'properties' => {
            'decision_id' => { 'type' => 'string' },
            'status' => { 'type' => 'string', 'enum' => %w[proposed approved rejected deferred] },
            'rationale' => { 'type' => 'string' }
          }
        },
        routing_rules: { 'broadcast_to_all' => true }
      }
    ]
  }
]

# ---------------------------------------------------------------------------
# Create Teams, Roles, Channels, Members
# ---------------------------------------------------------------------------
teams_created = 0
roles_created = 0
channels_created = 0
members_created = 0

teams_data.each do |td|
  team = Ai::AgentTeam.find_or_create_by!(account: admin_account, name: td[:name]) do |t|
    t.description = td[:description]
    t.team_type = td[:team_type]
    t.coordination_strategy = td[:coordination_strategy]
    t.goal_description = td[:goal_description]
    t.team_config = td[:team_config]
    t.review_config = td[:review_config]
    t.status = 'active'
  end
  teams_created += 1

  td[:roles].each do |rd|
    agent = agents[rd[:agent_name]]
    next unless agent

    Ai::TeamRole.find_or_create_by!(agent_team: team, role_name: rd[:role_name]) do |r|
      r.account = admin_account
      r.ai_agent = agent
      r.role_type = rd[:role_type]
      r.role_description = rd[:role_description]
      r.responsibilities = rd[:responsibilities]
      r.goals = rd[:goals]
      r.capabilities = rd[:capabilities]
      r.constraints = rd[:constraints]
      r.tools_allowed = rd[:tools_allowed]
      r.priority_order = rd[:priority_order]
      r.can_delegate = rd[:can_delegate]
      r.can_escalate = rd[:can_escalate]
      r.max_concurrent_tasks = rd[:max_concurrent_tasks]
    end
    roles_created += 1

    Ai::AgentTeamMember.find_or_create_by!(
      ai_agent_team_id: team.id,
      ai_agent_id: agent.id
    ) do |m|
      m.role = rd[:member_role]
      m.is_lead = rd[:is_lead]
      m.priority_order = rd[:priority_order]
      m.capabilities = rd[:capabilities]
    end
    members_created += 1
  end

  td[:channels].each do |cd|
    Ai::TeamChannel.find_or_create_by!(agent_team: team, name: cd[:name]) do |c|
      c.channel_type = cd[:channel_type]
      c.description = cd[:description]
      c.participant_roles = cd[:participant_roles]
      c.message_schema = cd[:message_schema]
      c.routing_rules = cd[:routing_rules]
      c.is_persistent = true
    end
    channels_created += 1
  end

  puts "  ✅ Team '#{team.name}' (#{td[:team_type]}) — #{td[:roles].size} roles, #{td[:channels].size} channels"
end

# ===========================================================================
# 8 MARKETPLACE TEMPLATES (Ai::AgentTemplate)
# ===========================================================================

# Ensure a system publisher exists for marketplace templates
system_publisher = if defined?(Ai::PublisherAccount)
  Ai::PublisherAccount.find_by(account_id: admin_account.id) ||
    Ai::PublisherAccount.create!(
      account: admin_account,
      primary_user: admin_user,
      publisher_name: 'Powernode',
      publisher_slug: 'powernode',
      description: 'Official Powernode marketplace publisher',
      status: 'active',
      verification_status: 'verified',
      verified_at: Time.current,
      revenue_share_percentage: 70,
      lifetime_earnings_usd: 0.0,
      pending_payout_usd: 0.0,
      total_templates: 0,
      total_installations: 0,
      support_email: 'support@example.com',
      branding: {},
      payout_settings: {}
    )
end

templates_data = [
  {
    name: 'SaaS Customer Success Bot',
    slug: 'powernode-saas-customer-success-bot',
    description: 'Customer success agent for SaaS: onboarding, health scoring, churn prediction, proactive outreach.',
    long_description: 'Customer success template for SaaS. Includes onboarding sequences, usage-based health scoring, churn-risk early warnings, and automated outreach campaigns. Integrates with common CRM and support tools.',
    category: 'customer_support',
    vertical: 'saas',
    pricing_type: 'free',
    price_usd: nil,
    is_featured: true,
    agent_config: {
      'agent_type' => 'assistant',
      'model_recommendation' => 'claude-sonnet-4-5-20250929',
      'temperature' => 0.4,
      'max_tokens' => 4096,
      'capabilities' => %w[onboarding health_scoring churn_prediction outreach]
    },
    default_settings: {
      'onboarding_steps' => 5,
      'health_check_interval' => 'weekly',
      'churn_risk_threshold' => 0.7
    },
    required_tools: %w[crm_integration email_sender analytics_reader],
    sample_prompts: [
      'Analyze the health score for account ABC Corp and suggest next actions',
      'Generate an onboarding sequence for a new enterprise customer',
      'Identify accounts at risk of churning this quarter'
    ],
    tags: %w[saas customer-success onboarding churn-prevention],
    features: ['Automated onboarding sequences', 'Health score calculation', 'Churn risk prediction', 'Proactive outreach campaigns'],
    supported_providers: %w[anthropic openai]
  },
  {
    name: 'E-Commerce Product Recommender',
    slug: 'powernode-ecommerce-product-recommender',
    description: 'Product recommendation engine for e-commerce using browsing history, purchase patterns, and collaborative filtering.',
    long_description: 'Recommendation system for e-commerce. Uses browsing behavior, purchase history, and collaborative filtering for personalized suggestions. Supports cross-sell, upsell, and bundles with configurable strategies.',
    category: 'data',
    vertical: 'ecommerce',
    pricing_type: 'freemium',
    price_usd: 29.99,
    is_featured: false,
    agent_config: {
      'agent_type' => 'data_analyst',
      'model_recommendation' => 'gpt-4o',
      'temperature' => 0.2,
      'max_tokens' => 2048,
      'capabilities' => %w[recommendation collaborative_filtering personalization]
    },
    default_settings: {
      'recommendation_count' => 10,
      'algorithm' => 'hybrid_collaborative',
      'refresh_interval' => 'hourly'
    },
    required_tools: %w[product_catalog user_analytics purchase_history],
    sample_prompts: [
      'Generate top 10 product recommendations for customer segment "frequent buyers"',
      'Analyze cross-sell opportunities for the electronics category',
      'Create a personalized bundle for customer with ID 12345'
    ],
    tags: %w[ecommerce recommendations personalization cross-selling],
    features: ['Collaborative filtering', 'Content-based filtering', 'Cross-sell/upsell logic', 'A/B testing support'],
    supported_providers: %w[openai anthropic]
  },
  {
    name: 'Healthcare Triage Assistant',
    slug: 'powernode-healthcare-triage-assistant',
    description: 'Medical intake triage for healthcare providers: collects symptoms, assesses urgency, routes to departments.',
    long_description: 'HIPAA-aware triage assistant. Guides structured symptom collection, assesses urgency via evidence-based protocols, and routes cases to clinical departments. Includes consent workflows and audit logging.',
    category: 'customer_support',
    vertical: 'healthcare',
    pricing_type: 'subscription',
    price_usd: nil,
    monthly_price_usd: 99.99,
    is_featured: false,
    agent_config: {
      'agent_type' => 'assistant',
      'model_recommendation' => 'claude-sonnet-4-5-20250929',
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'capabilities' => %w[symptom_collection urgency_assessment department_routing consent_management]
    },
    default_settings: {
      'triage_protocol' => 'ESI_5_level',
      'consent_required' => true,
      'audit_logging' => true,
      'max_assessment_time_minutes' => 15
    },
    required_tools: %w[ehr_integration scheduling_system consent_manager],
    sample_prompts: [
      'Begin triage assessment for a new patient presenting with chest pain',
      'Route this case to the appropriate department based on assessment',
      'Generate a triage summary report for the last 24 hours'
    ],
    tags: %w[healthcare triage medical hipaa-compliant],
    features: ['ESI 5-level triage', 'HIPAA-aware processing', 'Consent management', 'EHR integration ready'],
    supported_providers: %w[anthropic]
  },
  {
    name: 'EdTech Course Builder',
    slug: 'powernode-edtech-course-builder',
    description: 'Course creation assistant for edtech: curriculum outlines, lesson plans, assessments, learning objectives.',
    long_description: 'Course-building assistant for edtech. Creates curriculum outlines with standards-aligned objectives, lesson plans with activities and resources, assessments with rubrics, and multimedia suggestions.',
    category: 'productivity',
    vertical: 'education',
    pricing_type: 'one_time',
    price_usd: 49.99,
    is_featured: false,
    agent_config: {
      'agent_type' => 'content_generator',
      'model_recommendation' => 'claude-sonnet-4-5-20250929',
      'temperature' => 0.5,
      'max_tokens' => 8192,
      'capabilities' => %w[curriculum_design lesson_planning assessment_creation content_generation]
    },
    default_settings: {
      'education_level' => 'higher_education',
      'standard_alignment' => 'blooms_taxonomy',
      'assessment_types' => %w[quiz essay project rubric]
    },
    required_tools: %w[content_library media_manager lms_integration],
    sample_prompts: [
      'Create a 12-week curriculum for Introduction to Data Science',
      'Generate lesson plans for week 3 covering data visualization',
      'Design a final project assessment with rubric for the machine learning module'
    ],
    tags: %w[education course-building curriculum edtech],
    features: ['Curriculum generation', 'Lesson plan creation', 'Assessment design', 'Standards alignment'],
    supported_providers: %w[anthropic openai]
  },
  {
    name: 'FinTech Compliance Monitor',
    slug: 'powernode-fintech-compliance-monitor',
    description: 'Regulatory compliance monitor for fintech: tracks regulatory changes, assesses impact, generates reports.',
    long_description: 'Continuous compliance monitor for fintech. Tracks regulatory changes across jurisdictions, assesses business impact, runs gap analyses, and produces audit-ready reports. Covers PCI DSS, SOX, AML/KYC, GDPR.',
    category: 'legal',
    vertical: 'fintech',
    pricing_type: 'subscription',
    price_usd: nil,
    monthly_price_usd: 149.99,
    is_featured: false,
    agent_config: {
      'agent_type' => 'monitor',
      'model_recommendation' => 'gpt-4o',
      'temperature' => 0.1,
      'max_tokens' => 8192,
      'capabilities' => %w[regulatory_tracking impact_assessment gap_analysis report_generation]
    },
    default_settings: {
      'jurisdictions' => %w[US EU UK],
      'frameworks' => %w[PCI_DSS SOX AML_KYC GDPR],
      'scan_frequency' => 'daily',
      'alert_threshold' => 'medium'
    },
    required_tools: %w[regulatory_feed compliance_database audit_logger],
    sample_prompts: [
      'Scan for new PCI DSS requirement changes published this month',
      'Generate a compliance gap analysis for our payment processing module',
      'Produce a quarterly SOX compliance report for the audit committee'
    ],
    tags: %w[fintech compliance regulatory pci-dss sox],
    features: ['Multi-jurisdiction tracking', 'Automated gap analysis', 'Audit-ready reports', 'Real-time regulatory alerts'],
    supported_providers: %w[openai anthropic]
  },
  {
    name: 'Marketing Campaign Orchestrator',
    slug: 'powernode-marketing-campaign-orchestrator',
    description: 'End-to-end campaign manager: plans, creates, schedules, and analyzes multi-channel marketing campaigns.',
    long_description: 'Full-lifecycle campaign orchestrator. Plans strategy and timeline, generates content for email/social/web, schedules across platforms, and analyzes performance with optimization recommendations. Supports A/B testing.',
    category: 'marketing',
    vertical: 'marketing',
    pricing_type: 'usage_based',
    price_usd: nil,
    is_featured: false,
    agent_config: {
      'agent_type' => 'assistant',
      'model_recommendation' => 'claude-sonnet-4-5-20250929',
      'temperature' => 0.5,
      'max_tokens' => 4096,
      'capabilities' => %w[campaign_planning content_creation scheduling analytics]
    },
    default_settings: {
      'channels' => %w[email social_media web],
      'ab_testing' => true,
      'analytics_interval' => 'daily',
      'usage_unit' => 'campaign_execution'
    },
    required_tools: %w[email_platform social_scheduler analytics_dashboard crm],
    sample_prompts: [
      'Plan a 4-week product launch campaign across email and social media',
      'Generate A/B test variants for the Q3 newsletter subject line',
      'Analyze the performance of last month campaigns and suggest optimizations'
    ],
    tags: %w[marketing campaigns automation multi-channel],
    features: ['Multi-channel orchestration', 'A/B testing workflows', 'Performance analytics', 'Content generation'],
    supported_providers: %w[anthropic openai]
  },
  {
    name: 'DevOps Incident Commander',
    slug: 'powernode-devops-incident-commander',
    description: 'Incident manager for DevOps: detects incidents, coordinates response, manages comms, produces post-mortems.',
    long_description: 'Incident management assistant for DevOps/SRE. Detects metric anomalies, starts response workflows, coordinates comms, updates status pages, and generates post-mortems with action items.',
    category: 'productivity',
    vertical: 'devops',
    pricing_type: 'free',
    price_usd: nil,
    is_featured: true,
    agent_config: {
      'agent_type' => 'assistant',
      'model_recommendation' => 'claude-haiku-4-5-20251001',
      'temperature' => 0.1,
      'max_tokens' => 4096,
      'capabilities' => %w[incident_detection response_coordination communication post_mortem]
    },
    default_settings: {
      'severity_levels' => %w[SEV1 SEV2 SEV3 SEV4],
      'auto_detect' => true,
      'status_page_integration' => true,
      'post_mortem_template' => 'standard'
    },
    required_tools: %w[monitoring_api pager_integration status_page slack_integration],
    sample_prompts: [
      'Initiate incident response for elevated error rates on the payment service',
      'Generate a status page update for the ongoing database latency issue',
      'Create a post-mortem report for yesterday SEV2 incident'
    ],
    tags: %w[devops incident-management sre post-mortem],
    features: ['Automated incident detection', 'Response coordination', 'Status page management', 'Post-mortem generation'],
    supported_providers: %w[anthropic openai]
  },
  {
    name: 'Research Paper Analyzer',
    slug: 'powernode-research-paper-analyzer',
    description: 'Academic research analyzer: summarizes papers, extracts findings, finds methodology gaps, drafts literature reviews.',
    long_description: 'Research analysis assistant for academic/R&D teams. Extracts findings, methodology, and statistics from papers; identifies gaps; compares across papers; and drafts cited literature-review sections.',
    category: 'data',
    vertical: 'research',
    pricing_type: 'freemium',
    price_usd: 19.99,
    is_featured: false,
    agent_config: {
      'agent_type' => 'data_analyst',
      'model_recommendation' => 'gpt-4o',
      'temperature' => 0.2,
      'max_tokens' => 8192,
      'capabilities' => %w[paper_summarization finding_extraction methodology_analysis literature_review]
    },
    default_settings: {
      'citation_style' => 'APA7',
      'summary_length' => 'detailed',
      'extract_statistics' => true,
      'cross_reference' => true
    },
    required_tools: %w[pdf_reader citation_manager research_database],
    sample_prompts: [
      'Summarize this paper and extract the key findings and methodology',
      'Compare the results across these 5 papers on transformer architectures',
      'Generate a literature review section covering recent advances in LLM alignment'
    ],
    tags: %w[research academic analysis literature-review],
    features: ['Paper summarization', 'Finding extraction', 'Methodology analysis', 'Literature review generation'],
    supported_providers: %w[openai anthropic]
  }
]

templates_created = 0

# Marketplace templates require a publisher: ai_agent_templates.publisher_id is
# NOT NULL, and Ai::PublisherAccount is a business-extension model. In core mode
# system_publisher is nil, so skip this section — the agents/teams/skills above
# are core and seed regardless.
puts "  ⏭️  Marketplace templates skipped (publisher is business-only — core mode)" unless system_publisher
(system_publisher ? templates_data : []).each do |td|
  template = Ai::AgentTemplate.find_or_initialize_by(slug: td[:slug])
  template.assign_attributes(
    name: td[:name],
    description: td[:description],
    long_description: td[:long_description],
    version: '1.0.0',
    status: 'published',
    visibility: 'public',
    category: td[:category],
    vertical: td[:vertical],
    pricing_type: td[:pricing_type],
    price_usd: td[:price_usd],
    monthly_price_usd: td[:monthly_price_usd],
    is_featured: td[:is_featured],
    is_verified: true,
    agent_config: td[:agent_config],
    default_settings: td[:default_settings],
    required_tools: td[:required_tools],
    sample_prompts: td[:sample_prompts],
    tags: td[:tags],
    features: td[:features],
    supported_providers: td[:supported_providers],
    published_at: Time.current
  )
  template.publisher = system_publisher if system_publisher && template.respond_to?(:publisher=)
  template.save!
  templates_created += 1
  puts "  ✅ Template '#{template.name}' (#{td[:pricing_type]}, #{td[:vertical]})"
end
end # if seed_instances (agents, teams, marketplace templates)

# ===========================================================================
# 10 SKILLS (Ai::Skill) — GLOBAL baseline CONTENT (account_id nil, source_key)
# ===========================================================================
skills_data = [
  {
    name: 'Code Generation',
    description: 'Generate production-quality code across languages with error handling, tests, and documentation.',
    category: 'productivity',
    system_prompt: 'Generate clean, documented, tested code per target language/framework best practices.',
    commands: [
      { 'name' => 'generate_code', 'description' => 'Generate code from a specification', 'parameters' => %w[language specification] },
      { 'name' => 'refactor_code', 'description' => 'Refactor existing code for improvement', 'parameters' => %w[code language improvements] }
    ],
    tags: %w[code programming development generation]
  },
  {
    name: 'Database Design',
    description: 'Design schemas, write migrations, optimize queries, plan indexes for relational and document databases.',
    category: 'data',
    system_prompt: 'Design efficient schemas with proper normalization, indexing, and query optimization.',
    commands: [
      { 'name' => 'design_schema', 'description' => 'Design a database schema', 'parameters' => %w[requirements database_type] },
      { 'name' => 'optimize_query', 'description' => 'Optimize a slow database query', 'parameters' => %w[query schema] }
    ],
    tags: %w[database schema sql design optimization]
  },
  {
    name: 'API Design',
    description: 'Design REST and GraphQL APIs with auth, versioning, pagination, and error handling.',
    category: 'productivity',
    system_prompt: 'Design well-structured REST/GraphQL APIs with comprehensive documentation.',
    commands: [
      { 'name' => 'design_api', 'description' => 'Design API endpoints for a resource', 'parameters' => %w[resource operations auth_type] },
      { 'name' => 'generate_openapi', 'description' => 'Generate OpenAPI specification', 'parameters' => %w[endpoints] }
    ],
    tags: %w[api rest graphql design documentation]
  },
  {
    name: 'Security Audit',
    description: 'Audit for OWASP Top 10, dependency vulnerabilities, auth flows, and data-protection compliance.',
    category: 'business_search',
    system_prompt: 'Audit for vulnerabilities, misconfigurations, and compliance gaps.',
    commands: [
      { 'name' => 'audit_code', 'description' => 'Audit code for security vulnerabilities', 'parameters' => %w[code language framework] },
      { 'name' => 'check_dependencies', 'description' => 'Check dependencies for known CVEs', 'parameters' => %w[manifest_file] }
    ],
    tags: %w[security audit owasp vulnerability compliance]
  },
  {
    name: 'Performance Tuning',
    description: 'Optimize app performance: database queries, API response times, memory, caching.',
    category: 'data',
    system_prompt: 'Find bottlenecks; recommend optimizations with measurable targets.',
    commands: [
      { 'name' => 'profile_endpoint', 'description' => 'Profile an API endpoint for performance', 'parameters' => %w[endpoint metrics] },
      { 'name' => 'recommend_caching', 'description' => 'Recommend caching strategy', 'parameters' => %w[access_patterns data_volatility] }
    ],
    tags: %w[performance optimization caching profiling tuning]
  },
  {
    name: 'DevOps Automation',
    description: 'Automate CI/CD pipelines, infrastructure provisioning, deployments, and monitoring.',
    category: 'productivity',
    system_prompt: 'Build reliable, repeatable infrastructure and deployment automation.',
    commands: [
      { 'name' => 'create_pipeline', 'description' => 'Create a CI/CD pipeline configuration', 'parameters' => %w[platform stages triggers] },
      { 'name' => 'provision_infra', 'description' => 'Generate infrastructure-as-code', 'parameters' => %w[provider resources environment] }
    ],
    tags: %w[devops cicd automation infrastructure deployment]
  },
  {
    name: 'Content Localization',
    description: 'Localize content: translation, cultural adaptation, date/currency formatting, RTL support.',
    category: 'marketing',
    system_prompt: 'Localize for target markets: language, culture, formatting, accessibility.',
    commands: [
      { 'name' => 'localize_content', 'description' => 'Localize content for a target market', 'parameters' => %w[content source_locale target_locale] },
      { 'name' => 'extract_strings', 'description' => 'Extract localizable strings from code', 'parameters' => %w[source_files format] }
    ],
    tags: %w[localization i18n translation content international]
  },
  {
    name: 'Incident Analysis',
    description: 'Analyze production incidents: root cause, impact, timeline reconstruction, remediation planning.',
    category: 'productivity',
    system_prompt: 'Analyze incidents: identify root cause, assess impact, define prevention.',
    commands: [
      { 'name' => 'analyze_incident', 'description' => 'Perform root cause analysis on an incident', 'parameters' => %w[incident_id logs metrics timeline] },
      { 'name' => 'generate_postmortem', 'description' => 'Generate a post-mortem report', 'parameters' => %w[incident_id findings] }
    ],
    tags: %w[incident analysis postmortem root-cause sre]
  },
  {
    name: 'User Research',
    description: 'Design and analyze user studies: surveys, interviews, usability tests, behavioral analytics.',
    category: 'product_management',
    system_prompt: 'Design user studies and analyze findings to inform product decisions.',
    commands: [
      { 'name' => 'design_study', 'description' => 'Design a user research study', 'parameters' => %w[research_question method target_audience] },
      { 'name' => 'analyze_feedback', 'description' => 'Analyze user feedback data', 'parameters' => %w[feedback_data categories] }
    ],
    tags: %w[user-research ux surveys usability feedback]
  },
  {
    name: 'Compliance Review',
    description: 'Review systems and processes against GDPR, SOC 2, HIPAA, PCI DSS, ISO 27001.',
    category: 'legal',
    system_prompt: 'Review compliance, identify gaps, recommend prioritized remediation.',
    commands: [
      { 'name' => 'assess_compliance', 'description' => 'Assess compliance against a framework', 'parameters' => %w[framework scope evidence] },
      { 'name' => 'generate_report', 'description' => 'Generate a compliance report', 'parameters' => %w[framework findings] }
    ],
    tags: %w[compliance gdpr sox hipaa pci-dss iso27001]
  }
]

skills_created = 0

skills_data.each do |sd|
  # GLOBAL content: account_id nil, upserted by source_key (= parameterized name).
  source_key = sd[:name].parameterize
  skill = Ai::Skill.find_or_initialize_by(source_key: source_key, account_id: nil)
  skill.slug = source_key
  skill.assign_attributes(
    name: sd[:name],
    description: sd[:description],
    category: sd[:category],
    status: 'active',
    version: '1.0.0',
    is_system: true,
    is_enabled: true,
    system_prompt: sd[:system_prompt],
    commands: sd[:commands],
    tags: sd[:tags],
    metadata: { 'source' => 'seed', 'skill_type' => 'capability' }
  )
  skill.save!
  skills_created += 1
  puts "  ✅ Skill '#{skill.name}' (#{sd[:category]})"
end

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n📊 AI Example Templates Summary:"
puts "   Agents: #{agents_created}"
puts "   Teams: #{teams_created}"
puts "   Team Roles: #{roles_created}"
puts "   Team Members: #{members_created}"
puts "   Team Channels: #{channels_created}"
puts "   Marketplace Templates: #{templates_created}"
puts "   Skills: #{skills_created}"
puts "✅ AI Example Templates seeding completed!"
