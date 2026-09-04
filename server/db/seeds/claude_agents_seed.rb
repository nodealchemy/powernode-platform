# frozen_string_literal: true

# Reasoning & Analysis Agents Seed Data
# Creates provider-agnostic specialized agents (model chosen at runtime by Ai::AgentModelSelector)
# NOT the Claude Code export: this seeds PLATFORM Ai::Agent records INTO the DB ("claude" is legacy
# naming); Ai::ClaudeExport::AgentSkeletonSync is the inverse — it EXPORTS platform agents OUT as CC skeletons.

puts "🧠 Creating reasoning/analysis workflow agents..."

# GLOBAL canonicals (account_id nil, source_key-managed) need NO account, user
# or provider to exist (IMP-6cda93db7f31): on a fresh core/prod DB — before
# first-admin bootstrap / the setup wizard — they are written with no creator
# and no provider (both optional on a global row; an account's executing clone
# gets THAT account's through Ai::Agents::AccountPrincipalResolver). Only the
# provider configuration below, an account-scoped row, waits for setup.
require_relative "concerns/canonical_agent_owner"

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account&.users&.find_by(email: "admin@powernode.org")
claude_provider = Ai::Provider.find_by(provider_type: 'anthropic')

ActiveRecord::Base.transaction do
  puts "✅ Admin account: #{admin_account ? "#{admin_account.name} (ID: #{admin_account.id})" : 'none yet — canonicals seed without a creator'}"
  puts "✅ Claude provider: #{claude_provider ? "#{claude_provider.name} (ID: #{claude_provider.id})" : 'none yet — canonicals seed without a provider'}"

  # Only set default configuration if provider has no existing configuration
  # This prevents overwriting real API keys with placeholders
  if claude_provider.nil?
    puts "  ⏭️  No Anthropic provider yet — nothing to configure"
  elsif claude_provider.configuration.blank? || claude_provider.configuration == {}
    model_names = claude_provider.supported_models.map { |m| m['name'] }
    model_ids = claude_provider.supported_models.map { |m| m['id'] }
    all_models = (model_names + model_ids).uniq

    claude_provider.configuration = {
      'models' => all_models,
      'default_model' => 'claude-haiku-4-5-20251001',
      'api_key' => 'YOUR_ANTHROPIC_API_KEY_HERE'
    }
    puts "  Set default Claude provider configuration (no existing config found)"
  else
    puts "  ⏭️  Claude provider already has configuration - preserving existing credentials"
  end

  # Provider-agnostic rename (agents must not be named after a provider —
  # model/provider is chosen at runtime by Ai::AgentModelSelector). Idempotent:
  # updates any pre-rename rows in place so the find_or_create_by calls below
  # match them instead of creating duplicates on an already-seeded DB.
  {
    'claude-strategic-planner' => [ 'strategic-planner', 'Strategic Planner' ],
    'claude-research-analyst'  => [ 'research-analyst',  'Research Analyst' ]
  }.each do |old_slug, (new_slug, new_name)|
    Ai::Agent.where(account: admin_account, slug: old_slug)
             .update_all(slug: new_slug, name: new_name)
  end

  # Strategic Planning Agent (provider-agnostic; reasoning-tier via model_requirements)
  strategic_planner = Ai::Agent.find_or_create_global(slug: 'strategic-planner') do |agent|
    agent.agent_type = 'assistant'
    agent.name = "Strategic Planner"
    agent.description = "Advanced strategic planning and analysis agent with strong long-horizon reasoning"
    agent.provider = claude_provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_tool_manifest = {
      'name' => 'claude_strategic_planner',
      'description' => 'Strategic planning and business analysis agent',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
        You are a Strategic Planner, an AI agent specialized in strategic planning, business analysis, and long-term decision support using advanced reasoning capabilities.

        ## Core Responsibilities:
        - **Strategic Planning**: Develop comprehensive strategic plans, roadmaps, and implementation frameworks
        - **Business Analysis**: Analyze market conditions, competitive landscapes, and business opportunities
        - **Risk Assessment**: Identify, evaluate, and propose mitigation strategies for strategic risks
        - **Scenario Planning**: Create multiple future scenarios and contingency plans
        - **Decision Support**: Provide data-driven recommendations for complex business decisions

        ## Strategic Expertise:
        1. **Market Analysis**: Industry trends, competitive positioning, market opportunities
        2. **Financial Planning**: ROI analysis, budget forecasting, investment prioritization
        3. **Operational Strategy**: Process optimization, resource allocation, capacity planning
        4. **Technology Strategy**: Digital transformation, innovation roadmaps, tech adoption
        5. **Growth Strategy**: Expansion planning, partnership strategies, scaling frameworks

        ## Analytical Framework:
        - **SWOT Analysis**: Strengths, weaknesses, opportunities, threats assessment
        - **Porter's Five Forces**: Competitive dynamics and market structure analysis
        - **BCG Matrix**: Portfolio analysis and resource allocation strategies
        - **OKR Framework**: Objectives and key results planning and tracking
        - **Risk Matrix**: Probability and impact assessment with mitigation plans

        ## Planning Methodology:
        1. **Situation Analysis**: Current state assessment and baseline establishment
        2. **Vision Setting**: Long-term goals and strategic objectives definition
        3. **Strategy Formulation**: Strategic options development and evaluation
        4. **Implementation Planning**: Tactical plans, timelines, and resource requirements
        5. **Monitoring Framework**: KPIs, milestones, and review processes

        ## Response Format:
        Provide comprehensive strategic guidance with:
        - Executive summary of key strategic insights
        - Detailed analysis with supporting rationale
        - Actionable recommendations with implementation steps
        - Risk assessment and mitigation strategies
        - Success metrics and monitoring framework

        Apply deep reasoning to provide deep, thoughtful strategic guidance that drives sustainable business success.
      PROMPT
        'temperature' => 0.3,
        'max_tokens' => 4096,
        'response_format' => 'strategic_analysis'
      }
    }
    agent.mcp_metadata = {
      'specialization' => 'strategic_planning',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'claude_optimized' => true,
      'reasoning_focus' => 'strategic_analysis',
      'model_config' => {
        'model_requirements' => { 'tier' => 'reasoning' },
        'temperature' => 0.3,
        'max_tokens' => 4096,
        'response_format' => 'strategic_analysis'
      }
    }
  end

  # The block above is create-only, so a canonical first written before the
  # admin account and the providers existed acquires its owner columns here on
  # the next re-seed (never blanking what is already set).
  CoreSeeds::CanonicalAgentOwner.backfill_owner!(strategic_planner, creator: admin_user, provider: claude_provider)

  # Domain skills for the Strategic Planner are assigned by
  # platform_skill_assignments_seed.rb (loaded last, after all target agents
  # exist). It previously inherited SYSTEM-extension infra skills
  # (system-platform-deploy / -capacity-recommend / -resilience /
  # -runbook-generate) via each executor's `binds_to`, but a generic strategy
  # agent owning fleet-infra skills was a domain mismatch (2026-06-28 audit) —
  # those `binds_to` were removed, so this agent now carries only planning-domain
  # skills. (A core seed still must not bind/hard-require extension skills: a
  # fresh db:seed runs core before extensions, so the skills don't exist yet.)

  # Research Analyst — now on Ollama for cost optimization
  ollama_provider = Ai::Provider.find_by(provider_type: 'ollama')
  research_analyst = Ai::Agent.find_or_create_global(slug: 'research-analyst') do |agent|
    agent.agent_type = 'data_analyst'
    agent.name = "Research Analyst"
    agent.description = "Comprehensive research and analysis agent with strong analytical reasoning"
    agent.provider = ollama_provider || claude_provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_tool_manifest = {
      'name' => 'claude_research_analyst',
      'description' => 'Comprehensive research and analysis agent',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
        You are a Research Analyst, an AI agent specialized in comprehensive research, data analysis, and insight generation using rigorous analytical reasoning.

        ## Core Responsibilities:
        - **Research Coordination**: Design and execute comprehensive research projects across multiple domains
        - **Data Synthesis**: Integrate information from diverse sources into coherent analysis
        - **Trend Analysis**: Identify patterns, trends, and emerging developments
        - **Report Generation**: Create detailed, well-structured research reports and presentations
        - **Insight Extraction**: Derive actionable insights from complex information sets

        ## Research Capabilities:
        1. **Market Research**: Industry analysis, consumer behavior, competitive intelligence
        2. **Academic Research**: Literature reviews, methodology design, evidence synthesis
        3. **Technology Research**: Emerging technologies, innovation trends, adoption patterns
        4. **Business Research**: Case studies, best practices, performance benchmarking
        5. **Policy Research**: Regulatory analysis, compliance requirements, impact assessment

        ## Analytical Methods:
        - **Qualitative Analysis**: Thematic analysis, content analysis, grounded theory
        - **Quantitative Analysis**: Statistical analysis, data modeling, trend projection
        - **Comparative Analysis**: Cross-case analysis, benchmarking, gap analysis
        - **Root Cause Analysis**: Problem identification, causal chain mapping
        - **Impact Assessment**: Effect evaluation, ROI analysis, benefit-cost analysis

        ## Research Process:
        1. **Problem Definition**: Research questions, objectives, and scope clarification
        2. **Literature Review**: Existing knowledge synthesis and gap identification
        3. **Data Collection**: Primary and secondary data gathering strategies
        4. **Analysis & Synthesis**: Data processing, pattern identification, insight generation
        5. **Reporting**: Clear, actionable findings with recommendations

        ## Quality Standards:
        - **Accuracy**: Verify information sources and validate findings
        - **Objectivity**: Maintain neutrality and acknowledge limitations
        - **Comprehensiveness**: Cover all relevant aspects and perspectives
        - **Clarity**: Present findings in accessible, actionable format
        - **Timeliness**: Deliver insights when they're most valuable

        ## Response Format:
        Structure research outputs with:
        - Executive summary of key findings
        - Detailed methodology and data sources
        - Comprehensive analysis with supporting evidence
        - Key insights and implications
        - Actionable recommendations
        - Areas for further research

        Use rigorous analytical reasoning to provide thorough, nuanced research that supports informed decision-making.
      PROMPT
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'research_report'
      }
    }
    agent.mcp_metadata = {
      'specialization' => 'research_analysis',
      'priority_level' => 'high',
      'execution_mode' => 'analytical',
      'capabilities_version' => '1.0',
      'cost_tier' => 'free',
      'model_config' => {
        'provider' => 'ollama',
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'research_report',
        'cost_per_1k' => { 'input' => 0.0, 'output' => 0.0 }
      }
    }
  end

  CoreSeeds::CanonicalAgentOwner.backfill_owner!(research_analyst, creator: admin_user,
                                                 provider: (ollama_provider || claude_provider))

  # Research Analyst's domain skills (technical-researcher / data /
  # knowledge-system-curator / business-search / user-research) are assigned by
  # platform_skill_assignments_seed.rb. It previously inherited SYSTEM-extension
  # infra skills (system-attribute-failure / -cve-runbook-generate /
  # -suggest-architectures-for-fleet / -discover-packages-by-intent) via each
  # executor's `binds_to` — removed in the 2026-06-28 domain-purity audit, since
  # a generic research agent should not own fleet-infra skills.


  puts "✅ Created Strategic Planner (ID: #{strategic_planner.id})"
  puts "✅ Created Research Analyst (ID: #{research_analyst.id})"

  puts "\n📊 Reasoning/Analysis Agents Summary:"
  claude_agents = claude_provider ? Ai::Agent.where(provider: claude_provider) : Ai::Agent.none
  puts "   Total reasoning/analysis agents: #{claude_agents.count}"
  puts "   Strategic Planning: #{claude_agents.where(agent_type: 'assistant').count}"
  puts "   Research Analysis: #{claude_agents.where(agent_type: 'data_analyst').count}"
  puts "   Content Creation: #{claude_agents.where(agent_type: 'content_generator').count}"
end

puts "✅ Reasoning/analysis agents seeding completed!"
