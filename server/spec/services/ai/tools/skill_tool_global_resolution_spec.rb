# frozen_string_literal: true

require "rails_helper"

# Regression for the "globalize platform content" campaign: skills now seed
# GLOBAL (account_id nil) as canonical platform-provided content. SkillTool's
# resolver must be override-aware (for_account = global + own) so an account can
# attach/detach a global skill to its agents — before this it filtered on
# account_id: account.id and a global skill resolved to "Skill not found".
RSpec.describe Ai::Tools::SkillTool do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, provider_type: "openai") }
  let!(:agent) do
    create(:ai_agent, account: account, provider: provider, agent_type: "assistant", status: "active")
  end
  let!(:global_skill) do
    create(:ai_skill, :system_skill, account: nil, slug: "global-platform-skill", status: "active")
  end

  subject(:tool) { described_class.new(account: account) }

  describe "#resolve_skill (private)" do
    it "resolves a GLOBAL skill by slug for an account" do
      expect(tool.send(:resolve_skill, "global-platform-skill")).to eq(global_skill)
    end

    it "resolves a GLOBAL skill by id for an account" do
      expect(tool.send(:resolve_skill, global_skill.id)).to eq(global_skill)
    end

    it "still resolves the account's own skill" do
      own = create(:ai_skill, account: account, slug: "own-skill", status: "active")
      expect(tool.send(:resolve_skill, "own-skill")).to eq(own)
    end

    it "does not resolve another account's private skill" do
      other = create(:ai_skill, account: create(:account), slug: "foreign-skill", status: "active")
      expect(tool.send(:resolve_skill, "foreign-skill")).to be_nil
      expect(tool.send(:resolve_skill, other.id)).to be_nil
    end
  end

  describe "#attach_skill_to_agent" do
    it "attaches a global skill to an account-owned agent" do
      result = tool.send(:attach_skill_to_agent, skill_id: "global-platform-skill", agent_id: agent.id)

      expect(result[:success]).to be(true)
      expect(result[:skill_id]).to eq(global_skill.id)
      expect(Ai::AgentSkill.where(ai_agent_id: agent.id, ai_skill_id: global_skill.id)).to exist
    end
  end
end
