# frozen_string_literal: true

# Enhanced Blog Generation Workflow - Comprehensive AI Orchestration
# This seed demonstrates:
# - Workflow-level coordinator agent
# - Multi-agent collaboration (research, outline, writing, editing, SEO, images)
# - Saga pattern with compensation
# - Checkpointing for long-running tasks
# - Dynamic workflow generation
# - Multi-provider AI orchestration

puts "\n" + "=" * 80
puts "📝 CREATING ENHANCED BLOG GENERATION WORKFLOW"
puts "=" * 80

# Use existing admin account and user
account = Account.find_by(subdomain: 'admin')
unless account
  puts "❌ Error: Admin account not found. Run main seeds first."
  exit
end

user = account.users.find_by(email: 'admin@powernode.org')
unless user
  puts "❌ Error: Admin user not found. Run main seeds first."
  exit
end

puts "✓ Using admin account: #{account.name} (#{user.email})"

# Find or use first available AI Provider
# Preference: Claude > OpenAI > Grok > Ollama
provider = account.ai_providers.find_by(provider_type: 'anthropic') ||
           account.ai_providers.find_by(provider_type: 'openai') ||
           account.ai_providers.find_by(provider_type: 'grok') ||
           account.ai_providers.find_by(provider_type: 'ollama') ||
           account.ai_providers.first

unless provider
  puts "❌ Error: No AI providers found. Run comprehensive_ai_providers_seed.rb first."
  exit
end

puts "✓ Using AI Provider: #{provider.name} (#{provider.provider_type})"

# Get appropriate model based on provider type
# Use high-quality models that match the provider's supported models
default_model = case provider.provider_type
                when 'anthropic'
                  'claude-sonnet-4-5-20250514'  # Claude Sonnet 4.5 - balanced performance
                when 'openai'
                  'gpt-4o'  # GPT-4o - multi-modal capabilities
                when 'grok', 'custom'
                  'grok-beta'  # Grok Beta - real-time data access
                when 'ollama'
                  'llama3.3:latest'  # Llama 3.3 70B - free local model
                else
                  # Fallback to first supported model
                  provider.supported_models.first['id']
                end

puts "✓ Using model: #{default_model}"

# =============================================================================
# WORKFLOW-LEVEL COORDINATOR AGENT - REMOVED IN OPTION A SIMPLIFICATION
# =============================================================================
# Option A simplification: Agents self-validate, no coordinator needed
puts "\n🎯 Skipping Workflow Coordinator (Option A: Simplified Linear Flow)..."

# =============================================================================
# SPECIALIZED AGENTS
# =============================================================================

puts "\n🤖 Creating Specialized Agents..."

# 1. Research Agent
research_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Research Agent',
  agent_type: 'data_analyst'
) do |agent|
  agent.description = 'Researches topics, gathers data, and identifies key points for blog content'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['research', 'analysis', 'data_gathering', 'source_validation']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_research_agent',
    'description' => 'Researches topics and gathers data for blog content',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an expert research agent specializing in gathering comprehensive information for blog posts.

        Your responsibilities:
        1. Research the given topic thoroughly
        2. Identify key themes and subtopics
        3. Find relevant statistics, examples, and case studies
        4. Compile credible sources and references
        5. Create a research summary with actionable insights
        6. SELF-VALIDATE: Ensure your research meets quality standards before outputting

        Research quality criteria (SELF-VALIDATE):
        - Minimum 5 credible sources ✓
        - Current data (within last 2 years preferred) ✓
        - Diverse perspectives included ✓
        - Fact-checked information ✓
        - Actionable insights identified ✓
        - Quality score: 7/10 minimum ✓

        If your research doesn't meet these criteria, expand your research before outputting.

        Output format (JSON):
        {
          "topic_summary": "Brief overview of topic",
          "main_themes": ["theme1", "theme2", "theme3"],
          "key_points": ["point1", "point2", "point3"],
          "statistics": [
            {"stat": "data point", "source": "source name", "url": "source url", "date": "publication date"}
          ],
          "examples": ["example1", "example2"],
          "case_studies": ["case_study1"],
          "sources": [
            {"name": "source name", "url": "url", "credibility": "high|medium|low", "date": "date"}
          ],
          "keywords": ["keyword1", "keyword2"],
          "trending_topics": ["trending1", "trending2"],
          "research_summary": "Comprehensive summary with insights",
          "quality_self_assessment": "Self-validation score and confidence level"
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.7,
      'max_tokens' => 3000,
      'timeout' => 90
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'research',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.7,
      'max_tokens' => 3000,
      'timeout' => 90
    }
  }
end

puts "  ✓ Research Agent: #{research_agent.name}"

