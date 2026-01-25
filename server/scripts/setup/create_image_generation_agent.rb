# frozen_string_literal: true

# Create Blog Image Generation Agent
# This agent generates actual images using AI (DALL-E, etc.) based on suggestions

puts "\n" + "=" * 80
puts "🖼️  CREATING BLOG IMAGE GENERATION AGENT"
puts "=" * 80
puts ""

# Get admin account
account = Account.find_by(subdomain: 'admin')
unless account
  puts "❌ Error: Admin account not found"
  exit 1
end

user = account.users.find_by(email: 'admin@powernode.org')
unless user
  puts "❌ Error: Admin user not found"
  exit 1
end

# Get AI provider (prefer Claude/OpenAI for image generation)
provider = account.ai_providers.find_by(provider_type: 'anthropic') ||
          account.ai_providers.find_by(provider_type: 'openai') ||
          account.ai_providers.first

unless provider
  puts "❌ Error: No AI provider found"
  exit 1
end

puts "✓ Using AI Provider: #{provider.name} (#{provider.provider_type})"

# Determine model based on provider
default_model = case provider.provider_type
when 'anthropic'
                  'claude-sonnet-4-5-20250514'
when 'openai'
                  'gpt-4o'
when 'grok', 'custom'
                  'grok-beta'
when 'ollama'
                  'llama3.3:latest'
else
                  provider.supported_models.first['id']
end

puts "✓ Using model: #{default_model}"
puts ""

# Create or update the agent
image_gen_agent = AiAgent.find_or_initialize_by(
  account: account,
  name: 'Blog Image Generation Agent'
)

image_gen_agent.assign_attributes(
  agent_type: 'image_generator',
  description: 'Generates actual images using AI based on suggestions from the Image Suggestion Agent',
  creator: user,
  ai_provider: provider,
  mcp_capabilities: [ 'image_generation', 'dall-e', 'ai_art', 'prompt_engineering' ],
  version: '1.0.0',
  mcp_tool_manifest: {
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
  },
  status: 'active',
  mcp_metadata: {
    'specialization' => 'image_generation',
    'model_config' => {
      'model' => default_model,
      'temperature' => 0.8,
      'max_tokens' => 2000,
      'timeout' => 120
    }
  }
)

if image_gen_agent.save
  puts "✅ Created/Updated: #{image_gen_agent.name}"
  puts "   Agent ID: #{image_gen_agent.id}"
  puts "   Agent Type: #{image_gen_agent.agent_type}"
  puts "   MCP Capabilities: #{image_gen_agent.mcp_capabilities.join(', ')}"
  puts ""

  # Update the Generate Images node to use this agent
  workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')
  if workflow
    image_gen_node = workflow.ai_workflow_nodes.find_by(node_id: 'image_generator')
    if image_gen_node
      old_agent_id = image_gen_node.configuration['agent_id']
      image_gen_node.configuration['agent_id'] = image_gen_agent.id
      image_gen_node.save!

      puts "✅ Updated Generate Images node"
      puts "   Old Agent ID: #{old_agent_id}"
      puts "   New Agent ID: #{image_gen_agent.id}"
      puts ""
    end
  end

  puts "=" * 80
  puts "✅ BLOG IMAGE GENERATION AGENT READY"
  puts "=" * 80
else
  puts "❌ Failed to create agent:"
  image_gen_agent.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end
