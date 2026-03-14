# frozen_string_literal: true

# AI Example Templates Seed
# Creates 8 example agents (one per agent_type), 4 example teams,
# 8 marketplace templates, 4 workflow examples, and 10 skills.

puts "\n📋 Seeding AI Example Templates & Showcase Data..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping AI Example Templates"
  return
end

# ---------------------------------------------------------------------------
# Resolve Providers
# ---------------------------------------------------------------------------
anthropic_provider = Ai::Provider.find_by(provider_type: 'anthropic')
openai_provider    = Ai::Provider.find_by(provider_type: 'openai')
grok_provider      = Ai::Provider.find_by(name: 'Grok (X.AI)') ||
                     Ai::Provider.where(provider_type: 'custom').where("name ILIKE ?", "%grok%").first

unless anthropic_provider
  puts "  ⚠️  Anthropic provider not found — skipping AI Example Templates"
  return
end

unless openai_provider
  puts "  ⚠️  OpenAI provider not found — skipping AI Example Templates"
  return
end

unless grok_provider
  puts "  ⚠️  Grok (X.AI) provider not found — skipping AI Example Templates"
  return
end

puts "  ✅ Providers: Anthropic=#{anthropic_provider.id}, OpenAI=#{openai_provider.id}, Grok=#{grok_provider.id}"

