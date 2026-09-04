# frozen_string_literal: true

require "rails_helper"

# Pins the provider-agnostic agent naming contract: agents must not be named
# after a provider (model/provider is chosen at runtime by AgentModelSelector).
# The two formerly-"Claude"-prefixed core agents are renamed to "Strategic
# Planner" / "Research Analyst", and the rename is idempotent in place (no
# duplicate rows on an already-seeded DB). Also pins that Strategic Planner is
# rebound to planning-domain skills after losing the wrongly-bound system-infra
# skills.
RSpec.describe "provider-agnostic agent rename (claude_agents_seed)" do
  def load_seed!(file)
    silence_warnings do
      load Rails.root.join("db", "seeds", file)
    end
  end

  let!(:account)  { create(:account, name: "Powernode Admin") }
  let!(:user)     { create(:user, account: account, email: "admin@powernode.org") }
  let!(:provider) { create(:ai_provider, account: account, provider_type: "anthropic", is_active: true) }

  describe "fresh seed" do
    before { load_seed!("claude_agents_seed.rb") }

    # These are GLOBAL (platform-provided) agents now (account_id nil).
    it "creates provider-agnostic agent names + slugs" do
      planner  = Ai::Agent.global.find_by(slug: "strategic-planner")
      analyst  = Ai::Agent.global.find_by(slug: "research-analyst")
      expect(planner&.name).to eq("Strategic Planner")
      expect(analyst&.name).to eq("Research Analyst")
    end

    it "leaves no agent named after a provider" do
      provider_named = Ai::Agent.where("name ILIKE ? OR slug ILIKE ?", "claude %", "claude-%")
      expect(provider_named).to be_empty
    end

    it "is idempotent (no duplicates on re-run)" do
      expect { load_seed!("claude_agents_seed.rb") }
        .not_to change { Ai::Agent.global.where(slug: %w[strategic-planner research-analyst]).count }
    end
  end

  describe "idempotent in-place rename of an already-seeded (pre-rename) DB" do
    it "renames the existing row in place (and globalizes it) instead of duplicating" do
      legacy = create(:ai_agent, account: account, agent_type: "assistant",
                                 name: "Claude Strategic Planner", slug: "claude-strategic-planner")

      load_seed!("claude_agents_seed.rb")
      legacy.reload

      expect(legacy.slug).to eq("strategic-planner")
      expect(legacy.name).to eq("Strategic Planner")
      expect(legacy.account_id).to be_nil # converted to global in place (id stable)
      expect(Ai::Agent.where(slug: "strategic-planner").count).to eq(1)
      expect(Ai::Agent.where(slug: "claude-strategic-planner")).to be_empty
    end
  end

  describe "Strategic Planner rebound to planning-domain skills" do
    # GLOBAL, matching the real shape: these platform-provided skills are
    # seeded global (account_id nil) by ai_skills_seed.rb, and the assignment
    # seed binds via Ai::Skill.global.find_by(slug:) for a deterministic match.
    # The FULL bound-slug universe is required since IMP-dd2904d87d6d: the
    # assignment seed fails loud (writing nothing) on any missing slug, so a
    # partial fixture set would abort the whole load.
    let!(:skills) do
      %w[
        product-management business-search technical-researcher data
        sre-incident-response devops-engineer security-analyst
        knowledge-system-curator skill-management productivity powernode-dev
        design-skill-from-intent design-agent-team-from-intent
        marketing legal bio-research finance sales customer-support
        agent-autonomy ai-agent-architect api-design documentation-writer
        extension-developer
      ].map do |slug|
        create(:ai_skill, :global, slug: slug, status: "active")
      end
    end

    it "binds the planning skills (its own domain, not system-infra)" do
      load_seed!("claude_agents_seed.rb")
      load_seed!("platform_skill_assignments_seed.rb")

      planner = Ai::Agent.global.find_by!(slug: "strategic-planner")
      bound = Ai::AgentSkill.where(ai_agent_id: planner.id)
                            .joins("INNER JOIN ai_skills ON ai_skills.id = ai_agent_skills.ai_skill_id")
                            .pluck("ai_skills.slug")
      expect(bound).to match_array(%w[product-management business-search technical-researcher data])
    end
  end
end
