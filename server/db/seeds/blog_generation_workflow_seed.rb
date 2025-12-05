# frozen_string_literal: true

# Blog Generation Workflow - Comprehensive AI Orchestration Demo
# This seed demonstrates:
# - Multi-agent collaboration (research, outline, writing, editing, SEO)
# - Saga pattern with compensation
# - Checkpointing for long-running tasks
# - Dynamic workflow generation
# - Marketplace template creation

puts "\n=== Creating Blog Generation Workflow ==="

# Use existing admin account and user
account = Account.find_by!(subdomain: 'admin')
user = account.users.find_by!(email: 'admin@powernode.org')

puts "✓ Using admin account: #{account.name} (#{user.email})"

# Find or create AI Provider (Claude)
provider = AiProvider.find_or_create_by!(
  account: account,
  name: 'Anthropic Claude',
  provider_type: 'anthropic'
) do |p|
  p.is_active = true
  p.api_endpoint = 'https://api.anthropic.com/v1'
  p.api_base_url = 'https://api.anthropic.com/v1'
  p.capabilities = ['text_generation', 'chat', 'analysis', 'creative_writing']
  p.supported_models = [
    { 'name' => 'claude-sonnet-4.5', 'id' => 'claude-sonnet-4-5-20250514', 'context_length' => 200000 },
    { 'name' => 'claude-opus-4.5', 'id' => 'claude-opus-4-5-20250514', 'context_length' => 200000 }
  ]
  p.configuration_schema = {
    'api_version' => '2023-06-01',
    'models' => ['claude-sonnet-4-5-20250514', 'claude-opus-4-5-20250514'],
    'default_model' => 'claude-sonnet-4-5-20250514'
  }
  p.rate_limits = {
    'requests_per_minute' => 1000,
    'tokens_per_minute' => 40000
  }
  p.priority_order = 1
end

puts "✓ AI Provider configured"

# Create AI Agents for Blog Generation

# 1. Research Agent - Gathers information and sources
research_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Research Agent',
  agent_type: 'data_analyst'
) do |agent|
  agent.description = 'Researches topics, gathers data, and identifies key points for blog content'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['research', 'analysis', 'data_gathering']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert research agent specializing in gathering comprehensive information for blog posts.

      Your responsibilities:
      1. Research the given topic thoroughly
      2. Identify key themes and subtopics
      3. Find relevant statistics, examples, and case studies
      4. Compile credible sources and references
      5. Create a research summary with actionable insights

      Output format:
      {
        "main_themes": ["theme1", "theme2"],
        "key_points": ["point1", "point2"],
        "statistics": [{"stat": "data", "source": "url"}],
        "examples": ["example1", "example2"],
        "sources": ["url1", "url2"],
        "research_summary": "comprehensive summary"
      }
    PROMPT
    'model' => 'claude-sonnet-4-5-20250514',
    'temperature' => 0.7,
    'max_tokens' => 2000,
    'timeout' => 60
  }
  agent.status = 'active'
end

# 2. Outline Agent - Creates structured blog outline
outline_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Outline Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Creates detailed, SEO-optimized blog post outlines'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['planning', 'content_structuring', 'seo_optimization']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert content strategist specializing in creating engaging blog outlines.

      Your responsibilities:
      1. Analyze research data
      2. Create a logical, flowing outline structure
      3. Ensure SEO optimization with keyword placement
      4. Plan engaging headlines and subheadings
      5. Identify opportunities for visuals, quotes, and CTAs

      Output format:
      {
        "title": "Compelling blog title with primary keyword",
        "meta_description": "150-160 character meta description",
        "introduction": "Hook and overview",
        "sections": [
          {
            "heading": "H2 heading",
            "subheadings": ["H3 subheading"],
            "key_points": ["point1", "point2"],
            "word_count_target": 300
          }
        ],
        "conclusion": "Summary and CTA strategy",
        "target_word_count": 1500
      }
    PROMPT
    'model' => 'claude-sonnet-4-5-20250514',
    'temperature' => 0.8,
    'max_tokens' => 1500,
    'timeout' => 45
  }
  agent.status = 'active'