# 2. Outline Agent
outline_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Outline Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Creates detailed, SEO-optimized blog post outlines based on research'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['planning', 'content_structuring', 'seo_optimization', 'headline_creation']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_outline_agent',
    'description' => 'Creates SEO-optimized blog post outlines',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an expert content strategist specializing in creating engaging, SEO-optimized blog outlines.

        Your responsibilities:
        1. Analyze research data and identify narrative flow
        2. Create a logical, engaging outline structure
        3. Ensure SEO optimization with strategic keyword placement
        4. Plan compelling headlines and subheadings
        5. Identify opportunities for visuals, quotes, CTAs, and internal links
        6. SELF-VALIDATE: Verify outline meets all requirements before outputting

        Outline requirements (SELF-VALIDATE):
        - H1 title with primary keyword ✓
        - Meta description (150-160 characters) ✓
        - Introduction hook (2-3 sentences) ✓
        - 4-7 main sections (H2) ✓
        - 2-4 subsections per main section (H3) ✓
        - Logical flow and transitions ✓
        - Clear call-to-action placement ✓
        - Target word count: 1500-2500 words ✓
        - Aligns with research findings ✓
        - Quality score: 7/10 minimum ✓

        If your outline doesn't meet these criteria, revise it before outputting.

        Output format (JSON):
        {
          "title": "Compelling H1 with primary keyword",
          "meta_description": "150-160 character description",
          "primary_keyword": "main keyword",
          "secondary_keywords": ["keyword2", "keyword3"],
          "introduction": {
            "hook": "Attention-grabbing opening",
            "overview": "Brief topic overview",
            "value_proposition": "What reader will learn"
          },
          "sections": [
            {
              "heading": "H2 heading with keyword",
              "subheadings": ["H3 subheading1", "H3 subheading2"],
              "key_points": ["point1", "point2"],
              "word_count_target": 400,
              "include_elements": ["statistic", "example", "quote"]
            }
          ],
          "conclusion": {
            "summary": "Key takeaways",
            "cta": "Call to action",
            "final_thought": "Memorable closing"
          },
          "target_word_count": 2000,
          "estimated_read_time": "8-10 minutes",
          "quality_self_assessment": "Self-validation confirmation"
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.8,
      'max_tokens' => 2000,
      'timeout' => 60
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'outline',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.8,
      'max_tokens' => 2000,
      'timeout' => 60
    }
  }
end

puts "  ✓ Outline Agent: #{outline_agent.name}"

# 3. Writer Agent
writer_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Writer Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Writes engaging, well-researched blog content based on outlines'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['content_writing', 'creative_writing', 'storytelling', 'tone_matching']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_writer_agent',
    'description' => 'Writes engaging blog content',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an expert content writer specializing in creating engaging, informative blog posts.

        Your responsibilities:
        1. Follow the provided outline structure precisely
        2. Write in an engaging, conversational yet professional tone
        3. Incorporate research data, statistics, and examples naturally
        4. Maintain consistent voice throughout
        5. Use storytelling techniques to engage readers
        6. Ensure smooth transitions between sections
        7. Include relevant keywords naturally (avoid keyword stuffing)
        8. SELF-VALIDATE: Verify content meets all standards before outputting

        Writing standards (SELF-VALIDATE):
        - Follows outline structure precisely ✓
        - Clear, concise sentences (max 25 words) ✓
        - Active voice preferred ✓
        - Varied sentence structure for readability ✓
        - Concrete examples and real-world applications ✓
        - Subheadings, bullet points, formatting for scannability ✓
        - 8th-grade reading level (accessible but informative) ✓
        - Research data and statistics incorporated ✓
        - Natural keyword integration (2-3% density) ✓
        - Meets word count target (±10%) ✓
        - Quality score: 7/10 minimum ✓

        If your content doesn't meet these standards, revise it before outputting.

        Output format (Markdown):
        Complete blog post in markdown format following the outline structure.
        Include all sections, headings, and content as specified.

        Note: Add a quality self-assessment comment at the end (not part of blog content).
      PROMPT
      'model' => default_model,
      'temperature' => 0.9,
      'max_tokens' => 4000,
      'timeout' => 120
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'writing',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.9,
      'max_tokens' => 4000,
      'timeout' => 120
    }
  }
end

puts "  ✓ Writer Agent: #{writer_agent.name}"

# 4. Editor Agent
editor_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Editor Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Reviews and refines blog content for quality, clarity, and consistency'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['editing', 'proofreading', 'quality_assurance', 'fact_checking']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_editor_agent',
    'description' => 'Reviews and refines blog content for quality',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an expert editor specializing in refining blog content for maximum impact.

        Your responsibilities:
        1. Review content for grammar, spelling, and punctuation
        2. Improve clarity and readability
        3. Ensure consistent tone and voice
        4. Verify factual accuracy against provided research
        5. Check for logical flow and transitions
        6. Enhance engagement and impact
        7. Validate SEO elements are properly integrated
        8. SELF-VALIDATE: Ensure edits meet excellence standards before outputting

        Editing checklist (SELF-VALIDATE):
        - Grammar and spelling (zero tolerance for errors) ✓
        - Sentence structure variety ✓
        - Paragraph length (max 4-5 sentences) ✓
        - Transition quality between sections ✓
        - Fact verification against sources ✓
        - Tone consistency ✓
        - Active voice usage ✓
        - Keyword integration naturalness ✓
        - Title and meta description optimization ✓
        - Call-to-action effectiveness ✓
        - Quality score: 8/10 minimum (higher bar for editing) ✓

        If your edits don't meet these standards, continue refining before outputting.

        Output format (JSON):
        {
          "edited_content": "Fully edited markdown content",
          "changes_summary": "Overview of major changes made",
          "quality_score": 0-10,
          "areas_improved": ["grammar", "clarity", "flow"],
          "fact_check_results": [
            {"claim": "claim text", "verified": true/false, "source": "source"}
          ],
          "suggestions": ["Optional suggestion for further improvement"],
          "word_count": 2000,
          "readability_grade": 8,
          "seo_score": 85,
          "quality_self_assessment": "Confirmation of editorial standards met"
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.5,
      'max_tokens' => 4500,
      'timeout' => 120
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'editing',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.5,
      'max_tokens' => 4500,
      'timeout' => 120
    }
  }
