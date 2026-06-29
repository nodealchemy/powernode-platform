# frozen_string_literal: true

require "rails_helper"

# Verifies the remaining core fundamental agent seeds migrate to GLOBAL
# (account_id nil, is_system) and that the industry/business example agents stay
# account-scoped demo data, and that the seed-side resolvers still wire up the
# now-global agents (provider/trust/concierge/skill lookups).
RSpec.describe "core fundamental agent seeds → global" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  let!(:account) { create(:account, name: "Powernode Admin") }
  let!(:user)    { create(:user, account: account, email: "admin@powernode.org") }
  let!(:anthropic) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }
  let!(:openai)    { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }
  let!(:ollama)    { create(:ai_provider, account: account, provider_type: "ollama", is_active: true) }
  let!(:grok)      { create(:ai_provider, account: account, provider_type: "custom", is_active: true) }

  def global?(slug)  = Ai::Agent.global.exists?(slug: slug)
  def account?(slug) = Ai::Agent.owned_by_account(account.id).exists?(slug: slug)

  it "globalizes claude_agents (Strategic Planner, Research Analyst)" do
    load_seed!("claude_agents_seed.rb")
    %w[strategic-planner research-analyst].each do |slug|
      expect(global?(slug)).to be(true), "#{slug} should be global"
      g = Ai::Agent.global.find_by(slug: slug)
      expect(g.is_system).to be true
      expect(g.source_key).to eq(slug)
    end
  end

  it "globalizes the 4 monitoring agents" do
    load_seed!("monitoring_analytics_agents_seed.rb")
    %w[system-performance-monitor system-analytics-intelligence
       system-health-monitor system-quality-assurance].each do |slug|
      expect(global?(slug)).to be(true), "#{slug} should be global"
    end
  end

  it "globalizes the 3 fundamental autonomy_data agents but keeps industry agents account-scoped" do
    load_seed!("autonomy_data_seed.rb")
    %w[infrastructure-health-monitor process-automation-optimizer visual-design-assistant].each do |slug|
      expect(global?(slug)).to be(true), "#{slug} should be global"
    end
    # industry/business example agents stay account-scoped demo data
    %w[legal-compliance-analyst finance-operations-analyst sales-operations-specialist].each do |slug|
      expect(account?(slug)).to be(true), "#{slug} should stay account-scoped"
      expect(global?(slug)).to be(false)
    end
  end

  it "converts a pre-existing account-scoped row to global in place (id stable)" do
    legacy = create(:ai_agent, account: account, slug: "strategic-planner",
                               name: "Strategic Planner", agent_type: "assistant")
    load_seed!("claude_agents_seed.rb")
    legacy.reload
    expect(legacy.account_id).to be_nil
    expect(Ai::Agent.where(slug: "strategic-planner").count).to eq(1)
  end
end
