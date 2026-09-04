# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/concerns/canonical_agent_owner")

# Deploy-4 incident (2026-09-04): ops-hub's global `visual-design-assistant`
# was pinned to claude-sonnet-5 and back-filled with the OpenAI provider, so
# every later save of that row failed validation and the core hierarchy seed
# aborted. The back-fill must pick a provider that can run the pin.
RSpec.describe CoreSeeds::CanonicalAgentOwner do
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let!(:openai) { create(:ai_provider, :openai, account: seeding_account, is_active: true, priority_order: 1) }
  let!(:anthropic_inactive) { create(:ai_provider, :anthropic, account: seeding_account, is_active: false, priority_order: 2) }

  # Built the way the seeds leave it on a fresh install: a global row with the
  # pin and NO provider yet (IMP-6cda93db7f31 made that a valid row).
  def global_agent(pin)
    agent = create(:ai_agent, :global, owner_account: seeding_account, name: "Visual Design Assistant",
                                       slug: "visual-design-assistant", is_system: true,
                                       provider: anthropic_inactive,
                                       mcp_metadata: pin ? { "model_config" => { "model" => pin } } : {})
    agent.update_columns(ai_provider_id: nil)
    agent.reload
  end

  it "back-fills the provider of the pin's family even when the offered provider is another family" do
    agent = global_agent("claude-sonnet-5")

    described_class.backfill_owner!(agent, provider: openai)

    expect(agent.reload.ai_provider_id).to eq(anthropic_inactive.id)
    expect(agent).to be_valid
  end

  it "prefers an ACTIVE provider of the pin's family" do
    active = create(:ai_provider, :anthropic, account: seeding_account, is_active: true, name: "Anthropic 2", slug: "anthropic-2", priority_order: 9)
    agent = global_agent("claude-sonnet-5")

    described_class.backfill_owner!(agent, provider: openai)

    expect(agent.reload.ai_provider_id).to eq(active.id)
  end

  it "leaves the row provider-less rather than invalid when no provider of the pin's family exists" do
    agent = global_agent("claude-sonnet-5")
    anthropic_inactive.destroy!

    described_class.backfill_owner!(agent, provider: openai)

    expect(agent.reload.ai_provider_id).to be_nil
  end

  it "takes the offered provider for an unpinned canonical" do
    agent = global_agent(nil)

    described_class.backfill_owner!(agent, provider: openai)

    expect(agent.reload.ai_provider_id).to eq(openai.id)
  end
end