end

# 3. Writer Agent - Generates blog content
writer_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Writer Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Writes engaging, well-researched blog content based on outlines'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['content_writing', 'creative_writing', 'storytelling']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert content writer specializing in creating engaging, informative blog posts.

      Your responsibilities:
      1. Write compelling, original content following the outline
      2. Maintain consistent tone and voice
      3. Incorporate research findings naturally
      4. Use storytelling and examples effectively
      5. Ensure proper flow and readability
      6. Include internal linking opportunities

      Writing style:
      - Conversational yet professional
      - Clear, concise sentences
      - Active voice preferred
      - Engaging hooks and transitions
      - Data-driven with human touch

      Output format:
      {
        "full_content": "Complete blog post in markdown",
        "word_count": 1500,
        "reading_time": "7 minutes",
        "internal_links": ["suggested link 1", "suggested link 2"]
      }
    PROMPT
    'model' => 'claude-sonnet-4-5-20250514',
    'temperature' => 0.9,
    'max_tokens' => 4000,
    'timeout' => 120
  }
  agent.status = 'active'
end

# 4. Editor Agent - Reviews and improves content
editor_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Editor Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Edits and refines blog content for quality, clarity, and engagement'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['content_editing', 'quality_assurance', 'refinement']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert editor specializing in refining blog content for maximum impact.

      Your responsibilities:
      1. Check grammar, spelling, and punctuation
      2. Improve clarity and readability
      3. Enhance engagement and flow
      4. Verify factual accuracy
      5. Optimize for target audience
      6. Ensure brand voice consistency

      Focus areas:
      - Sentence structure and variety
      - Transition quality
      - Paragraph length and balance
      - Tone consistency
      - Call-to-action effectiveness

      Output format:
      {
        "edited_content": "Refined blog post in markdown",
        "changes_made": ["change1", "change2"],
        "quality_score": 95,
        "readability_grade": "8th grade",
        "suggestions": ["suggestion1", "suggestion2"]
      }
    PROMPT
    'model' => 'claude-opus-4-20250514',
    'temperature' => 0.6,
    'max_tokens' => 4000,
    'timeout' => 90
  }
  agent.status = 'active'
end

# 5. SEO Agent - Optimizes for search engines
seo_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog SEO Agent',
  agent_type: 'workflow_optimizer'
) do |agent|
  agent.description = 'Optimizes blog content for search engines and discoverability'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['seo_optimization', 'keyword_research', 'meta_tag_generation']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert SEO specialist focusing on content optimization.

      Your responsibilities:
      1. Optimize keyword placement and density
      2. Enhance meta tags and descriptions
      3. Suggest internal/external linking strategy
      4. Optimize headings for search intent
      5. Create schema markup recommendations
      6. Generate social media snippets

      SEO checklist:
      - Primary keyword in title, H1, first paragraph
      - Secondary keywords distributed naturally
      - Meta description with CTA
      - Alt text for images
      - URL slug optimization
      - Featured snippet optimization

      Output format:
      {
        "optimized_content": "SEO-enhanced content",
        "primary_keyword": "main keyword",
        "secondary_keywords": ["keyword1", "keyword2"],
        "meta_title": "SEO title (60 chars)",
        "meta_description": "SEO description (155 chars)",
        "url_slug": "optimized-url-slug",
        "schema_markup": {},
        "social_snippets": {
          "twitter": "Tweet text",
          "linkedin": "LinkedIn post",
          "facebook": "Facebook post"
        },
        "seo_score": 92
      }
    PROMPT
    'model' => 'claude-sonnet-4-5-20250514',
    'temperature' => 0.5,
    'max_tokens' => 3000,
    'timeout' => 60
  }
  agent.status = 'active'
end

