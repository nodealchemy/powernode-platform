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
