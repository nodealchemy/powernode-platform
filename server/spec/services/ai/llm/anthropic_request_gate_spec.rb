# frozen_string_literal: true

require "rails_helper"

# The Anthropic request gate (sampling params / thinking / effort) used to be
# re-implemented inline at every server call site, so a new site could silently
# bypass it and 400 on an adaptive-only model. It now lives in ONE place —
# Ai::Llm::ModelCapabilities.apply_anthropic_request_gate! — and every server
# Anthropic body-builder funnels through it. This spec pins the gate semantics
# and asserts each builder delegates to it. (Verbatim mirror of the worker spec.)
RSpec.describe Ai::Llm::ModelCapabilities, ".apply_anthropic_request_gate!" do
  it "omits sampling params for an adaptive-only model" do
    body = {}
    described_class.apply_anthropic_request_gate!(body, "claude-fable-5", temperature: 0.7, top_p: 0.9)
    expect(body).not_to have_key(:temperature)
    expect(body).not_to have_key(:top_p)
  end

  it "passes sampling params for a permissive model" do
    body = {}
    described_class.apply_anthropic_request_gate!(body, "claude-opus-4-6", temperature: 0.7, top_p: 0.9)
    expect(body[:temperature]).to eq(0.7)
    expect(body[:top_p]).to eq(0.9)
  end

  it "emits a thinking block only when surface_reasoning is asked on an adaptive-only model" do
    plain = {}
    described_class.apply_anthropic_request_gate!(plain, "claude-fable-5", effort: "high")
    expect(plain).not_to have_key(:thinking)

    surfaced = {}
    described_class.apply_anthropic_request_gate!(surfaced, "claude-fable-5", surface_reasoning: true)
    expect(surfaced[:thinking]).to eq(type: "adaptive", display: "summarized")
  end

  it "never emits a thinking block for a permissive model even when surface_reasoning is asked" do
    body = {}
    described_class.apply_anthropic_request_gate!(body, "claude-opus-4-6", surface_reasoning: true)
    expect(body).not_to have_key(:thinking)
  end

  it "sets output_config.effort only for effort-capable models" do
    adaptive = {}
    described_class.apply_anthropic_request_gate!(adaptive, "claude-fable-5", effort: "high")
    expect(adaptive[:output_config]).to eq(effort: "high")

    permissive = {}
    described_class.apply_anthropic_request_gate!(permissive, "claude-opus-4-6", effort: "high")
    expect(permissive).not_to have_key(:output_config)
  end

  it "merges effort into an existing output_config without clobbering it" do
    body = { output_config: { format: { type: "json_schema" } } }
    described_class.apply_anthropic_request_gate!(body, "claude-fable-5", effort: "high")
    expect(body[:output_config]).to eq(format: { type: "json_schema" }, effort: "high")
  end

  describe "every server Anthropic body-builder funnels through the gate" do
    let(:messages) { [{ role: "user", content: "hi" }] }

    it "Ai::Llm::Adapters::AnthropicAdapter#build_messages_body" do
      adapter = Ai::Llm::Adapters::AnthropicAdapter.new(api_key: "k", base_url: "https://api.anthropic.com/v1", provider_name: "anthropic")
      expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
      adapter.send(:build_messages_body, messages, "claude-fable-5", temperature: 0.7)
    end

    describe "Ai::ProviderClientService" do
      subject(:service) do
        s = Ai::ProviderClientService.allocate
        s.instance_variable_set(:@headers, { "x-api-key" => "k", "anthropic-version" => "2023-06-01" })
        s.instance_variable_set(:@provider, instance_double(Ai::Provider, api_base_url: "https://api.anthropic.com/v1"))
        s
      end

      it "#anthropic_send_message" do
        allow(Ai::ProviderClientService).to receive(:post).and_return(:resp)
        allow(service).to receive(:handle_chat_response).and_return({})
        expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
        service.send(:anthropic_send_message, messages, "claude-fable-5", temperature: 0.7)
      end

      it "#anthropic_generate_text" do
        allow(Ai::ProviderClientService).to receive(:post).and_return(:resp)
        allow(service).to receive(:handle_response).and_return({})
        expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
        service.send(:anthropic_generate_text, "hi", "claude-fable-5", temperature: 0.7)
      end

      it "#anthropic_stream_text" do
        allow(service).to receive(:stream_response_with_sse).and_return(nil)
        expect(described_class).to receive(:apply_anthropic_request_gate!).at_least(:once).and_call_original
        service.send(:anthropic_stream_text, "hi", "claude-fable-5", temperature: 0.7)
      end
    end
  end
end
