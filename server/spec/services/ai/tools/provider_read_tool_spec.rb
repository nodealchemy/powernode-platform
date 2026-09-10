# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment E1 — LLM providers and the model catalog.
#
# The oracle that matters most here is the credential one, and it is asserted
# by PLANTING a real secret in a provider credential and grepping the serialized
# response for that exact string. Checking that a `credentials` key is absent
# would pass a serializer that renamed it, and would pass one that reached the
# decrypted hash through `#configuration`.
RSpec.describe Ai::Tools::ProviderReadTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let!(:first_user) { create(:user, account: account) }

  def actor(*permissions)
    described_class.new(account: account, user: create(:user, account: account, permissions: permissions))
  end

  let(:tool) { actor("ai.providers.read") }

  def advertised_actions = %w[list_llm_providers get_llm_provider list_models]

  # The factory, not a hand-rolled create!: Ai::Provider validates
  # api_endpoint and a non-empty capabilities array, so an inline hash misses
  # required fields and fails for a reason unrelated to what is being tested.
  def provider(**attrs)
    create(:ai_provider, **{ account: account, provider_type: "anthropic", is_active: true,
                             supported_models: [ "claude-opus-5" ] }.merge(attrs))
  end

  describe "declarations" do
    it "declares every advertised action, all read-only" do
      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, klass| klass == described_class.name }
                                                       .keys.map(&:to_s)
      expect(advertised).to match_array(advertised_actions)

      advertised.each do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).not_to be_nil, "#{action} is advertised but not declared"
        expect(declaration[:mutating]).to be(false)
      end
    end

    it "carries readOnlyHint on the wire for every verb" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      advertised_actions.each do |action|
        expect(entries["platform.#{action}"]).not_to be_nil
        expect(entries["platform.#{action}"]["annotations"]).to include("readOnlyHint" => true)
      end
    end

    it "floors every action on ai.providers.read, the name the REST controller checks" do
      expect(::Permissions.permission_exists?("ai.providers.read")).to be true
      expect(described_class::ACTION_PERMISSIONS.values.uniq).to eq([ "ai.providers.read" ])
      expect(described_class::ACTION_PERMISSIONS.keys).to match_array(advertised_actions)
    end
  end

  describe "permission enforcement" do
    it "refuses every verb without ai.providers.read, and allows every verb with it" do
      row = provider
      calls = [
        { action: "list_llm_providers" },
        { action: "get_llm_provider", id: row.id },
        { action: "list_models" }
      ]

      stranger = actor
      calls.each do |params|
        result = stranger.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} was allowed without the permission"
        expect(result[:error]).to include("ai.providers.read")
        expect(result[:data]).to be_nil
      end

      calls.each do |params|
        expect(tool.execute(params: params)[:success]).to be(true), "#{params[:action]} was refused for a holder"
      end
    end
  end

  describe "account isolation" do
    it "lists only this account's providers and 404s another account's" do
      mine = provider(name: "Mine")
      theirs = create(:ai_provider, account: other_account, name: "Theirs Provider", provider_type: "openai")

      listed = tool.execute(params: { action: "list_llm_providers" })
      expect(listed.dig(:data, :providers).map { |p| p[:id] }).to eq([ mine.id ])
      expect(listed.to_json).not_to include("Theirs Provider")

      expect(tool.execute(params: { action: "get_llm_provider", id: theirs.id })[:success]).to be false
    end
  end

  describe "list_llm_providers" do
    it "filters by active_only and provider_type, both arms" do
      active = provider(is_active: true, provider_type: "anthropic")
      inactive = provider(is_active: false, provider_type: "openai")

      only_active = tool.execute(params: { action: "list_llm_providers", active_only: true })
                        .dig(:data, :providers).map { |p| p[:id] }
      expect(only_active).to include(active.id)
      expect(only_active).not_to include(inactive.id)

      by_type = tool.execute(params: { action: "list_llm_providers", provider_type: "openai" })
                    .dig(:data, :providers).map { |p| p[:id] }
      expect(by_type).to eq([ inactive.id ])
      expect(by_type).not_to include(active.id)
    end

    it "reports credential status as booleans and counts, not values" do
      row = provider
      status = tool.execute(params: { action: "list_llm_providers" })
                   .dig(:data, :providers).first[:credential_status]
      expect(status).to include(configured: false, active_count: 0)

      create(:ai_provider_credential, account: account, provider: row, is_active: true)

      status = tool.execute(params: { action: "list_llm_providers" })
                   .dig(:data, :providers).first[:credential_status]
      expect(status).to include(configured: true, active_count: 1)
    end
  end

  describe "get_llm_provider" do
    it "resolves by id or slug and returns detail fields the list omits" do
      row = provider(api_base_url: "https://api.example.test", rate_limits: { "rpm" => 60 })

      by_id = tool.execute(params: { action: "get_llm_provider", id: row.id }).dig(:data, :provider)
      expect(by_id[:api_base_url]).to eq("https://api.example.test")
      expect(by_id[:rate_limits]).to eq("rpm" => 60)

      by_slug = tool.execute(params: { action: "get_llm_provider", slug: row.slug }).dig(:data, :provider)
      expect(by_slug[:id]).to eq(row.id)

      # The list shape must NOT carry them, or "detail fields" means nothing.
      listed = tool.execute(params: { action: "list_llm_providers" }).dig(:data, :providers).first
      expect(listed).not_to have_key(:api_base_url)
      expect(listed).not_to have_key(:rate_limits)
    end

    it "says what it needs when given neither id nor slug" do
      expect(tool.execute(params: { action: "get_llm_provider" })[:error]).to include("slug")
    end
  end

  describe "list_models" do
    it "returns each active provider's models joined with pricing where the catalog has it" do
      row = provider(supported_models: [ "claude-opus-5", "claude-haiku-4-5" ])
      ::Ai::ModelPricing.create!(model_id: "claude-opus-5", provider_type: "anthropic",
                                 input_per_1k: 0.015, output_per_1k: 0.075, source: "manual")

      models = tool.execute(params: { action: "list_models" }).dig(:data, :models)
      priced = models.find { |m| m[:model_id] == "claude-opus-5" }
      unpriced = models.find { |m| m[:model_id] == "claude-haiku-4-5" }

      expect(priced[:provider_id]).to eq(row.id)
      expect(priced.dig(:pricing, :input_per_1k)).to eq(0.015)
      # nil pricing is a real answer — "the catalog has no row" — not an error.
      expect(unpriced[:pricing]).to be_nil
    end

    it "with_pricing_only drops the unpriced models, both arms" do
      provider(supported_models: [ "priced-model", "unpriced-model" ])
      ::Ai::ModelPricing.create!(model_id: "priced-model", provider_type: "anthropic",
                                 input_per_1k: 0.001, output_per_1k: 0.002, source: "manual")

      all = tool.execute(params: { action: "list_models" }).dig(:data, :models).map { |m| m[:model_id] }
      expect(all).to include("priced-model", "unpriced-model")

      filtered = tool.execute(params: { action: "list_models", with_pricing_only: true })
                     .dig(:data, :models).map { |m| m[:model_id] }
      expect(filtered).to include("priced-model")
      expect(filtered).not_to include("unpriced-model")
    end

    it "excludes an inactive provider's models" do
      provider(is_active: false, supported_models: [ "hidden-model" ])

      models = tool.execute(params: { action: "list_models" }).dig(:data, :models).map { |m| m[:model_id] }
      expect(models).not_to include("hidden-model")
    end
  end

  # THE ONE THAT MATTERS. Plant a real key, then grep every response.
  describe "credential material" do
    let!(:row) { provider }
    let(:api_key) { "sk-live-#{SecureRandom.hex(24)}" }
    let!(:credential) do
      create(:ai_provider_credential, account: account, provider: row, is_active: true,
                                      credentials: { "api_key" => api_key })
    end

    it "stores the key in a form the tool COULD reach (so this oracle is not vacuous)" do
      expect(row.reload.credentials["api_key"]).to eq(api_key)
      expect(credential.reload.credentials["api_key"]).to eq(api_key)
    end

    it "never emits the key, the ciphertext, or the vault pointer from any verb" do
      bodies = [
        tool.execute(params: { action: "list_llm_providers" }).to_json,
        tool.execute(params: { action: "get_llm_provider", id: row.id }).to_json,
        tool.execute(params: { action: "list_models" }).to_json
      ]

      bodies.each do |body|
        expect(body).not_to include(api_key)
        expect(body).not_to include(credential.encrypted_credentials.to_s) if credential.encrypted_credentials.present?
        %w[encrypted_credentials vault_path encryption_key_id api_key last_error].each do |forbidden|
          expect(body).not_to include(forbidden), "#{forbidden} appears in a provider response"
        end
      end
    end
  end

  it "refuses an action it does not advertise" do
    expect(tool.execute(params: { action: "delete_llm_provider" })[:success]).to be false
  end
end
