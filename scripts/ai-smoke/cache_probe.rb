# frozen_string_literal: true

# Prompt-cache probe (cost-optimization §2.1): sends one representative
# long-prefix request twice through the server Anthropic adapter and checks that
#   1. the second call reads from the cache (cached_tokens > 0), and
#   2. on both calls prompt_tokens == input + cache_read + cache_creation, i.e. the
#      platform's prompt_tokens is the TOTAL input with the cache counts inside it.
#
# Run from the server/ directory:
#   bin/rails runner ../scripts/ai-smoke/cache_probe.rb -- MODEL [PROVIDER_ID]
# MODEL is required (never hardcoded). PROVIDER_ID picks an Ai::Provider; without
# it the first active anthropic provider with an active credential is used.
# The API key is read in-process only and never printed. The client is built with
# Client.for_type (no provider record), so no usage metrics are written.
# Exits 0 on pass, 1 on a failed check, 2 when it cannot run.

args = ARGV.drop_while { |a| a == "--" }
model = args[0]
provider_id = args[1]
abort("usage: cache_probe.rb -- MODEL [PROVIDER_ID]") if model.blank?

scope = Ai::Provider.where(provider_type: "anthropic")
scope = scope.where(id: provider_id) if provider_id
provider = scope.detect { |p| p.provider_credentials.any?(&:is_active) }
unless provider
  warn "cache_probe: no anthropic provider with an active credential"
  exit 2
end
credential = provider.provider_credentials.detect(&:is_active)
api_key = credential.credentials&.dig("api_key")
if api_key.blank?
  warn "cache_probe: credential has no api_key"
  exit 2
end

client = Ai::Llm::Client.for_type("anthropic", api_key: api_key, base_url: provider.api_base_url,
                                              provider_name: provider.name)

# ~9K-token stable prefix: above every current model's minimum cacheable length.
# A per-run nonce keeps this run from reading an earlier run's cache entry.
nonce = SecureRandom.hex(8)
paragraph = "Powernode fleets run agents on nodes; each node composes modules from a manifest, " \
            "and the control plane reconciles desired and observed state on every heartbeat. "
system_prompt = "Cache probe #{nonce}. Answer in one short sentence.\n\n" + (paragraph * 400)
messages = [{ role: "user", content: "In one sentence: what does the control plane reconcile?" }]

results = 2.times.map do |i|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  r = client.complete(messages: messages, model: model, system_prompt: system_prompt, max_tokens: 1024)
  elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).round(2)
  raw = r.raw_response.is_a?(Hash) ? (r.raw_response["usage"] || {}) : {}
  row = {
    call: i + 1, ok: r.success?, finish_reason: r.finish_reason, seconds: elapsed,
    prompt_tokens: r.usage[:prompt_tokens], cached_tokens: r.cached_tokens,
    cache_creation_tokens: r.cache_creation_tokens, completion_tokens: r.usage[:completion_tokens],
    api_input_tokens: raw["input_tokens"], api_cache_read: raw["cache_read_input_tokens"],
    api_cache_creation: raw["cache_creation_input_tokens"], api_output_tokens: raw["output_tokens"]
  }
  row[:error] = r.raw_response[:error] || r.raw_response["error"] unless r.success?
  puts row.to_json
  row
end

failures = []
results.each do |row|
  next failures << "call #{row[:call]} failed: #{row[:error]}" unless row[:ok]

  sum = row[:api_input_tokens].to_i + row[:api_cache_read].to_i + row[:api_cache_creation].to_i
  failures << "call #{row[:call]}: prompt_tokens #{row[:prompt_tokens]} != input+read+write #{sum}" unless row[:prompt_tokens] == sum
end
second = results[1]
failures << "second call read nothing from the cache" if second[:ok] && second[:cached_tokens].to_i.zero?

if failures.empty?
  puts "cache_probe: PASS"
  exit 0
else
  failures.each { |f| puts "cache_probe: FAIL #{f}" }
  exit 1
end