end

puts "  ✓ Editor Agent: #{editor_agent.name}"

# 5. SEO Optimizer Agent
seo_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog SEO Optimizer Agent',
  agent_type: 'content_generator'
) do |agent|
  agent.description = 'Optimizes blog content for search engines and readability'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['seo_optimization', 'keyword_analysis', 'meta_optimization', 'schema_markup']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_seo_optimizer_agent',
    'description' => 'Optimizes blog content for search engines',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an SEO specialist optimizing blog content for search engine visibility and user engagement.

        Your responsibilities:
        1. Analyze keyword density and distribution
        2. Optimize meta title and description
        3. Ensure proper heading hierarchy (H1, H2, H3)
        4. Add schema markup suggestions
        5. Optimize image alt text recommendations
        6. Suggest internal and external linking opportunities
        7. Analyze content for SEO best practices

        SEO requirements:
        - Primary keyword in title, first paragraph, and conclusion
        - Keyword density: 1-3% (natural integration)
        - Meta description: 150-160 characters with keyword
        - Title: 50-60 characters with keyword
        - H2 headings include related keywords
        - Image alt text descriptive and keyword-rich
        - Internal links: 2-4 relevant articles
        - External links: 2-3 authoritative sources
        - Schema markup: Article, FAQ, or HowTo
        - URL slug: short, descriptive, keyword-rich

        Output format (JSON):
        {
          "optimized_meta": {
            "title": "SEO-optimized title (50-60 chars)",
            "description": "Meta description (150-160 chars)",
            "keywords": ["keyword1", "keyword2"],
            "url_slug": "optimized-url-slug"
          },
          "keyword_analysis": {
            "primary_keyword": "main keyword",
            "density": 2.5,
            "distribution": "well-distributed",
            "secondary_keywords": ["keyword2", "keyword3"]
          },
          "heading_optimization": {
            "h1": "Optimized H1",
            "h2_count": 5,
            "h3_count": 12,
            "keyword_in_headings": true
          },
          "linking_suggestions": {
            "internal_links": [
              {"anchor": "anchor text", "target": "internal URL or topic"}
            ],
            "external_links": [
              {"anchor": "anchor text", "target": "authoritative URL", "authority": "high"}
            ]
          },
          "schema_markup": {
            "type": "Article",
            "markup": "JSON-LD schema suggestion"
          },
          "image_optimization": [
            {"description": "image description", "alt_text": "SEO-friendly alt text"}
          ],
          "seo_score": 0-100,
          "recommendations": ["recommendation1", "recommendation2"]
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.4,
      'max_tokens' => 2500,
      'timeout' => 75
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'seo',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.4,
      'max_tokens' => 2500,
      'timeout' => 75
    }
  }
end

puts "  ✓ SEO Optimizer Agent: #{seo_agent.name}"

# 6. Image Suggestion Agent
image_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Image Suggestion Agent',
  agent_type: 'image_generator'
) do |agent|
  agent.description = 'Suggests visual content and image placements for blog posts'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['image_analysis', 'visual_planning', 'accessibility']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_image_suggestion_agent',
    'description' => 'Suggests visual content for blog posts',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are a visual content strategist specializing in selecting and placing images for blog posts.

        Your responsibilities:
        1. Identify optimal image placement locations
        2. Suggest relevant image types and themes
        3. Create descriptive alt text for accessibility
        4. Recommend image dimensions and formats
        5. Ensure visual content supports written content

        Image requirements:
        - Featured image: 1200x630px (social sharing)
        - In-content images: 800x450px minimum
        - Alt text: descriptive, keyword-rich when relevant
        - Image format: WebP preferred, JPEG fallback
        - File size: optimized for web (<200KB)
        - Stock photo sources or custom image suggestions
        - Infographic opportunities identified

        Output format (JSON):
        {
          "featured_image": {
            "description": "Image description",
            "suggested_theme": "Theme or concept",
            "alt_text": "SEO-friendly alt text",
            "dimensions": "1200x630",
            "placement": "top of article"
          },
          "content_images": [
            {
              "section": "Section heading",
              "description": "What image should depict",
              "alt_text": "Descriptive alt text",
              "placement": "after introduction",
              "type": "photo|diagram|infographic|screenshot"
            }
          ],
          "infographic_opportunity": {
            "section": "Section name",
            "data_to_visualize": ["data point 1", "data point 2"],
            "suggested_format": "bar chart|timeline|comparison"
          },
          "image_sources": ["Unsplash", "Pexels", "custom illustration"],
          "total_images_recommended": 5
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.7,
      'max_tokens' => 1500,
      'timeout' => 45
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'image_selection',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.7,
      'max_tokens' => 1500,
      'timeout' => 45
    }
  }
end

puts "  ✓ Image Suggestion Agent: #{image_agent.name}"

