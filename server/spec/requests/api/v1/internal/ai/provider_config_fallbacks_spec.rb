# frozen_string_literal: true

require "rails_helper"

# The worker's refusal handler consumes `fallback_models` from provider_config.
# The endpoint resolves them SERVER-side and ONLY for refusal-capable (Fable/
# Mythos) models, so the hot path stays cheap for every other model.
RSpec.describe "Internal::Ai provider_config fallback_models", type: :request do
  include_context "internal api auth"

  let(:agent) { create(:ai_agent, account: internal_account) }
  let(:path) { "/api/v1/internal/ai/provider_config" }

  def post_config
    post path, params: { agent_id: agent.id }.to_json, headers: service_headers
    JSON.parse(response.body)
  end

  it "includes server-resolved fallback_models for a refusal-capable model" do
    # Stubbed per-instance, not by intercepting the class-level `find`: the
    # controller now loads the agent through a TENANCY-SCOPED relation
    # (Ai::Agent.for_account(...).find), so a stub on `Ai::Agent.find` no longer
    # sits on the path and the stub on this particular object never applies —
    # the relation materializes its own instance of the same row.
    allow_any_instance_of(::Ai::Agent).to receive(:resolved_model).and_return("claude-fable-5")
    allow(::Ai::ModelFallbackResolver).to receive(:reasoning_fallbacks)
      .and_return(["claude-opus-4-8"])

    body = post_config

    expect(response).to have_http_status(:ok)
    expect(body.dig("data", "model")).to eq("claude-fable-5")
    expect(body.dig("data", "fallback_models")).to eq(["claude-opus-4-8"])
  end

  it "returns an empty fallback list (no resolution cost) for a non-Fable model" do
    allow_any_instance_of(::Ai::Agent).to receive(:resolved_model).and_return("claude-opus-4-8")
    expect(::Ai::ModelFallbackResolver).not_to receive(:reasoning_fallbacks)

    body = post_config

    expect(response).to have_http_status(:ok)
    expect(body.dig("data", "fallback_models")).to eq([])
  end
end
