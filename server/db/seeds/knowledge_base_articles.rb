# frozen_string_literal: true

# Knowledge Base Articles Orchestrator
# This file creates categories, tags, and loads all article files
# Run with: rails db:seed (includes this file automatically)

puts "\n🔄 Seeding Knowledge Base Articles..."

# =============================================================================
# CATEGORIES (13 total)
# =============================================================================

puts "\n📁 Creating Knowledge Base categories..."

categories_data = [
  { name: "Getting Started", slug: "getting-started", description: "Essential guides for new users", sort_order: 1 },
  { name: "Account Management", slug: "account-management", description: "Profile settings and team management", sort_order: 2 },
  { name: "Billing & Subscriptions", slug: "billing-subscriptions", description: "Subscription plans, payments, and invoicing", sort_order: 3 },
  { name: "Business Analytics", slug: "business-analytics", description: "Metrics, KPIs, and reporting", sort_order: 4 },
  { name: "AI Orchestration", slug: "ai-orchestration", description: "AI providers, agents, workflows, and MCP", sort_order: 5 },
  { name: "Content Management", slug: "content-management", description: "Pages, files, and knowledge base", sort_order: 6 },
  { name: "DevOps", slug: "devops", description: "Git providers, CI/CD pipelines, and webhooks", sort_order: 7 },
  { name: "Supply Chain Security", slug: "supply-chain-security", description: "SBOMs, attestations, and vendor risk", sort_order: 8 },
  { name: "Marketplace", slug: "marketplace", description: "Browse and publish marketplace items", sort_order: 9 },
  { name: "System Administration", slug: "system-administration", description: "System services and audit logs", sort_order: 10 },
  { name: "Security & Compliance", slug: "security-compliance", description: "Security settings and data protection", sort_order: 11 },
  { name: "API & Integrations", slug: "api-integrations", description: "REST API and webhook integration", sort_order: 12 },
  { name: "Troubleshooting", slug: "troubleshooting", description: "Common issues and support contact", sort_order: 13 }
]

categories_data.each do |cat_data|
  category = KnowledgeBase::Category.find_or_initialize_by(slug: cat_data[:slug])
  category.assign_attributes(
    name: cat_data[:name],
    description: cat_data[:description],
    sort_order: cat_data[:sort_order],
    is_public: true
  )
  category.save!
  puts "  ✅ Category: #{category.name}"
end

puts "  📊 Total categories: #{KnowledgeBase::Category.count}"

# =============================================================================
# COMMON TAGS
# =============================================================================

puts "\n🏷️  Creating common tags..."

common_tags = %w[
  getting-started
  tutorial
  guide
  billing
  payments
  subscription
  api
  webhook
  integration
  security
  compliance
  privacy
  devops
  cicd
  git
  ai
  agents
  workflows
  supply-chain
  sbom
  vendor
  troubleshooting
  faq
]

common_tags.each do |tag_name|
  KnowledgeBase::Tag.find_or_create_by!(slug: tag_name) do |tag|
    tag.name = tag_name.titleize.gsub("-", " ")
  end
end

puts "  ✅ Created #{common_tags.count} common tags"

# =============================================================================
# LOAD ARTICLE FILES
# =============================================================================

puts "\n📄 Loading article files..."

# Define article files in priority order
KB_ARTICLE_FILES = %w[
  devops_articles
  supply_chain_articles
  ai_orchestration_articles
  getting_started_articles
  billing_articles
  business_analytics_articles
  business_articles
  account_management_articles
  content_management_articles
  marketplace_articles
  system_admin_articles
  security_compliance_articles
  api_integrations_articles
  troubleshooting_articles
].freeze

KB_ARTICLE_FILES.each do |file|
  file_path = Rails.root.join('db', 'seeds', 'kb', "#{file}.rb")
  if File.exist?(file_path)
    load file_path
  else
    puts "  ⚠️  File not found: #{file}.rb"
  end
end

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n📊 Knowledge Base Articles Summary:"
puts "   Categories: #{KnowledgeBase::Category.count}"
puts "   Total Articles: #{KnowledgeBase::Article.count}"
puts "   Featured Articles: #{KnowledgeBase::Article.where(is_featured: true).count}"
puts "   Published Articles: #{KnowledgeBase::Article.where(status: 'published').count}"

# Article count by category
puts "\n   Articles by Category:"
KnowledgeBase::Category.order(:sort_order).each do |cat|
  count = KnowledgeBase::Article.where(category: cat).count
  puts "   - #{cat.name}: #{count}"
end

puts "\n✅ Knowledge Base seeding completed successfully!"
