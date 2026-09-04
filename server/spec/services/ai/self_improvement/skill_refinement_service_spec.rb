# frozen_string_literal: true

require "rails_helper"

# HIER-P3 (proposal §5 ruling 6) — the Platform Architect's VERSIONED path for
# refining a skill's prompt. SkillMutationService reads only an account's own
# skills and mutates through an LLM; this seam takes an already-authored
# prompt (an approved offer's diff) and records it as an Ai::SkillVersion so a
# canonical (global) skill can be refined without an in-place edit nobody can
# diff or revert. It writes; the caller gates (dev.prompt_refine).
RSpec.describe Ai::SelfImprovement::SkillRefinementService do
  let(:account) { create(:account) }
  let(:agent)   { create(:ai_agent, account: account, name: "Platform Architect", agent_type: "assistant") }
  let(:skill)   { create(:ai_skill, :global, slug: "system-restore-volume", system_prompt: "Restore a volume.") }

  subject(:service) { described_class.new(account: account, agent: agent) }

  it "records the new prompt as the skill's active version and applies it to the skill" do
    result = service.refine!(skill: skill, system_prompt: "Restore a volume; refuse above the lag gate.",
                             reason: "name the data-loss gate")

    expect(result.changed).to be(true)
    version = result.version
    expect(version).to be_a(Ai::SkillVersion)
    expect(version.account_id).to eq(account.id)
    expect(version.ai_skill_id).to eq(skill.id)
    expect(version.is_active).to be(true)
    expect(version.change_type).to eq("evolution")
    expect(version.change_reason).to eq("name the data-loss gate")
    expect(version.system_prompt).to eq("Restore a volume; refuse above the lag gate.")
    expect(version.created_by_agent_id).to eq(agent.id)
    expect(version.metadata).to include("previous_system_prompt" => "Restore a volume.", "source" => "governance")
    expect(skill.reload.system_prompt).to eq("Restore a volume; refuse above the lag gate.")
  end

  it "numbers versions after the skill's existing ones and deactivates the previous active version" do
    earlier = Ai::SkillVersion.create!(account: account, ai_skill: skill, version: "1", change_type: "manual",
                                       system_prompt: "Restore a volume.", is_active: true)

    result = service.refine!(skill: skill, system_prompt: "Restore a volume, carefully.", reason: "wording")

    expect(result.version.version).to eq("2")
    expect(earlier.reload.is_active).to be(false)
    expect(Ai::SkillVersion.where(ai_skill_id: skill.id).active.pluck(:id)).to eq([ result.version.id ])
  end

  it "is a no-op for an unchanged prompt (no version, no audit)" do
    expect { @result = service.refine!(skill: skill, system_prompt: "Restore a volume.", reason: "same") }
      .not_to change { Ai::SkillVersion.count }
    expect(@result.changed).to be(false)
    expect(@result.version).to be_nil
  end

  it "refuses a blank prompt rather than blanking the skill" do
    expect { service.refine!(skill: skill, system_prompt: "  ", reason: "oops") }
      .to raise_error(ArgumentError, /system_prompt/)
    expect(skill.reload.system_prompt).to eq("Restore a volume.")
  end

  it "rolls the skill back when the version cannot be written" do
    allow(Ai::SkillVersion).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

    expect { service.refine!(skill: skill, system_prompt: "New prompt.", reason: "x") }
      .to raise_error(ActiveRecord::RecordInvalid)
    expect(skill.reload.system_prompt).to eq("Restore a volume.")
  end
end
