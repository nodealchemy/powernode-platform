# frozen_string_literal: true

# Fix Generate Images node prompt template
# Add proper prompt template with variable substitution

puts "\n" + "=" * 80
puts "🔧 FIXING GENERATE IMAGES NODE PROMPT TEMPLATE"
puts "=" * 80
puts ""

workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')
unless workflow
  puts "❌ Workflow not found"
  exit 1
end

image_gen_node = workflow.ai_workflow_nodes.find_by(node_id: 'image_generator')
unless image_gen_node
  puts "❌ Image generator node not found"
  exit 1
end

puts "✓ Found node: #{image_gen_node.name}"
puts ""

# Update configuration with proper prompt template
old_config = image_gen_node.configuration.dup

image_gen_node.configuration.merge!({
  'prompt_template' => <<~PROMPT.strip,
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
  'action' => 'generate_images'
})

# Remove old 'prompt' field if it exists
image_gen_node.configuration.delete('prompt')

if image_gen_node.save
  puts "✅ Updated Generate Images node configuration"
  puts ""
  puts "Configuration changes:"
  puts "  ✓ Added: prompt_template (#{image_gen_node.configuration['prompt_template'].length} chars)"
  puts "  ✓ Added: action = 'generate_images'"
  puts "  ✓ Removed: old 'prompt' field" if old_config.key?('prompt')
  puts ""
  puts "Template includes variable substitutions:"
  puts "  - {{image_output}} - from Image Suggestions node"
  puts "  - {{editor_output}} - from Edit & Refine node"
  puts ""
  puts "=" * 80
  puts "✅ PROMPT TEMPLATE FIX COMPLETE"
  puts "=" * 80
else
  puts "❌ Failed to save node:"
  image_gen_node.errors.full_messages.each do |error|
    puts "   - #{error}"
  end
end
