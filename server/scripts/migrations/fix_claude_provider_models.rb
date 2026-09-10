# frozen_string_literal: true

# Re-sync EVERY Anthropic provider's supported_models from Anthropic's own
# models endpoint, never from a list written into this file.
#
#   bin/rails runner scripts/migrations/fix_claude_provider_models.rb
#
# This script used to overwrite one provider's `supported_models` with four
# hand-picked model ids and announce the first as the new default. All four
# are retired, so running it would have pinned the provider to models the API
# 404s — and it could not run anyway: it looked the provider up through a
# model class that no longer exists. (E3 review, campaign 01a08c9b.)
#
# Same seam as scripts/migrations/fix_provider_models.rb, scoped to one
# provider type: Ai::ProviderManagementService.sync_provider_models, which
# reads the models endpoint with the provider's active credential and falls
# back to the per-type catalog in Ai::Providers::DefaultConfig. This script
# never sees the credential and prints no part of it.

providers = Ai::Provider.where(provider_type: "anthropic").order(:name).to_a
abort "no Anthropic providers found" if providers.empty?

puts "This will re-sync #{providers.size} Anthropic provider(s) from the provider's own catalog."

failures = providers.reject do |provider|
  synced = Ai::ProviderManagementService.sync_provider_models(provider, force_refresh: true)
  provider.reload
  puts format("  %-40s %s", provider.name,
              synced ? "#{Array(provider.supported_models).size} models, default #{provider.default_model.inspect}" : "NOT synced")
  synced
end

# A deferred sync (no active credential) returns false without raising; say so
# rather than report success for a provider whose catalog did not change.
abort "#{failures.size} provider(s) did not sync — check their credentials and retry." if failures.any?
