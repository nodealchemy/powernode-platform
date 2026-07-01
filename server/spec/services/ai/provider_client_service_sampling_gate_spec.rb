# frozen_string_literal: true

require "rails_helper"

# provider_client_service builds Anthropic bodies directly (bypassing the gated
# AnthropicAdapter), so its three Anthropic methods must independently gate
# sampling params or Fable / Opus 4.7+ / Sonnet 5 would 400.
RSpec.describe Ai::ProviderClientService, "Anthropic sampling-param gating" do
  subject(:service) do
    s = described_class.allocate
    s.instance_variable_set(:@headers, { "x-api-key" => "k", "anthropic-version" => "2023-06-01" })
    s.instance_variable_set(:@provider, instance_double(Ai::Provider, api_base_url: "https://api.anthropic.com/v1"))
    s
  end

  let(:messages) { [{ role: "user", content: "hi" }] }

  # anthropic_send_message + anthropic_generate_text POST via self.class.post(body: json).
  def post_body(method, model)
    captured = nil
    allow(described_class).to receive(:post) { |_url, opts| captured = opts[:body]; :resp }
    allow(service).to receive(:handle_chat_response).and_return({})
    allow(service).to receive(:handle_response).and_return({})
    if method == :send_message
      service.send(:anthropic_send_message, messages, model, temperature: 0.7)
    else
      service.send(:anthropic_generate_text, "hi", model, temperature: 0.7)
    end
    JSON.parse(captured)
  end

  # anthropic_stream_text hands a Ruby hash body to stream_response_with_sse.
  def stream_body(model)
    captured = nil
    allow(service).to receive(:stream_response_with_sse) { |_url, body, _pt| captured = body; nil }
    service.send(:anthropic_stream_text, "hi", model, temperature: 0.7)
    captured.deep_stringify_keys
  end

  describe "restricted models omit temperature" do
    %w[claude-fable-5 claude-opus-4-8].each do |model|
      it "anthropic_send_message #{model}" do
        expect(post_body(:send_message, model)).not_to have_key("temperature")
      end

      it "anthropic_generate_text #{model}" do
        expect(post_body(:generate_text, model)).not_to have_key("temperature")
      end

      it "anthropic_stream_text #{model}" do
        expect(stream_body(model)).not_to have_key("temperature")
      end
    end
  end

  describe "permissive model still includes temperature (no regression)" do
    it "anthropic_send_message claude-opus-4-6" do
      expect(post_body(:send_message, "claude-opus-4-6")["temperature"]).to eq(0.7)
    end

    it "anthropic_generate_text claude-opus-4-6" do
      expect(post_body(:generate_text, "claude-opus-4-6")["temperature"]).to eq(0.7)
    end

    it "anthropic_stream_text claude-opus-4-6" do
      expect(stream_body("claude-opus-4-6")["temperature"]).to eq(0.7)
    end
  end
end
