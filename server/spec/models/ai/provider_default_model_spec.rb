# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, E3b ruling — Ai::Provider#default_model.
#
# The default an unpinned caller gets is the LIGHTEST-tier model in the
# provider's synced catalog (Ai::ModelTiers.classify), ties broken by catalog
# order; an operator's explicit non-blank default wins; an empty catalog has
# no default. The oracle that matters is the first one: sync ORDERS catalogs
# most-capable-first, so a rule that took catalog[0] would pass every
# "resolves something in the catalog" check while silently making every
# unpinned default the priciest model. The ids below carry real family
# PREFIXES (that is what ModelTiers classifies on) and fake suffixes, so no
# real model id is pinned here.
RSpec.describe Ai::Provider, "#default_model" do
  let(:account) { create(:account) }

  before { Ai::ModelTiers.reset_price_cache! }

  # A FRESH load: #default_model reads an in-memory @configuration first, and
  # a provider that went through create keeps the one its callback set.
  def fresh(provider) = described_class.find(provider.id)

  def provider_with(catalog, schema_extra: {})
    create(:ai_provider, account: account).tap do |p|
      p.update_columns(supported_models: catalog,
                       configuration_schema: p.configuration_schema.merge(schema_extra))
    end
  end

  it "picks the LIGHTEST-tier model from a catalog synced expensive-first" do
    provider = provider_with([ { "id" => "claude-opus-tier-probe" },
                               { "id" => "claude-sonnet-tier-probe" },
                               { "id" => "claude-haiku-tier-probe" } ])

    expect(fresh(provider).default_model).to eq("claude-haiku-tier-probe")
  end

  it "reads bare-string catalog entries too (they used to vanish from #available_models)" do
    provider = provider_with(%w[claude-opus-tier-probe claude-haiku-tier-probe])

    expect(fresh(provider).available_models).to eq(%w[claude-opus-tier-probe claude-haiku-tier-probe])
    expect(fresh(provider).default_model).to eq("claude-haiku-tier-probe")
  end

  it "keeps catalog order between models of the same tier" do
    provider = provider_with([ { "id" => "unclassified-probe-a" }, { "id" => "unclassified-probe-b" } ])

    expect(fresh(provider).default_model).to eq("unclassified-probe-a")
  end

  it "lets an explicit configured default win over the tier rule" do
    provider = provider_with([ { "id" => "claude-haiku-tier-probe" }, { "id" => "claude-opus-tier-probe" } ],
                             schema_extra: { "default_model" => "claude-opus-tier-probe" })

    expect(fresh(provider).default_model).to eq("claude-opus-tier-probe")
  end

  it "treats a blank configured default as absent" do
    provider = provider_with([ { "id" => "claude-opus-tier-probe" }, { "id" => "claude-haiku-tier-probe" } ],
                             schema_extra: { "default_model" => "" })

    expect(fresh(provider).default_model).to eq("claude-haiku-tier-probe")
  end

  it "has NO default for an empty catalog, so resolvers refuse instead of guessing" do
    provider = provider_with([])

    expect(fresh(provider).default_model).to be_nil
  end

  it "writes no literal model for openai or anthropic on create" do
    %w[openai anthropic].each do |type|
      provider = create(:ai_provider, account: account, provider_type: type, is_active: false, supported_models: [])
      schema = fresh(provider).configuration_schema

      expect(schema["default_model"]).to be_nil, "#{type} was given a literal default_model"
      expect(schema["models"]).to eq([]), "#{type} was given a literal model list"
      expect(fresh(provider).default_model).to be_nil
    end
  end

  it "does not re-default a configured default_model on a later save" do
    provider = provider_with([ { "id" => "claude-haiku-tier-probe" } ],
                             schema_extra: { "default_model" => "claude-haiku-tier-probe" })
    reloaded = fresh(provider)
    reloaded.update!(description: "touched")

    expect(fresh(provider).configuration_schema["default_model"]).to eq("claude-haiku-tier-probe")
  end
end