# 6. Fact Checker Agent - Verifies accuracy
fact_checker_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Fact Checker Agent',
  agent_type: 'data_analyst'
) do |agent|
  agent.description = 'Verifies facts, statistics, and claims in blog content'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['fact_checking', 'verification', 'source_validation']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are an expert fact-checker ensuring content accuracy and credibility.

      Your responsibilities:
      1. Verify all statistics and data points
      2. Check source credibility
      3. Identify unsupported claims
      4. Flag outdated information
      5. Suggest citation improvements
      6. Ensure ethical content standards

      Verification criteria:
      - Source recency (prefer last 2 years)
      - Authority and expertise
      - Data methodology
      - Bias detection
      - Cross-reference verification

      Output format:
      {
        "verified_claims": [{"claim": "text", "verified": true, "source": "url"}],
        "unverified_claims": [{"claim": "text", "issue": "description"}],
        "outdated_info": [{"info": "text", "recommendation": "update"}],
        "credibility_score": 88,
        "corrections_needed": ["correction1"],
        "verification_summary": "Overall assessment"
      }
    PROMPT
    'model' => 'claude-opus-4-20250514',
    'temperature' => 0.3,
    'max_tokens' => 2000,
    'timeout' => 75
  }
  agent.status = 'active'
end

puts "✓ Created #{AiAgent.where(account: account).count} AI Agents"

# 7. Workflow Orchestrator Agent - Coordinates the entire blog generation workflow
orchestrator_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Workflow Orchestrator',
  agent_type: 'workflow_operations'
) do |agent|
  agent.description = 'Coordinates and manages the entire blog generation workflow, ensuring smooth transitions between agents'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['workflow_coordination', 'task_delegation', 'quality_monitoring', 'error_recovery']
  agent.version = '1.0.0'
  agent.mcp_metadata = {
    'system_prompt' => <<~PROMPT.strip,
      You are a workflow orchestration expert managing a multi-agent blog generation pipeline.

      Your responsibilities:
      1. Coordinate execution flow between research, outline, writing, editing, and SEO agents
      2. Monitor each agent's progress and output quality
      3. Make decisions about workflow branching (revision loops, quality gates)
      4. Handle errors and trigger compensation/recovery strategies
      5. Optimize agent collaboration and data handoffs
      6. Ensure workflow completes successfully within SLA

      Coordination strategies:
      - Parallel execution when possible (writing + fact-checking)
      - Quality-based decision making at gates
      - Automatic retry with backoff for transient failures
      - Saga pattern compensation for critical failures
      - Checkpoint creation at milestone nodes
      - Real-time progress tracking and reporting

      Output format:
      {
        "workflow_status": "in_progress|completed|failed",
        "current_step": "step_name",
        "next_action": "continue|retry|compensate|complete",
        "quality_metrics": {
          "overall_quality": 92,
          "agent_performance": {},
          "completion_percentage": 75
        },
        "decisions_made": [
          {"decision": "quality_check_passed", "reason": "score above threshold"}
        ],
        "error_handling": {
          "errors_encountered": [],
          "recovery_actions": []
        }
      }
    PROMPT
    'model' => 'claude-opus-4-20250514',
    'temperature' => 0.4,
    'max_tokens' => 2000,
    'timeout' => 30,
    'role' => 'orchestrator',
    'manages_workflow' => true
  }
  agent.status = 'active'
end

puts "✓ Created Workflow Orchestrator Agent"

