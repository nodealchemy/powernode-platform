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

  # The REST index shows a disabled provider only to this permission; the verb
  # mirrors that, so half of the list oracles need a holder of it.
  let(:admin) { actor("ai.providers.read", "admin.ai.providers.read") }

  def advertised_actions = %w[list_llm_providers get_llm_provider list_models]

  # The factory, not a hand-rolled create!: Ai::Provider validates
  # api_endpoint and a non-empty capabilities array, so an inline hash misses
  # required fields and fails for a reason unrelated to what is being tested.
  def provider(**attrs)
    create(:ai_provider, **{ account: account, provider_type: "anthropic", is_active: true,
                             supported_models: [ "catalog-model-9" ] }.merge(attrs))
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

      # The provider_type arm is asserted on a caller who can see the inactive
      # row AT ALL — the default below hides it from a plain ai.providers.read
      # holder, which would make an empty list look like a working filter.
      by_type = admin.execute(params: { action: "list_llm_providers", provider_type: "openai" })
                     .dig(:data, :providers).map { |p| p[:id] }
      expect(by_type).to eq([ inactive.id ])
      expect(by_type).not_to include(active.id)
    end

    # REST PARITY (E1 review F2). Api::V1::Ai::ProvidersController#index narrows
    # to `.active` unless the caller holds admin.ai.providers.read; a verb that
    # listed disabled providers to anyone with ai.providers.read would be a way
    # around that door rather than a floor on it.
    it "hides inactive providers by default, and shows them to admin.ai.providers.read — both arms" do
      active = provider(is_active: true)
      inactive = provider(is_active: false)

      default_ids = tool.execute(params: { action: "list_llm_providers" })
                        .dig(:data, :providers).map { |p| p[:id] }
      expect(default_ids).to include(active.id)
      expect(default_ids).not_to include(inactive.id)

      # active_only: false does NOT widen it for a caller without the admin read.
      asked_for_all = tool.execute(params: { action: "list_llm_providers", active_only: false })
                          .dig(:data, :providers).map { |p| p[:id] }
      expect(asked_for_all).not_to include(inactive.id)

      admin_ids = admin.execute(params: { action: "list_llm_providers" })
                       .dig(:data, :providers).map { |p| p[:id] }
      expect(admin_ids).to include(inactive.id), "admin.ai.providers.read did not widen the list"
      expect(admin_ids).to include(active.id)
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
      row = provider(supported_models: [ "catalog-model-9", "catalog-model-8" ])
      ::Ai::ModelPricing.create!(model_id: "catalog-model-9", provider_type: "anthropic",
                                 input_per_1k: 0.015, output_per_1k: 0.075, source: "manual")

      models = tool.execute(params: { action: "list_models" }).dig(:data, :models)
      priced = models.find { |m| m[:model_id] == "catalog-model-9" }
      unpriced = models.find { |m| m[:model_id] == "catalog-model-8" }

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

    # E1 review F3. Before this the verb fanned out EVERY active provider with
    # no envelope, so a truncated catalog and a complete one looked identical.
    # The page unit is the provider (a model has no row and so no cursor), which
    # is why count/has_more are asserted against provider counts and the model
    # tally is read from models_returned.
    it "pages through providers with a cursor, and the walk reaches every model" do
      %w[alpha-model-1 beta-model-1 gamma-model-1].each_with_index do |model_id, i|
        provider(name: "P#{i}", supported_models: [ model_id ])
      end

      first = tool.execute(params: { action: "list_models", limit: 1 })[:data]
      expect(first[:count]).to eq(3), "count must be the providers matching the filters, not the page"
      expect(first[:returned]).to eq(1)
      expect(first[:models_returned]).to eq(1)
      expect(first[:has_more]).to be true
      expect(first[:next_cursor]).to be_present

      seen = first[:models].map { |m| m[:model_id] }
      cursor = first[:next_cursor]
      2.times do
        page = tool.execute(params: { action: "list_models", limit: 1, cursor: cursor })[:data]
        seen.concat(page[:models].map { |m| m[:model_id] })
        cursor = page[:next_cursor]
      end

      expect(seen).to match_array(%w[alpha-model-1 beta-model-1 gamma-model-1])
      expect(cursor).to be_nil, "the walk did not end after the last provider"
    end

    # E1 residual R3. The pricing filter used to run AFTER the provider page
    # was cut, so a page of unpriced providers came back empty with has_more
    # true. Priced and unpriced providers ALTERNATE here so every page
    # boundary falls on an unpriced one — string AND hash catalog entries, the
    # two shapes #models_for reads.
    it "with_pricing_only filters providers before the page is cut — no empty page, count is the priced set" do
      %w[priced-a priced-b].each do |model_id|
        ::Ai::ModelPricing.create!(model_id: model_id, provider_type: "anthropic",
                                   input_per_1k: 0.001, output_per_1k: 0.002, source: "manual")
      end
      provider(name: "P1", supported_models: [ "priced-a" ])
      provider(name: "P2", supported_models: [ "unpriced-x" ])
      provider(name: "P3", supported_models: [ { "id" => "priced-b", "name" => "B" } ])
      provider(name: "P4", supported_models: [ "unpriced-y" ])

      pages = []
      cursor = nil
      loop do
        data = tool.execute(params: { action: "list_models", with_pricing_only: true, limit: 1, cursor: cursor }.compact)[:data]
        pages << data
        cursor = data[:next_cursor]
        break unless cursor
        raise "the walk did not terminate" if pages.size > 10
      end

      expect(pages.first[:count]).to eq(2), "count must be the priced providers, not all four"
      expect(pages).to all(satisfy { |page| page[:models].any? }), "a page came back with no models"
      expect(pages.flat_map { |page| page[:models].map { |m| m[:model_id] } }).to match_array(%w[priced-a priced-b])

      # The other arm: without the filter the same walk counts all four.
      expect(tool.execute(params: { action: "list_models", limit: 1 })[:data][:count]).to eq(4)
    end

    it "refuses a cursor the platform did not issue rather than answering from page one" do
      provider
      result = tool.execute(params: { action: "list_models", cursor: "not-a-cursor" })

      expect(result[:success]).to be false
      expect(result[:data]).to be_nil
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

  # E1 review F1. The credential oracle above covers the credentials
  # ASSOCIATION. This covers the other way a key gets into a provider: an
  # operator pasting one into a free-form jsonb column through the REST update
  # endpoint. An allow-list of COLUMNS does not screen what is inside a column,
  # and get_llm_provider serializes five of them verbatim.
  describe "secrets planted in free-form jsonb" do
    let(:planted) { "sk-live-#{SecureRandom.hex(24)}" }
    let!(:row) do
      provider(
        default_parameters: { "api_key" => planted, "temperature" => 0.4 },
        rate_limits: { "rpm" => 60, "client_secret" => planted },
        pricing_info: { "currency" => "USD", "nested" => { "bearer" => planted, "tier" => "standard" } }
      ).tap do |p|
        # All FIVE scrubbed columns carry a plant (E1 residual R1). These two
        # are validated on write (a known-capability list; a non-empty
        # catalog), so they go in with update_columns: the oracle is about what
        # the SERIALIZER screens, and a jsonb column has writers other than
        # that validator. Both stay arrays, the shape the columns really hold.
        p.update_columns(
          capabilities: [ "chat", { "api_key" => planted, "note" => "beta" } ],
          supported_models: [ { "id" => "catalog-model-1", "name" => "Catalog One", "api_key" => planted } ]
        )
      end
    end

    it "stores the planted key in a form the tool COULD reach (so this oracle is not vacuous)" do
      expect(row.reload.default_parameters["api_key"]).to eq(planted)
      expect(row.rate_limits["client_secret"]).to eq(planted)
      expect(row.pricing_info.dig("nested", "bearer")).to eq(planted)
      expect(row.capabilities.last["api_key"]).to eq(planted)
      expect(row.supported_models.first["api_key"]).to eq(planted)
    end

    it "drops the secret-keyed entries and keeps the benign ones — both arms" do
      detail = tool.execute(params: { action: "get_llm_provider", id: row.id }).dig(:data, :provider)

      # DROPPED, key and value: a surviving "api_key": "[FILTERED]" would still
      # say which providers carry an inline key.
      expect(detail[:default_parameters]).not_to have_key("api_key")
      expect(detail[:rate_limits]).not_to have_key("client_secret")
      expect(detail[:pricing_info]["nested"]).not_to have_key("bearer")

      # SURVIVING: the scrub is keyed on the NAME, so a config value that is not
      # secret-bearing must come through untouched, nesting included.
      expect(detail[:default_parameters]).to eq("temperature" => 0.4)
      expect(detail[:rate_limits]).to eq("rpm" => 60)
      expect(detail[:pricing_info]).to eq("currency" => "USD", "nested" => { "tier" => "standard" })
      expect(detail[:capabilities]).to eq([ "chat", { "note" => "beta" } ])
      expect(detail[:supported_models]).to eq([ { "id" => "catalog-model-1", "name" => "Catalog One" } ])
    end

    it "never emits the planted key from any verb" do
      [
        tool.execute(params: { action: "list_llm_providers" }).to_json,
        tool.execute(params: { action: "get_llm_provider", id: row.id }).to_json,
        tool.execute(params: { action: "list_models" }).to_json
      ].each { |body| expect(body).not_to include(planted) }
    end

    it "uses the same seam the export manifest does, not a second copy of the rule" do
      expect(::Ai::DataSources::ConfigPortabilityService.ancestors).to include(::Ai::SecretKeyScrubber)
      expect(::Ai::SecretKeyScrubber.scrub_value("api_key" => planted, "temperature" => 0.4))
        .to eq("temperature" => 0.4)
    end
  end

  it "refuses an action it does not advertise" do
    expect(tool.execute(params: { action: "delete_llm_provider" })[:success]).to be false
  end
end
