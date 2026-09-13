# frozen_string_literal: true

# Monitoring Agents Seed Data
# Creates the Platform Health Monitor and System Quality Assurance canonicals.

puts "📊 Creating Monitoring Agents..."

# Both monitoring agents are GLOBAL canonicals (account_id nil,
# source_key-managed) and need NO account, user or provider to exist
# (IMP-6cda93db7f31): on a fresh core/prod DB — before first-admin bootstrap /
# the setup wizard — they are written with no creator and no provider (both
# optional on a global row; an account's executing clone gets THAT account's
# through Ai::Agents::AccountPrincipalResolver).
require_relative "concerns/canonical_agent_owner"
require_relative "concerns/canonical_tool_access"

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")
# The monitoring canonicals carry no model pin (tier requirements only), so any
# provider can run them — but `Ai::Provider.first` took whatever row was oldest,
# active or not. The seam answers with an ACTIVE provider, and would answer
# with the pin's family if one of these ever acquires a pin.
provider = CoreSeeds::CanonicalAgentOwner.provider_for(pinned_model: nil)

puts "✅ Admin account: #{admin_account ? "#{admin_account.name} (ID: #{admin_account.id})" : 'none yet — canonicals seed without a creator'}"
puts "✅ AI provider: #{provider ? "#{provider.name} (ID: #{provider.id})" : 'none yet — canonicals seed without a provider'}"

# ---------------------------------------------------------------------------
# Platform Health Monitor (IMP-80a353489ba4)
# ---------------------------------------------------------------------------
# ONE canonical for "watch the platform". It replaces four that were four
# prompts for the same job — System Performance Monitor, System Analytics
# Intelligence and System Health Monitor (this file) and Infrastructure Health
# Monitor (autonomy_data_seed.rb). None of them owned a sensor, a policy set, a
# schedule or a health verb, and each one's routing description named another
# as its alternative. The prompt below is written against the health verbs that
# exist instead of generic monitoring prose.
#
# RETIRING WHAT EARLIER SEEDS WROTE. Seeds do not re-run on a deployed plane
# after first boot, but they do on dev installs, CI databases and fresh planes:
#   * an existing Infrastructure Health Monitor row is ADOPTED in place (slug,
#     source_key, name and definition rewritten; id kept), so its skills, trust
#     score, budgets, executions, team seats and account clones follow it;
#   * the other three — and a stray Infrastructure Health Monitor when the
#     Platform Health Monitor already exists — are ARCHIVED, never destroyed.
#     Ai::Agent destroys its executions, conversations and messages, and an
#     archived row already leaves the canonical roster
#     (Ai::Routing::RoutableAgents reads active agents only), so archiving
#     removes it from routing and from the Claude Code export while keeping
#     its history.
platform_health_monitor_slug = "platform-health-monitor"
adopted_monitor_slug = "infrastructure-health-monitor"
retired_monitor_slugs = %w[system-performance-monitor system-analytics-intelligence system-health-monitor]

platform_health_monitor_definition = {
  agent_type: "monitor",
  name: "Platform Health Monitor",
  # The "Use when" sentence is the routing sentence the Claude Code export pins
  # whole (Ai::ClaudeExport::RoutingDescription::ROUTING_SENTENCE); the first
  # sentence is only a trigger that the 400-character budget may drop.
  description: "Measures and reports the health of the Powernode platform with its health checks. " \
               "Use when the question is whether the platform itself — its services, fleet tick, AI providers " \
               "or agents — is healthy, degraded or down, and what changed.",
  mcp_metadata: {
    # Ai::Agent#build_system_prompt_with_profile reads the prompt from here;
    # mcp_tool_manifest is the model's to generate (ensure_mcp_tool_manifest).
    "system_prompt" => <<~PROMPT.strip,
        You are the Platform Health Monitor: the one agent that watches the Powernode platform itself — its services, its fleet tick, its AI providers and the agents running on it. Questions about platform performance, availability, capacity trends or infrastructure health are yours.

        ## The platform's health checks
        - Activity monitor `get_system_health`: missions, agents and providers at a glance.
        - `system_platform_maintenance` with action `health_check` (system extension): the composite probe — the Rails API, worker, Sidekiq, Redis, PostgreSQL, the reverse proxy, the MCP endpoint, fleet tick liveness, provider egress and fleet error/silent counts — persisted as a platform health snapshot. The scheduled platform health sweep also runs it.
        - `system_platform_resilience` with action `failover_check` (system extension): which federation peers and instances are showing stress.
        - Fleet and status reads (recent signals, silent instances, drift report, component status) to explain what a check reported.
        Not every install gives you every check: the two system-extension skills may be bound to another agent (the System Concierge) rather than to you. Before reporting, confirm the check is in your tool list; if it is not, say which check you could not run and who holds it. Never describe a check you did not run.

        ## How you work
        1. Measure first. Run the check that answers the question and quote its result: status, subsystem, time of the reading.
        2. Keep "down", "degraded" and "not measured" apart. A probe that could not run is not a pass.
        3. Correlate before concluding. A provider timeout can be blocked egress rather than bad credentials; a silent instance can be a stopped guest rather than a failed one.
        4. Recommend; do not remediate. You own no remediation lane: name the owning agent (fleet autonomy, capacity, ingress, release) or the operator for anything that needs action.
        5. On module-composed nodes, services run as powernode-<moduleID>-<serviceName>.service units. Discover unit names with `systemctl list-units`; never guess one.

        ## Report
        Overall status first, then each subsystem with its status and the evidence for it, what changed since the previous reading, and the recommended owner for anything that is not ok.
    PROMPT
    "specialization" => "platform_health",
    "priority_level" => "critical",
    "capabilities_version" => "2.0",
    "model_config" => {
      "model_requirements" => { "tier" => "standard" },
      "temperature" => 0.1,
      "max_tokens" => 4096,
      "response_format" => "health_report"
    }
  }
}.freeze

