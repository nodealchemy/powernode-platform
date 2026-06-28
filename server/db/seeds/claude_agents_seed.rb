# frozen_string_literal: true

# Claude-Powered Agents Seed Data
# Creates specialized agents that leverage Claude AI capabilities

puts "🧠 Creating Claude-Powered Workflow Agents..."

admin_account = Account.find_by(name: "Powernode Admin")
raise "claude_agents_seed: admin account 'Powernode Admin' not found — seed accounts first" unless admin_account

admin_user = admin_account.users.find_by(email: "admin@powernode.org")
raise "claude_agents_seed: admin user 'admin@powernode.org' not found" unless admin_user

claude_provider = Ai::Provider.find_by(provider_type: 'anthropic')
raise "claude_agents_seed: Anthropic provider not seeded — run ai_providers_seed first" unless claude_provider

ActiveRecord::Base.transaction do
  puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
  puts "✅ Using admin user: #{admin_user.name} (ID: #{admin_user.id})"
  puts "✅ Using Claude provider: #{claude_provider.name} (ID: #{claude_provider.id})"

  # Only set default configuration if provider has no existing configuration
  # This prevents overwriting real API keys with placeholders
  if claude_provider.configuration.blank? || claude_provider.configuration == {}
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

  # Claude-Powered Strategic Planning Agent
  strategic_planner = Ai::Agent.find_or_create_by(
    account: admin_account,
    slug: 'claude-strategic-planner',
    agent_type: 'assistant'
  ) do |agent|
    agent.name = "Claude Strategic Planner"
    agent.description = "Advanced strategic planning and analysis agent powered by Claude's reasoning capabilities"
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
        You are a Claude Strategic Planner, an AI agent specialized in strategic planning, business analysis, and long-term decision support using Claude's advanced reasoning capabilities.

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

        Leverage Claude's reasoning strength to provide deep, thoughtful strategic guidance that drives sustainable business success.
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

  # System-extension skills (system-capacity-recommend / -platform-deploy /
  # -platform-resilience / -runbook-generate) are bound to this agent by the
  # SYSTEM extension itself — each executor declares `binds_to "Claude Strategic
  # Planner"`, materialized by system_skill_bindings_seed.rb (the single source
  # of truth for agent↔skill bindings). A core seed must not bind or hard-require
  # extension skills: doing so crashed a fresh db:seed, which runs core seeds
  # before extension seeds, so the skills did not exist yet.

  # Research Analyst — now on Ollama for cost optimization
  ollama_provider = Ai::Provider.find_by(provider_type: 'ollama')
  research_analyst = Ai::Agent.find_or_create_by(
    account: admin_account,
    slug: 'claude-research-analyst',
    agent_type: 'data_analyst'
  ) do |agent|
    agent.name = "Claude Research Analyst"
    agent.description = "Comprehensive research and analysis agent leveraging Claude's analytical capabilities"
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
        You are a Claude Research Analyst, an AI agent specialized in comprehensive research, data analysis, and insight generation using Claude's analytical reasoning capabilities.

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

        Use Claude's analytical strength to provide thorough, nuanced research that supports informed decision-making.
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

  # System-extension skills (system-attribute-failure / -cve-runbook-generate /
  # -suggest-architectures-for-fleet / -discover-packages-by-intent) are bound to
  # this agent by the SYSTEM extension itself — each executor declares
  # `binds_to "Claude Research Analyst"`, materialized by
  # system_skill_bindings_seed.rb. See the note on Strategic Planner above.


  puts "✅ Created Claude Strategic Planner (ID: #{strategic_planner.id})"
  puts "✅ Created Claude Research Analyst (ID: #{research_analyst.id})"

  puts "\n📊 Claude-Powered Agents Summary:"
  claude_agents = Ai::Agent.where(provider: claude_provider)
  puts "   Total Claude Agents: #{claude_agents.count}"
  puts "   Strategic Planning: #{claude_agents.where(agent_type: 'assistant').count}"
  puts "   Research Analysis: #{claude_agents.where(agent_type: 'data_analyst').count}"
  puts "   Content Creation: #{claude_agents.where(agent_type: 'content_generator').count}"
end

puts "✅ Claude-powered agents seeding completed!"
