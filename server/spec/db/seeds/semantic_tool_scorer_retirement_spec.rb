# frozen_string_literal: true

require "rails_helper"

# IMP-85c9964aa840. The "semantic-tool-scorer" utility agent was seeded on every
# plane and listed in the protected must-survive-seeds set, but nothing resolved
# it: SemanticToolDiscoveryService was its only caller, and only to ask it for an
# embedding it could not produce. That path now goes to Ai::Memory::EmbeddingService,
# leaving an agent no code path can invoke.
#
# Retired rather than wired. The alternative — an LLM re-rank layered on the
# embedding shortlist, which is what its prompt was written for — is a feature
# with per-discovery latency and token cost, and belongs to a design with budget
# controls, not to a dead-code cleanup. The prompt is recoverable from git if
# that feature is ever built.
RSpec.describe "semantic-tool-scorer retirement" do
  def load_seed!(file)
    silence_warnings { load Rails.root.join("db", "seeds", file) }
  end

  # The seed bails early without an admin account/user AND a provider — without
  # all three it creates nothing, which would make the absence assertion below
  # pass for the wrong reason.
  let!(:account)  { create(:account, name: "Powernode Admin") }
  let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
  let!(:provider) { create(:ai_provider, account: account, provider_type: "openai", is_active: true) }

  it "no longer seeds the orphaned scorer agent" do
    load_seed!("ai_utility_agents_seed.rb")

    expect(Ai::Agent.exists?(slug: "semantic-tool-scorer")).to be(false)
    expect(Ai::Agent.exists?(name: "Semantic Tool Scorer")).to be(false)
  end

  it "still seeds the utility agents that remain in use" do
    load_seed!("ai_utility_agents_seed.rb")

    expect(Ai::Agent.global.exists?(slug: "intent-classifier")).to be(true)
  end

  it "drops it from the protected must-survive-seeds set" do
    source = Rails.root.join("db", "seeds", "autonomy_data_seed.rb").read

    expect(source).not_to include("Semantic Tool Scorer")
  end

  it "leaves no code path resolving the slug" do
    hits = Dir.glob(Rails.root.join("app", "**", "*.rb")).select do |path|
      File.read(path).include?("semantic-tool-scorer")
    end

    expect(hits).to be_empty
  end
end
