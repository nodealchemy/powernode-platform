# frozen_string_literal: true

require "rails_helper"

# IMP-245d8ae56f8c follow-up — SkillTool gated WRITES behind a READ permission.
#
# REQUIRED_PERMISSION was "ai.skills.read" with no ACTION_PERMISSIONS map, so
# every action — create_skill, update_skill, clone_skill, delete_skill — cleared
# on the same read-tier floor. The catalog has carried granular
# ai.skills.create / .update / .delete the whole time; nothing consumed them on
# this surface.
#
# Concretely: the `member` role holds ai.skills.read and none of the write
# permissions (config/permissions.rb), and could nonetheless author and mutate
# skills through MCP.
#
# This matters beyond the usual read/write hygiene because a skill is where a
# RECIPE lives (metadata["recipe"]) — an ordered list of tool invocations that
# SkillRecipeRunner dispatches with the DISPATCHER's permissions. Authoring
# rights are therefore the right to write steps somebody more privileged may
# later execute. Recipe dispatch has no production entry point today, which is
# why this is worth closing before it does.
#
# Sibling precedent: SelfImprovementTool already carries exactly this shape
# (floor + ACTION_PERMISSIONS mapping mutate_skill -> ai.skills.update and
# compose_skills -> ai.skills.create) from IMP-6fbfeff384fa. SkillTool was the
# outlier in its own family, not a new policy question.
RSpec.describe Ai::Tools::SkillTool, "per-action permission gating" do
  let(:account) { create(:account) }

  def tool_for(*permissions)
    described_class.new(
      account: account,
      user: create(:user, account: account, permissions: permissions)
    )
  end

  def create_params
    { action: "create_skill", name: "Recipe Skill", description: "d", category: "productivity",
      system_prompt: "You are helpful." }
  end

  describe "writes" do
    it "refuses create_skill for a caller holding only the read floor" do
      result = tool_for("ai.skills.read").execute(params: create_params)

      expect(result[:success]).to be(false),
                                  "a read-only caller authored a skill — and a skill is where a recipe lives"
      expect(result[:error]).to match(/permission denied/i)
      expect(result[:error]).to include("ai.skills.create")
      expect(Ai::Skill.where(account: account, name: "Recipe Skill")).not_to exist
    end

    it "refuses update_skill for a caller holding only the read floor" do
      skill = create(:ai_skill, account: account)

      result = tool_for("ai.skills.read").execute(
        params: { action: "update_skill", skill_id: skill.id, description: "mutated" }
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("ai.skills.update")
    end

    it "refuses delete_skill for a caller holding only the read floor" do
      skill = create(:ai_skill, account: account)

      result = tool_for("ai.skills.read").execute(
        params: { action: "delete_skill", skill_id: skill.id }
      )

      expect(result[:success]).to be false
      expect(result[:error]).to include("ai.skills.delete")
    end
  end

  # POSITIVE CONTROLS. These are what fail if the gate over-applies — refusing
  # every write would satisfy the examples above while breaking the surface.
  describe "permitted callers" do
    it "allows create_skill for a caller holding ai.skills.create" do
      result = tool_for("ai.skills.read", "ai.skills.create").execute(params: create_params)

      expect(result[:success]).to be(true), "a permitted caller was refused: #{result[:error]}"
      expect(Ai::Skill.where(account: account, name: "Recipe Skill")).to exist
    end

    it "allows update_skill for a caller holding ai.skills.update" do
      skill = create(:ai_skill, account: account)

      result = tool_for("ai.skills.read", "ai.skills.update").execute(
        params: { action: "update_skill", skill_id: skill.id, description: "mutated" }
      )

      expect(result[:success]).to be(true), "a permitted caller was refused: #{result[:error]}"
    end
  end

  # READS must keep clearing on the floor alone — the whole point is to split
  # write from read, not to raise the bar on reading.
  describe "reads" do
    it "still allows list_skills on the read floor" do
      result = tool_for("ai.skills.read").execute(params: { action: "list_skills" })

      expect(result[:success]).to be(true), "reads must not be tightened: #{result[:error]}"
    end
  end
end
