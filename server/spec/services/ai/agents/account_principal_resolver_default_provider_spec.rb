# frozen_string_literal: true

require "rails_helper"

# IMP-9370797fac9f — the provider a freshly minted concierge (or any canonical
# clone) lands on follows the account's chosen default provider, and never the
# synthetic Claude Code local-sessions scope.
RSpec.describe Ai::Agents::AccountPrincipalResolver, "default provider" do
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let(:canonical) do
    create(:ai_agent, :global, owner_account: seeding_account, name: "Concierge Canonical",
                               slug: "concierge-canonical", source_key: "concierge-canonical",
                               agent_type: "assistant", is_system: true)
  end

  def routable(name, order, default: false)
    create(:ai_provider, account: account, name: name, provider_type: "custom", priority_order: order,
                         is_active: true, metadata: default ? { "is_default" => true } : {}).tap do |p|
      create(:ai_provider_credential, account: account, provider: p)
    end
  end

  it "mints the clone on the account default, not on the first provider by name" do
    routable("Alpha", 2)
    chosen = routable("Zulu", 1, default: true)

    canonical
    clone = described_class.for(canonical_slug: "concierge-canonical", account: account)

    expect(clone.provider).to eq(chosen)
  end

  it "follows the default when it is changed before the clone exists" do
    first = routable("Alpha", 1, default: true)
    second = routable("Zulu", 2)
    Ai::ProviderDefaultService.set_default!(second, skip_eligibility: true)

    canonical
    clone = described_class.for(canonical_slug: "concierge-canonical", account: account)

    expect(clone.provider).to eq(second)
    expect(first.reload.priority_order).to be > 1
  end

  it "prefers the default over a pinned model's family, dropping the pin" do
    allow(Ai::Agent).to receive(:provider_family_for).and_return(nil)
    allow(Ai::Agent).to receive(:provider_family_for).with("pinned-model-x").and_return("anthropic")
    pinned = create(:ai_provider, account: account, name: "Pinned Family", provider_type: "anthropic",
                                  priority_order: 2, is_active: true)
    chosen = routable("Chosen", 1, default: true)
    canonical.update_columns(mcp_metadata: { "model_config" => { "model" => "pinned-model-x" } })

    clone = described_class.for(canonical_slug: "concierge-canonical", account: account)

    expect(pinned).to be_persisted
    expect(clone.provider).to eq(chosen)
    expect(clone.mcp_metadata.dig("model_config", "model")).to be_nil
  end

  it "never lands a clone on the Claude Code local-sessions scope" do
    scope = Ai::ClaudeExport::ProviderScopeSeeder.ensure_for!(account)
    real = routable("Real", 9)
    scope.update_columns(priority_order: 1)
    canonical

    clone = described_class.for(canonical_slug: "concierge-canonical", account: account)

    expect(clone.provider).to eq(real)
  end
end
