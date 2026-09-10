# frozen_string_literal: true

# Re-sync an AI provider's supported_models FROM THE PROVIDER, never from a
# list written into this file.
#
#   bin/rails runner scripts/migrations/fix_provider_models.rb <provider-id-or-slug>
#
# This script used to overwrite `supported_models` with a hand-written array
# of model ids. Every id in that array has since been retired, so running it
# would have pinned a provider to models its API rejects — and it could not
# run anyway: it looked the provider up through a model class that no longer
# exists. (E3 review, campaign 01a08c9b.)
#
# The catalog now comes from the one place that knows it:
# Ai::ProviderManagementService.sync_provider_models, the same seam the
# "Sync models" button calls (Api::V1::Ai::ProviderSyncController). It reads
# the provider's own models endpoint with the provider's active credential and
# falls back to the per-type catalog in Ai::Providers::DefaultConfig when the
# API is unreachable. This script never sees the credential and prints no part
# of it.

ref = ARGV.first.to_s.strip
abort "usage: bin/rails runner #{__FILE__} <provider-id-or-slug>" if ref.empty?

provider = Ai::Provider.find_by(id: ref) || Ai::Provider.find_by(slug: ref)
abort "no Ai::Provider with id or slug #{ref.inspect}" unless provider

before = Array(provider.supported_models).size
puts "Provider: #{provider.name} (#{provider.provider_type}) — #{before} models before sync"

synced = Ai::ProviderManagementService.sync_provider_models(provider, force_refresh: true)
provider.reload

if synced
  puts "Synced: #{Array(provider.supported_models).size} models; default_model now #{provider.default_model.inspect}"
else
  # A deferred sync (no active credential yet) returns false without raising.
  abort "Sync did not complete for #{provider.name}. Check that it has an active credential, then retry."
end