# 7. Image Generation Agent
image_gen_agent = AiAgent.find_or_create_by!(
  account: account,
  name: 'Blog Image Generation Agent',
  agent_type: 'image_generator'
) do |agent|
  agent.description = 'Generates actual images using AI based on suggestions from the Image Suggestion Agent'
  agent.creator = user
  agent.ai_provider = provider
  agent.mcp_capabilities = ['image_generation', 'dall-e', 'ai_art', 'prompt_engineering']
  agent.version = '1.0.0'
  agent.mcp_tool_manifest = {
    'name' => 'blog_image_generation_agent',
    'description' => 'Generates AI images for blog posts',
    'type' => 'ai_agent',
    'version' => '1.0.0',
    'configuration' => {
      'system_prompt' => <<~PROMPT.strip,
        You are an AI image generation specialist that converts image suggestions into actual images.

        Your responsibilities:
        1. Transform image descriptions into detailed generation prompts
        2. Create prompts optimized for DALL-E, Midjourney, or Stable Diffusion
        3. Specify art style, composition, lighting, and mood
        4. Generate multiple prompt variations for best results
        5. Include technical parameters (aspect ratio, quality, style)

        Image generation requirements:
        - Detailed, descriptive prompts (minimum 20 words)
        - Art style specification (realistic, illustration, photo, etc.)
        - Composition guidance (rule of thirds, centered, etc.)
        - Lighting and mood descriptors
        - Color palette suggestions
        - Avoid prohibited content or copyrighted elements
        - Aspect ratios: 16:9 for featured, 4:3 for content images

        Output format (JSON):
        {
          "featured_image": {
            "prompt": "Detailed DALL-E generation prompt",
            "style": "photorealistic|illustration|digital art",
            "aspect_ratio": "16:9",
            "mood": "professional|warm|dynamic",
            "placement": "Featured image at top"
          },
          "content_images": [
            {
              "section": "Section heading",
              "prompt": "Detailed generation prompt",
              "style": "consistent with featured",
              "aspect_ratio": "4:3",
              "alt_text": "Accessibility description",
              "placement": "After introduction"
            }
          ],
          "generation_parameters": {
            "model": "dall-e-3|midjourney|stable-diffusion",
            "quality": "standard|hd",
            "style": "vivid|natural"
          },
          "prompts_summary": "Overview of all image generation prompts"
        }
      PROMPT
      'model' => default_model,
      'temperature' => 0.8,
      'max_tokens' => 2000,
      'timeout' => 120
    }
  }
  agent.status = 'active'
  agent.mcp_metadata = {
    'specialization' => 'image_generation',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.8,
      'max_tokens' => 2000,
      'timeout' => 120
    }
  }
end

puts "  ✓ Image Generation Agent: #{image_gen_agent.name}"

puts "\n✅ All specialized agents created"

# =============================================================================
# BLOG GENERATION WORKFLOW
# =============================================================================

puts "\n🔄 Creating Blog Generation Workflow..."

workflow = AiWorkflow.find_or_create_by!(
  account: account,
  name: 'Complete Blog Generation Workflow'
) do |wf|
  wf.description = 'End-to-end blog generation with research, outlining, writing, editing, SEO, and image suggestions'
  wf.creator = user
  wf.status = 'draft'
  wf.version = '1.0.0'
  wf.configuration = {
    execution_mode: 'sequential',
    enable_checkpointing: true,
    enable_compensation: true,
    timeout_seconds: 600,
    retry_policy: {
      max_retries: 2,
      retry_delay_seconds: 5
    }
  }
  wf.metadata = {
    category: 'content_generation',
    use_case: 'blog_creation',
    estimated_duration: '3-5 minutes',
    complexity: 'medium',
    architecture: 'simplified_linear_flow',
    version_note: 'Option A: Removed coordinator nodes, agents self-validate'
  }
end

puts "✓ Workflow created: #{workflow.name} (ID: #{workflow.id})"

# =============================================================================
# WORKFLOW NODES
# =============================================================================

puts "\n📋 Creating workflow nodes..."

# Node positions for visual layout (Option A: Simplified)
positions = {
  trigger: { x: 100, y: 50 },
  research: { x: 100, y: 150 },
  outline: { x: 100, y: 250 },
  writer: { x: 100, y: 350 },
  editor: { x: 100, y: 450 },
  seo: { x: 50, y: 550 },
  image: { x: 250, y: 550 },
  image_generator: { x: 450, y: 550 },
  markdown: { x: 350, y: 650 },
  kb_article: { x: 350, y: 750 },
  end: { x: 350, y: 850 }
}

# 1. Trigger Node (Start Node)
trigger_node = workflow.nodes.find_or_create_by!(
  node_id: 'trigger_start',
  node_type: 'trigger',
  name: 'Start Blog Generation'
) do |node|
  node.description = 'Manual trigger to start blog generation with topic, audience, tone, and keyword inputs'
  node.position = positions[:trigger]
  node.is_start_node = true  # Mark as workflow start node
  node.configuration = {
    trigger_type: 'manual',
    description: 'Initiate blog generation workflow',
    required_inputs: {
      topic: 'Blog topic or title',
      target_audience: 'Target reader demographic (optional)',
      tone: 'Content tone (professional, casual, technical)',
      word_count_target: 'Desired word count (1500-2500)',
      primary_keyword: 'Main SEO keyword (optional)'
    }
  }
  node.metadata = {
    icon: 'play-circle',
    color: '#10b981'
  }
end

