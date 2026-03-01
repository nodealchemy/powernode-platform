# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SkillUsageRecord, type: :model do
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
    it { should belong_to(:ai_agent).class_name('Ai::Agent').optional }
  end

  describe 'validations' do
    subject { build(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: agent) }

    it { should validate_presence_of(:outcome) }
    it { should validate_inclusion_of(:outcome).in_array(%w[success failure partial]) }

    it 'rejects an invalid outcome' do
      record = build(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: agent, outcome: "unknown")
      expect(record).not_to be_valid
      expect(record.errors[:outcome]).to be_present
    end

    it 'is valid with all valid attributes' do
      record = build(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: agent)
      expect(record).to be_valid
    end

    it 'is valid without an agent (optional association)' do
      record = build(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: nil)
      expect(record).to be_valid
    end
  end

  describe 'scopes' do
    let!(:success_record) { create(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: agent, outcome: "success") }
    let!(:failure_record) { create(:ai_skill_usage_record, :failure, account: account, ai_skill: skill, ai_agent: agent) }
    let!(:partial_record) { create(:ai_skill_usage_record, :partial, account: account, ai_skill: skill, ai_agent: agent) }

    describe '.successful' do
      it 'returns only success records' do
        results = described_class.successful
        expect(results).to include(success_record)
        expect(results).not_to include(failure_record, partial_record)
      end
    end

    describe '.failed' do
      it 'returns only failure records' do
        results = described_class.failed
        expect(results).to include(failure_record)
        expect(results).not_to include(success_record, partial_record)
      end
    end

    describe '.for_skill' do
      it 'returns records for the given skill' do
        other_skill = create(:ai_skill, account: account)
        other_record = create(:ai_skill_usage_record, account: account, ai_skill: other_skill, ai_agent: agent)

        results = described_class.for_skill(skill.id)
        expect(results).to include(success_record, failure_record, partial_record)
        expect(results).not_to include(other_record)
      end
    end

    describe '.for_agent' do
      it 'returns records for the given agent' do
        other_agent = create(:ai_agent, account: account, creator: user, provider: provider)
        other_record = create(:ai_skill_usage_record, account: account, ai_skill: skill, ai_agent: other_agent)

        results = described_class.for_agent(agent.id)
        expect(results).to include(success_record, failure_record, partial_record)
        expect(results).not_to include(other_record)
      end
    end

    describe '.recent' do
      it 'returns records ordered by created_at desc with default limit' do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end

      it 'respects custom limit' do
        results = described_class.recent(2)
        expect(results.count).to eq(2)
      end
    end
  end

  describe 'factory traits' do
    it 'creates a failure record' do
      record = create(:ai_skill_usage_record, :failure, account: account, ai_skill: skill, ai_agent: agent)
      expect(record.outcome).to eq("failure")
      expect(record.confidence_delta).to eq(-0.05)
    end

    it 'creates a partial record' do
      record = create(:ai_skill_usage_record, :partial, account: account, ai_skill: skill, ai_agent: agent)
      expect(record.outcome).to eq("partial")
      expect(record.confidence_delta).to eq(0.01)
    end
  end
end
