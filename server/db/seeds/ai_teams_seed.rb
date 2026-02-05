# frozen_string_literal: true

# AI Teams Seed
# Creates 3 functional multi-agent teams with roles, channels, and members

puts "\n👥 Seeding AI Agent Teams..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")

unless admin_account && admin_user
  puts "  ⏭️  Admin account/user not found — skipping AI Teams"
  return
end

# Resolve agents by slug
agents = {}
%w[
  claude-strategic-planner
  claude-research-analyst
  claude-content-creator
  workflow-performance-monitor
  workflow-analytics-intelligence
].each do |slug|
  agents[slug] = Ai::Agent.find_by(account: admin_account, slug: slug)
  unless agents[slug]
    puts "  ⚠️  Agent '#{slug}' not found — skipping AI Teams"
    return
  end
end

puts "  ✅ Using account: #{admin_account.name}"
puts "  ✅ Resolved #{agents.size} agents"

# ---------------------------------------------------------------------------
# Team Definitions
# ---------------------------------------------------------------------------
teams_data = [
  {
    name: 'Code Review Squad',
    description: 'Hierarchical team for automated code review, security analysis, and quality reporting. The lead assigns review tasks and aggregates findings.',
    team_type: 'hierarchical',
    coordination_strategy: 'manager_led',
    goal_description: 'Perform thorough code reviews covering correctness, security, and maintainability',
    team_config: {
      'max_iterations' => 5,
      'timeout_seconds' => 600,
      'retry_on_failure' => true,
      'max_retries' => 2
    },
    review_config: {
      'production' => { 'mode' => 'blocking', 'require_approval' => true },
      'staging' => { 'mode' => 'shadow', 'require_approval' => false }
    },
    roles: [
      {
        role_name: 'Review Lead',
        role_type: 'manager',
        agent_slug: 'claude-strategic-planner',
        role_description: 'Coordinates review tasks and synthesizes findings into final reports',
        responsibilities: 'Assign review tasks, resolve conflicting findings, produce summary reports',
        goals: 'Ensure comprehensive review coverage and actionable feedback',
        capabilities: %w[task_assignment report_generation conflict_resolution],
        constraints: %w[must_review_all_findings max_review_time_10m],
        tools_allowed: %w[code_diff file_read structured_output],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: true,
        member_role: 'manager'
      },
      {
        role_name: 'Code Reviewer',
        role_type: 'specialist',
        agent_slug: 'claude-research-analyst',
        role_description: 'Performs detailed code analysis for correctness, patterns, and security issues',
        responsibilities: 'Analyze code diffs, identify bugs and anti-patterns, suggest improvements',
        goals: 'Find all significant code quality issues',
        capabilities: %w[code_analysis pattern_detection security_scanning],
        constraints: %w[focus_on_changed_files respect_style_guide],
        tools_allowed: %w[code_diff file_read ast_parse],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'reviewer'
      },
      {
        role_name: 'Report Writer',
        role_type: 'worker',
        agent_slug: 'claude-content-creator',
        role_description: 'Formats review findings into clear, developer-friendly reports',
        responsibilities: 'Generate markdown reports, create inline comments, summarize findings',
        goals: 'Produce clear and actionable review documentation',
        capabilities: %w[markdown_generation inline_commenting summary_writing],
        constraints: %w[concise_output developer_friendly_language],
        tools_allowed: %w[markdown_formatting structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'writer'
      }
    ],
    channels: [
      {
        name: 'review-broadcast',
        channel_type: 'broadcast',
        description: 'Team-wide announcements and review status updates',
        participant_roles: %w[Review\ Lead Code\ Reviewer Report\ Writer],
        message_schema: { 'type' => 'object', 'properties' => { 'message' => { 'type' => 'string' }, 'priority' => { 'type' => 'string' } } },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'review-tasks',
        channel_type: 'task',
        description: 'Task assignments and completion notifications for review work items',
        participant_roles: %w[Review\ Lead Code\ Reviewer Report\ Writer],
        message_schema: { 'type' => 'object', 'properties' => { 'task_id' => { 'type' => 'string' }, 'action' => { 'type' => 'string' }, 'payload' => { 'type' => 'object' } } },
        routing_rules: { 'route_by_role' => true, 'priority_routing' => true }
      }
    ]
  },
  {
    name: 'Research & Analysis Team',
    description: 'Mesh-topology team where peers collaborate on research, data analysis, and knowledge synthesis. All members communicate directly.',
    team_type: 'mesh',
    coordination_strategy: 'consensus',
    goal_description: 'Collaboratively research topics and produce synthesized analytical reports',
    team_config: {
      'max_iterations' => 8,
      'timeout_seconds' => 900,
      'retry_on_failure' => true,
      'max_retries' => 1,
      'consensus_threshold' => 0.7
    },
    review_config: {
      'default' => { 'mode' => 'shadow', 'require_approval' => false }
    },
    roles: [
      {
        role_name: 'Lead Researcher',
        role_type: 'coordinator',
        agent_slug: 'claude-research-analyst',
        role_description: 'Coordinates research efforts and ensures comprehensive topic coverage',
        responsibilities: 'Define research scope, coordinate data gathering, validate sources',
        goals: 'Ensure thorough and accurate research coverage',
        capabilities: %w[web_search data_extraction source_validation literature_review],
        constraints: %w[verify_sources cite_references],
        tools_allowed: %w[web_search document_analysis data_extraction citation_generation],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: true,
        member_role: 'researcher'
      },
      {
        role_name: 'Data Analyst',
        role_type: 'specialist',
        agent_slug: 'workflow-analytics-intelligence',
        role_description: 'Performs quantitative analysis, trend detection, and data visualization',
        responsibilities: 'Analyze datasets, identify trends, create statistical summaries',
        goals: 'Extract meaningful quantitative insights from data',
        capabilities: %w[statistical_analysis trend_detection data_aggregation visualization],
        constraints: %w[statistical_significance data_quality_checks],
        tools_allowed: %w[database_queries csv_processing data_aggregation report_generation],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'analyst'
      },
      {
        role_name: 'Report Author',
        role_type: 'worker',
        agent_slug: 'claude-content-creator',
        role_description: 'Synthesizes research findings into polished reports and presentations',
        responsibilities: 'Write reports, create executive summaries, format deliverables',
        goals: 'Produce clear, well-structured research deliverables',
        capabilities: %w[report_writing executive_summaries presentation_creation],
        constraints: %w[maintain_objectivity cite_data_sources],
        tools_allowed: %w[text_generation markdown_formatting structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'writer'
      }
    ],
    channels: [
      {
        name: 'research-broadcast',
        channel_type: 'broadcast',
        description: 'Shared findings and coordination messages for the research team',
        participant_roles: %w[Lead\ Researcher Data\ Analyst Report\ Author],
        message_schema: { 'type' => 'object', 'properties' => { 'message' => { 'type' => 'string' }, 'finding_type' => { 'type' => 'string' } } },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'research-tasks',
        channel_type: 'task',
        description: 'Research task assignments and deliverable tracking',
        participant_roles: %w[Lead\ Researcher Data\ Analyst Report\ Author],
        message_schema: { 'type' => 'object', 'properties' => { 'task_id' => { 'type' => 'string' }, 'action' => { 'type' => 'string' }, 'payload' => { 'type' => 'object' } } },
        routing_rules: { 'route_by_role' => true }
      }
    ]
  },
  {
    name: 'DevOps Pipeline Team',
    description: 'Sequential pipeline team: scan code, analyze results, validate deployment readiness, produce reports. Each stage feeds the next.',
    team_type: 'sequential',
    coordination_strategy: 'manager_led',
    goal_description: 'Execute sequential DevOps pipeline stages from scanning through deployment validation',
    team_config: {
      'max_iterations' => 4,
      'timeout_seconds' => 1200,
      'retry_on_failure' => true,
      'max_retries' => 1,
      'stage_timeout_seconds' => 300
    },
    review_config: {
      'production' => { 'mode' => 'blocking', 'require_approval' => true },
      'staging' => { 'mode' => 'shadow', 'require_approval' => false },
      'development' => { 'mode' => 'shadow', 'require_approval' => false }
    },
    roles: [
      {
        role_name: 'Pipeline Orchestrator',
        role_type: 'manager',
        agent_slug: 'claude-strategic-planner',
        role_description: 'Orchestrates the sequential pipeline stages and manages stage transitions',
        responsibilities: 'Coordinate pipeline stages, handle failures, gate stage transitions',
        goals: 'Ensure reliable end-to-end pipeline execution',
        capabilities: %w[pipeline_orchestration stage_gating failure_handling],
        constraints: %w[sequential_execution respect_stage_gates],
        tools_allowed: %w[pipeline_control stage_management structured_output],
        priority_order: 0,
        can_delegate: true,
        can_escalate: true,
        max_concurrent_tasks: 1,
        is_lead: true,
        member_role: 'manager'
      },
      {
        role_name: 'Pipeline Monitor',
        role_type: 'specialist',
        agent_slug: 'workflow-performance-monitor',
        role_description: 'Monitors pipeline execution health, resource usage, and performance metrics',
        responsibilities: 'Track execution metrics, detect anomalies, report performance issues',
        goals: 'Ensure pipeline health and identify bottlenecks',
        capabilities: %w[metric_collection anomaly_detection performance_tracking],
        constraints: %w[real_time_monitoring alert_thresholds],
        tools_allowed: %w[http_requests log_analysis metric_collection alerting],
        priority_order: 1,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 3,
        is_lead: false,
        member_role: 'executor'
      },
      {
        role_name: 'Pipeline Reporter',
        role_type: 'worker',
        agent_slug: 'claude-content-creator',
        role_description: 'Generates pipeline execution reports, changelogs, and deployment summaries',
        responsibilities: 'Create execution reports, format results, generate deployment notes',
        goals: 'Produce comprehensive pipeline execution documentation',
        capabilities: %w[report_generation changelog_creation deployment_summaries],
        constraints: %w[structured_format include_metrics],
        tools_allowed: %w[text_generation markdown_formatting structured_output],
        priority_order: 2,
        can_delegate: false,
        can_escalate: true,
        max_concurrent_tasks: 2,
        is_lead: false,
        member_role: 'writer'
      }
    ],
    channels: [
      {
        name: 'pipeline-broadcast',
        channel_type: 'broadcast',
        description: 'Pipeline status updates and stage transition notifications',
        participant_roles: %w[Pipeline\ Orchestrator Pipeline\ Monitor Pipeline\ Reporter],
        message_schema: { 'type' => 'object', 'properties' => { 'stage' => { 'type' => 'string' }, 'status' => { 'type' => 'string' }, 'message' => { 'type' => 'string' } } },
        routing_rules: { 'broadcast_to_all' => true }
      },
      {
        name: 'pipeline-tasks',
        channel_type: 'task',
        description: 'Pipeline stage task assignments and completion tracking',
        participant_roles: %w[Pipeline\ Orchestrator Pipeline\ Monitor Pipeline\ Reporter],
        message_schema: { 'type' => 'object', 'properties' => { 'task_id' => { 'type' => 'string' }, 'stage' => { 'type' => 'string' }, 'action' => { 'type' => 'string' } } },
        routing_rules: { 'route_by_stage' => true, 'sequential_delivery' => true }
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

  # Create roles
  td[:roles].each do |rd|
    agent = agents[rd[:agent_slug]]
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

    # Create corresponding team member
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

  # Create channels
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

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
puts "\n📊 AI Teams Summary:"
puts "   Teams: #{teams_created}"
puts "   Roles: #{roles_created}"
puts "   Channels: #{channels_created}"
puts "   Members: #{members_created}"
puts "✅ AI Teams seeding completed!"