adoptable_monitor = Ai::Agent.global.find_by(slug: adopted_monitor_slug)
if adoptable_monitor && !Ai::Agent.global.exists?(slug: platform_health_monitor_slug)
  adoptable_monitor.update!(
    slug: platform_health_monitor_slug,
    source_key: platform_health_monitor_slug,
    status: "active",
    version: "1.0.0",
    **platform_health_monitor_definition
  )
  puts "✅ Adopted #{adopted_monitor_slug} (ID: #{adoptable_monitor.id}) as #{platform_health_monitor_slug}"
end

# Not find_or_create_global: its block runs only on a NEW row, but on a demo
# install ai_example_templates_seed's account-scoped showcase copy (same
# generated slug) already exists and find_or_initialize_global converts it to
# the global row in place — a create-only block would leave the canonical
# carrying the showcase copy's prompt. The definition is applied to a new row
# and to a just-converted one; an existing global row is left as it is.
platform_health_monitor = Ai::Agent.find_or_initialize_global(slug: "platform-health-monitor")
if platform_health_monitor.new_record? || platform_health_monitor.account_id_changed?
  platform_health_monitor.name = "Platform Health Monitor"
  platform_health_monitor.assign_attributes(platform_health_monitor_definition)
  platform_health_monitor.provider ||= provider
  platform_health_monitor.creator ||= admin_user
  platform_health_monitor.status = "active"
  platform_health_monitor.version = "1.0.0"
end
platform_health_monitor.save! if platform_health_monitor.new_record? || platform_health_monitor.changed?

CoreSeeds::CanonicalAgentOwner.backfill_owner!(platform_health_monitor, creator: admin_user, provider: provider)
# Tool scope: the health checks its prompt names, and the status and signal
# reads that explain them. The system_* verbs exist only with the system
# extension; the core ones keep the list live without it.
CoreSeeds::CanonicalToolAccess.declare_families!(platform_health_monitor, %w[
  get_system_health list_component_status get_component_status get_component_impact integration_health
  kill_switch_status get_investigations get_investigation platform_investigate get_remediation_route get_runbook
  agent_container_status system_platform_maintenance system_platform_resilience system_recent_signals
  system_get_silent_instances system_drift_report
])

# update!, so retiring a platform-wide agent goes through the model's audit and
# change notifications. A retired row may be one a later change made invalid,
# and a validation failure must not abort the seeds that follow, so that row
# alone falls back to a column write.
retire_slugs = retired_monitor_slugs + [ adopted_monitor_slug ]
Ai::Agent.global.where(slug: retire_slugs).where.not(status: "archived").find_each do |retired|
  begin
    retired.update!(status: "archived")
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn("[MonitoringSeed] #{retired.slug} is invalid (#{e.message}); archiving by column write")
    retired.update_columns(status: "archived", updated_at: Time.current)
  end
  puts "🗄️  Archived retired monitoring agent #{retired.slug} (ID: #{retired.id})"
end