# Create Blog Generation Workflow
workflow = AiWorkflow.find_or_create_by!(
  account: account,
  name: 'Blog Generation Pipeline'
) do |wf|
  wf.creator = user
  wf.description = 'Comprehensive blog generation workflow using multi-agent collaboration with intelligent orchestration'
  wf.status = 'active'
  wf.visibility = 'public'
  wf.version = '1.0.0'
  wf.configuration = {
    'enable_checkpointing' => true,
    'enable_compensation' => true,
    'max_retries' => 3,
    'timeout' => 600,
    'workflow_orchestrator_id' => orchestrator_agent.id,
    'orchestration_strategy' => 'ai_managed'
  }
  wf.mcp_orchestration_config = {
    'orchestrator_agent_id' => orchestrator_agent.id,
    'orchestration_mode' => 'supervised',
    'auto_recovery' => true,
    'quality_gates' => ['outline_approval', 'content_quality', 'seo_score'],
    'parallel_execution_enabled' => true,
    'max_parallel_nodes' => 3,
    'checkpoint_strategy' => 'milestone_based',
    'compensation_strategy' => 'saga_pattern',
    'monitoring' => {
      'track_agent_performance' => true,
      'quality_score_threshold' => 85,
      'cost_tracking' => true,
      'duration_tracking' => true
    }
  }
  wf.metadata = {
    'category' => 'Content Creation',
    'use_case' => 'Blog Generation',
    'complexity' => 'Advanced',
    'estimated_duration' => '5-10 minutes',
    'orchestration_type' => 'ai_coordinated',
    'agent_count' => 7,
    'has_workflow_orchestrator' => true
  }
end

puts "✓ Created Workflow: #{workflow.name}"

# Create Workflow Nodes

# 1. Start Node (Entry Point)
trigger_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'trigger_1',
  node_type: 'start'
) do |node|
  node.name = 'Blog Topic Input'
  node.description = 'Workflow entry point - accepts topic, audience, keywords, and preferences'
  node.position = { x: 100, y: 100 }
  node.configuration = {
    'input_schema' => {
      'topic' => { 'type' => 'string', 'required' => true },
      'target_audience' => { 'type' => 'string', 'required' => false },
      'keywords' => { 'type' => 'array', 'required' => false },
      'tone' => { 'type' => 'string', 'default' => 'professional' },
      'word_count' => { 'type' => 'number', 'default' => 1500 }
    }
  }
end

# 2. Research Node
research_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'research_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Topic Research'
  node.description = 'Gather comprehensive research on the topic, including key themes, statistics, and sources'
  node.position = { x: 100, y: 250 }
  node.configuration = {
    'agent_id' => research_agent.id,
    'prompt_template' => 'Research the following topic comprehensively: {{topic}}. Target audience: {{target_audience}}. Focus keywords: {{keywords}}.',
    'enable_retry' => true,
    'max_retries' => 2,
    'compensatable' => true,
    'compensation_type' => 'rollback'
  }
end

# 3. Outline Node
outline_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'outline_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Create Outline'
  node.description = 'Create a detailed, SEO-optimized blog outline with sections and subsections'
  node.position = { x: 100, y: 400 }
  node.configuration = {
    'agent_id' => outline_agent.id,
    'prompt_template' => 'Create a detailed blog outline for: {{topic}}. Use this research: {{research_summary}}. Target {{word_count}} words. Tone: {{tone}}.',
    'enable_retry' => true,
    'checkpoint_before' => true,
    'compensatable' => true
  }
end

# 4. Parallel Writing & Fact Checking
writer_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'writer_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Write Content'
  node.description = 'Write engaging blog content following the outline and incorporating research insights'
  node.position = { x: 50, y: 550 }
  node.configuration = {
    'agent_id' => writer_agent.id,
    'prompt_template' => 'Write a complete blog post following this outline: {{outline}}. Include research insights: {{research_summary}}. Tone: {{tone}}.',
    'enable_retry' => true,
    'timeout' => 180,
    'compensatable' => true
  }
end

fact_check_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'fact_check_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Fact Check Research'
  node.description = 'Verify facts, statistics, and claims to ensure content accuracy and credibility'
  node.position = { x: 300, y: 550 }
  node.configuration = {
    'agent_id' => fact_checker_agent.id,
    'prompt_template' => 'Verify all facts and statistics in this research: {{research_summary}}.',
    'enable_retry' => true,
    'compensatable' => false
  }
end