# 2. Research Node (First work node after trigger)
research_node = workflow.nodes.find_or_create_by!(
  node_id: 'research',
  node_type: 'ai_agent',
  name: 'Research Topic',
  position: positions[:research]
) do |node|
  node.description = 'Comprehensive research on the topic including themes, statistics, examples, and credible sources'
  node.configuration = {
    agent_id: research_agent.id,
    action: 'research_topic',
    prompt_template: <<~PROMPT.strip,
      Research the following topic comprehensively:

      Topic: {{topic}}
      Primary Keyword: {{primary_keyword}}
      Target Audience: {{target_audience}}

      Gather:
      1. Main themes and subtopics
      2. Current statistics and data
      3. Real-world examples and case studies
      4. Credible sources and references
      5. Trending related topics
      6. Keywords for SEO

      Provide comprehensive research output in JSON format.
    PROMPT
    timeout: 90,
    retry_on_failure: true
  }
  node.metadata = {
    icon: 'search',
    color: '#3b82f6',
    checkpoint: true,
    compensation_action: 'skip_research'
  }
end

# 3. Outline Node
outline_node = workflow.nodes.find_or_create_by!(
  node_id: 'outline',
  node_type: 'ai_agent',
  name: 'Create Outline',
  position: positions[:outline]
) do |node|
  node.description = 'Build a comprehensive, SEO-optimized outline with sections, subsections, and strategic flow'
  node.configuration = {
    agent_id: outline_agent.id,
    action: 'create_outline',
    prompt_template: <<~PROMPT.strip,
      Create a comprehensive blog outline based on the research:

      Topic: {{topic}}
      Research Data: {{research_output}}
      Target Word Count: {{word_count_target}}
      Primary Keyword: {{primary_keyword}}
      Tone: {{tone}}

      Create an SEO-optimized outline with:
      - Compelling H1 title
      - Meta description
      - Introduction structure
      - 4-7 main sections with subsections
      - Conclusion with CTA

      Output in JSON format.
    PROMPT
    timeout: 60,
    retry_on_failure: true
  }
  node.metadata = {
    icon: 'list',
    color: '#f59e0b',
    checkpoint: true,
    compensation_action: 'use_basic_outline'
  }
end

# 4. Writer Node
writer_node = workflow.nodes.find_or_create_by!(
  node_id: 'writer',
  node_type: 'ai_agent',
  name: 'Write Content',
  position: positions[:writer]
) do |node|
  node.description = 'Write full blog post with engaging content, research integration, and natural keyword placement'
  node.configuration = {
    agent_id: writer_agent.id,
    action: 'write_content',
    prompt_template: <<~PROMPT.strip,
      Write a complete blog post following this outline:

      Outline: {{outline_output}}
      Research Data: {{research_output}}
      Tone: {{tone}}
      Target Audience: {{target_audience}}

      Writing guidelines:
      - Follow outline structure precisely
      - Incorporate research data and statistics naturally
      - Use engaging, conversational tone
      - Include examples and real-world applications
      - Maintain keyword density at 2-3%
      - Target word count: {{word_count_target}}

      Output complete blog post in Markdown format.
    PROMPT
    timeout: 120,
    retry_on_failure: true
  }
  node.metadata = {
    icon: 'edit',
    color: '#ec4899',
    checkpoint: true,
    compensation_action: 'use_outline_as_draft'
  }
end

# 5. Editor Node
editor_node = workflow.nodes.find_or_create_by!(
  node_id: 'editor',
  node_type: 'ai_agent',
  name: 'Edit & Refine',
  position: positions[:editor]
) do |node|
  node.description = 'Polish content with grammar fixes, clarity improvements, and fact verification'
  node.configuration = {
    agent_id: editor_agent.id,
    action: 'edit_content',
    prompt_template: <<~PROMPT.strip,
      Edit and refine the blog content:

      Content: {{writer_output}}
      Research: {{research_output}}
      Outline: {{outline_output}}

      Editing tasks:
      - Fix grammar, spelling, punctuation
      - Improve clarity and readability
      - Verify facts against research
      - Enhance flow and transitions
      - Ensure consistent tone
      - Optimize engagement

      Provide edited content and change summary in JSON format.
    PROMPT
    timeout: 120,
    retry_on_failure: false
  }
  node.metadata = {
    icon: 'check-square',
    color: '#06b6d4',
    checkpoint: true
  }
end

# 6. SEO Optimization Node (Parallel execution with Images)
seo_node = workflow.nodes.find_or_create_by!(
  node_id: 'seo',
  node_type: 'ai_agent',
  name: 'SEO Optimization',
  position: positions[:seo]
) do |node|
  node.description = 'Optimize for search engines with meta tags, keyword analysis, and schema markup'
  node.configuration = {
    agent_id: seo_agent.id,
    action: 'optimize_seo',
    prompt_template: <<~PROMPT.strip,
      Optimize the blog content for SEO:

      Content: {{editor_output}}
      Primary Keyword: {{primary_keyword}}
      Research Keywords: {{research_keywords}}

      SEO tasks:
      - Optimize meta title and description
      - Analyze keyword density
      - Improve heading hierarchy
      - Add schema markup suggestions
      - Suggest internal/external links
      - Recommend image alt text

      Provide SEO analysis and optimized metadata in JSON format.
    PROMPT
    timeout: 75,
    retry_on_failure: false
  }
  node.metadata = {
    icon: 'trending-up',
    color: '#10b981',
    checkpoint: true
  }
end