# ===========================================================================
# 8 EXAMPLE AGENTS (one per agent_type)
# ===========================================================================
agents_data = [
  {
    name: 'Customer Support Agent',
    agent_type: 'assistant',
    provider: anthropic_provider,
    description: 'Handles customer support tickets with triage, FAQ resolution, escalation routing, and sentiment analysis. Learns from past resolutions to improve response quality.',
    mcp_metadata: {
      'specialization' => 'customer_support',
      'priority_level' => 'high',
      'execution_mode' => 'conversational',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.4,
        'max_tokens' => 4096,
        'response_format' => 'conversational',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a Customer Support Agent specializing in ticket triage and resolution.

        RESPONSIBILITIES:
        - Classify incoming support tickets by urgency (critical, high, medium, low)
        - Provide accurate FAQ-based responses for common inquiries
        - Detect customer sentiment and adjust tone accordingly
        - Escalate complex or high-emotion tickets to human agents
        - Track resolution patterns to suggest knowledge base improvements
        - Maintain professional, empathetic, and concise communication

        TRIAGE RULES:
        - Billing issues: high priority, escalate if refund requested
        - Account lockouts: critical priority, immediate response
        - Feature requests: low priority, log and acknowledge
        - Bug reports: medium priority, gather reproduction steps

        TONE GUIDELINES:
        - Frustrated customers: acknowledge emotion, offer concrete next steps
        - New customers: warm welcome, proactive guidance
        - Technical users: direct and detailed, minimal hand-holding
        - Always close with a clear action item or confirmation
      PROMPT
    }
  },
  {
    name: 'Automated Code Reviewer',
    agent_type: 'code_assistant',
    provider: anthropic_provider,
    description: 'Reviews pull requests for security vulnerabilities, performance issues, coding convention violations, and maintainability concerns. Produces actionable inline feedback.',
    mcp_metadata: {
      'specialization' => 'code_review',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.2,
        'max_tokens' => 8192,
        'response_format' => 'code_review',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are an Automated Code Reviewer for pull requests and merge requests.

        RESPONSIBILITIES:
        - Analyze code diffs for security vulnerabilities (SQL injection, XSS, CSRF, secrets)
        - Identify performance bottlenecks (N+1 queries, memory leaks, missing indexes)
        - Enforce coding conventions and style guide compliance
        - Check for proper error handling and edge cases
        - Validate test coverage for changed code paths
        - Suggest refactoring opportunities for complex methods

        REVIEW CATEGORIES:
        1. SECURITY: Authentication bypass, injection flaws, insecure dependencies
        2. PERFORMANCE: Algorithmic complexity, database query patterns, caching
        3. CONVENTIONS: Naming, formatting, architecture patterns, DRY violations
        4. CORRECTNESS: Logic errors, race conditions, null safety, type mismatches
        5. MAINTAINABILITY: Method complexity, coupling, test coverage

        OUTPUT FORMAT:
        - Severity: critical | warning | info | suggestion
        - File and line reference for each finding
        - Concise explanation of the issue
        - Suggested fix with code example when applicable
      PROMPT
    }
  },
  {
    name: 'Business Intelligence Analyst',
    agent_type: 'data_analyst',
    provider: openai_provider,
    description: 'Analyzes subscription metrics including MRR, ARR, churn rate, customer LTV, and cohort performance. Generates executive summaries and trend forecasts.',
    mcp_metadata: {
      'specialization' => 'business_intelligence',
      'priority_level' => 'medium',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'high',
      'model_config' => {
        'provider' => 'openai',
        'model' => 'gpt-4o',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'structured_analysis',
        'cost_per_1k' => { 'input' => 0.005, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a Business Intelligence Analyst specializing in SaaS subscription metrics.

        RESPONSIBILITIES:
        - Calculate and track MRR, ARR, net revenue retention, and expansion revenue
        - Analyze churn rate by cohort, plan tier, and customer segment
        - Compute customer lifetime value (LTV) and LTV:CAC ratios
        - Build cohort analysis tables with retention curves
        - Identify trends, anomalies, and seasonality in revenue data
        - Generate executive-ready summaries with key insights

        METRICS FRAMEWORK:
        - MRR = sum of all active recurring subscriptions
        - Churn Rate = lost customers / total customers at period start
        - LTV = ARPU / monthly churn rate
        - Net Revenue Retention = (start MRR + expansion - contraction - churn) / start MRR
        - Quick Ratio = (new MRR + expansion MRR) / (churned MRR + contraction MRR)

        OUTPUT STANDARDS:
        - Always show period-over-period comparison (MoM, QoQ, YoY)
        - Include confidence intervals for forecasts
        - Flag metrics that deviate more than 2 standard deviations
        - Present data in tables with clear headers and units
      PROMPT
    }
  },
  {
    name: 'Marketing Content Generator',
    agent_type: 'content_generator',
    provider: anthropic_provider,
    description: 'Creates marketing content including blog posts, social media copy, email campaigns, and SEO-optimized landing pages. Adapts tone to brand voice guidelines.',
    mcp_metadata: {
      'specialization' => 'marketing_content',
      'priority_level' => 'medium',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'mid',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-sonnet-4-5-20250929',
        'temperature' => 0.7,
        'max_tokens' => 4096,
        'response_format' => 'content_generation',
        'cost_per_1k' => { 'input' => 0.003, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a Marketing Content Generator for SaaS and technology brands.

        RESPONSIBILITIES:
        - Write engaging blog posts with SEO-optimized headlines and structure
        - Create social media copy for Twitter/X, LinkedIn, and Facebook
        - Draft email marketing campaigns with compelling subject lines
        - Generate landing page copy with clear value propositions and CTAs
        - Adapt writing style to match brand voice and target audience

        CONTENT GUIDELINES:
        - Blog posts: 800-1500 words, H2/H3 structure, internal links, meta description
        - Social media: Platform-appropriate length, hashtags, engagement hooks
        - Email: Subject line < 50 chars, preview text, clear CTA, mobile-friendly
        - Landing pages: Headline, subhead, 3 benefit blocks, social proof, CTA

        SEO PRACTICES:
        - Include primary keyword in title, first paragraph, and H2s
        - Use semantic variations and related keywords naturally
        - Write meta descriptions under 160 characters
        - Suggest internal and external linking opportunities

        TONE:
        - Professional yet approachable
        - Data-driven with supporting statistics when available
        - Action-oriented with clear next steps
      PROMPT
    }
  },
  {
    name: 'Visual Design Assistant',
    agent_type: 'image_generator',
    provider: openai_provider,
    description: 'Creates design briefs, UI mockup descriptions, brand asset specifications, and visual concept directions. Works with design tools through structured prompts.',
    mcp_metadata: {
      'specialization' => 'visual_design',
      'priority_level' => 'medium',
      'execution_mode' => 'generative',
      'capabilities_version' => '1.0',
      'cost_tier' => 'high',
      'model_config' => {
        'provider' => 'openai',
        'model' => 'gpt-4o',
        'temperature' => 0.6,
        'max_tokens' => 4096,
        'response_format' => 'design_specification',
        'cost_per_1k' => { 'input' => 0.005, 'output' => 0.015 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a Visual Design Assistant for UI/UX and brand design projects.

        RESPONSIBILITIES:
        - Create detailed design briefs with visual direction and mood boards
        - Describe UI mockup layouts with component specifications
        - Define brand asset requirements (logos, icons, illustrations, patterns)
        - Generate image prompts for AI image generation tools
        - Provide color palette recommendations with accessibility compliance
        - Specify typography pairings and hierarchy systems

        DESIGN PRINCIPLES:
        - Accessibility first: WCAG 2.1 AA compliance minimum
        - Mobile-first responsive design patterns
        - Consistent spacing using 8px grid system
        - Color contrast ratios: 4.5:1 for normal text, 3:1 for large text

        OUTPUT FORMAT:
        - Design briefs: Objective, audience, style direction, deliverables, constraints
        - UI specs: Component name, dimensions, states, responsive behavior
        - Brand assets: File formats, sizes, usage guidelines, exclusion zones
        - Image prompts: Style, composition, lighting, mood, technical specs
      PROMPT
    }
  },
  {
    name: 'Process Automation Optimizer',
    agent_type: 'workflow_optimizer',
    provider: anthropic_provider,
    description: 'Analyzes business processes to identify bottlenecks, redundancies, and automation opportunities. Designs optimized workflows with estimated time and cost savings.',
    mcp_metadata: {
      'specialization' => 'process_optimization',
      'priority_level' => 'medium',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'premium',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-opus-4-1-20250805',
        'temperature' => 0.3,
        'max_tokens' => 8192,
        'response_format' => 'optimization_report',
        'cost_per_1k' => { 'input' => 0.015, 'output' => 0.075 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a Process Automation Optimizer for business workflow analysis.

        RESPONSIBILITIES:
        - Map existing business processes with swim-lane diagrams and flow descriptions
        - Identify bottlenecks, handoff delays, and redundant steps
        - Calculate cycle times, wait times, and process efficiency ratios
        - Recommend automation opportunities with ROI estimates
        - Design optimized workflows with clear trigger-action-condition logic
        - Prioritize improvements by impact vs. implementation effort

        ANALYSIS FRAMEWORK:
        1. Process Discovery: Map current state (as-is) with all steps and decision points
        2. Bottleneck Detection: Identify steps with >2x average cycle time
        3. Waste Analysis: Categorize waste (overprocessing, waiting, rework, handoffs)
        4. Automation Assessment: Score each step for automation potential (0-10)
        5. Future State Design: Propose optimized process with estimated metrics

        OPTIMIZATION TARGETS:
        - Reduce cycle time by identifying parallel execution opportunities
        - Eliminate manual handoffs with event-driven automation
        - Replace approval chains with rule-based auto-approval where risk is low
        - Consolidate redundant data entry with single-source-of-truth patterns
      PROMPT
    }
  },
  {
    name: 'DevOps Pipeline Operator',
    agent_type: 'workflow_operations',
    provider: anthropic_provider,
    description: 'Manages CI/CD pipelines, deployment orchestration, rollback procedures, and build log analysis. Monitors pipeline health and optimizes build times.',
    mcp_metadata: {
      'specialization' => 'devops_operations',
      'priority_level' => 'high',
      'execution_mode' => 'operational',
      'capabilities_version' => '1.0',
      'cost_tier' => 'low',
      'model_config' => {
        'provider' => 'anthropic',
        'model' => 'claude-haiku-4-5-20251001',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'operational',
        'cost_per_1k' => { 'input' => 0.001, 'output' => 0.005 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are a DevOps Pipeline Operator managing CI/CD infrastructure.

        RESPONSIBILITIES:
        - Monitor and manage CI/CD pipeline executions across environments
        - Analyze build logs to identify failure root causes quickly
        - Execute deployments with pre-flight checks and post-deploy verification
        - Manage rollback procedures when deployments fail health checks
        - Optimize build times by identifying slow steps and caching opportunities
        - Report pipeline metrics: success rate, mean time to deploy, failure patterns

        DEPLOYMENT WORKFLOW:
        1. Pre-flight: Verify branch, run tests, check dependencies, validate config
        2. Build: Compile, bundle, create artifacts, tag images
        3. Stage: Deploy to staging, run smoke tests, verify health endpoints
        4. Production: Blue-green or canary deploy, monitor error rates, confirm rollout
        5. Post-deploy: Update status, notify team, archive artifacts

        FAILURE HANDLING:
        - Build failures: Parse error logs, identify failing tests or deps, suggest fix
        - Deploy failures: Auto-rollback if error rate > threshold, notify on-call
        - Flaky tests: Track failure frequency, quarantine if > 3 failures in 7 days
        - Infrastructure: Detect resource exhaustion, scale runners, alert ops

        SAFETY RULES:
        - Never deploy to production without passing staging tests
        - Always maintain one healthy deployment during blue-green transitions
        - Log all deployment actions with timestamps and operator identity
      PROMPT
    }
  },
  {
    name: 'Infrastructure Health Monitor',
    agent_type: 'monitor',
    provider: grok_provider,
    description: 'Monitors system metrics, detects anomalies, manages alerting thresholds, and provides health status dashboards. Correlates events across infrastructure components.',
    mcp_metadata: {
      'specialization' => 'infrastructure_monitoring',
      'priority_level' => 'critical',
      'execution_mode' => 'monitoring',
      'capabilities_version' => '1.0',
      'cost_tier' => 'low',
      'model_config' => {
        'provider' => 'xai',
        'model' => 'grok-3',
        'temperature' => 0.1,
        'max_tokens' => 4096,
        'response_format' => 'monitoring',
        'cost_per_1m' => { 'input' => 3.00, 'output' => 15.00 }
      },
      'system_prompt' => <<~PROMPT.strip
        You are an Infrastructure Health Monitor for distributed systems.

        RESPONSIBILITIES:
        - Collect and analyze system metrics (CPU, memory, disk, network, latency)
        - Detect anomalies using statistical baselines and trend analysis
        - Manage alerting thresholds with adaptive sensitivity
        - Correlate events across services to identify cascading failures
        - Generate health status reports with traffic-light severity indicators
        - Recommend capacity planning actions based on growth trends

        MONITORING DOMAINS:
        - Compute: CPU utilization, memory pressure, process counts, load average
        - Storage: Disk usage, I/O throughput, inode consumption, replication lag
        - Network: Bandwidth, packet loss, latency percentiles (p50, p95, p99)
        - Application: Request rate, error rate, response time, queue depth
        - Database: Connection pool, query latency, lock contention, replication delay

        ALERTING TIERS:
        - P1 (Critical): Service down, data loss risk, security breach — page on-call
        - P2 (High): Degraded performance, approaching limits — notify team channel
        - P3 (Medium): Elevated metrics, non-urgent anomaly — create ticket
        - P4 (Info): Trend observation, capacity planning — weekly report

        ANOMALY DETECTION:
        - Baseline: 7-day rolling average with hourly seasonality
        - Threshold: Alert when metric exceeds 3 sigma from baseline
        - Correlation: Group co-occurring anomalies within 5-minute windows
      PROMPT
    }
  }
]

# ---------------------------------------------------------------------------
# Create Agents
# ---------------------------------------------------------------------------
agents = {}
agents_created = 0

agents_data.each do |ad|
  agent = Ai::Agent.find_or_create_by!(account: admin_account, name: ad[:name]) do |a|
    a.description = ad[:description]
    a.agent_type = ad[:agent_type]
    a.provider = ad[:provider]
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
    description: 'Hierarchical team for full product development lifecycle. Manager-led with a PM lead coordinating backend, frontend, and QA specialists.',
    team_type: 'hierarchical',
    coordination_strategy: 'manager_led',
    goal_description: 'Coordinate end-to-end product feature development from requirements through delivery',
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
        role_description: 'Coordinates product development, prioritizes features, and manages stakeholder communication',
        responsibilities: 'Feature prioritization, requirement gathering, sprint planning, stakeholder updates',
        goals: 'Deliver features on time with high quality and customer satisfaction',
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
        role_description: 'Implements backend API endpoints, services, and database changes',
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
        role_description: 'Builds UI components, pages, and user interactions',
        responsibilities: 'Component development, state management, responsive design, accessibility',
        goals: 'Deliver polished, accessible, and performant user interfaces',
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
        role_description: 'Tests features, validates edge cases, and ensures quality standards',
        responsibilities: 'Test writing, regression testing, edge case validation, bug reporting',
        goals: 'Ensure comprehensive test coverage and catch defects before release',
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
        description: 'Team-wide announcements, sprint updates, and architectural decisions',
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
    description: 'Sequential pipeline team for content creation workflow. Research, write, edit, and publish stages execute in order with handoff validation.',
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
        role_description: 'Conducts topic research, gathers data, and prepares research briefs',
        responsibilities: 'Topic research, data gathering, source validation, research brief creation',
        goals: 'Provide comprehensive, accurate research foundation for content',
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
        role_description: 'Writes content based on research briefs following brand guidelines',
        responsibilities: 'Content drafting, SEO optimization, brand voice adherence',
        goals: 'Produce engaging, well-structured content aligned with research',
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
        role_description: 'Reviews and edits content for quality, accuracy, and style consistency',
        responsibilities: 'Copy editing, fact checking, style enforcement, quality assurance',
        goals: 'Ensure all published content meets quality and accuracy standards',
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
        description: 'Sequential content pipeline stage handoffs and status updates',
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
    description: 'Parallel team for handling customer support. Lead triages and routes tickets while parallel agents handle resolution independently.',
    team_type: 'parallel',
    coordination_strategy: 'round_robin',
    goal_description: 'Provide fast, high-quality customer support responses across multiple channels',
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
        role_description: 'Triages incoming tickets and routes to appropriate support agents',
        responsibilities: 'Ticket triage, routing, escalation management, quality oversight',
        goals: 'Ensure fast response times and proper ticket routing',
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
        role_description: 'Handles technical support tickets requiring system knowledge',
        responsibilities: 'Technical troubleshooting, log analysis, configuration assistance',
        goals: 'Resolve technical issues with clear explanations and solutions',
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
        role_description: 'Handles billing, payment, and subscription-related support tickets',
        responsibilities: 'Billing inquiries, payment issues, subscription changes, refund processing',
        goals: 'Resolve billing issues accurately while maintaining customer satisfaction',
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
    description: 'Mesh team for collaborative architecture reviews. Peers evaluate proposals from security, performance, and design perspectives using auction-based task claiming.',
    team_type: 'mesh',
    coordination_strategy: 'auction',
    goal_description: 'Provide comprehensive architecture reviews covering security, performance, and design quality',
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
        role_description: 'Coordinates architecture reviews and synthesizes findings into decisions',
        responsibilities: 'Review coordination, decision synthesis, trade-off analysis, documentation',
        goals: 'Ensure sound architectural decisions with documented rationale',
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
        role_description: 'Evaluates architecture proposals for security implications and threat modeling',
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
        role_description: 'Evaluates architecture proposals for scalability, performance, and resource efficiency',
        responsibilities: 'Performance modeling, scalability analysis, resource estimation, bottleneck identification',
        goals: 'Ensure architectures meet performance requirements at projected scale',
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
        description: 'Architecture review discussions and proposal analysis',
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
      support_email: 'support@powernode.org',
      branding: {},
      payout_settings: {}
    )
end

templates_data = [
  {
    name: 'SaaS Customer Success Bot',
    slug: 'powernode-saas-customer-success-bot',
    description: 'AI-powered customer success agent for SaaS platforms. Handles onboarding, health scoring, churn prediction, and proactive outreach.',
    long_description: 'A comprehensive customer success solution designed for SaaS businesses. This template includes pre-built workflows for customer onboarding sequences, health score calculation based on product usage metrics, churn risk identification with early warning signals, and automated proactive outreach campaigns. Integrates with common CRM and support tools.',
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
    description: 'Intelligent product recommendation engine for e-commerce. Uses browsing history, purchase patterns, and collaborative filtering.',
    long_description: 'Advanced product recommendation system for e-commerce platforms. Leverages customer browsing behavior, purchase history, and collaborative filtering algorithms to deliver personalized product suggestions. Supports cross-selling, upselling, and bundle recommendations with configurable strategies.',
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
    description: 'Medical intake triage assistant for healthcare providers. Collects symptoms, assesses urgency, and routes to appropriate departments.',
    long_description: 'HIPAA-aware triage assistant for healthcare organizations. Guides patients through structured symptom collection, performs urgency assessment using evidence-based triage protocols, and routes cases to appropriate clinical departments. Includes consent workflows and audit logging for compliance.',
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
    description: 'AI course creation assistant for educational platforms. Generates curriculum outlines, lesson plans, assessments, and learning objectives.',
    long_description: 'Comprehensive course building assistant for educational technology platforms. Creates structured curriculum outlines with learning objectives aligned to educational standards, generates lesson plans with activities and resources, designs assessments with rubrics, and suggests multimedia content to enhance engagement.',
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
    description: 'Regulatory compliance monitoring agent for financial technology companies. Tracks regulatory changes, assesses impact, and generates compliance reports.',
    long_description: 'Continuous compliance monitoring solution for FinTech companies. Tracks regulatory changes across jurisdictions, assesses business impact, generates compliance gap analyses, and produces audit-ready reports. Covers PCI DSS, SOX, AML/KYC, and GDPR requirements.',
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
    description: 'End-to-end marketing campaign management agent. Plans, creates, schedules, and analyzes multi-channel marketing campaigns.',
    long_description: 'Full-lifecycle marketing campaign orchestration agent. Plans campaign strategy and timeline, generates content for email, social, and web channels, schedules posts and sends across platforms, and analyzes performance metrics with optimization recommendations. Supports A/B testing workflows.',
    category: 'marketing',
    vertical: 'marketing',
    pricing_type: 'usage_based',
    price_usd: nil,
    is_featured: false,
    agent_config: {
      'agent_type' => 'workflow_optimizer',
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
    description: 'Automated incident management agent for DevOps teams. Detects incidents, coordinates response, manages communication, and produces post-mortems.',
    long_description: 'Production incident management assistant for DevOps and SRE teams. Automatically detects anomalies in system metrics, initiates incident response workflows, coordinates team communication during incidents, manages status page updates, and generates comprehensive post-mortem reports with action items.',
    category: 'productivity',
    vertical: 'devops',
    pricing_type: 'free',
    price_usd: nil,
    is_featured: true,
    agent_config: {
      'agent_type' => 'workflow_operations',
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
    description: 'Academic research analysis agent. Summarizes papers, extracts key findings, identifies methodology gaps, and generates literature review sections.',
    long_description: 'Research analysis assistant for academic and R&D teams. Processes research papers to extract key findings, methodology details, and statistical results. Identifies research gaps, compares findings across papers, and generates structured literature review sections with proper citations.',
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

templates_data.each do |td|
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

# ===========================================================================
# 4 WORKFLOW EXAMPLES (Ai::Workflow)
# ===========================================================================
workflows_data = [
  {
    name: 'Customer Onboarding Workflow',
    description: 'Automated customer onboarding sequence: welcome email, account setup verification, product tour scheduling, and success check-in.',
    workflow_type: 'ai',
    status: 'active',
    configuration: {
      'execution_mode' => 'sequential',
      'timeout_seconds' => 7200,
      'max_parallel_nodes' => 1,
      'auto_retry' => true,
      'error_handling' => 'continue',
      'notifications' => { 'on_completion' => true, 'on_error' => true }
    }
  },
  {
    name: 'Content Publishing Workflow',
    description: 'Content publishing pipeline: draft creation, editorial review, SEO optimization, scheduled publication, and social media distribution.',
    workflow_type: 'ai',
    status: 'active',
    configuration: {
      'execution_mode' => 'sequential',
      'timeout_seconds' => 3600,
      'max_parallel_nodes' => 1,
      'auto_retry' => false,
      'error_handling' => 'stop',
      'notifications' => { 'on_completion' => true, 'on_error' => true }
    }
  },
  {
    name: 'Incident Response Workflow',
    description: 'Parallel incident response: detect anomaly, notify on-call, gather diagnostics, update status page, and initiate mitigation concurrently.',
    workflow_type: 'ai',
    status: 'active',
    configuration: {
      'execution_mode' => 'parallel',
      'timeout_seconds' => 1800,
      'max_parallel_nodes' => 5,
      'auto_retry' => true,
      'error_handling' => 'continue',
      'notifications' => { 'on_completion' => true, 'on_error' => true }
    }
  },
  {
    name: 'Data Processing Pipeline',
    description: 'Sequential data processing: ingest raw data, validate schema, transform and enrich, load into warehouse, and generate summary report.',
    workflow_type: 'ai',
    status: 'active',
    configuration: {
      'execution_mode' => 'sequential',
      'timeout_seconds' => 5400,
      'max_parallel_nodes' => 1,
      'auto_retry' => true,
      'error_handling' => 'stop',
      'notifications' => { 'on_completion' => true, 'on_error' => true }
    }
  }
]

workflows_created = 0

workflows_data.each do |wd|
  workflow = Ai::Workflow.find_or_create_by!(account: admin_account, name: wd[:name]) do |w|
    w.description = wd[:description]
    w.workflow_type = wd[:workflow_type]
    w.status = wd[:status]
    w.creator = admin_user
    w.configuration = wd[:configuration]
    w.version = '1.0.0'
    w.visibility = 'public'
    w.is_active = true
  end
  workflows_created += 1
  puts "  ✅ Workflow '#{workflow.name}' (#{wd[:workflow_type]}, #{wd[:status]})"
end

# ===========================================================================
# 10 SKILLS (Ai::Skill)
# ===========================================================================
skills_data = [
  {
    name: 'Code Generation',
    description: 'Generate production-quality code in multiple languages with proper error handling, testing patterns, and documentation.',
    category: 'productivity',
    system_prompt: 'Generate clean, well-documented code following best practices for the target language and framework.',
    commands: [
      { 'name' => 'generate_code', 'description' => 'Generate code from a specification', 'parameters' => %w[language specification] },
      { 'name' => 'refactor_code', 'description' => 'Refactor existing code for improvement', 'parameters' => %w[code language improvements] }
    ],
    tags: %w[code programming development generation]
  },
  {
    name: 'Database Design',
    description: 'Design database schemas, write migrations, optimize queries, and plan indexing strategies for relational and document databases.',
    category: 'data',
    system_prompt: 'Design efficient database schemas with proper normalization, indexing, and query optimization.',
    commands: [
      { 'name' => 'design_schema', 'description' => 'Design a database schema', 'parameters' => %w[requirements database_type] },
      { 'name' => 'optimize_query', 'description' => 'Optimize a slow database query', 'parameters' => %w[query schema] }
    ],
    tags: %w[database schema sql design optimization]
  },
  {
    name: 'API Design',
    description: 'Design RESTful and GraphQL APIs with proper authentication, versioning, pagination, and error handling patterns.',
    category: 'productivity',
    system_prompt: 'Design well-structured APIs following REST or GraphQL best practices with comprehensive documentation.',
    commands: [
      { 'name' => 'design_api', 'description' => 'Design API endpoints for a resource', 'parameters' => %w[resource operations auth_type] },
      { 'name' => 'generate_openapi', 'description' => 'Generate OpenAPI specification', 'parameters' => %w[endpoints] }
    ],
    tags: %w[api rest graphql design documentation]
  },
  {
    name: 'Security Audit',
    description: 'Perform security audits covering OWASP Top 10, dependency vulnerabilities, authentication flows, and data protection compliance.',
    category: 'business_search',
    system_prompt: 'Conduct thorough security audits identifying vulnerabilities, misconfigurations, and compliance gaps.',
    commands: [
      { 'name' => 'audit_code', 'description' => 'Audit code for security vulnerabilities', 'parameters' => %w[code language framework] },
      { 'name' => 'check_dependencies', 'description' => 'Check dependencies for known CVEs', 'parameters' => %w[manifest_file] }
    ],
    tags: %w[security audit owasp vulnerability compliance]
  },
  {
    name: 'Performance Tuning',
    description: 'Analyze and optimize application performance including database queries, API response times, memory usage, and caching strategies.',
    category: 'data',
    system_prompt: 'Analyze performance bottlenecks and recommend optimizations with measurable improvement targets.',
    commands: [
      { 'name' => 'profile_endpoint', 'description' => 'Profile an API endpoint for performance', 'parameters' => %w[endpoint metrics] },
      { 'name' => 'recommend_caching', 'description' => 'Recommend caching strategy', 'parameters' => %w[access_patterns data_volatility] }
    ],
    tags: %w[performance optimization caching profiling tuning]
  },
  {
    name: 'DevOps Automation',
    description: 'Automate CI/CD pipelines, infrastructure provisioning, deployment strategies, and monitoring setup.',
    category: 'productivity',
    system_prompt: 'Design and implement DevOps automation for reliable, repeatable infrastructure and deployment processes.',
    commands: [
      { 'name' => 'create_pipeline', 'description' => 'Create a CI/CD pipeline configuration', 'parameters' => %w[platform stages triggers] },
      { 'name' => 'provision_infra', 'description' => 'Generate infrastructure-as-code', 'parameters' => %w[provider resources environment] }
    ],
    tags: %w[devops cicd automation infrastructure deployment]
  },
  {
    name: 'Content Localization',
    description: 'Localize content for international markets including translation, cultural adaptation, date/currency formatting, and RTL support.',
    category: 'marketing',
    system_prompt: 'Localize content for target markets considering language, culture, formatting conventions, and accessibility.',
    commands: [
      { 'name' => 'localize_content', 'description' => 'Localize content for a target market', 'parameters' => %w[content source_locale target_locale] },
      { 'name' => 'extract_strings', 'description' => 'Extract localizable strings from code', 'parameters' => %w[source_files format] }
    ],
    tags: %w[localization i18n translation content international]
  },
  {
    name: 'Incident Analysis',
    description: 'Analyze production incidents with root cause analysis, impact assessment, timeline reconstruction, and remediation planning.',
    category: 'productivity',
    system_prompt: 'Analyze incidents systematically to identify root causes, assess impact, and develop prevention strategies.',
    commands: [
      { 'name' => 'analyze_incident', 'description' => 'Perform root cause analysis on an incident', 'parameters' => %w[incident_id logs metrics timeline] },
      { 'name' => 'generate_postmortem', 'description' => 'Generate a post-mortem report', 'parameters' => %w[incident_id findings] }
    ],
    tags: %w[incident analysis postmortem root-cause sre]
  },
  {
    name: 'User Research',
    description: 'Design and analyze user research studies including surveys, interviews, usability tests, and behavioral analytics.',
    category: 'product_management',
    system_prompt: 'Design effective user research studies and analyze findings to inform product decisions.',
    commands: [
      { 'name' => 'design_study', 'description' => 'Design a user research study', 'parameters' => %w[research_question method target_audience] },
      { 'name' => 'analyze_feedback', 'description' => 'Analyze user feedback data', 'parameters' => %w[feedback_data categories] }
    ],
    tags: %w[user-research ux surveys usability feedback]
  },
  {
    name: 'Compliance Review',
    description: 'Review systems and processes for regulatory compliance including GDPR, SOC 2, HIPAA, PCI DSS, and ISO 27001.',
    category: 'legal',
    system_prompt: 'Review systems for regulatory compliance, identify gaps, and recommend remediation with priority ranking.',
    commands: [
      { 'name' => 'assess_compliance', 'description' => 'Assess compliance against a framework', 'parameters' => %w[framework scope evidence] },
      { 'name' => 'generate_report', 'description' => 'Generate a compliance report', 'parameters' => %w[framework findings] }
    ],
    tags: %w[compliance gdpr sox hipaa pci-dss iso27001]
  }
]

skills_created = 0

skills_data.each do |sd|
  skill = Ai::Skill.find_or_initialize_by(slug: sd[:name].parameterize)
  skill.assign_attributes(
    account: admin_account,
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
puts "   Workflows: #{workflows_created}"
puts "   Skills: #{skills_created}"
puts "✅ AI Example Templates seeding completed!"
