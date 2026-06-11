# frozen_string_literal: true

require "rails_helper"

# Operator rule (2026-06-11): AI model names are never hardcoded. The
# Anthropic and xAI connection testers used to POST a paid test completion
# with a hardcoded model id ("claude-haiku-4-5-20251001" / "grok-3") — a
# model deprecation would break credential testing platform-wide. Both now
# validate credentials via the providers' free models-list endpoint, the
# same pattern the OpenAI tester already used: no model name, no token spend.
RSpec.describe ProviderTesting::ProviderAdapters do
  let(:account) { create(:account) }

  def service_for(provider, api_key: "sk-test-key")
    credential = create(:ai_provider_credential, provider: provider, account: account,
                        is_active: true, credentials: { "api_key" => api_key })
    Ai::ProviderManagementService.new(credential)
  end

  describe "#test_anthropic_connection" do
    let(:provider) do
      create(:ai_provider, :anthropic, account: account).tap do |p|
        p.update_column(:api_base_url, "https://api.anthropic.com/v1")
      end
    end

    it "validates the credential against the free models endpoint — no hardcoded model, no completion" do
      stub_request(:get, "https://api.anthropic.com/v1/models")
        .with(headers: { "x-api-key" => "sk-test-key", "anthropic-version" => "2023-06-01" })
        .to_return(status: 200, body: { data: [ { id: "some-model" }, { id: "another" } ] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = service_for(provider).send(:test_anthropic_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be true
      expect(result[:model_info][:available_models]).to eq(2)
      expect(a_request(:post, %r{api\.anthropic\.com})).not_to have_been_made
    end

    it "reports authentication failure from the models endpoint" do
      stub_request(:get, "https://api.anthropic.com/v1/models")
        .to_return(status: 401, body: { error: { message: "invalid x-api-key" } }.to_json)

      result = service_for(provider).send(:test_anthropic_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq("AUTHENTICATION_FAILED")
      expect(result[:error]).to match(/invalid x-api-key/)
    end
  end

  describe "#test_huggingface_connection" do
    let(:provider) do
      create(:ai_provider, account: account, provider_type: "huggingface",
             api_base_url: "https://api-inference.huggingface.co")
    end

    it "validates the token against the free whoami endpoint instead of stub-succeeding" do
      stub_request(:get, "https://huggingface.co/api/whoami-v2")
        .with(headers: { "Authorization" => "Bearer sk-test-key" })
        .to_return(status: 200, body: { name: "powernode-ci" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = service_for(provider).send(:test_huggingface_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be true
      expect(result[:provider_info][:username]).to eq("powernode-ci")
    end

    it "reports authentication failure honestly" do
      stub_request(:get, "https://huggingface.co/api/whoami-v2")
        .to_return(status: 401, body: { error: "Invalid token" }.to_json)

      result = service_for(provider).send(:test_huggingface_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq("AUTHENTICATION_FAILED")
    end
  end

  describe "#test_cohere_connection" do
    let(:provider) do
      create(:ai_provider, account: account, provider_type: "cohere",
             api_base_url: "https://api.cohere.com/v1")
    end

    it "validates the credential against the free models endpoint instead of stub-succeeding" do
      stub_request(:get, "https://api.cohere.com/v1/models")
        .with(headers: { "Authorization" => "Bearer sk-test-key" })
        .to_return(status: 200, body: { models: [ { name: "a" }, { name: "b" }, { name: "c" } ] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = service_for(provider).send(:test_cohere_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be true
      expect(result[:model_info][:available_models]).to eq(3)
    end

    it "reports authentication failure honestly" do
      stub_request(:get, "https://api.cohere.com/v1/models")
        .to_return(status: 401, body: { message: "invalid api token" }.to_json)

      result = service_for(provider).send(:test_cohere_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq("AUTHENTICATION_FAILED")
    end
  end

  describe "#test_xai_connection" do
    let(:provider) do
      create(:ai_provider, account: account, provider_type: "grok",
             api_base_url: "https://api.x.ai/v1")
    end

    it "validates the credential against the free models endpoint — no hardcoded model, no completion" do
      stub_request(:get, "https://api.x.ai/v1/models")
        .with(headers: { "Authorization" => "Bearer sk-test-key" })
        .to_return(status: 200, body: { data: [ { id: "a-model" } ] }.to_json,
                   headers: { "Content-Type" => "application/json" })

      result = service_for(provider).send(:test_xai_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be true
      expect(result[:model_info][:available_models]).to eq(1)
      expect(a_request(:post, %r{api\.x\.ai})).not_to have_been_made
    end

    it "reports authentication failure from the models endpoint" do
      stub_request(:get, "https://api.x.ai/v1/models")
        .to_return(status: 401, body: { error: "bad key" }.to_json)

      result = service_for(provider).send(:test_xai_connection, provider, { "api_key" => "sk-test-key" })

      expect(result[:success]).to be false
      expect(result[:error_code]).to eq("AUTHENTICATION_FAILED")
    end
  end
end