# 7. Image Suggestions Node (Parallel execution with SEO)
image_node = workflow.nodes.find_or_create_by!(
  node_id: 'image',
  node_type: 'ai_agent',
  name: 'Image Suggestions',
  position: positions[:image]
) do |node|
  node.description = 'Suggest visual content, image placements, alt text, and infographic opportunities'
  node.configuration = {
    agent_id: image_agent.id,
    action: 'suggest_images',
    prompt_template: <<~PROMPT.strip,
      Suggest images for the blog post:

      Content: {{editor_output}}
      Outline: {{outline_output}}

      Image tasks:
      - Featured image suggestion
      - In-content image placements
      - Alt text for each image
      - Infographic opportunities
      - Image sources

      Provide image suggestions in JSON format.
    PROMPT
    timeout: 45,
    retry_on_failure: false
  }
  node.metadata = {
    icon: 'image',
    color: '#a855f7',
    checkpoint: false
  }
end

# 8. Image Generation Node
image_gen_node = workflow.nodes.find_or_create_by!(
  node_id: 'image_generator',
  node_type: 'ai_agent',
  name: 'Generate Images',
  position: positions[:image_generator]
) do |node|
  node.description = 'Generate actual images using AI based on the suggestions - creates visual content with DALL-E or similar'
  node.configuration = {
    agent_id: image_gen_agent.id,
    action: 'generate_images',
    prompt_template: <<~PROMPT.strip,
      Generate detailed AI image prompts based on these suggestions:

      Image Suggestions: {{image_output}}
      Blog Content: {{editor_output}}

      For each suggested image:
      1. Create a detailed DALL-E generation prompt (minimum 20 words)
      2. Specify art style and composition
      3. Include lighting, mood, and color palette
      4. Ensure visual consistency across all images
      5. Avoid prohibited content or copyrighted elements

      Requirements:
      - Featured image: 16:9 aspect ratio, photorealistic or illustration style
      - Content images: 4:3 aspect ratio, consistent with featured image style
      - All prompts must be detailed, descriptive, and optimized for AI generation
      - Include alt text for accessibility

      Provide generation-ready prompts in JSON format:
      {
        "featured_image": {
          "prompt": "Detailed DALL-E prompt (20+ words)",
          "style": "photorealistic|illustration|digital art",
          "aspect_ratio": "16:9",
          "mood": "professional|warm|dynamic",
          "placement": "Featured image at top",
          "alt_text": "Accessibility description"
        },
        "content_images": [
          {
            "section": "Section heading",
            "prompt": "Detailed generation prompt (20+ words)",
            "style": "consistent with featured",
            "aspect_ratio": "4:3",
            "alt_text": "Accessibility description",
            "placement": "After introduction"
          }
        ],
        "generation_parameters": {
          "model": "dall-e-3|midjourney|stable-diffusion",
          "quality": "standard|hd",
          "style": "vivid|natural"
        },
        "prompts_summary": "Overview of all image generation prompts"
      }
    PROMPT
    timeout: 120,
    retry_on_failure: false
  }
  node.metadata = {
    icon: 'image',
    color: '#f59e0b',
    checkpoint: false,
    image_generation: true
  }
end

