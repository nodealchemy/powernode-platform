# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260911114018_clear_literal_provider_default_models.rb")

# E3b, campaign 01a08c9b. The deploy-time half of the literal-default cleanup.
# The migration delegates to Ai::Providers::LiteralDefaultCleanup.auto_clear,
# whose arms (clear at 5 or fewer, no-op above, never raise, audit) are
# specced in spec/services/ai/providers/literal_default_cleanup_spec.rb. What
# is left to prove here is the wiring, and that the migration itself cannot
# raise: live nodes apply pending migrations at boot.
RSpec.describe ClearLiteralProviderDefaultModels do
  subject(:migration) { described_class.new }

  let(:account) { create(:account) }
  let(:literal) { Ai::Providers::LiteralDefaultCleanup::SHIPPED_DEFAULTS.fetch("openai").first }

  before { allow(migration).to receive(:say) }

  def stale_provider
    create(:ai_provider, account: account, provider_type: "openai").tap do |p|
      p.update_columns(configuration_schema: { "models" => [], "default_model" => literal },
                       supported_models: [ { "id" => "catalog-model-1", "name" => "catalog-model-1" } ])
    end
  end

  it "clears a stale shipped literal and says what it did" do
    provider = stale_provider

    migration.up

    expect(Ai::Provider.find(provider.id).configuration_schema).to include("default_model" => nil)
    expect(migration).to have_received(:say).with(a_string_including("cleared"))
  end

  it "never raises, even when the cleanup cannot be reached at all" do
    allow(Ai::Providers::LiteralDefaultCleanup).to receive(:auto_clear).and_raise(NameError, "boom")

    expect { migration.up }.not_to raise_error
    expect(migration).to have_received(:say).with(a_string_including("skipped", "boom", "ai:clear_literal_provider_defaults"))
  end

  it "runs outside a wrapping transaction, so a rescued failure cannot poison the version insert" do
    expect(described_class.disable_ddl_transaction).to be true
  end

  it "changes nothing on the way down" do
    provider = stale_provider

    expect { migration.down }.not_to raise_error
    expect(Ai::Provider.find(provider.id).configuration_schema["default_model"]).to eq(literal)
  end
end
