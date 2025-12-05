#!/usr/bin/env ruby
# frozen_string_literal: true

# This script merges duplicate Anthropic providers into a single canonical provider

puts '═══════════════════════════════════════════════════════'
puts 'MERGE DUPLICATE ANTHROPIC PROVIDERS'
puts '═══════════════════════════════════════════════════════'
puts ''

# Find both providers
provider_old = AiProvider.find_by(slug: 'anthropic')  # Claude (Anthropic) - older
provider_new = AiProvider.find_by(slug: 'anthropic-claude')  # Anthropic Claude - newer

if provider_old.nil? || provider_new.nil?
  puts '❌ Could not find both Anthropic providers'
  exit 1
end

puts "Found duplicate providers:"
puts "  1. #{provider_old.name} (slug: #{provider_old.slug}) - #{AiAgent.where(ai_provider_id: provider_old.id).count} agents"
puts "  2. #{provider_new.name} (slug: #{provider_new.slug}) - #{AiAgent.where(ai_provider_id: provider_new.id).count} agents"
puts ''

# Determine which provider to keep (newer one has more agents)
keep_provider = provider_new
remove_provider = provider_old

puts "Decision: Keep '#{keep_provider.name}' (more agents), remove '#{remove_provider.name}'"
puts ''

# Step 1: Migrate all agents from old provider to new provider
agents_to_migrate = AiAgent.where(ai_provider_id: remove_provider.id)

puts "Step 1: Migrating #{agents_to_migrate.count} agent(s) to '#{keep_provider.name}'..."

agents_to_migrate.each do |agent|
  agent.update!(ai_provider_id: keep_provider.id)
  puts "  ✅ Migrated: #{agent.name}"
end

puts ''

# Step 2: Handle provider credentials
puts "Step 2: Handling provider credentials..."

# Check if old provider has credentials
old_credentials = remove_provider.ai_provider_credentials rescue []
puts "  Old provider credentials: #{old_credentials.count}"

if old_credentials.any?
  # Check if keep provider already has credential for this account
  old_credentials.each do |old_cred|
    existing_cred = keep_provider.ai_provider_credentials.find_by(account_id: old_cred.account_id) rescue nil

    if existing_cred
      puts "  ⚠️  Target provider already has credential for account #{old_cred.account_id}, deleting duplicate..."
      old_cred.delete  # Use delete instead of destroy to skip callbacks
    else
      puts "  ✅ Migrating credential for account #{old_cred.account_id}..."
      old_cred.update!(ai_provider_id: keep_provider.id)
    end
  end

  # Reload provider to ensure association is updated
  remove_provider.reload
else
  puts "  ✅ No credentials to migrate"
end

puts ''

# Step 3: Remove the duplicate provider (now that credentials are handled)
puts "Step 3: Removing duplicate provider '#{remove_provider.name}'..."

# First verify no agents remain
remaining_agents = AiAgent.where(ai_provider_id: remove_provider.id).count

if remaining_agents > 0
  puts "  ❌ ERROR: Provider still has #{remaining_agents} agents. Cannot delete."
  exit 1
end

# Verify no credentials remain
remaining_creds = remove_provider.ai_provider_credentials.count rescue 0

if remaining_creds > 0
  puts "  ❌ ERROR: Provider still has #{remaining_creds} credentials. Cannot delete."
  exit 1
end

remove_provider.destroy!
puts "  ✅ Removed duplicate provider"
puts ''

# Step 4: Update the canonical provider to have the better slug
puts "Step 4: Updating canonical provider slug from '#{keep_provider.slug}' to 'anthropic'..."

keep_provider.update!(
  slug: 'anthropic',
  name: 'Anthropic Claude'
)

puts "  ✅ Updated slug to 'anthropic'"
puts ''

# Step 5: Verify final state
puts '═══════════════════════════════════════════════════════'
puts 'FINAL STATE'
puts '═══════════════════════════════════════════════════════'
puts ''

anthropic_providers = AiProvider.where(provider_type: 'anthropic')

puts "Anthropic Providers: #{anthropic_providers.count}"
anthropic_providers.each do |provider|
  agent_count = AiAgent.where(ai_provider_id: provider.id).count
  puts "  📍 #{provider.name}"
  puts "     - Slug: #{provider.slug}"
  puts "     - Agents: #{agent_count}"

  if agent_count > 0
    agents = AiAgent.where(ai_provider_id: provider.id).pluck(:name)
    agents.each { |name| puts "       • #{name}" }
  end
  puts ''
end

puts '✅ MERGE COMPLETE'
puts ''
puts 'Summary:'
puts "  - Canonical Provider: Anthropic Claude (slug: anthropic)"
puts "  - Total Agents: #{AiAgent.where(ai_provider_id: keep_provider.id).count}"
puts "  - Duplicate Removed: Claude (Anthropic)"
