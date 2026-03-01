# frozen_string_literal: true

# Add descriptions to all existing workflow nodes
# This updates nodes in the database that were created before descriptions were added

puts "\n" + "=" * 80
puts "📝 ADDING DESCRIPTIONS TO WORKFLOW NODES"
puts "=" * 80

# Description mappings based on node names and types
DESCRIPTIONS = {
  # Start/Trigger nodes
  'Start' => 'Workflow entry point - begins execution',
  'Start Blog Generation' => 'Manual trigger to start blog generation with topic, audience, tone, and keyword inputs',
  'Blog Topic Input' => 'Workflow entry point - accepts topic, audience, keywords, and preferences',

  # AI Agent nodes
  'Research Topic' => 'Comprehensive research on the topic including themes, statistics, examples, and credible sources',
  'Topic Research' => 'Gather comprehensive research on the topic, including key themes, statistics, and sources',
  'Create Outline' => 'Build a comprehensive, SEO-optimized outline with sections, subsections, and strategic flow',
  'Write Content' => 'Write full blog post with engaging content, research integration, and natural keyword placement',
  'Write Blog Post' => 'Write comprehensive, engaging, and SEO-friendly blog content based on research',
  'Edit & Refine' => 'Polish content with grammar fixes, clarity improvements, and fact verification',
  'Edit & Polish' => 'Edit and refine blog content for grammar, clarity, readability, and proper structure',
  'SEO Optimization' => 'Optimize for search engines with meta tags, keyword analysis, and schema markup',
  'Image Suggestions' => 'Suggest visual content, image placements, alt text, and infographic opportunities',
  'Fact Check Research' => 'Verify facts, statistics, and claims to ensure content accuracy and credibility',
  'Content Revision' => 'Revise content to improve quality and SEO scores when quality gate fails',
  'Format as Markdown' => 'Convert the final blog content into properly formatted markdown',

  # Transform nodes
  'Echo Text' => 'Simple text transformation for testing workflow functionality',
  'Merge Content & Facts' => 'Combine written content with fact-checking results for editing phase',

  # Condition nodes
  'Quality Check' => 'Evaluate content quality and SEO scores - pass to output or revision',

  # End nodes
  'End' => 'Workflow completion - outputs final results',
  'Blog Complete' => 'Workflow completion - outputs complete blog package with content, SEO, and image suggestions',
  'Final Blog Post' => 'Workflow completion - outputs publication-ready blog with all metadata and metrics'
}.freeze

# Update nodes
updated_count = 0
skipped_count = 0
not_found_count = 0

AiWorkflowNode.find_each do |node|
  if node.description.present?
    puts "⏭️  Skipping #{node.name} - already has description"
    skipped_count += 1
    next
  end

  description = DESCRIPTIONS[node.name]

  if description
    node.update!(description: description)
    puts "✅ Updated: #{node.name} (#{node.node_type})"
    updated_count += 1
  else
    puts "⚠️  No description mapping for: #{node.name} (#{node.node_type})"
    not_found_count += 1
  end
end

puts "\n" + "=" * 80
puts "✅ DESCRIPTION UPDATE COMPLETE"
puts "=" * 80
puts "\n📊 Summary:"
puts "   Updated: #{updated_count} nodes"
puts "   Skipped (already had description): #{skipped_count} nodes"
puts "   No mapping found: #{not_found_count} nodes"
puts "   Total nodes: #{AiWorkflowNode.count}"
puts "\n" + "=" * 80
