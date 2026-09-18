# frozen_string_literal: true

require "rails_helper"

# IMP-f1f96c292991 — the 5 business example agents (Legal & Compliance
# Analyst, Life Sciences Research Analyst, Finance Operations Analyst, Sales
# Operations Specialist, Customer Success Agent) are sample content: created
# by autonomy_data_seed.rb (loaded unconditionally in the BASELINE block of
# server/db/seeds.rb, which defaults ON) on every deployment, including the
# control plane. They now go behind Powernode::SampleContentGate, default
# OFF. The GLOBAL canonicals in the same seed (process-automation-optimizer,
# visual-design-assistant) are product, not sample, and stay unconditional —
# covered separately by core_agents_global_seed_spec.rb.
RSpec.describe "autonomy_data_seed.rb sample-content gating" do
  def load_seed!
    silence_warnings { load Rails.root.join("db", "seeds", "autonomy_data_seed.rb") }
  end

  let!(:account) { create(:account, name: "Powernode Admin") }
  let!(:user)    { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:openai)    { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }
  let!(:grok)      { create(:ai_provider, account: account, provider_type: "custom", is_active: true) }

  SAMPLE_AGENT_NAMES = [
    "Legal & Compliance Analyst",
    "Life Sciences Research Analyst",
    "Finance Operations Analyst",
    "Sales Operations Specialist",
    "Customer Success Agent"
  ].freeze

  context "when sample content is disabled (default)" do
    it "creates none of the 5 business example agents" do
      load_seed!
      found = Ai::Agent.where(account: account, name: SAMPLE_AGENT_NAMES)
      expect(found).to be_empty
    end

    it "still creates the GLOBAL canonicals (product, not sample)" do
      load_seed!
      %w[process-automation-optimizer visual-design-assistant].each do |slug|
        expect(Ai::Agent.global.exists?(slug: slug)).to be(true), "#{slug} should still be seeded"
      end
    end

    it "writes no trust score or budget for the 5 sample agents" do
      load_seed!
      expect(Ai::AgentTrustScore.joins(:agent).where(ai_agents: { name: SAMPLE_AGENT_NAMES }).count).to eq(0)
      expect(Ai::AgentBudget.joins(:agent).where(ai_agents: { name: SAMPLE_AGENT_NAMES }).count).to eq(0)
    end
  end

  context "when sample content is enabled" do
    before { SiteSetting.set(Powernode::SampleContentGate::SETTING_KEY, "true", setting_type: "boolean") }

    it "creates all 5 business example agents, account-scoped" do
      load_seed!
      found = Ai::Agent.where(account: account, name: SAMPLE_AGENT_NAMES)
      expect(found.pluck(:name)).to match_array(SAMPLE_AGENT_NAMES)
      expect(found.pluck(:account_id).uniq).to eq([ account.id ])
    end

    it "writes a trust score and a budget for each sample agent" do
      load_seed!
      names = Ai::Agent.where(account: account, name: SAMPLE_AGENT_NAMES).pluck(:name)
      expect(names).to match_array(SAMPLE_AGENT_NAMES)
      expect(Ai::AgentTrustScore.joins(:agent).where(ai_agents: { name: SAMPLE_AGENT_NAMES }).count).to eq(5)
      expect(Ai::AgentBudget.joins(:agent).where(ai_agents: { name: SAMPLE_AGENT_NAMES }).count).to eq(5)
    end

    it "is idempotent — running twice does not duplicate the sample agents" do
      load_seed!
      load_seed!
      expect(Ai::Agent.where(account: account, name: SAMPLE_AGENT_NAMES).count).to eq(5)
    end
  end
end
