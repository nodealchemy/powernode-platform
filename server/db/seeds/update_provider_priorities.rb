# frozen_string_literal: true

# Data migration: Update AI provider priorities and models
# Run with: cd server && rails runner db/seeds/update_provider_priorities.rb
#
# Priority order: gpt-4.1-mini (1) → Grok (2) → Haiku (3) → Ollama (4)
# Also modernizes Grok models (beta → grok-3 family) and adds new OpenAI models

puts "\n🔄 Updating AI Provider Priorities and Models..."

admin_account = Account.find_by(name: "Powernode Admin")

unless admin_account
  puts "❌ Admin account not found. Skipping."
  exit
end

changes_made = 0

# =============================================================================
# 1. OPENAI — priority 1, default_model → gpt-4.1-mini, add new models
# =============================================================================

openai = admin_account.ai_providers.find_by(name: "OpenAI")
if openai
  updates = {}

  updates[:priority_order] = 1 unless openai.priority_order == 1

  current_default = openai.configuration_schema&.dig("default_model")
  if current_default != "gpt-4.1-mini"
    schema = (openai.configuration_schema || {}).merge("default_model" => "gpt-4.1-mini")
    updates[:configuration_schema] = schema
  end

  # Add new models if missing
  existing_ids = openai.supported_models.map { |m| m["id"] }
  new_models = []

  unless existing_ids.include?("gpt-4.1")
    new_models << {
      "name" => "gpt-4.1", "id" => "gpt-4.1", "display_name" => "GPT-4.1",
      "context_length" => 1_047_576, "max_output_tokens" => 32_768,
      "cost_per_1k_tokens" => { "input" => 0.002, "output" => 0.008 },
      "capabilities" => %w[text vision function_calling structured_output],
      "recommended_for" => %w[coding instruction_following long_context agentic_tasks]
    }
  end

  unless existing_ids.include?("gpt-4.1-mini")
    new_models << {
      "name" => "gpt-4.1-mini", "id" => "gpt-4.1-mini", "display_name" => "GPT-4.1 Mini",
      "context_length" => 1_047_576, "max_output_tokens" => 32_768,
      "cost_per_1k_tokens" => { "input" => 0.0004, "output" => 0.0016 },
      "capabilities" => %w[text vision function_calling structured_output],
      "recommended_for" => %w[cost_effective high_volume general_purpose agentic_tasks]
    }
  end

  unless existing_ids.include?("gpt-4.1-nano")
    new_models << {
      "name" => "gpt-4.1-nano", "id" => "gpt-4.1-nano", "display_name" => "GPT-4.1 Nano",
      "context_length" => 1_047_576, "max_output_tokens" => 32_768,
      "cost_per_1k_tokens" => { "input" => 0.0001, "output" => 0.0004 },
      "capabilities" => %w[text function_calling structured_output],
      "recommended_for" => %w[classification extraction routing ultra_low_cost]
    }
  end

  unless existing_ids.include?("o3")
    new_models << {
      "name" => "o3", "id" => "o3", "display_name" => "o3",
      "context_length" => 200_000, "max_output_tokens" => 100_000,
      "cost_per_1k_tokens" => { "input" => 0.002, "output" => 0.008 },
      "capabilities" => %w[advanced_reasoning complex_problem_solving function_calling],
      "recommended_for" => %w[math coding scientific_reasoning complex_analysis]
    }
  end

  unless existing_ids.include?("o4-mini")
    new_models << {
      "name" => "o4-mini", "id" => "o4-mini", "display_name" => "o4 Mini",
      "context_length" => 200_000, "max_output_tokens" => 100_000,
      "cost_per_1k_tokens" => { "input" => 0.0011, "output" => 0.0044 },
      "capabilities" => %w[reasoning coding function_calling],
      "recommended_for" => %w[coding_tasks stem_reasoning faster_reasoning]
    }
  end

  if new_models.any?
    updates[:supported_models] = new_models + openai.supported_models
  end

  if updates.any?
    openai.update!(updates)
    changes_made += 1
    puts "✅ OpenAI: priority=1, default=gpt-4.1-mini, added #{new_models.length} new models"
  else
    puts "⏭️  OpenAI: already up to date"
  end
else
  puts "⚠️  OpenAI provider not found"
end

# =============================================================================
# 2. GROK (X.AI) — priority 2, provider_type → grok, modernize models
# =============================================================================

