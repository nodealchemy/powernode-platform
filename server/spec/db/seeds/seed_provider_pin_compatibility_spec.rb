# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/seeds/concerns/canonical_agent_owner")

# Deploy-4 incident (2026-09-04), SEED-LAYER half. The agent seeds choose a
# provider by hard-coded type (Ai::Provider.first / find_by(provider_type:))
# and attach it without consulting the row's model pin, so on an install whose
# only active provider is OpenAI the global `visual-design-assistant`
# (pinned claude-sonnet-5) was written onto the OpenAI provider — invalid on
# every later save, which aborted the hierarchy seed and needed manual SQL
# repair. The provider choice must go through the ONE family rule
# (Ai::Agents::AccountPrincipalResolver.provider_for_pin), and leaving a row
# provider-less is the correct outcome when nothing can run its pin.
RSpec.describe "seed provider choice honours the model pin" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account) { create(:account, name: "Powernode Admin") }
  let!(:user)    { create(:user, account: account, email: "admin@powernode.org") }

  describe "autonomy_data_seed provider re-assignment" do
    let!(:openai) { create(:ai_provider, :openai, account: account, is_active: true, priority_order: 1) }

    # The canonical as the live plane had it: a claude pin, on the account's
    # (inactive) Anthropic provider. Built provider-first so Ai::Agent's own
    # auto-resolve callback lets the row exist at all.
    def pinned_canonical(provider)
      create(:ai_agent, :global, owner_account: account, name: "Visual Design Assistant",
                                 slug: "visual-design-assistant", agent_type: "content_generator",
                                 provider: provider,
                                 mcp_metadata: { "model_config" => { "model" => "claude-sonnet-5" } })
    end

    it "does not move a claude-pinned canonical onto the OpenAI provider" do
      anthropic = create(:ai_provider, :anthropic, account: account, is_active: false, priority_order: 2)
      agent = pinned_canonical(anthropic)

      load_seed!("autonomy_data_seed.rb")

      expect(agent.reload.ai_provider_id).to eq(anthropic.id)
      expect(agent).to be_valid
    end

    it "leaves the canonical provider-less when no provider can run its pin" do
      anthropic = create(:ai_provider, :anthropic, account: account, is_active: false, priority_order: 2)
      agent = pinned_canonical(anthropic)
      agent.update_columns(ai_provider_id: nil)
      anthropic.destroy!

      load_seed!("autonomy_data_seed.rb")

      expect(agent.reload.ai_provider_id).to be_nil
      expect(agent).to be_valid
    end
  end

  describe "monitoring_analytics_agents_seed provider choice" do
    # `Ai::Provider.first` takes whatever row is oldest, active or not.
    let!(:inactive_first) { create(:ai_provider, :openai, account: account, is_active: false, priority_order: 1) }
    let!(:active_second)  { create(:ai_provider, :ollama, account: account, is_active: true, priority_order: 2) }

    it "seeds the monitoring canonicals on an ACTIVE provider" do
      load_seed!("monitoring_analytics_agents_seed.rb")

      agent = Ai::Agent.global.find_by(slug: "system-performance-monitor")
      expect(agent).to be_present
      expect(agent.ai_provider_id).to eq(active_second.id)
    end
  end

  describe CoreSeeds::CanonicalAgentOwner do
    let!(:openai)    { create(:ai_provider, :openai, account: account, is_active: true, priority_order: 1) }
    let!(:anthropic) { create(:ai_provider, :anthropic, account: account, is_active: false, priority_order: 2) }

    it "keeps the seed's preferred provider for an unpinned row" do
      expect(described_class.provider_for(pinned_model: nil, preferred: openai)).to eq(openai)
    end

    it "answers with the pin's family even when the seed prefers another" do
      expect(described_class.provider_for(pinned_model: "claude-sonnet-5", preferred: openai)).to eq(anthropic)
    end

    it "answers nil when no provider of the pin's family exists" do
      anthropic.destroy!

      expect(described_class.provider_for(pinned_model: "claude-sonnet-5", preferred: openai)).to be_nil
    end

    it "prefers an ACTIVE provider over an inactive one offered by the seed" do
      inactive = create(:ai_provider, :ollama, account: account, is_active: false, priority_order: 3)

      expect(described_class.provider_for(pinned_model: nil, preferred: inactive)).to eq(openai)
    end
  end
end