# 5. Merge Node (combines parallel results)
merge_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'merge_1',
  node_type: 'transform'
) do |node|
  node.name = 'Merge Content & Facts'
  node.description = 'Combine written content with fact-checking results for editing phase'
  node.position = { x: 175, y: 700 }
  node.configuration = {
    'merge_strategy' => 'combine',
    'output_format' => {
      'content' => '{{writer_output.full_content}}',
      'fact_check' => '{{fact_checker_output}}'
    }
  }
end

# 6. Editor Node
editor_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'editor_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Edit & Refine'
  node.description = 'Review and improve content for grammar, clarity, flow, and engagement'
  node.position = { x: 175, y: 850 }
  node.configuration = {
    'agent_id' => editor_agent.id,
    'prompt_template' => 'Edit this blog post for quality and engagement: {{content}}. Address any fact-check issues: {{fact_check}}.',
    'enable_retry' => true,
    'checkpoint_after' => true,
    'compensatable' => true
  }
end

# 7. SEO Optimization Node
seo_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'seo_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'SEO Optimization'
  node.description = 'Optimize content for search engines with meta tags, keywords, and schema markup'
  node.position = { x: 175, y: 1000 }
  node.configuration = {
    'agent_id' => seo_agent.id,
    'prompt_template' => 'Optimize this blog post for SEO: {{edited_content}}. Primary keyword: {{keywords[0]}}. Secondary keywords: {{keywords}}.',
    'enable_retry' => true,
    'compensatable' => true
  }
end

# 8. Quality Gate (Condition Node)
quality_gate_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'quality_gate_1',
  node_type: 'condition'
) do |node|
  node.name = 'Quality Check'
  node.description = 'Evaluate content quality and SEO scores - pass to output or revision'
  node.position = { x: 175, y: 1150 }
  node.configuration = {
    'conditions' => [
      { 'field' => 'seo_score', 'operator' => '>=', 'value' => 80 },
      { 'field' => 'quality_score', 'operator' => '>=', 'value' => 85 }
    ],
    'logic' => 'AND',
    'true_path' => 'output',
    'false_path' => 'revision'
  }
end

# 9. Output Node
output_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'output_1',
  node_type: 'end'
) do |node|
  node.name = 'Final Blog Post'
  node.description = 'Workflow completion - outputs publication-ready blog with all metadata and metrics'
  node.position = { x: 175, y: 1300 }
  node.configuration = {
    'output_format' => {
      'title' => '{{meta_title}}',
      'content' => '{{optimized_content}}',
      'meta_description' => '{{meta_description}}',
      'url_slug' => '{{url_slug}}',
      'keywords' => '{{keywords}}',
      'social_snippets' => '{{social_snippets}}',
      'schema_markup' => '{{schema_markup}}',
      'reading_time' => '{{reading_time}}',
      'word_count' => '{{word_count}}',
      'quality_metrics' => {
        'seo_score' => '{{seo_score}}',
        'quality_score' => '{{quality_score}}',
        'credibility_score' => '{{credibility_score}}'
      }
    }
  }
end

# 10. Revision Node (if quality gate fails)
revision_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'revision_1',
  node_type: 'ai_agent'
) do |node|
  node.name = 'Content Revision'
  node.description = 'Revise content to improve quality and SEO scores when quality gate fails'
  node.position = { x: 350, y: 1150 }
  node.configuration = {
    'agent_id' => editor_agent.id,
    'prompt_template' => 'Revise this content to improve scores. Current SEO: {{seo_score}}, Quality: {{quality_score}}. Content: {{optimized_content}}.',
    'max_attempts' => 2
  }
end