# ---------------------------------------------------------------------------
# System Quality Assurance — stays; it hangs under the Platform Architect
# (ai_agent_hierarchy_seed.rb) as Engineering's reviewer.
# ---------------------------------------------------------------------------
qa_monitor = Ai::Agent.find_or_create_global(slug: 'system-quality-assurance') do |agent|
  agent.agent_type = 'monitor'
  agent.name = "System Quality Assurance"
  agent.description = "Quality assurance specialist monitoring execution quality, data integrity, and compliance standards"
  agent.provider = provider
  agent.creator = admin_user
  agent.status = 'active'
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'system_quality_assurance',
    'description' => 'Quality assurance specialist for platform systems',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a System Quality Assurance Monitor, a specialized AI agent focused on ensuring the highest quality standards across all system operations.

        ## Core Responsibilities:
        - **Quality Monitoring**: Continuous assessment of execution quality and output standards
        - **Data Validation**: Verify data integrity, format compliance, and business rule adherence
        - **Compliance Checking**: Ensure workflows meet regulatory, security, and organizational standards
        - **Test Automation**: Execute automated quality tests and validation procedures
        - **Regression Detection**: Identify quality degradation and performance regressions
        - **Standards Enforcement**: Monitor adherence to coding standards, best practices, and policies

        ## Quality Dimensions:
        1. **Functional Quality**: Correct behavior, expected outputs, business logic compliance
        2. **Performance Quality**: Response times, throughput, resource efficiency
        3. **Reliability Quality**: Stability, error rates, recovery capabilities
        4. **Security Quality**: Access controls, data protection, vulnerability management
        5. **Usability Quality**: User experience, interface responsiveness, accessibility

        ## Monitoring Areas:
        - **Execution Quality**: Success rates, error patterns, execution consistency
        - **Data Quality**: Completeness, accuracy, consistency, validity
        - **Code Quality**: Standards compliance, security practices, maintainability
        - **User Experience**: Performance perception, error handling, accessibility
        - **Compliance**: Regulatory requirements, security policies, audit readiness

        ## Quality Metrics:
        1. **Defect Rates**: Bug frequency, severity distribution, resolution times
        2. **Quality Scores**: Automated quality assessments, trending analysis
        3. **Compliance Metrics**: Policy adherence, audit findings, corrective actions
        4. **User Satisfaction**: Feedback scores, usability metrics, adoption rates
        5. **Process Metrics**: Review completion, testing coverage, documentation quality

        ## Quality Assurance Process:
        1. **Prevention**: Proactive quality measures, standards implementation
        2. **Detection**: Quality issue identification through monitoring and testing
        3. **Analysis**: Root cause analysis, impact assessment, trend evaluation
        4. **Correction**: Issue resolution, process improvements, preventive measures
        5. **Validation**: Quality verification, testing confirmation, compliance validation

        ## Response Format:
        Deliver comprehensive quality reports with:
        - Overall quality status and key quality indicators
        - Specific quality issues and recommendations
        - Compliance status and audit readiness
        - Quality trends and improvement opportunities
        - Action plans for quality enhancement

        Focus on proactive quality assurance that prevents issues and maintains excellence across all system operations.
      PROMPT
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'quality_assurance'
    }
  }
  agent.mcp_metadata = {
    'specialization' => 'quality_assurance',
    'priority_level' => 'high',
    'execution_mode' => 'continuous',
    'capabilities_version' => '1.0',
    'quality_metrics' => {
      'avg_validation_time_ms' => 800,
      'quality_detection_rate' => 96.2,
      'supported_standards' => [ 'iso_9001', 'security_standards', 'accessibility_guidelines' ]
    },
    'model_config' => {
      'model_requirements' => { 'tier' => 'reasoning' },
      'temperature' => 0.2,
      'max_tokens' => 4096,
      'response_format' => 'quality_assurance'
    }
  }
end

CoreSeeds::CanonicalAgentOwner.backfill_owner!(qa_monitor, creator: admin_user, provider: provider)
# Tool scope from its review duties: governance reports, audit logs, knowledge
# and skill health, learning verification, and static code quality reads.
CoreSeeds::CanonicalToolAccess.declare_families!(qa_monitor, %w[
  governance_scan governance_dashboard list_governance_reports get_governance_report list_audit_logs
  knowledge_health skill_health learning_metrics verify_learning_batch detect_collusion data_source_quality
  code_static_analysis code_dead_code code_find_duplicates
])

puts "✅ Platform Health Monitor (ID: #{platform_health_monitor.id})"
puts "✅ System Quality Assurance (ID: #{qa_monitor.id})"
puts "✅ Monitoring Agents seeding completed!"
