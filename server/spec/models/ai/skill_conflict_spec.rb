# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SkillConflict, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:skill_a) { create(:ai_skill, account: account) }
  let(:skill_b) { create(:ai_skill, account: account) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:skill_a).class_name('Ai::Skill') }
    it { should belong_to(:skill_b).class_name('Ai::Skill').optional }
    it { should belong_to(:resolved_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b) }

    it { should validate_presence_of(:conflict_type) }
    it { should validate_presence_of(:severity) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:conflict_type).in_array(%w[duplicate overlapping circular_dependency stale orphan version_drift]) }
    it { should validate_inclusion_of(:severity).in_array(%w[critical high medium low]) }
    it { should validate_inclusion_of(:status).in_array(%w[detected reviewing auto_resolved resolved dismissed]) }

    it 'rejects an invalid conflict_type' do
      conflict = build(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b, conflict_type: "bogus")
      expect(conflict).not_to be_valid
      expect(conflict.errors[:conflict_type]).to be_present
    end

    it 'rejects an invalid severity' do
      conflict = build(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b, severity: "extreme")
      expect(conflict).not_to be_valid
      expect(conflict.errors[:severity]).to be_present
    end

    it 'rejects an invalid status' do
      conflict = build(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b, status: "unknown")
      expect(conflict).not_to be_valid
      expect(conflict.errors[:status]).to be_present
    end
  end

  describe '#resolve!' do
    let(:conflict) { create(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b) }

    it 'sets status to resolved' do
      conflict.resolve!(user: user, strategy: "merged")
      expect(conflict.reload.status).to eq("resolved")
    end

    it 'sets resolved_at timestamp' do
      freeze_time do
        conflict.resolve!(user: user, strategy: "merged")
        expect(conflict.resolved_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'sets resolved_by to the given user' do
      conflict.resolve!(user: user, strategy: "merged")
      expect(conflict.resolved_by).to eq(user)
    end

    it 'stores the resolution strategy' do
      conflict.resolve!(user: user, strategy: "deprecated_one")
      expect(conflict.resolution_strategy).to eq("deprecated_one")
    end

    it 'accepts optional details hash' do
      details = { "notes" => "Merged skill A into skill B" }
      conflict.resolve!(user: user, strategy: "merged", details: details)
      expect(conflict.resolution_details).to eq(details)
    end
  end

  describe '#dismiss!' do
    let(:conflict) { create(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b) }

    it 'sets status to dismissed' do
      conflict.dismiss!(user: user)
      expect(conflict.reload.status).to eq("dismissed")
    end

    it 'sets resolved_at timestamp' do
      freeze_time do
        conflict.dismiss!(user: user)
        expect(conflict.resolved_at).to be_within(1.second).of(Time.current)
      end
    end

    it 'sets resolved_by to the given user' do
      conflict.dismiss!(user: user)
      expect(conflict.resolved_by).to eq(user)
    end
  end

  describe '#calculate_priority!' do
    it 'calculates priority based on severity weight, age factor, and impact' do
      conflict = create(:ai_skill_conflict,
                        account: account,
                        skill_a: skill_a,
                        skill_b: skill_b,
                        severity: "high",
                        similarity_score: 0.9,
                        detected_at: 15.days.ago)

      conflict.calculate_priority!
      # severity_weight = 3 (high)
      # days = 15, age_factor = max(1.0, 15/30) = 1.0
      # impact = 0.9
      # priority = 3 * 1.0 * (1 + 0.9) = 5.7
      expect(conflict.reload.priority_score).to be_within(0.1).of(5.7)
    end

    it 'uses minimum age factor of 1.0' do
      conflict = create(:ai_skill_conflict,
                        account: account,
                        skill_a: skill_a,
                        skill_b: skill_b,
                        severity: "medium",
                        similarity_score: 0.5,
                        detected_at: Time.current)

      conflict.calculate_priority!
      # severity_weight = 2 (medium)
      # days ~ 0, age_factor = max(1.0, 0/30) = 1.0
      # impact = 0.5
      # priority = 2 * 1.0 * (1 + 0.5) = 3.0
      expect(conflict.reload.priority_score).to be_within(0.1).of(3.0)
    end

    it 'caps age factor at 3.0' do
      conflict = create(:ai_skill_conflict,
                        account: account,
                        skill_a: skill_a,
                        skill_b: skill_b,
                        severity: "low",
                        similarity_score: 0.0,
                        detected_at: 120.days.ago)

      conflict.calculate_priority!
      # severity_weight = 1 (low)
      # days = 120, age_factor = min(max(1.0, 120/30), 3.0) = min(4.0, 3.0) = 3.0
      # impact = 0.0
      # priority = 1 * 3.0 * (1 + 0.0) = 3.0
      expect(conflict.reload.priority_score).to be_within(0.1).of(3.0)
    end

    it 'handles nil similarity_score as 0.0 impact' do
      conflict = create(:ai_skill_conflict, :stale,
                        account: account,
                        skill_a: skill_a,
                        severity: "critical",
                        detected_at: Time.current)

      conflict.calculate_priority!
      # severity_weight = 4 (critical)
      # impact = 0.0 (nil similarity_score)
      # priority = 4 * 1.0 * (1 + 0.0) = 4.0
      expect(conflict.reload.priority_score).to be_within(0.1).of(4.0)
    end

    it 'handles critical severity with high similarity and age' do
      conflict = create(:ai_skill_conflict, :critical,
                        account: account,
                        skill_a: skill_a,
                        skill_b: skill_b,
                        similarity_score: 1.0,
                        detected_at: 60.days.ago)

      conflict.calculate_priority!
      # severity_weight = 4 (critical)
      # days = 60, age_factor = min(max(1.0, 60/30), 3.0) = 2.0
      # impact = 1.0
      # priority = 4 * 2.0 * (1 + 1.0) = 16.0
      expect(conflict.reload.priority_score).to be_within(0.1).of(16.0)
    end
  end

  describe 'scopes' do
    let(:skill_c) { create(:ai_skill, account: account, name: "Skill C") }
    let(:skill_d) { create(:ai_skill, account: account, name: "Skill D") }
    let(:skill_e) { create(:ai_skill, account: account, name: "Skill E") }
    let!(:detected_conflict) { create(:ai_skill_conflict, account: account, skill_a: skill_a, skill_b: skill_b, conflict_type: "duplicate", status: "detected", priority_score: 10.0) }
    let!(:reviewing_conflict) { create(:ai_skill_conflict, account: account, skill_a: skill_c, skill_b: skill_d, conflict_type: "overlapping", status: "reviewing", priority_score: 5.0) }
    let!(:resolved_conflict) { create(:ai_skill_conflict, :resolved, account: account, skill_a: skill_a, skill_b: skill_c, conflict_type: "stale") }
    let!(:dismissed_conflict) { create(:ai_skill_conflict, :dismissed, account: account, skill_a: skill_b, skill_b: skill_d, conflict_type: "orphan") }
    let!(:auto_resolvable_conflict) { create(:ai_skill_conflict, :auto_resolvable, account: account, skill_a: skill_d, skill_b: skill_e, conflict_type: "version_drift", priority_score: 8.0) }

    describe '.active' do
      it 'excludes resolved and dismissed conflicts' do
        results = described_class.active
        expect(results).to include(detected_conflict, reviewing_conflict, auto_resolvable_conflict)
        expect(results).not_to include(resolved_conflict, dismissed_conflict)
      end
    end

    describe '.unresolved' do
      it 'returns only detected and reviewing conflicts' do
        results = described_class.unresolved
        expect(results).to include(detected_conflict, reviewing_conflict)
        expect(results).not_to include(resolved_conflict, dismissed_conflict)
      end
    end

    describe '.auto_resolvable' do
      it 'returns only auto-resolvable conflicts' do
        results = described_class.auto_resolvable
        expect(results).to include(auto_resolvable_conflict)
        expect(results).not_to include(detected_conflict, reviewing_conflict)
      end
    end

    describe '.by_priority' do
      it 'orders by priority_score descending' do
        results = described_class.by_priority
        scores = results.pluck(:priority_score).compact
        expect(scores).to eq(scores.sort.reverse)
      end
    end
  end

  describe 'conflict type traits' do
    it 'creates an overlapping conflict' do
      conflict = create(:ai_skill_conflict, :overlapping, account: account, skill_a: skill_a, skill_b: skill_b)
      expect(conflict.conflict_type).to eq("overlapping")
      expect(conflict.similarity_score).to eq(0.8)
    end

    it 'creates a stale conflict without skill_b' do
      conflict = create(:ai_skill_conflict, :stale, account: account, skill_a: skill_a)
      expect(conflict.conflict_type).to eq("stale")
      expect(conflict.skill_b).to be_nil
      expect(conflict.similarity_score).to be_nil
    end

    it 'creates an orphan conflict without skill_b' do
      conflict = create(:ai_skill_conflict, :orphan, account: account, skill_a: skill_a)
      expect(conflict.conflict_type).to eq("orphan")
      expect(conflict.skill_b).to be_nil
    end

    it 'creates a version_drift conflict' do
      conflict = create(:ai_skill_conflict, :version_drift, account: account, skill_a: skill_a, skill_b: skill_b)
      expect(conflict.conflict_type).to eq("version_drift")
    end
  end
end