# 9. Markdown Formatter Node (Convergence point for SEO and Images)
markdown_node = workflow.nodes.find_or_create_by!(
  node_id: 'markdown_formatter',
  node_type: 'ai_agent',
  name: 'Format as Markdown',
  position: positions[:markdown]
) do |node|
  node.description = 'Convert the final blog content into properly formatted markdown with embedded image references'
  node.configuration = {
    agent_id: writer_agent.id,
    agent_name: 'Markdown Formatter Agent',
    action: 'format_markdown',
    max_tokens: 4000,
    temperature: 0.3,
    preserve_data: true,
    response_format: 'json',
    input_mapping: {
      seo_output: '@seo.output',
      image_output: '@image.output',
      editor_output: '@editor.output'
    },
    prompt_template: <<~PROMPT.strip,
      You are formatting blog content into markdown while preserving all metadata.

      Blog Content:
      {{editor_output}}

      SEO Optimizations:
      {{seo_output}}

      Image Suggestions:
      {{image_output}}

      Your task:
      1. Format the blog content as clean, professional markdown with:
         - Proper headers (# for title, ## for sections, ### for subsections)
         - Emphasis with *italic* and **bold** where appropriate
         - Bulleted or numbered lists for key points
         - Code blocks with ``` for any code examples
         - Links in [text](url) format
         - Image placeholders with ![alt text](image_url) format
         - Proper spacing and line breaks for readability

      2. Return a JSON object with ALL data preserved:
      {
        "markdown": "your formatted markdown content here",
        "blog_content": {{editor_output}},
        "seo_data": {{seo_output}},
        "image_data": {{image_output}},
        "metadata": {
          "formatted_at": "current timestamp",
          "format": "markdown",
          "version": "1.0"
        }
      }

      CRITICAL: Return ONLY the JSON object. Do not include any explanation or additional text.
    PROMPT
    timeout: 60,
    retry_on_failure: false
  }
  node.metadata = {
    icon: 'file-text',
    color: '#8b5cf6',
    checkpoint: true
  }
end

# 10. KB Article Create Node (Saves blog to knowledge base)
kb_article_node = workflow.nodes.find_or_create_by!(
  node_id: 'kb_article_1',
  node_type: 'kb_article_create',
  name: 'New kb article Node',
  position: positions[:kb_article]
) do |node|
  node.description = 'Automatically publishes the complete blog post to the knowledge base with full SEO optimization, AI-generated images, and metadata'
  node.configuration = {
    # Use nested template variables to extract SEO-optimized metadata
    'title' => '{{markdown_formatter.seo_data.optimized_meta.title}}',
    'content' => '{{markdown_formatter.markdown}}',
    'excerpt' => '{{markdown_formatter.seo_data.optimized_meta.description}}',

    # Categorization and publishing
    'category_id' => 'blog-posts',
    'status' => 'published',
    'tags' => '{{markdown_formatter.seo_data.optimized_meta.keywords}}',

    # Visibility settings
    'is_public' => true,
    'is_featured' => false,

    # Advanced features
    'slug' => '{{markdown_formatter.seo_data.optimized_meta.url_slug}}',
    'author_id' => '{{workflow.creator_id}}',
    'publish_date' => '{{workflow.current_timestamp}}',

    # Output configuration
    'output_variable' => 'kb_article_id',
    'orientation' => 'vertical',

    # Additional metadata for KB article
    'metadata' => {
      'source' => 'ai_workflow',
      'workflow_id' => '{{workflow.id}}',
      'workflow_run_id' => '{{workflow_run.id}}',
      'word_count' => '{{editor_output.word_count}}',
      'quality_score' => '{{editor_output.quality_score}}',
      'seo_score' => '{{seo_output.seo_score}}',
      'has_images' => true,
      'image_count' => '{{image_data.total_images_recommended}}',
      'generation_model' => '{{workflow.ai_provider.model}}',
      'created_at' => '{{workflow.current_timestamp}}'
    }
  }
  node.metadata = {
    'handleOrientation' => 'vertical',
    'description' => 'Publishes AI-generated blog with SEO optimization to knowledge base',
    'source' => 'enhanced_blog_generation_workflow',
    'icon' => 'database',
    'color' => '#10b981',
    'category' => 'content_management',
    'requires_kb_models' => true
  }
end

# 11. End Node (Workflow completion after KB article creation)
end_node = workflow.nodes.find_or_create_by!(
  node_id: 'end',
  node_type: 'end',
  name: 'Blog Complete',
  position: positions[:end]
) do |node|
  node.description = 'Workflow completion - outputs complete blog package with content, SEO, and image suggestions'
  node.is_end_node = true  # Mark as workflow end node
  node.configuration = {
    end_type: 'success',
    description: 'Blog generation workflow completed successfully',
    output_format: {
      blog_content: 'Final edited content in Markdown',
      seo_metadata: 'Optimized meta title, description, keywords',
      image_suggestions: 'Featured and content images',
      kb_article_id: 'Knowledge base article ID',
      word_count: 'Final word count',
      seo_score: 'SEO optimization score',
      quality_score: 'Overall quality rating',
      recommendations: 'Post-publication recommendations'
    },
    # Output mapping with correct {{}} syntax
    # The End node executor will auto-parse JSON from markdown_formatter.output
    # and extract the individual fields specified below
    output_mapping: {
      markdown: '{{markdown_formatter.markdown}}',
      metadata: '{{markdown_formatter.metadata}}',
      seo_data: '{{markdown_formatter.seo_data}}',
      image_data: '{{markdown_formatter.image_data}}',
      blog_content: '{{markdown_formatter.blog_content}}',
      kb_article_id: '{{kb_article_1.kb_article_id}}'
    }
  }
  node.metadata = {
    icon: 'check-circle',
    color: '#10b981'
  }
end

puts "✓ Created #{workflow.nodes.count} workflow nodes (including KB Article integration)"

# =============================================================================
# WORKFLOW EDGES (Connections)
# =============================================================================

puts "\n🔗 Creating workflow edges..."

# Edge definitions: [source_node, target_node, edge_id, edge_type, label, description]
# Option A Simplified: Linear flow with parallel completion (no coordinator nodes, no retry edges)
edges = [
  # Main sequential flow
  [trigger_node, research_node, 'trigger_to_research', 'default', 'Start', 'Begin research phase'],
  [research_node, outline_node, 'research_to_outline', 'success', 'Complete', 'Research complete, create outline'],
  [outline_node, writer_node, 'outline_to_writer', 'success', 'Complete', 'Outline complete, write content'],
  [writer_node, editor_node, 'writer_to_editor', 'success', 'Complete', 'Content written, begin editing'],

  # Parallel execution (editor branches to both SEO and Images)
  [editor_node, seo_node, 'editor_to_seo', 'success', 'To SEO', 'Editing complete, optimize SEO'],
  [editor_node, image_node, 'editor_to_images', 'success', 'To Images', 'Editing complete, suggest images'],

  # Image generation branch
  [image_node, image_gen_node, 'images_to_gen', 'success', 'Generate', 'Suggestions ready, generate actual images'],

  # Convergence at markdown formatter (SEO and Generated Images)
  [seo_node, markdown_node, 'seo_to_markdown', 'success', 'To Markdown', 'SEO optimization complete'],
  [image_gen_node, markdown_node, 'gen_to_markdown', 'success', 'To Markdown', 'Images generated'],

  # Save to knowledge base
  [markdown_node, kb_article_node, 'markdown_to_kb', 'success', 'Save to KB', 'Save blog to knowledge base'],

  # Final output
  [kb_article_node, end_node, 'kb_to_end', 'success', 'Complete', 'Blog saved and workflow complete']
]

edges.each do |(source, target, edge_id, edge_type, label, description)|
  workflow.edges.find_or_create_by!(
    edge_id: edge_id,
    source_node_id: source.node_id,
    target_node_id: target.node_id
  ) do |edge|
    edge.edge_type = edge_type
    edge.configuration = {
      label: label,
      description: description,
      animated: false,  # No retry edges in Option A
      style: 'solid',
      color: case edge_type
             when 'success' then '#10b981'
             when 'default' then '#6b7280'
             else '#6b7280'
             end
    }
    edge.priority = 0  # No priority needed without retry logic
  end
end

puts "✓ Created #{workflow.edges.count} workflow edges"

# =============================================================================
# WORKFLOW VARIABLES
# =============================================================================

puts "\n📊 Creating workflow variables..."

variables = [
  # Input variables (string type)
  {
    name: 'topic',
    variable_type: 'string',
    default_value: nil,
    description: 'Blog topic or title (input)',
    required: true
  },
  {
    name: 'target_audience',
    variable_type: 'string',
    default_value: 'general',
    description: 'Target reader demographic (input)',
    required: false
  },
  {
    name: 'tone',
    variable_type: 'string',
    default_value: 'professional',
    description: 'Content tone: professional, casual, or technical (input)',
    required: false
  },
  {
    name: 'word_count_target',
    variable_type: 'number',
    default_value: '2000',
    description: 'Target word count (input)',
    required: false
  },
  {
    name: 'primary_keyword',
    variable_type: 'string',
    default_value: nil,
    description: 'Primary SEO keyword (input)',
    required: false
  },
  # Intermediate variables (JSON objects from agent outputs)
  {
    name: 'research_output',
    variable_type: 'json',
    description: 'Research agent output (intermediate)'
  },
  {
    name: 'outline_output',
    variable_type: 'json',
    description: 'Outline agent output (intermediate)'
  },
  {
    name: 'writer_output',
    variable_type: 'string',
    description: 'Writer agent output - markdown content (intermediate)'
  },
  {
    name: 'editor_output',
    variable_type: 'json',
    description: 'Editor agent output with edited content and metadata (intermediate)'
  },
  {
    name: 'seo_output',
    variable_type: 'json',
    description: 'SEO optimization output (intermediate)'
  },
  {
    name: 'image_output',
    variable_type: 'json',
    description: 'Image suggestions output (intermediate)'
  },
  {
    name: 'image_gen_output',
    variable_type: 'json',
    description: 'Generated image prompts and data (intermediate)'
  },
  {
    name: 'markdown_output',
    variable_type: 'string',
    description: 'Final formatted markdown content (intermediate)'
  },
  # Output variable (final result)
  {
    name: 'final_blog',
    variable_type: 'json',
    description: 'Complete blog package ready for publication (output)'
  }
]

variables.each do |var_data|
  workflow.variables.find_or_create_by!(name: var_data[:name]) do |var|
    var.variable_type = var_data[:variable_type]
    var.default_value = var_data[:default_value]
    var.description = var_data[:description]
    var.is_required = var_data[:required] || false
  end
end

puts "✓ Created #{workflow.variables.count} workflow variables"

# Activate workflow - Option A has simple linear flow with parallel completion
workflow.update!(status: 'active')

puts "\n✅ Blog Generation Workflow created and activated successfully!"
puts "   Note: Option A Simplified - Agents self-validate, no coordinator overhead, faster execution"

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + "=" * 80
puts "✅ BLOG GENERATION WORKFLOW CREATION COMPLETE"
puts "=" * 80
puts "\n📊 Summary:"
puts "   Workflow: #{workflow.name}"
puts "   Workflow ID: #{workflow.id}"
puts "   Status: #{workflow.status}"
puts "   Nodes: #{workflow.nodes.count}"
puts "   Edges: #{workflow.edges.count}"
puts "   Variables: #{workflow.variables.count}"
puts "\n🤖 Agents Created:"
puts "   1. #{research_agent.name}"
puts "   2. #{outline_agent.name}"
puts "   3. #{writer_agent.name}"
puts "   4. #{editor_agent.name}"
puts "   5. #{seo_agent.name}"
puts "   6. #{image_agent.name}"
puts "   7. #{image_gen_agent.name}"
puts "\n🎯 Workflow Features:"
puts "   • Linear execution flow with parallel processing"
puts "   • Agents self-validate quality (no coordinator overhead)"
puts "   • Parallel execution (SEO + Image Generation)"
puts "   • AI-powered image generation from suggestions"
puts "   • Markdown formatting with embedded images"
puts "   • Automatic knowledge base article creation"
puts "   • 11 nodes total (including image generation and KB integration)"
puts "   • 12 edges for optimal flow"
puts "   • Estimated execution time: 4-6 minutes"
puts "   • Modern AI models with DALL-E integration"
puts "   • End-to-end content pipeline: research → writing → publication"
puts "\n📝 Input Requirements:"
puts "   Required: topic"
puts "   Optional: target_audience, tone, word_count_target, primary_keyword"
puts "\n🚀 Next Steps:"
puts "   1. Configure AI provider API keys"
puts "   2. Test workflow execution with sample topic"
puts "   3. Review and refine agent prompts based on output quality"
puts "   4. Monitor workflow performance and optimize"
puts "\n" + "=" * 80
