# frozen_string_literal: true

require "rails_helper"

# F3: clone-on-write for system skills, surfaced through the MCP
# skill_management tool. `update_skill` on a global/is_system baseline forks
# an account-owned clone instead of mutating the shared row (and signals
# cloned: true / cloned_from_id so the caller isn't surprised into thinking
# it edited the baseline); the new `clone_skill` action lets a caller fork
# explicitly, with optional overrides, without going through update_skill.
# See also spec/services/ai/tools/skill_tool_global_resolution_spec.rb
# (attach/detach override-aware resolution) and
# spec/services/ai/skill_service_spec.rb (service-level coverage).
RSpec.describe Ai::Tools::SkillTool do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  subject(:tool) { described_class.new(account: account) }

  let!(:global_skill) do
    create(:ai_skill, :global, :system_skill, name: "Global Baseline", slug: "global-baseline",
                                                category: "productivity",
                                                system_prompt: "You are a helpful baseline assistant.")
  end

  describe "action: update_skill" do
    it "clones a global skill into the account and signals cloned: true" do
      result = tool.execute(params: { action: "update_skill", skill_id: global_skill.id, name: "My Baseline" })

      expect(result[:success]).to be true
      expect(result[:cloned]).to be true
      expect(result[:cloned_from_id]).to eq(global_skill.id)
      expect(result[:skill][:name]).to eq("My Baseline")
      expect(result[:skill][:id]).not_to eq(global_skill.id)

      global_skill.reload
      expect(global_skill.name).to eq("Global Baseline")
    end

    it "edits the account's own non-system skill in place (cloned: false, no cloned_from_id)" do
      own = create(:ai_skill, account: account, name: "Mine", category: "productivity")

      result = tool.execute(params: { action: "update_skill", skill_id: own.id, name: "Mine Renamed" })

      expect(result[:success]).to be true
      expect(result[:cloned]).to be false
      expect(result).not_to have_key(:cloned_from_id)
      expect(result[:skill][:id]).to eq(own.id)
      expect(result[:skill][:name]).to eq("Mine Renamed")
    end

    it "reuses the same clone across repeated updates instead of duplicating it" do
      first = tool.execute(params: { action: "update_skill", skill_id: global_skill.id, name: "V1" })
      second = tool.execute(params: { action: "update_skill", skill_id: global_skill.id, description: "V2 desc" })

      expect(second[:skill][:id]).to eq(first[:skill][:id])
      expect(Ai::Skill.where(cloned_from_id: global_skill.id).count).to eq(1)
    end
  end

  describe "action: clone_skill" do
    it "clones a global skill and returns clone provenance" do
      result = tool.execute(params: { action: "clone_skill", skill_id: global_skill.id })

      expect(result[:success]).to be true
      expect(result[:cloned_from_id]).to eq(global_skill.id)
      expect(result[:skill][:account_id]).to eq(account.id)
      expect(result[:skill][:is_system]).to be false
    end

    it "applies overrides on the clone without touching the origin" do
      result = tool.execute(params: { action: "clone_skill", skill_id: global_skill.id, name: "Custom Name" })

      expect(result[:success]).to be true
      expect(result[:skill][:name]).to eq("Custom Name")

      global_skill.reload
      expect(global_skill.name).to eq("Global Baseline")
    end

    it "returns an error for a skill_id that isn't visible to the account" do
      foreign = create(:ai_skill, account: other_account, category: "productivity")

      result = tool.execute(params: { action: "clone_skill", skill_id: foreign.id })

      expect(result[:success]).to be false
      expect(result[:error]).to be_present
    end

    it "returns an error when skill_id is missing" do
      result = tool.execute(params: { action: "clone_skill" })

      expect(result[:success]).to be false
      expect(result[:error]).to match(/skill_id/)
    end

    it "composes with resolve_for: the cloning account sees its fork, other accounts see the baseline" do
      tool.execute(params: { action: "clone_skill", skill_id: global_skill.id, name: "Account A Clone" })

      resolved_for_account = Ai::Skill.resolve_for(account.id, slug: global_skill.slug)
      resolved_for_other   = Ai::Skill.resolve_for(other_account.id, slug: global_skill.slug)

      expect(resolved_for_account.name).to eq("Account A Clone")
      expect(resolved_for_other.id).to eq(global_skill.id)
    end
  end

  describe "PlatformApiToolRegistry wiring" do
    it "routes the clone_skill action to this tool" do
      expect(Ai::Tools::PlatformApiToolRegistry::TOOLS["clone_skill"]).to eq("Ai::Tools::SkillTool")
    end

    it "declares a clone_skill action_definitions entry matching the registry key" do
      expect(described_class.action_definitions).to have_key("clone_skill")
    end
  end
end
