# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::GitPipelineSchedule, type: :model do
  subject(:schedule) { build(:git_pipeline_schedule) }

  describe 'associations' do
    it { is_expected.to belong_to(:repository) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to belong_to(:last_pipeline).class_name('Devops::GitPipeline').optional }
    it { is_expected.to have_one(:credential).through(:repository) }
    it { is_expected.to have_one(:provider).through(:repository) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:cron_expression) }
    it { is_expected.to validate_presence_of(:timezone) }
    it { is_expected.to validate_presence_of(:ref) }
    it { is_expected.to validate_length_of(:name).is_at_most(100) }

    it 'validates name uniqueness scoped to repository' do
      existing = create(:git_pipeline_schedule)
      duplicate = build(:git_pipeline_schedule,
                        repository: existing.repository,
                        name: existing.name)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:name]).to include('has already been taken')
    end

    describe 'cron_expression validation' do
      it 'accepts valid cron expressions' do
        schedule = build(:git_pipeline_schedule, cron_expression: '0 9 * * 1-5')
        expect(schedule).to be_valid
      end

      it 'rejects invalid cron expressions' do
        schedule = build(:git_pipeline_schedule, cron_expression: 'invalid')
        expect(schedule).not_to be_valid
        expect(schedule.errors[:cron_expression]).to include('is not a valid cron expression')
      end
    end

    describe 'timezone validation' do
      it 'accepts valid timezones' do
        schedule = build(:git_pipeline_schedule, timezone: 'America/New_York')
        expect(schedule).to be_valid
      end

      it 'rejects invalid timezones' do
        schedule = build(:git_pipeline_schedule, timezone: 'Invalid/Zone')
        expect(schedule).not_to be_valid
        expect(schedule.errors[:timezone]).to include('is not a valid timezone')
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    let!(:active_schedule) { create(:git_pipeline_schedule, :active, repository: repo, account: account) }
    let!(:inactive_schedule) { create(:git_pipeline_schedule, :inactive, repository: repo, account: account) }

    describe '.active' do
      it 'returns only active schedules' do
        expect(described_class.active).to include(active_schedule)
        expect(described_class.active).not_to include(inactive_schedule)
      end
    end

    describe '.inactive' do
      it 'returns only inactive schedules' do
        expect(described_class.inactive).to include(inactive_schedule)
        expect(described_class.inactive).not_to include(active_schedule)
      end
    end

    describe '.due' do
      let!(:due_schedule) do
        schedule = create(:git_pipeline_schedule, :active, repository: repo, account: account)
        schedule.update_column(:next_run_at, 1.hour.ago)
        schedule
      end

      it 'returns active schedules with next_run_at in the past' do
        expect(described_class.due).to include(due_schedule)
        expect(described_class.due).not_to include(active_schedule)
      end
    end

    describe '.upcoming' do
      it 'returns active schedules with future next_run_at ordered by next_run_at' do
        result = described_class.upcoming
        expect(result).to include(active_schedule)
        expect(result).not_to include(inactive_schedule)
      end
    end

    describe '.for_repository' do
      it 'filters by repository' do
        expect(described_class.for_repository(repo.id)).to include(active_schedule)
      end
    end

    describe '.by_status' do
      let!(:successful_schedule) { create(:git_pipeline_schedule, :with_history, repository: repo, account: account) }

      it 'filters by last_run_status' do
        expect(described_class.by_status('success')).to include(successful_schedule)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create :calculate_next_run' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
      let(:repo) { create(:git_repository, credential: credential, account: account) }

      it 'sets next_run_at on creation' do
        schedule = create(:git_pipeline_schedule, repository: repo, account: account)
        expect(schedule.next_run_at).to be_present
      end
    end
  end

  describe 'instance methods' do
    describe '#active? and #inactive?' do
      it 'returns correct boolean for is_active state' do
        active = build(:git_pipeline_schedule, :active)
        inactive = build(:git_pipeline_schedule, :inactive)

        expect(active.active?).to be true
        expect(active.inactive?).to be false
        expect(inactive.active?).to be false
        expect(inactive.inactive?).to be true
      end
    end

    describe '#activate!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
      let(:repo) { create(:git_repository, credential: credential, account: account) }
      let(:schedule) { create(:git_pipeline_schedule, :inactive, :failing, repository: repo, account: account) }

      it 'activates the schedule and resets failures' do
        schedule.activate!
        expect(schedule.is_active).to be true
        expect(schedule.consecutive_failures).to eq(0)
        expect(schedule.next_run_at).to be_present
      end
    end

    describe '#deactivate!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
      let(:repo) { create(:git_repository, credential: credential, account: account) }
      let(:schedule) { create(:git_pipeline_schedule, :active, repository: repo, account: account) }

      it 'deactivates the schedule' do
        schedule.deactivate!
        expect(schedule.is_active).to be false
      end
    end

    describe '#success_rate' do
      it 'calculates success percentage' do
        schedule = build(:git_pipeline_schedule, run_count: 100, success_count: 90, failure_count: 10)
        expect(schedule.success_rate).to eq(90.0)
      end

      it 'returns 0 when no runs' do
        schedule = build(:git_pipeline_schedule, run_count: 0)
        expect(schedule.success_rate).to eq(0.0)
      end
    end

    describe '#failure_rate' do
      it 'calculates failure percentage' do
        schedule = build(:git_pipeline_schedule, run_count: 100, success_count: 90, failure_count: 10)
        expect(schedule.failure_rate).to eq(10.0)
      end

      it 'returns 0 when no runs' do
        schedule = build(:git_pipeline_schedule, run_count: 0)
        expect(schedule.failure_rate).to eq(0.0)
      end
    end

    describe '#overdue?' do
      it 'returns true for active schedules with past next_run_at' do
        schedule = build(:git_pipeline_schedule, is_active: true, next_run_at: 1.hour.ago)
        expect(schedule.overdue?).to be true
      end

      it 'returns false for inactive schedules' do
        schedule = build(:git_pipeline_schedule, is_active: false, next_run_at: 1.hour.ago)
        expect(schedule.overdue?).to be false
      end

      it 'returns false for schedules with future next_run_at' do
        schedule = build(:git_pipeline_schedule, is_active: true, next_run_at: 1.hour.from_now)
        expect(schedule.overdue?).to be false
      end
    end

    describe '#record_run!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
      let(:repo) { create(:git_repository, credential: credential, account: account) }
      let(:schedule) { create(:git_pipeline_schedule, run_count: 10, success_count: 8, failure_count: 2, consecutive_failures: 1, repository: repo, account: account) }

      it 'records successful run' do
        schedule.record_run!('success')
        expect(schedule.run_count).to eq(11)
        expect(schedule.success_count).to eq(9)
        expect(schedule.consecutive_failures).to eq(0)
        expect(schedule.last_run_status).to eq('success')
        expect(schedule.last_run_at).to be_within(1.second).of(Time.current)
      end

      it 'records failed run' do
        schedule.record_run!('failure')
        expect(schedule.run_count).to eq(11)
        expect(schedule.failure_count).to eq(3)
        expect(schedule.consecutive_failures).to eq(2)
        expect(schedule.last_run_status).to eq('failure')
      end

      it 'records pipeline reference when provided' do
        pipeline = create(:git_pipeline, repository: repo, account: account)
        schedule.record_run!('success', pipeline)
        expect(schedule.last_pipeline_id).to eq(pipeline.id)
      end

      it 'recalculates next_run_at' do
        schedule.record_run!('success')
        expect(schedule.next_run_at).to be_present
        expect(schedule.next_run_at).to be > Time.current
      end
    end

    describe '#cron_schedule' do
      it 'parses cron expression using Fugit' do
        schedule = build(:git_pipeline_schedule, cron_expression: '0 9 * * *')
        expect(schedule.cron_schedule).to be_a(Fugit::Cron)
      end
    end

    describe '#human_schedule' do
      it 'returns human-readable schedule description' do
        schedule = build(:git_pipeline_schedule, cron_expression: '0 9 * * *')
        expect(schedule.human_schedule).to be_a(String)
        expect(schedule.human_schedule).not_to eq('Invalid schedule')
      end

      it 'returns fallback for invalid expressions' do
        schedule = build(:git_pipeline_schedule)
        allow(schedule).to receive(:cron_schedule).and_return(nil)
        expect(schedule.human_schedule).to eq('Invalid schedule')
      end
    end

    describe '#next_runs' do
      it 'returns upcoming run times' do
        schedule = build(:git_pipeline_schedule, cron_expression: '0 * * * *', timezone: 'UTC')
        runs = schedule.next_runs(3)
        expect(runs.length).to eq(3)
        expect(runs).to all(be_a(Time))
        expect(runs[0]).to be < runs[1]
        expect(runs[1]).to be < runs[2]
      end

      it 'returns empty array when cron_schedule is nil' do
        schedule = build(:git_pipeline_schedule)
        allow(schedule).to receive(:cron_schedule).and_return(nil)
        expect(schedule.next_runs).to eq([])
      end
    end
  end

  describe 'class methods' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    describe '.due_for_execution' do
      let!(:due_schedule) do
        schedule = create(:git_pipeline_schedule, :active, repository: repo, account: account)
        schedule.update_column(:next_run_at, 1.hour.ago)
        schedule
      end
      let!(:future_schedule) { create(:git_pipeline_schedule, :active, repository: repo, account: account) }
      let!(:inactive_schedule) do
        schedule = create(:git_pipeline_schedule, :inactive, repository: repo, account: account)
        schedule.update_column(:next_run_at, 1.hour.ago)
        schedule
      end

      it 'returns active schedules due for execution' do
        result = described_class.due_for_execution
        expect(result).to include(due_schedule)
        expect(result).not_to include(future_schedule, inactive_schedule)
      end
    end

    describe '.with_failures' do
      let!(:failing_schedule) { create(:git_pipeline_schedule, :failing, repository: repo, account: account) }
      let!(:healthy_schedule) { create(:git_pipeline_schedule, consecutive_failures: 0, repository: repo, account: account) }

      it 'returns schedules with consecutive failures' do
        result = described_class.with_failures
        expect(result).to include(failing_schedule)
        expect(result).not_to include(healthy_schedule)
      end
    end
  end
end
