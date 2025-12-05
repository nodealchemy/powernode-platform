# frozen_string_literal: true

# Claude-Powered Agents Seed Data
# Creates specialized agents that leverage Claude AI capabilities

puts "🧠 Creating Claude-Powered Workflow Agents..."

admin_account = Account.find_by(name: "Powernode Admin")
admin_user = admin_account.users.find_by(email: "admin@powernode.org")
claude_provider = AiProvider.find_by(provider_type: 'anthropic')

if admin_account && admin_user && claude_provider
  puts "✅ Using admin account: #{admin_account.name} (ID: #{admin_account.id})"
  puts "✅ Using admin user: #{admin_user.name} (ID: #{admin_user.id})"
  puts "✅ Using Claude provider: #{claude_provider.name} (ID: #{claude_provider.id})"

  # Set configuration for Claude provider
  model_names = claude_provider.supported_models.map { |m| m['name'] }
  model_ids = claude_provider.supported_models.map { |m| m['id'] }
  all_models = (model_names + model_ids).uniq

  claude_provider.configuration = {
    'models' => all_models,
    'default_model' => 'claude-3.5-sonnet',
    'api_key' => 'YOUR_ANTHROPIC_API_KEY_HERE'
  }

  # Claude-Powered Strategic Planning Agent
  strategic_planner = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'claude-strategic-planner',
    agent_type: 'assistant'
  ) do |agent|
    agent.name = "Claude Strategic Planner"
    agent.description = "Advanced strategic planning and analysis agent powered by Claude's reasoning capabilities"
    agent.ai_provider = claude_provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'strategic_planning',
      'business_analysis',
      'risk_assessment',
      'scenario_planning',
      'competitive_analysis',
      'market_research',
      'decision_support',
      'long_term_planning'
    ]
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
        'model' => 'claude-sonnet-4-5-20250514',
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
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.3,
        'max_tokens' => 4096,
        'response_format' => 'strategic_analysis'
      }
    }
  end

  # Claude-Powered Research Analyst
  research_analyst = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'claude-research-analyst',
    agent_type: 'data_analyst'
  ) do |agent|
    agent.name = "Claude Research Analyst"
    agent.description = "Comprehensive research and analysis agent leveraging Claude's analytical capabilities"
    agent.ai_provider = claude_provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'research_analysis',
      'data_synthesis',
      'report_generation',
      'trend_analysis',
      'comparative_analysis',
      'literature_review',
      'insights_extraction',
      'evidence_evaluation'
    ]
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
        'model' => 'claude-sonnet-4-5-20250514',
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
      'claude_optimized' => true,
      'reasoning_focus' => 'analytical_research',
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.2,
        'max_tokens' => 4096,
        'response_format' => 'research_report'
      }
    }
  end

  # Claude-Powered Creative Content Generator
  content_creator = AiAgent.find_or_create_by(
    account: admin_account,
    slug: 'claude-content-creator',
    agent_type: 'content_generator'
  ) do |agent|
    agent.name = "Claude Content Creator"
    agent.description = "Advanced content creation agent utilizing Claude's language and creative capabilities"
    agent.ai_provider = claude_provider
    agent.creator = admin_user
    agent.status = 'active'
    agent.version = '1.0.0'
    agent.mcp_capabilities = [
      'content_creation',
      'copywriting',
      'storytelling',
      'brand_voice',
      'content_strategy',
      'technical_writing',
      'creative_writing',
      'content_optimization'
    ]
    agent.mcp_tool_manifest = {
      'name' => 'claude_content_creator',
      'description' => 'Advanced content creation and copywriting agent',
      'type' => 'ai_agent',
      'version' => '1.0.0',
      'configuration' => {
        'system_prompt' => <<~PROMPT.strip,
        You are a Claude Content Creator, an AI agent specialized in creating high-quality, engaging content across multiple formats and channels using Claude's language and creative capabilities.

        ## Core Responsibilities:
        - **Content Strategy**: Develop comprehensive content strategies aligned with business objectives
        - **Creative Writing**: Produce engaging, original content across various formats and styles
        - **Brand Voice**: Maintain consistent brand voice and messaging across all content
        - **Content Optimization**: Optimize content for specific audiences, platforms, and objectives
        - **Technical Documentation**: Create clear, comprehensive technical and educational content

        ## Content Expertise:
        1. **Marketing Content**: Blog posts, social media, email campaigns, landing pages
        2. **Technical Content**: Documentation, tutorials, guides, specifications
        3. **Creative Content**: Stories, scripts, creative campaigns, brand narratives
        4. **Business Content**: Reports, proposals, presentations, case studies
        5. **Educational Content**: Training materials, courses, workshops, webinars

        ## Writing Styles:
        - **Persuasive**: Compelling copy that drives action and engagement
        - **Informative**: Clear, educational content that builds understanding
        - **Narrative**: Engaging stories that connect emotionally with audiences
        - **Technical**: Precise, detailed explanations for expert audiences
        - **Conversational**: Friendly, approachable content for broad appeal

        ## Content Strategy Framework:
        1. **Audience Analysis**: Target audience identification and persona development
        2. **Content Planning**: Editorial calendars, content pillars, topic research
        3. **Content Creation**: Writing, editing, and optimization processes
        4. **Performance Optimization**: A/B testing, analytics, continuous improvement
        5. **Brand Consistency**: Voice, tone, style guide adherence

        ## Quality Standards:
        - **Clarity**: Clear, concise communication that serves the audience
        - **Engagement**: Compelling content that captures and holds attention
        - **Accuracy**: Factual correctness and attention to detail
        - **Originality**: Fresh perspectives and unique value proposition
        - **Purposefulness**: Content that serves specific business and audience goals

        ## Response Format:
        Deliver content with:
        - Clear structure and logical flow
        - Compelling headlines and openings
        - Supporting evidence and examples
        - Strong calls-to-action when appropriate
        - SEO optimization when relevant
        - Brand voice consistency

        Leverage Claude's language expertise to create content that resonates with audiences and drives meaningful engagement.
      PROMPT
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.7,
        'max_tokens' => 4096,
        'response_format' => 'creative_content'
      }
    }
    agent.mcp_metadata = {
      'specialization' => 'content_creation',
      'priority_level' => 'medium',
      'execution_mode' => 'creative',
      'capabilities_version' => '1.0',
      'claude_optimized' => true,
      'reasoning_focus' => 'creative_language',
      'model_config' => {
        'model' => 'claude-sonnet-4-5-20250514',
        'temperature' => 0.7,
        'max_tokens' => 4096,
        'response_format' => 'creative_content'
      }
    }
  end

  puts "✅ Created Claude Strategic Planner (ID: #{strategic_planner.id})"
  puts "✅ Created Claude Research Analyst (ID: #{research_analyst.id})"
  puts "✅ Created Claude Content Creator (ID: #{content_creator.id})"

  puts "\n📊 Claude-Powered Agents Summary:"
  claude_agents = AiAgent.where(ai_provider: claude_provider)
  puts "   Total Claude Agents: #{claude_agents.count}"
  puts "   Strategic Planning: #{claude_agents.where(agent_type: 'assistant').count}"
  puts "   Research Analysis: #{claude_agents.where(agent_type: 'data_analyst').count}"
  puts "   Content Creation: #{claude_agents.where(agent_type: 'content_generator').count}"

else
  puts "❌ Missing required data"
  puts "   Account: #{admin_account&.name || 'NOT FOUND'}"
  puts "   User: #{admin_user&.name || 'NOT FOUND'}"
  puts "   Claude Provider: #{claude_provider&.name || 'NOT FOUND'}"
end

puts "✅ Claude-powered agents seeding completed!"