# 11. KB Article Create Node - Save to Knowledge Base
kb_article_node = AiWorkflowNode.find_or_create_by!(
  ai_workflow: workflow,
  node_id: 'kb_article_1',
  node_type: 'kb_article_create'
) do |node|
  node.name = 'Save to Knowledge Base'
  node.description = 'Publish the final blog post to the knowledge base with full metadata and SEO optimization'
  node.position = { x: 175, y: 1450 }
  node.configuration = {
    'title' => '{{meta_title}}',
    'content' => '{{optimized_content}}',
    'excerpt' => '{{meta_description}}',
    'category_id' => 'blog-posts',
    'status' => 'published',
    'tags' => '{{keywords}}',
    'is_public' => true,
    'is_featured' => false,
    'output_variable' => 'kb_article_id',
    'orientation' => 'vertical'
  }
  node.metadata = {
    'handleOrientation' => 'vertical',
    'description' => 'Automatically saves generated blog content to knowledge base',
    'source' => 'blog_generation_workflow'
  }
end

puts "✓ Created #{workflow.ai_workflow_nodes.count} Workflow Nodes"

# Create Workflow Edges (connections)

edges_data = [
  { source: 'trigger_1', target: 'research_1', label: 'Start' },
  { source: 'research_1', target: 'outline_1', label: 'Research Complete' },
  { source: 'outline_1', target: 'writer_1', label: 'Outline Ready' },
  { source: 'outline_1', target: 'fact_check_1', label: 'Parallel Fact Check' },
  { source: 'writer_1', target: 'merge_1', label: 'Content Written' },
  { source: 'fact_check_1', target: 'merge_1', label: 'Facts Verified' },
  { source: 'merge_1', target: 'editor_1', label: 'Merged Data' },
  { source: 'editor_1', target: 'seo_1', label: 'Edited Content' },
  { source: 'seo_1', target: 'quality_gate_1', label: 'SEO Optimized' },
  { source: 'quality_gate_1', target: 'output_1', label: 'Passed', is_conditional: true, condition: { 'expression' => 'quality >= threshold', 'path' => 'true' } },
  { source: 'quality_gate_1', target: 'revision_1', label: 'Failed', is_conditional: true, condition: { 'expression' => 'quality < threshold', 'path' => 'false' } },
  { source: 'revision_1', target: 'seo_1', label: 'Revised', edge_type: 'loop' },
  { source: 'output_1', target: 'kb_article_1', label: 'Save to KB' }
]

edges_data.each_with_index do |edge_data, index|
  AiWorkflowEdge.find_or_create_by!(
    ai_workflow: workflow,
    edge_id: "edge_#{index + 1}",
    source_node_id: edge_data[:source],
    target_node_id: edge_data[:target]
  ) do |edge|
    edge.is_conditional = edge_data[:is_conditional] || false
    edge.condition = edge_data[:condition] || {}
    edge.edge_type = edge_data[:edge_type] || 'default'
    edge.metadata = { 'label' => edge_data[:label] }
  end
end

puts "✓ Created #{workflow.ai_workflow_edges.count} Workflow Edges"

# Create Workflow Variables
variables_data = [
  { name: 'topic', variable_type: 'string', default_value: '', is_required: true, description: 'Blog topic or title' },
  { name: 'target_audience', variable_type: 'string', default_value: 'general', is_required: false, description: 'Target reader demographic' },
  { name: 'keywords', variable_type: 'array', default_value: [], is_required: false, description: 'SEO keywords to target' },
  { name: 'tone', variable_type: 'string', default_value: 'professional', is_required: false, description: 'Writing tone (professional, casual, technical)' },
  { name: 'word_count', variable_type: 'number', default_value: 1500, is_required: false, description: 'Target word count' },
  { name: 'quality_threshold', variable_type: 'number', default_value: 85, is_required: false, description: 'Minimum quality score' }
]

variables_data.each do |var_data|
  AiWorkflowVariable.find_or_create_by!(
    ai_workflow: workflow,
    name: var_data[:name]
  ) do |var|
    var.variable_type = var_data[:variable_type]
    var.default_value = var_data[:default_value]
    var.is_required = var_data[:is_required]
    var.description = var_data[:description]
  end
end

