# frozen_string_literal: true

require "rails_helper"

# Specs for Ai::Agent's runtime model-resolution triple
# (#resolved_model / #resolved_provider / #resolved_credential via
# #model_resolution). Covers the correctness-critical branches of the refactor:
# pinned-and-valid, pinned-but-unservable (fall through to the selector),
# unpinned (selector-driven), skill-requirement merging (skills are no longer
# inert), and memoization (including the deliberate non-memoization of a
# transient failure).
RSpec.describe Ai::Agent, type: :model do
  let(:account) { create(:account) }

  # A provider that genuinely lists `claude-*` models, with one active default
  # credential — the natural target for a pinned claude model.
  let(:anthropic_provider) { create(:ai_provider, :anthropic, account: account) }
  let!(:anthropic_credential) do
    create(:ai_provider_credential, :default, account: account, provider: anthropic_provider)
  end
  let(:pinned_claude_model) { anthropic_provider.supported_models.first["id"] }

  describe "#model_resolution (PINNED + valid)" do
    subject(:agent) do
      create(:ai_agent, account: account, provider: anthropic_provider, mcp_metadata: {
               "system_prompt" => "You are a helpful assistant",
               "model_config" => { "model" => pinned_claude_model, "provider" => "anthropic" }
             })
    end

    it "resolves the model to the pin verbatim" do
      expect(agent.resolved_model).to eq(pinned_claude_model)
    end

    it "resolves the provider to the agent's own (model-listing) provider" do
      expect(agent.resolved_provider).to eq(anthropic_provider)
    end

    it "resolves the credential to that provider's active default credential" do
      expect(agent.resolved_credential).to eq(anthropic_credential)
    end

    it "never invokes the selector when the pin is servable" do
      expect(Ai::AgentModelSelector).not_to receive(:recommend)
      agent.resolved_model
    end
  end

  describe "#model_resolution (PINNED but unservable → selector fallthrough)" do
    # A bogus pin whose family is unrecognized (provider_type_for_model → nil) and
    # which no provider lists, so provider_for_pinned_model is nil and resolution
    # falls through to the selector. It hangs on an OPENAI provider because openai's
    # model_matches_provider is permissive (accepts any non-claude/grok id) so the
    # agent saves; anthropic would reject a non-claude pin at validation. Only
    # anthropic is credentialed, so the selector picks from it.
    let(:openai_provider) { create(:ai_provider, :openai, account: account) }
    let(:bogus_pin) { "bogus-model-xyz" }

    subject(:agent) do
      create(:ai_agent, account: account, provider: openai_provider, mcp_metadata: {
               "system_prompt" => "You are a helpful assistant",
               "model_config" => { "model" => bogus_pin }
             })
    end

    it "does not resolve to the bogus pin" do
      expect(agent.resolved_model).not_to eq(bogus_pin)
    end

    it "resolves to a real model + provider + credential via the selector" do
      expect(agent.resolved_model).to be_present
      expect(agent.resolved_provider).to be_a(Ai::Provider)
      expect(agent.resolved_credential).to eq(anthropic_credential)
    end
  end

  describe "#model_resolution (UNPINNED → selector-driven)" do
    subject(:agent) do
      # No model_config.model ⇒ unpinned. The agent's own provider is anthropic,
      # which is active + credentialed, so the selector picks from it.
      create(:ai_agent, account: account, provider: anthropic_provider, mcp_metadata: {
               "system_prompt" => "You are a helpful assistant"
             })
    end

    it "produces a coherent provider + model + credential from the SAME provider" do
      resolution = agent.model_resolution

      expect(resolution[:provider]).to be_a(Ai::Provider)
      expect(resolution[:model]).to be_present

      catalog_ids = resolution[:provider].supported_models.map { |m| m["id"] || m["name"] }
      expect(catalog_ids).to include(resolution[:model])

      # The credential belongs to the resolved provider (never a stale cross-provider one).
      expect(resolution[:credential].provider).to eq(resolution[:provider])
    end
  end

  describe "#model_resolution (SKILL requirements merge — skills steer selection)" do
    # A single provider offering BOTH a light and a reasoning-tier model, each
    # satisfying the assistant hard gate (text_generation + chat). Without a skill
    # the assistant profile wants :standard (neither model earns the tier bonus);
    # an active skill requiring tier: reasoning flips the win to the reasoning
    # model — proving model_requirements are folded into selection.
    let(:provider) do
      create(:ai_provider, account: account, provider_type: "custom",
                           capabilities: %w[text_generation chat],
                           supported_models: [
                             { "id" => "llama-3-8b",     "name" => "llama-3-8b",
                               "capabilities" => %w[text_generation chat] },
                             { "id" => "claude-opus-4",  "name" => "claude-opus-4",
                               "capabilities" => %w[text_generation chat] }
                           ])
    end
    let!(:credential) { create(:ai_provider_credential, :default, account: account, provider: provider) }

    let(:reasoning_skill) do
      create(:ai_skill, account: account, status: "active", is_enabled: true,
                        model_requirements: { "tier" => "reasoning" })
    end

    subject(:agent) do
      create(:ai_agent, account: account, provider: provider, mcp_metadata: {
               "system_prompt" => "You are a helpful assistant"
             })
    end

    it "selects a reasoning-tier model when an active skill requires it" do
      create(:ai_agent_skill, agent: agent, skill: reasoning_skill, is_active: true)

      expect(Ai::ModelTiers.classify(agent.resolved_model)).to eq(:reasoning)
      expect(agent.resolved_model).to eq("claude-opus-4")
    end

    it "does not force reasoning when the skill is inactive (proves the skill is what steers)" do
      create(:ai_agent_skill, agent: agent, skill: reasoning_skill, is_active: false)

      # With no effective reasoning requirement the assistant profile wants
      # :standard; neither catalog model is reasoning-preferred, so the reasoning
      # bonus does not apply and the resolved model is the first candidate.
      expect(agent.resolved_model).to eq("llama-3-8b")
    end
  end

  describe "#model_resolution (memoization semantics)" do
    subject(:agent) do
      create(:ai_agent, account: account, provider: anthropic_provider, mcp_metadata: {
               "system_prompt" => "You are a helpful assistant"
             })
    end

    it "memoizes a successful resolution (selector invoked once across repeated calls)" do
      expect(Ai::AgentModelSelector).to receive(:recommend).once.and_call_original

      first  = agent.resolved_model
      second = agent.resolved_model
      third  = agent.resolved_provider

      expect(first).to eq(second)
      expect(third).to eq(agent.resolved_provider)
    end

    it "does NOT memoize a transient failure — a later call recomputes and recovers" do
      # The recovered model must be DISTINCT from the fallback so the assertions
      # can tell them apart. Fallback resolves to the provider's default_model
      # (its first catalog model); make the "good" selector answer the *second*
      # catalog model so success differs from failure.
      fallback_model  = anthropic_provider.default_model            # first catalog id
      recovered_model = anthropic_provider.supported_models[1]["id"] # a different id
      expect(recovered_model).not_to eq(fallback_model) # guard the fixture assumption

      good = { provider: anthropic_provider, model: recovered_model, provider_type: "anthropic" }

      call_count = 0
      allow(Ai::AgentModelSelector).to receive(:recommend) do
        call_count += 1
        raise StandardError, "transient selector blip" if call_count == 1

        good
      end

      # First call: selector raises → rescued → fallback_resolution (agent's own
      # provider default_model), NOT the eventual good answer.
      first = agent.resolved_model
      expect(first).to eq(fallback_model)

      # Second call must recompute (failure was not memoized) and now recover.
      expect(agent.resolved_model).to eq(recovered_model)
      expect(call_count).to eq(2)
    end
  end
end
