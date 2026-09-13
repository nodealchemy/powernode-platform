# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SkillVersion, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
  let(:skill) { create(:ai_skill, account: account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:ai_skill).class_name('Ai::Skill') }
    it { should belong_to(:created_by_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:created_by_user).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:ai_skill_version, account: account, ai_skill: skill) }

    it { should validate_presence_of(:version) }
    it { should validate_uniqueness_of(:version).scoped_to(:ai_skill_id).case_insensitive }
    it { should validate_presence_of(:change_type) }
    it { should validate_inclusion_of(:change_type).in_array(%w[manual evolution consolidation ab_test]) }

    it 'rejects an invalid change_type' do
      sv = build(:ai_skill_version, account: account, ai_skill: skill, change_type: "unknown")
      expect(sv).not_to be_valid
      expect(sv.errors[:change_type]).to be_present
    end

    it 'enforces version uniqueness within the same skill' do
      create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0")
      duplicate = build(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0")
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:version]).to include('has already been taken')
    end

    it 'allows the same version string for different skills' do
      other_skill = create(:ai_skill, account: account)
      create(:ai_skill_version, account: account, ai_skill: skill, version: "2.0.0")
      other_version = build(:ai_skill_version, account: account, ai_skill: other_skill, version: "2.0.0")
      expect(other_version).to be_valid
    end
  end

  describe '#record_outcome!' do
    let(:skill_version) do
      create(:ai_skill_version, account: account, ai_skill: skill,
             usage_count: 0, success_count: 0, failure_count: 0, effectiveness_score: 0.5)
    end

    context 'when successful' do
      it 'increments success_count' do
        expect { skill_version.record_outcome!(successful: true) }
          .to change { skill_version.reload.success_count }.by(1)
      end

      it 'increments usage_count' do
        expect { skill_version.record_outcome!(successful: true) }
          .to change { skill_version.reload.usage_count }.by(1)
      end
    end

    context 'when unsuccessful' do
      it 'increments failure_count' do
        expect { skill_version.record_outcome!(successful: false) }
          .to change { skill_version.reload.failure_count }.by(1)
      end

      it 'increments usage_count' do
        expect { skill_version.record_outcome!(successful: false) }
          .to change { skill_version.reload.usage_count }.by(1)
      end
    end

    context 'effectiveness recalculation' do
      it 'does not recalculate when usage_count is below 5' do
        skill_version.update_columns(usage_count: 3, success_count: 2, failure_count: 1)
        original_score = skill_version.effectiveness_score
        skill_version.record_outcome!(successful: true)
        expect(skill_version.reload.effectiveness_score).to eq(original_score)
      end

      it 'recalculates effectiveness after 5+ usages' do
        skill_version.update_columns(usage_count: 4, success_count: 3, failure_count: 1, effectiveness_score: 0.5)
        skill_version.record_outcome!(successful: true)
        # After: usage=5, success=4, failure=1 -> effectiveness = 4/5 = 0.8
        expect(skill_version.reload.effectiveness_score).to be_within(0.01).of(0.8)
      end

      it 'calculates effectiveness as success_count / usage_count' do
        skill_version.update_columns(usage_count: 9, success_count: 7, failure_count: 2, effectiveness_score: 0.5)
        skill_version.record_outcome!(successful: true)
        # After: usage=10, success=8, failure=2 -> effectiveness = 8/10 = 0.8
        expect(skill_version.reload.effectiveness_score).to be_within(0.01).of(0.8)
      end
    end
  end

  describe '#activate!' do
    it 'sets is_active to true' do
      version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill)
      version.activate!
      expect(version.reload.is_active).to be true
    end

    it 'deactivates other versions for the same skill' do
      existing_active = create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0", is_active: true)
      new_version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill, version: "2.0.0")

      new_version.activate!
      expect(existing_active.reload.is_active).to be false
      expect(new_version.reload.is_active).to be true
    end

    it 'does not deactivate versions for other skills' do
      other_skill = create(:ai_skill, account: account)
      other_version = create(:ai_skill_version, account: account, ai_skill: other_skill, version: "1.0.0", is_active: true)
      new_version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill, version: "3.0.0")

      new_version.activate!
      expect(other_version.reload.is_active).to be true
    end

    # D5 — activation must change WHAT IS SERVED, not just a label.
    #
    # Ai::Agent#build_skill_system_prompts plucks ai_skills.system_prompt, so a
    # version that is "active" but whose text was never copied there is
    # inert: the skill goes on serving whatever prompt it already had, every
    # outcome recorded against the "active version" is really an outcome of the
    # old text, and the evolution loop's whole premise is false.
    it 'writes the activated version prompt onto the skill it serves' do
      skill.update!(system_prompt: "the old text")
      version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill,
                       version: "9.0.0", system_prompt: "the new text")

      version.activate!

      expect(skill.reload.system_prompt).to eq("the new text")
    end

    it 'is visible through the prompt an agent actually receives' do
      # The end of the chain, not the column: this is the oracle the design
      # names — after activation, build_skill_system_prompts returns the new
      # text. Asserting only the column would pass even if the serving path
      # read from somewhere else.
      agent = create(:ai_agent, account: account)
      skill.update!(system_prompt: "the old text", status: "active", is_enabled: true)
      Ai::AgentSkill.create!(ai_agent_id: agent.id, ai_skill_id: skill.id, is_active: true, priority: 1)
      version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill,
                       version: "9.1.0", system_prompt: "the new text")

      expect(agent.send(:build_skill_system_prompts)).to include("the old text")

      version.activate!

      expect(agent.reload.send(:build_skill_system_prompts)).to include("the new text")
      expect(agent.send(:build_skill_system_prompts)).not_to include("the old text")
    end

    it 'leaves the served prompt alone when the version carries none' do
      # The other arm: older rows predate system_prompt being written, and
      # activating one must not blank the skill it serves.
      skill.update!(system_prompt: "the old text")
      version = create(:ai_skill_version, :inactive, account: account, ai_skill: skill,
                       version: "9.2.0", system_prompt: nil)

      version.activate!

      expect(skill.reload.system_prompt).to eq("the old text")
    end
  end

  # D5 — the producer half of attribution: which versions served an execution.
  describe '.record_served!' do
    let(:agent) { create(:ai_agent, account: account) }
    let(:execution) do
      create(:ai_agent_execution, account: account, agent: agent, execution_context: { "kind" => "keep-me" })
    end

    it 'writes the served ids under the one named key and keeps the rest of the context' do
      version = create(:ai_skill_version, account: account, ai_skill: skill, version: "7.0.0")

      described_class.record_served!(execution: execution, version_ids: [ version.id ])

      stored = execution.reload.execution_context
      expect(stored[described_class::SERVED_CONTEXT_KEY]).to eq([ version.id ])
      expect(stored["kind"]).to eq("keep-me")
    end

    it 'leaves the in-memory row consistent and clean, so a later update! cannot clobber it' do
      version = create(:ai_skill_version, account: account, ai_skill: skill, version: "7.1.0")

      described_class.record_served!(execution: execution, version_ids: [ version.id ])

      expect(execution.execution_context[described_class::SERVED_CONTEXT_KEY]).to eq([ version.id ])
      expect(execution.changed?).to be(false)
    end

    it 'records an empty list, so "served none" differs from "never stamped"' do
      described_class.record_served!(execution: execution, version_ids: [])

      expect(execution.reload.execution_context).to include(described_class::SERVED_CONTEXT_KEY => [])
    end

    it 'does nothing without a persisted execution' do
      expect { described_class.record_served!(execution: nil, version_ids: [ "x" ]) }.not_to raise_error
    end
  end

  describe 'scopes' do
    let!(:active_version) { create(:ai_skill_version, account: account, ai_skill: skill, version: "1.0.0", is_active: true) }
    let!(:inactive_version) { create(:ai_skill_version, :inactive, account: account, ai_skill: skill, version: "2.0.0") }
    let!(:ab_variant) { create(:ai_skill_version, :ab_variant, account: account, ai_skill: skill, version: "3.0.0") }

    describe '.active' do
      it 'returns only active versions' do
        results = described_class.active
        expect(results).to include(active_version)
        expect(results).not_to include(inactive_version, ab_variant)
      end
    end

    describe '.for_skill' do
      it 'returns versions for the given skill' do
        other_skill = create(:ai_skill, account: account)
        other_version = create(:ai_skill_version, account: account, ai_skill: other_skill, version: "1.0.0")

        results = described_class.for_skill(skill.id)
        expect(results).to include(active_version, inactive_version, ab_variant)
        expect(results).not_to include(other_version)
      end
    end

    describe '.ab_variants' do
      it 'returns only A/B variant versions' do
        results = described_class.ab_variants
        expect(results).to include(ab_variant)
        expect(results).not_to include(active_version, inactive_version)
      end
    end
  end

  describe 'traits' do
    it 'creates an evolved version' do
      version = create(:ai_skill_version, :evolved, account: account, ai_skill: skill)
      expect(version.change_type).to eq("evolution")
      expect(version.change_reason).to eq("LLM-assisted improvement")
    end

    it 'creates a high-performing version' do
      version = create(:ai_skill_version, :high_performing, account: account, ai_skill: skill)
      expect(version.effectiveness_score).to eq(0.95)
      expect(version.usage_count).to eq(100)
      expect(version.success_count).to eq(90)
      expect(version.failure_count).to eq(10)
    end
  end
end
