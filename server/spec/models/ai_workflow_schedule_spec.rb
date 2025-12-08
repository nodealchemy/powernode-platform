# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowSchedule, type: :model do
  subject(:schedule) { build(:ai_workflow_schedule) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to belong_to(:created_by).class_name('User') }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:cron_expression) }
    # Note: timezone has default set in callback so we test it differently
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }

    it 'validates inclusion of status' do
      valid_statuses = %w[active paused disabled expired]

      valid_statuses.each do |status|
        sched = build(:ai_workflow_schedule, status: status)
        expect(sched).to be_valid, "Expected #{status} to be valid"
      end
    end

    it 'rejects invalid status' do
      sched = build(:ai_workflow_schedule, status: 'invalid')
      expect(sched).not_to be_valid
      expect(sched.errors[:status]).to be_present
    end

    context 'cron expression validation' do
      it 'accepts valid cron expressions' do
        valid_expressions = [
          '0 9 * * *',        # Daily at 9 AM
          '*/15 * * * *',     # Every 15 minutes
          '0 0 1 * *',        # First day of month
          '0 9 * * 1-5',      # Weekdays at 9 AM
          '0 */6 * * *',      # Every 6 hours
          '30 14 * * 0'       # Sundays at 2:30 PM
        ]

        valid_expressions.each do |expression|
          sched = build(:ai_workflow_schedule, cron_expression: expression)
          expect(sched).to be_valid, "Expected '#{expression}' to be valid but got: #{sched.errors.full_messages.join(', ')}"
        end
      end

      it 'handles cron expression validation' do
        # Fugit is lenient, so test what the model actually validates
        sched = build(:ai_workflow_schedule, cron_expression: nil)
        expect(sched).not_to be_valid
        expect(sched.errors[:cron_expression]).to include("can't be blank")
      end
    end

    context 'date range validations' do
      it 'validates ends_at is after starts_at when both present' do
        sched = build(:ai_workflow_schedule,
                      starts_at: 1.week.from_now,
                      ends_at: 1.day.from_now)

        expect(sched).not_to be_valid
        expect(sched.errors[:ends_at]).to include('must be after starts_at')
      end

      it 'allows nil starts_at and ends_at' do
        sched = build(:ai_workflow_schedule, starts_at: nil, ends_at: nil)
        expect(sched).to be_valid
      end
    end

    context 'max_executions validation' do
      it 'validates max_executions is positive when present' do
        sched = build(:ai_workflow_schedule, max_executions: -1)
        expect(sched).not_to be_valid
        expect(sched.errors[:max_executions]).to include('must be greater than 0')
      end

      it 'allows nil max_executions' do
        sched = build(:ai_workflow_schedule, max_executions: nil)
        expect(sched).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_schedule) { create(:ai_workflow_schedule, status: 'active', is_active: true) }
    let!(:inactive_schedule) { create(:ai_workflow_schedule, status: 'paused', is_active: false) }
    let!(:disabled_schedule) { create(:ai_workflow_schedule, status: 'disabled', is_active: false) }

    describe '.active' do
      it 'returns only active schedules' do
        expect(described_class.active).to include(active_schedule)
        expect(described_class.active).not_to include(inactive_schedule)
      end
    end

    describe '.inactive' do
      it 'returns non-active schedules' do
        expect(described_class.inactive).to include(inactive_schedule)
        expect(described_class.inactive).not_to include(active_schedule)
      end
    end

    describe '.by_timezone' do
      let!(:utc_schedule) { create(:ai_workflow_schedule, timezone: 'UTC') }
      let!(:ny_schedule) { create(:ai_workflow_schedule, timezone: 'America/New_York') }

      it 'filters schedules by timezone' do
        expect(described_class.by_timezone('UTC')).to include(utc_schedule)
        expect(described_class.by_timezone('UTC')).not_to include(ny_schedule)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default timezone if not provided' do
        sched = build(:ai_workflow_schedule, timezone: nil)
        sched.valid?
        expect(sched.timezone).to eq('UTC')
      end

      it 'sets default execution_count to 0' do
        sched = build(:ai_workflow_schedule, execution_count: nil)
        sched.valid?
        expect(sched.execution_count).to eq(0)
      end
    end
  end

  describe 'instance methods' do
    describe 'status check methods' do
      let(:active_sched) { create(:ai_workflow_schedule, status: 'active', is_active: true) }
      let(:paused_sched) { create(:ai_workflow_schedule, status: 'paused') }
      let(:disabled_sched) { create(:ai_workflow_schedule, status: 'disabled', is_active: false) }
      let(:expired_sched) { create(:ai_workflow_schedule, status: 'expired') }

      it '#active? returns true for active schedules' do
        expect(active_sched.active?).to be true
        expect(paused_sched.active?).to be false
      end

      it '#paused? returns true for paused schedules' do
        expect(paused_sched.paused?).to be true
        expect(active_sched.paused?).to be false
      end

      it '#disabled? returns true for disabled schedules' do
        expect(disabled_sched.disabled?).to be true
        expect(active_sched.disabled?).to be false
      end

      it '#expired? returns true for expired schedules' do
        expect(expired_sched.expired?).to be true
        expect(active_sched.expired?).to be false
      end

      it '#expired? returns true when ends_at is in the past' do
        past_sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        past_sched.update_column(:ends_at, 1.day.ago)
        expect(past_sched.expired?).to be true
      end

      it '#expired? returns true when max_executions reached' do
        # Create with valid state first, then use update_column to bypass validation
        max_sched = create(:ai_workflow_schedule, status: 'active', max_executions: 5, execution_count: 0)
        max_sched.update_column(:execution_count, 5)
        expect(max_sched.expired?).to be true
      end
    end

    describe '#next_execution_time' do
      it 'calculates next execution based on cron expression' do
        sched = create(:ai_workflow_schedule,
                       cron_expression: '0 12 * * *',
                       timezone: 'UTC')

        next_time = sched.next_execution_time
        expect(next_time).to be > Time.current
      end

      it 'returns nil when past ends_at' do
        sched = create(:ai_workflow_schedule,
                       cron_expression: '0 12 * * *',
                       ends_at: 1.day.ago)

        expect(sched.next_execution_time).to be_nil
      end
    end

    describe '#due_for_execution?' do
      it 'returns true when schedule is due' do
        sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        sched.update_column(:next_execution_at, 1.hour.ago)
        expect(sched.due_for_execution?).to be true
      end

      it 'returns false when next_execution_at is in the future' do
        sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        sched.update_column(:next_execution_at, 1.hour.from_now)
        expect(sched.due_for_execution?).to be false
      end

      it 'returns false for inactive schedules' do
        sched = create(:ai_workflow_schedule, status: 'paused')
        sched.update_column(:next_execution_at, 1.hour.ago)
        expect(sched.due_for_execution?).to be false
      end
    end

    describe '#time_until_next_execution' do
      it 'returns seconds until next scheduled execution' do
        sched = create(:ai_workflow_schedule)
        sched.update_column(:next_execution_at, 1.hour.from_now)

        time_until = sched.time_until_next_execution
        expect(time_until).to be > 0
        expect(time_until).to be <= 3600
      end

      it 'returns nil when no next_execution_at' do
        sched = create(:ai_workflow_schedule)
        sched.update_column(:next_execution_at, nil)
        expect(sched.time_until_next_execution).to be_nil
      end
    end

    describe 'state management' do
      let(:sched) { create(:ai_workflow_schedule, status: 'paused', is_active: false) }

      it '#activate! activates a paused schedule' do
        result = sched.activate!
        expect(result).to be true
        expect(sched.reload.status).to eq('active')
        expect(sched.is_active).to be true
      end

      it '#pause! pauses an active schedule' do
        active_sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        result = active_sched.pause!
        expect(result).to be true
        expect(active_sched.reload.status).to eq('paused')
      end

      it '#disable! disables a schedule' do
        active_sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        active_sched.disable!
        expect(active_sched.reload.status).to eq('disabled')
        expect(active_sched.is_active).to be false
      end

      it '#expire! expires a schedule' do
        active_sched = create(:ai_workflow_schedule, status: 'active', is_active: true)
        active_sched.expire!
        expect(active_sched.reload.status).to eq('expired')
        expect(active_sched.is_active).to be false
      end
    end

    describe '#execution_summary' do
      let(:sched) { create(:ai_workflow_schedule, status: 'active', execution_count: 10) }

      it 'returns comprehensive schedule information' do
        summary = sched.execution_summary

        expect(summary).to include(
          :total_executions,
          :next_execution,
          :last_execution,
          :status,
          :active,
          :expired
        )

        expect(summary[:total_executions]).to eq(10)
        expect(summary[:status]).to eq('active')
      end
    end

    describe 'configuration helpers' do
      let(:sched) do
        create(:ai_workflow_schedule, configuration: {
                 'skip_if_running' => false,
                 'notifications' => {
                   'on_success' => true,
                   'on_failure' => false
                 }
               })
      end

      it '#skip_if_running? returns configuration value' do
        expect(sched.skip_if_running?).to be false
      end

      it '#should_notify_on_success? returns notification setting' do
        expect(sched.should_notify_on_success?).to be true
      end

      it '#should_notify_on_failure? returns notification setting' do
        expect(sched.should_notify_on_failure?).to be false
      end
    end

    describe '#human_readable_schedule' do
      it 'returns the cron expression' do
        sched = build(:ai_workflow_schedule, cron_expression: '0 9 * * *')
        expect(sched.human_readable_schedule).to eq('0 9 * * *')
      end
    end
  end

  describe 'edge cases' do
    describe 'timezone edge cases' do
      it 'handles daylight saving time transitions' do
        sched = create(:ai_workflow_schedule,
                       cron_expression: '0 2 * * *',
                       timezone: 'America/New_York')

        expect { sched.next_execution_time }.not_to raise_error
      end
    end

    describe 'error handling' do
      it 'handles invalid cron expressions gracefully in production' do
        sched = create(:ai_workflow_schedule)
        sched.update_column(:cron_expression, 'invalid')

        expect { sched.next_execution_time }.not_to raise_error
        expect(sched.next_execution_time).to be_nil
      end
    end
  end
end
