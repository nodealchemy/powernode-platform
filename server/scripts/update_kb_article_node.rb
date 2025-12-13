# frozen_string_literal: true

# Update KB Article Node Configuration in Complete Blog Generation Workflow

puts "\n" + "=" * 80
puts "📝 UPDATING KB ARTICLE NODE CONFIGURATION"
puts "=" * 80

# Find the workflow
workflow = AiWorkflow.find_by(name: 'Complete Blog Generation Workflow')

unless workflow
  puts "❌ Error: 'Complete Blog Generation Workflow' not found."
  exit 1
end

puts "✓ Found workflow: #{workflow.name} (ID: #{workflow.id})"

# Find the KB Article node
kb_node = workflow.nodes.find_by(node_type: 'kb_article_create')

unless kb_node
  puts "❌ Error: KB Article Create node not found in workflow."
  puts "Available nodes: #{workflow.nodes.pluck(:node_type, :name).inspect}"
  exit 1
end

puts "✓ Found KB Article node: #{kb_node.name} (ID: #{kb_node.node_id})"
puts "  Current configuration: #{kb_node.configuration.present? ? 'Set' : 'NOT SET'}"

# Update the node configuration
kb_node.update!(
  name: 'New kb article Node',
  description: 'Automatically publishes the complete blog post to the knowledge base with full SEO optimization, AI-generated images, and metadata',
  configuration: {
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
  },
  metadata: {
    'handleOrientation' => 'vertical',
    'description' => 'Publishes AI-generated blog with SEO optimization to knowledge base',
    'source' => 'enhanced_blog_generation_workflow',
    'icon' => 'database',
    'color' => '#10b981',
    'category' => 'content_management',
    'requires_kb_models' => true
  }
)

puts "\n✅ KB Article node updated successfully!"
puts "\n📊 Updated Configuration:"
puts "   Name: #{kb_node.name}"
puts "   Description: #{kb_node.description[0..80]}..."
puts "   Configuration fields: #{kb_node.configuration.keys.count}"
puts "   Metadata fields: #{kb_node.metadata.keys.count}"
puts "\n🎯 Configuration Preview:"
kb_node.configuration.each do |key, value|
  next if key == 'metadata'
  display_value = value.is_a?(String) && value.length > 50 ? "#{value[0..50]}..." : value
  puts "   #{key}: #{display_value}"
end
puts "\n" + "=" * 80
puts "✅ UPDATE COMPLETE"
puts "=" * 80