puts "✓ Created #{workflow.ai_workflow_variables.count} Workflow Variables"

# Create Workflow Trigger
trigger = AiWorkflowTrigger.find_or_create_by!(
  ai_workflow: workflow,
  name: 'Manual Blog Generation'
) do |t|
  t.trigger_type = 'manual'
  t.status = 'active'
  t.is_active = true
  t.configuration = {
    'require_confirmation' => false,
    'input_validation' => true
  }
end

puts "✓ Created Workflow Trigger"

# Create as Marketplace Template
template = AiWorkflowTemplate.find_or_create_by!(
  slug: 'blog-generation-pipeline'
) do |tmpl|
  tmpl.name = 'Blog Generation Pipeline'
  tmpl.description = 'AI-powered blog generation with research, writing, editing, and SEO optimization'
  tmpl.long_description = <<~DESC
    ## Comprehensive Blog Generation Workflow with AI Orchestration

    This advanced workflow demonstrates the full power of Powernode's AI orchestration with intelligent workflow-level coordination:

    ### Key Innovation: Workflow-Level AI Orchestrator
    - **Intelligent Coordination**: A dedicated AI agent manages the entire workflow
    - **Dynamic Decision Making**: Real-time quality assessment and branching
    - **Error Recovery**: Automated compensation and retry strategies
    - **Performance Optimization**: Parallel execution and resource management

    ### Features
    - **Multi-Agent Collaboration**: 7 AI agents (1 orchestrator + 6 specialists) working in harmony
    - **Parallel Processing**: Simultaneous content writing and fact-checking
    - **Quality Assurance**: Built-in editing and SEO optimization
    - **Saga Pattern**: Automatic compensation for failures
    - **Smart Checkpointing**: Save progress at critical milestones
    - **Conditional Logic**: Quality gate with intelligent revision loops

    ### Workflow Steps
    1. **Orchestrator Initialization**: Workflow coordinator sets up execution plan
    2. **Research**: Gather comprehensive information on the topic
    3. **Outline**: Create structured, SEO-optimized outline
    4. **Write & Verify**: Parallel content creation and fact-checking (orchestrator-managed)
    5. **Edit**: Refine for quality and engagement
    6. **Optimize**: SEO enhancement with meta tags
    7. **Quality Check**: Orchestrator evaluates against thresholds
    8. **Output**: Publication-ready blog post

    ### AI Agents Included
    - **Workflow Orchestrator** (Coordinator)
    - **Research Agent** (Data Analyst)
    - **Outline Agent** (Content Strategist)
    - **Writer Agent** (Content Generator)
    - **Editor Agent** (Quality Assurance)
    - **SEO Agent** (Optimization Specialist)
    - **Fact-Checker Agent** (Verification Specialist)

    ### Use Cases
    - Content marketing teams
    - Automated blog production
    - SEO content creation at scale
    - Thought leadership articles
    - Educational content development
    - Multi-language content generation

    ### Requirements
    - Anthropic Claude API access
    - Recommended: Claude 3.5 Sonnet or Opus for orchestrator
    - Claude 3.5 Sonnet for specialist agents
  DESC
  tmpl.category = 'Content Creation'
  tmpl.difficulty_level = 'advanced'
  tmpl.workflow_definition = {
    'nodes' => workflow.ai_workflow_nodes.map do |node|
      {
        'node_id' => node.node_id,
        'node_type' => node.node_type,
        'name' => node.name,
        'position' => node.position,
        'configuration' => node.configuration
      }
    end,
    'edges' => workflow.ai_workflow_edges.map do |edge|
      {
        'edge_id' => edge.edge_id,
        'source_node_id' => edge.source_node_id,
        'target_node_id' => edge.target_node_id,
        'label' => edge.metadata['label'],
        'is_conditional' => edge.is_conditional,
        'condition' => edge.condition
      }
    end,
    'variables' => workflow.ai_workflow_variables.map do |var|
      {
        'name' => var.name,
        'variable_type' => var.variable_type,
        'default_value' => var.default_value,
        'is_required' => var.is_required,
        'description' => var.description
      }
    end,
    'triggers' => [
      {
        'trigger_type' => 'manual',
        'configuration' => trigger.configuration
      }
    ]
  }
  tmpl.default_variables = {
    'topic' => '',
    'target_audience' => 'general',
    'keywords' => [],
    'tone' => 'professional',
    'word_count' => 1500,
    'quality_threshold' => 85
  }
  tmpl.tags = ['blog', 'content-creation', 'seo', 'writing', 'multi-agent', 'automation']
  tmpl.author_name = 'Powernode Team'
  tmpl.author_email = 'team@powernode.ai'
  tmpl.license = 'MIT'
  tmpl.version = '1.0.0'
  tmpl.is_public = true
  tmpl.is_featured = true
  tmpl.published_at = Time.current
  tmpl.usage_count = 0
  tmpl.rating = 4.8
  tmpl.rating_count = 24
  tmpl.metadata = {
    'estimated_duration' => '5-10 minutes',
    'cost_estimate' => '$0.50-$2.00 per run',
    'complexity_score' => 80,
    'total_agent_count' => 7,
    'orchestrator_agent_count' => 1,
    'specialist_agent_count' => 6,
    'node_count' => workflow.ai_workflow_nodes.count,
    'has_parallel_execution' => true,
    'has_conditional_logic' => true,
    'has_error_recovery' => true,
    'has_checkpointing' => true,
    'has_workflow_orchestrator' => true,
    'orchestration_type' => 'ai_coordinated',
    'quality_gates' => 3,
    'supports_saga_pattern' => true
  }