grok = admin_account.ai_providers.find_by(name: "Grok (X.AI)")
if grok
  grok_models = [
    {
      "name" => "grok-3", "id" => "grok-3", "display_name" => "Grok 3",
      "context_length" => 131_072, "max_output_tokens" => 16_384,
      "cost_per_1k_tokens" => { "input" => 0.003, "output" => 0.015 },
      "capabilities" => %w[text reasoning conversation function_calling],
      "recommended_for" => %w[complex_reasoning analysis general_purpose]
    },
    {
      "name" => "grok-3-mini", "id" => "grok-3-mini", "display_name" => "Grok 3 Mini",
      "context_length" => 131_072, "max_output_tokens" => 16_384,
      "cost_per_1k_tokens" => { "input" => 0.0003, "output" => 0.0005 },
      "capabilities" => %w[text reasoning conversation function_calling],
      "recommended_for" => %w[cost_effective high_volume quick_tasks]
    },
    {
      "name" => "grok-3-fast", "id" => "grok-3-fast", "display_name" => "Grok 3 Fast",
      "context_length" => 131_072, "max_output_tokens" => 16_384,
      "cost_per_1k_tokens" => { "input" => 0.005, "output" => 0.025 },
      "capabilities" => %w[text reasoning conversation function_calling],
      "recommended_for" => %w[low_latency real_time fast_responses]
    },
    {
      "name" => "grok-3-mini-fast", "id" => "grok-3-mini-fast", "display_name" => "Grok 3 Mini Fast",
      "context_length" => 131_072, "max_output_tokens" => 16_384,
      "cost_per_1k_tokens" => { "input" => 0.0006, "output" => 0.004 },
      "capabilities" => %w[text reasoning conversation function_calling],
      "recommended_for" => %w[low_latency cost_effective simple_tasks]
    },
    {
      "name" => "grok-2", "id" => "grok-2", "display_name" => "Grok 2",
      "context_length" => 131_072, "max_output_tokens" => 8_192,
      "cost_per_1k_tokens" => { "input" => 0.002, "output" => 0.01 },
      "capabilities" => %w[text conversation function_calling],
      "recommended_for" => %w[general_purpose legacy_workflows]
    }
  ]

  schema = (grok.configuration_schema || {}).merge("default_model" => "grok-3-mini")
  meta = (grok.metadata || {}).tap { |m| m.delete("is_default") }

  grok.update!(
    provider_type: "grok",
    priority_order: 2,
    supported_models: grok_models,
    configuration_schema: schema,
    supports_vision: false,
    metadata: meta
  )
  changes_made += 1
  puts "✅ Grok: priority=2, provider_type=grok, default=grok-3-mini, #{grok_models.length} models"
else
  puts "⚠️  Grok (X.AI) provider not found"
end

# =============================================================================
# 3. CLAUDE (ANTHROPIC) — priority 3, default_model → haiku, clear is_default
# =============================================================================

claude = admin_account.ai_providers.find_by(name: "Claude AI (Anthropic)")
if claude
  updates = {}

  updates[:priority_order] = 3 unless claude.priority_order == 3

  current_default = claude.configuration_schema&.dig("default_model")
  if current_default != "claude-haiku-4-5-20251001"
    schema = (claude.configuration_schema || {}).merge("default_model" => "claude-haiku-4-5-20251001")
    updates[:configuration_schema] = schema
  end

  if claude.metadata&.dig("is_default")
    meta = claude.metadata.dup
    meta.delete("is_default")
    updates[:metadata] = meta
  end

  if updates.any?
    claude.update!(updates)
    changes_made += 1
    puts "✅ Claude: priority=3, default=claude-haiku-4-5-20251001, cleared is_default"
  else
    puts "⏭️  Claude: already up to date"
  end
else
  puts "⚠️  Claude AI (Anthropic) provider not found"
end

# =============================================================================
# 4. OLLAMA — priority 4
# =============================================================================

ollama = admin_account.ai_providers.find_by(name: "Ollama")
if ollama
  if ollama.priority_order != 4
    ollama.update!(priority_order: 4)
    changes_made += 1
    puts "✅ Ollama: priority=4"
  else
    puts "⏭️  Ollama: already up to date"
  end
else
  puts "⚠️  Ollama provider not found"
end

# =============================================================================
# SUMMARY
# =============================================================================

puts "\n" + "=" * 60
if changes_made > 0
  puts "✅ Updated #{changes_made} provider(s)"
else
  puts "⏭️  All providers already up to date"
end

puts "\n📊 Current priority order:"
Ai::Provider.where(account: admin_account).order(:priority_order).each do |p|
  default_model = p.configuration_schema&.dig("default_model") || "n/a"
  puts "   #{p.priority_order}. #{p.name} (#{p.provider_type}) — default: #{default_model}"
end
puts "=" * 60