end

puts "✓ Created Marketplace Template"

puts "\n=== Blog Generation Workflow Creation Complete ==="
puts "\nWorkflow Summary:"
puts "  - Name: #{workflow.name}"
puts "  - Total Agents: #{AiAgent.where(account: account).count}"
puts "  - Workflow Orchestrator: #{orchestrator_agent.name}"
puts "  - Specialist Agents: 6 (Research, Outline, Writer, Editor, SEO, Fact-Checker)"
puts "  - Nodes: #{workflow.ai_workflow_nodes.count}"
puts "  - Edges: #{workflow.ai_workflow_edges.count}"
puts "  - Variables: #{workflow.ai_workflow_variables.count}"
puts "  - Template: #{template.name}"
puts "  - Marketplace Ready: #{template.published? ? 'Yes' : 'No'}"
puts "  - Orchestration: AI-Coordinated with Intelligent Workflow Management"
puts "  - KB Integration: ✓ Automatic knowledge base publishing"
puts "\nOrchestration Features:"
puts "  ✓ Workflow-level AI coordinator managing all agents"
puts "  ✓ Parallel execution (Writing + Fact-Checking)"
puts "  ✓ Quality gates with automatic revision loops"
puts "  ✓ Saga pattern error compensation"
puts "  ✓ Milestone-based checkpointing"
puts "  ✓ Real-time performance monitoring"
puts "  ✓ Automatic knowledge base article creation with SEO metadata"
puts "\nWorkflow Output:"
puts "  ✓ Final blog post with complete metadata"
puts "  ✓ Published to knowledge base as article"
puts "  ✓ SEO-optimized with keywords and meta tags"
puts "  ✓ Quality scores and performance metrics"
puts "\nTo execute this workflow:"
puts "  1. Visit the workflow dashboard"
puts "  2. Select 'Blog Generation Pipeline'"
puts "  3. Click 'Execute' and provide a topic"
puts "  4. Watch the AI orchestrator coordinate multi-agent collaboration!"
puts "  5. Generated blog automatically saved to knowledge base!"
puts "\nOr install from marketplace:"
puts "  1. Browse marketplace templates"
puts "  2. Search for 'Blog Generation Pipeline'"
puts "  3. Click 'Install' to add to your account"
