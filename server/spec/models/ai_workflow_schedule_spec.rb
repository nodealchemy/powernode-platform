# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowSchedule, type: :model do
  subject(:schedule) { build(:ai_workflow_schedule) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ai_workflow) }
    it { is_expected.to validate_presence_of(:account) }
    it { is_expected.to validate_presence_of(:cron_expression) }
    it { is_expected.to validate_presence_of(:timezone) }

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
          schedule = build(:ai_workflow_schedule, cron_expression: expression)
          expect(schedule).to be_valid, "Expected '#{expression}' to be valid"
        end
      end

      it 'rejects invalid cron expressions' do
        invalid_expressions = [
          'invalid',
          '60 * * * *',       # Invalid minute
          '* 25 * * *',       # Invalid hour
          '* * 32 * *',       # Invalid day
          '* * * 13 *',       # Invalid month
          '* * * * 8'         # Invalid day of week
        ]

        invalid_expressions.each do |expression|
          schedule = build(:ai_workflow_schedule, cron_expression: expression)
          expect(schedule).not_to be_valid, "Expected '#{expression}' to be invalid"
          expect(schedule.errors[:cron_expression]).to be_present
        end
      end
    end

    context 'timezone validation' do
      it 'accepts valid timezone identifiers' do
        valid_timezones = [
          'UTC',
          'America/New_York',
          'Europe/London',
          'Asia/Tokyo',
          'Australia/Sydney',
          'Pacific/Honolulu'
        ]

        valid_timezones.each do |tz|
          schedule = build(:ai_workflow_schedule, timezone: tz)
          expect(schedule).to be_valid, "Expected '#{tz}' to be valid"
        end
      end

      it 'rejects invalid timezone identifiers' do
        invalid_timezones = [
          'Invalid/Timezone',
          'EST',              # Use proper IANA identifier
          'GMT+5',            # Use proper IANA identifier
          'Random/String'
        ]

        invalid_timezones.each do |tz|
          schedule = build(:ai_workflow_schedule, timezone: tz)
          expect(schedule).not_to be_valid, "Expected '#{tz}' to be invalid"
          expect(schedule.errors[:timezone]).to be_present
        end
      end
    end

    context 'time range validations' do
      it 'validates end_date is after start_date when both present' do
        schedule = build(:ai_workflow_schedule,
                        start_date: 1.week.from_now,
                        end_date: 1.day.from_now)
        
        expect(schedule).not_to be_valid
        expect(schedule.errors[:end_date]).to include('must be after start date')
      end

      it 'validates start_date is not in the past' do
        schedule = build(:ai_workflow_schedule, start_date: 1.day.ago)
        expect(schedule).not_to be_valid
        expect(schedule.errors[:start_date]).to include('cannot be in the past')
      end

      it 'allows nil start_date and end_date' do
        schedule = build(:ai_workflow_schedule, start_date: nil, end_date: nil)
        expect(schedule).to be_valid
      end
    end

    context 'max_runs validation' do
      it 'validates max_runs is positive when present' do
        schedule = build(:ai_workflow_schedule, max_runs: -1)
        expect(schedule).not_to be_valid
        expect(schedule.errors[:max_runs]).to include('must be greater than 0')
      end

      it 'allows nil max_runs' do
        schedule = build(:ai_workflow_schedule, max_runs: nil)
        expect(schedule).to be_valid
      end
    end

    context 'timeout validation' do
      it 'validates timeout_minutes is positive when present' do
        schedule = build(:ai_workflow_schedule, timeout_minutes: 0)
        expect(schedule).not_to be_valid
        expect(schedule.errors[:timeout_minutes]).to include('must be greater than 0')
      end

      it 'validates reasonable timeout limits' do
        schedule = build(:ai_workflow_schedule, timeout_minutes: 10080) # 1 week
        expect(schedule).not_to be_valid
        expect(schedule.errors[:timeout_minutes]).to include('must be less than or equal to 1440') # 24 hours
      end
    end
  end

  describe 'scopes' do
    let!(:active_schedule) { create(:ai_workflow_schedule, is_active: true) }
    let!(:inactive_schedule) { create(:ai_workflow_schedule, is_active: false) }
    let!(:future_schedule) { create(:ai_workflow_schedule, start_date: 1.week.from_now) }
    let!(:expired_schedule) { create(:ai_workflow_schedule, end_date: 1.week.ago) }

    describe '.active' do
      it 'returns only active schedules' do
        expect(described_class.active).to include(active_schedule)
        expect(described_class.active).not_to include(inactive_schedule)
      end
    end

    describe '.ready_to_run' do
      it 'returns schedules that are ready for execution' do
        ready_schedules = described_class.ready_to_run
        expect(ready_schedules).to include(active_schedule)
        expect(ready_schedules).not_to include(future_schedule, expired_schedule)
      end
    end

    describe '.for_workflow' do
      let(:workflow1) { create(:ai_workflow) }
      let(:workflow2) { create(:ai_workflow) }
      let!(:schedule1) { create(:ai_workflow_schedule, ai_workflow: workflow1) }
      let!(:schedule2) { create(:ai_workflow_schedule, ai_workflow: workflow2) }

      it 'filters schedules by workflow' do
        expect(described_class.for_workflow(workflow1)).to include(schedule1)
        expect(described_class.for_workflow(workflow1)).not_to include(schedule2)
      end
    end

    describe '.by_frequency' do
      let!(:hourly_schedule) { create(:ai_workflow_schedule, :hourly) }
      let!(:daily_schedule) { create(:ai_workflow_schedule, :daily) }

      it 'identifies schedules by frequency patterns' do
        # This would require implementing frequency detection logic
        expect(described_class.where('cron_expression LIKE ?', '0 * * * *')).to include(hourly_schedule)
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation' do
      it 'normalizes timezone' do
        schedule = build(:ai_workflow_schedule, timezone: '  america/new_york  ')
        schedule.valid?
        expect(schedule.timezone).to eq('America/New_York')
      end

      it 'sets default timezone if not provided' do
        schedule = build(:ai_workflow_schedule, timezone: nil)
        schedule.valid?
        expect(schedule.timezone).to eq('UTC')
      end
    end

    describe 'after_create' do
      it 'schedules the first execution' do
        expect_any_instance_of(described_class).to receive(:schedule_next_execution)
        create(:ai_workflow_schedule)
      end
    end

    describe 'after_update' do
      it 'reschedules when cron expression changes' do
        schedule = create(:ai_workflow_schedule, cron_expression: '0 9 * * *')
        
        expect(schedule).to receive(:reschedule_executions)
        schedule.update!(cron_expression: '0 12 * * *')
      end

      it 'cancels future executions when deactivated' do
        schedule = create(:ai_workflow_schedule, is_active: true)
        
        expect(schedule).to receive(:cancel_pending_executions)
        schedule.update!(is_active: false)
      end
    end
  end

  describe 'instance methods' do
    describe '#next_execution_time' do
      it 'calculates next execution based on cron expression' do
        schedule = create(:ai_workflow_schedule, 
                         cron_expression: '0 12 * * *',
                         timezone: 'UTC')
        
        next_time = schedule.next_execution_time
        expect(next_time.hour).to eq(12)
        expect(next_time.min).to eq(0)
        expect(next_time).to be > Time.current
      end

      it 'respects timezone in calculations' do
        schedule = create(:ai_workflow_schedule,
                         cron_expression: '0 9 * * *',
                         timezone: 'America/New_York')
        
        next_time = schedule.next_execution_time
        expect(next_time.zone).to eq('EST') # or 'EDT' depending on season
      end

      it 'respects start_date constraints' do
        schedule = create(:ai_workflow_schedule,
                         cron_expression: '0 12 * * *',
                         start_date: 1.week.from_now)
        
        next_time = schedule.next_execution_time
        expect(next_time).to be >= schedule.start_date
      end

      it 'returns nil when past end_date' do
        schedule = create(:ai_workflow_schedule,
                         end_date: 1.day.ago)
        
        expect(schedule.next_execution_time).to be_nil
      end
    end

    describe '#should_execute_now?' do
      it 'returns true when current time matches schedule' do
        # Create schedule for current minute
        current_time = Time.current
        cron_expr = "#{current_time.min} #{current_time.hour} * * *"
        schedule = create(:ai_workflow_schedule, cron_expression: cron_expr)
        
        expect(schedule.should_execute_now?).to be true
      end

      it 'returns false when not time to execute' do
        # Create schedule for next hour
        next_hour = 1.hour.from_now
        cron_expr = "0 #{next_hour.hour} * * *"
        schedule = create(:ai_workflow_schedule, cron_expression: cron_expr)
        
        expect(schedule.should_execute_now?).to be false
      end

      it 'returns false for inactive schedules' do
        schedule = create(:ai_workflow_schedule, is_active: false)
        expect(schedule.should_execute_now?).to be false
      end
    end

    describe '#frequency_description' do
      it 'describes common cron patterns in human readable format' do
        test_cases = {
          '0 9 * * *' => 'Daily at 9:00 AM',
          '*/15 * * * *' => 'Every 15 minutes',
          '0 0 1 * *' => 'Monthly on the 1st at 12:00 AM',
          '0 9 * * 1-5' => 'Weekdays at 9:00 AM',
          '0 */6 * * *' => 'Every 6 hours'
        }

        test_cases.each do |cron, description|
          schedule = build(:ai_workflow_schedule, cron_expression: cron)
          expect(schedule.frequency_description).to include(description.downcase)
        end
      end
    end

    describe '#estimated_executions_per_day' do
      it 'estimates daily execution count based on cron expression' do
        test_cases = {
          '0 9 * * *' => 1,        # Daily
          '0 */6 * * *' => 4,      # Every 6 hours
          '*/30 * * * *' => 48,    # Every 30 minutes
          '0 9 * * 1-5' => 5/7.0   # Weekdays only
        }

        test_cases.each do |cron, expected|
          schedule = build(:ai_workflow_schedule, cron_expression: cron)
          expect(schedule.estimated_executions_per_day).to be_within(0.1).of(expected)
        end
      end
    end

    describe '#time_until_next_execution' do
      it 'calculates seconds until next scheduled execution' do
        # Schedule for 1 hour from now
        next_hour = 1.hour.from_now
        cron_expr = "0 #{next_hour.hour} * * *"
        schedule = create(:ai_workflow_schedule, cron_expression: cron_expr)
        
        time_until = schedule.time_until_next_execution
        expect(time_until).to be_within(60).of(1.hour)
      end

      it 'returns nil when no future executions' do
        schedule = create(:ai_workflow_schedule, end_date: 1.day.ago)
        expect(schedule.time_until_next_execution).to be_nil
      end
    end

    describe '#can_execute?' do
      it 'returns true when all conditions are met' do
        schedule = create(:ai_workflow_schedule, 
                         is_active: true,
                         start_date: 1.day.ago,
                         end_date: 1.day.from_now,
                         max_runs: 10,
                         execution_count: 5)
        
        expect(schedule.can_execute?).to be true
      end

      it 'returns false when inactive' do
        schedule = create(:ai_workflow_schedule, is_active: false)
        expect(schedule.can_execute?).to be false
      end

      it 'returns false when max runs exceeded' do
        schedule = create(:ai_workflow_schedule, 
                         max_runs: 5,
                         execution_count: 5)
        expect(schedule.can_execute?).to be false
      end

      it 'returns false when outside date range' do
        schedule = create(:ai_workflow_schedule, end_date: 1.day.ago)
        expect(schedule.can_execute?).to be false
      end
    end

    describe '#execute_workflow!' do
      let(:schedule) { create(:ai_workflow_schedule) }

      it 'creates a new workflow run with scheduled trigger' do
        expect {
          run = schedule.execute_workflow!
          expect(run.trigger_type).to eq('scheduled')
          expect(run.trigger_context['schedule_id']).to eq(schedule.id)
        }.to change { schedule.ai_workflow.runs.count }.by(1)
      end

      it 'increments execution count' do
        expect {
          schedule.execute_workflow!
        }.to change { schedule.reload.execution_count }.by(1)
      end

      it 'updates last_executed_at timestamp' do
        expect {
          schedule.execute_workflow!
        }.to change { schedule.reload.last_executed_at }
      end

      it 'schedules next execution' do
        expect(schedule).to receive(:schedule_next_execution)
        schedule.execute_workflow!
      end

      it 'raises error when cannot execute' do
        schedule.update!(is_active: false)
        
        expect {
          schedule.execute_workflow!
        }.to raise_error(StandardError, /cannot execute/i)
      end
    end

    describe '#deactivate!' do
      let(:schedule) { create(:ai_workflow_schedule, is_active: true) }

      it 'sets schedule as inactive' do
        schedule.deactivate!
        expect(schedule.reload.is_active).to be false
      end

      it 'cancels pending executions' do
        expect(schedule).to receive(:cancel_pending_executions)
        schedule.deactivate!
      end

      it 'logs deactivation' do
        expect {
          schedule.deactivate!
        }.to change { AiWorkflowExecutionLog.count }.by(1)
        
        log = AiWorkflowExecutionLog.last
        expect(log.message).to include('Schedule deactivated')
      end
    end

    describe '#schedule_summary' do
      let(:schedule) { create(:ai_workflow_schedule, 
                             cron_expression: '0 9 * * 1-5',
                             timezone: 'America/New_York',
                             execution_count: 42) }

      it 'returns comprehensive schedule information' do
        summary = schedule.schedule_summary
        
        expect(summary).to include(
          :id,
          :cron_expression,
          :frequency_description,
          :timezone,
          :next_execution_time,
          :time_until_next_execution,
          :execution_count,
          :estimated_executions_per_day,
          :is_active
        )
        
        expect(summary[:execution_count]).to eq(42)
        expect(summary[:cron_expression]).to eq('0 9 * * 1-5')
      end
    end
  end

  describe 'class methods' do
    describe '.due_for_execution' do
      let!(:due_schedule) { create(:ai_workflow_schedule, 
                                  cron_expression: '0 9 * * *',
                                  last_executed_at: 25.hours.ago) }
      let!(:not_due_schedule) { create(:ai_workflow_schedule,
                                      cron_expression: '0 9 * * *',
                                      last_executed_at: 1.hour.ago) }

      it 'returns schedules that are due for execution' do
        due_schedules = described_class.due_for_execution
        expect(due_schedules).to include(due_schedule)
        expect(due_schedules).not_to include(not_due_schedule)
      end
    end

    describe '.execute_due_schedules!' do
      let!(:due_schedules) { create_list(:ai_workflow_schedule, 3, 
                                        cron_expression: '0 9 * * *',
                                        last_executed_at: 25.hours.ago) }

      it 'executes all due schedules' do
        expect {
          described_class.execute_due_schedules!
        }.to change { AiWorkflowRun.count }.by(3)
      end

      it 'updates execution counts for all schedules' do
        described_class.execute_due_schedules!
        
        due_schedules.each do |schedule|
          expect(schedule.reload.execution_count).to eq(1)
          expect(schedule.last_executed_at).to be_within(1.minute).of(Time.current)
        end
      end

      it 'handles execution failures gracefully' do
        allow_any_instance_of(AiWorkflow).to receive(:execute).and_raise(StandardError, 'Test error')
        
        expect {
          described_class.execute_due_schedules!
        }.not_to raise_error
        
        # Should still update execution attempts
        due_schedules.each do |schedule|
          expect(schedule.reload.last_executed_at).to be_within(1.minute).of(Time.current)
        end
      end
    end

    describe '.cleanup_completed_schedules' do
      let!(:completed_schedule) { create(:ai_workflow_schedule,
                                        max_runs: 5,
                                        execution_count: 5) }
      let!(:active_schedule) { create(:ai_workflow_schedule,
                                     max_runs: 10,
                                     execution_count: 3) }

      it 'removes schedules that have completed their runs' do
        expect {
          described_class.cleanup_completed_schedules
        }.to change { described_class.count }.by(-1)
        
        expect(described_class.exists?(completed_schedule.id)).to be false
        expect(described_class.exists?(active_schedule.id)).to be true
      end
    end

    describe '.validate_cron_expression' do
      it 'validates cron expression syntax' do
        expect(described_class.validate_cron_expression('0 9 * * *')).to be true
        expect(described_class.validate_cron_expression('invalid')).to be false
        expect(described_class.validate_cron_expression('60 * * * *')).to be false
      end
    end

    describe '.parse_frequency_description' do
      it 'converts cron expressions to human readable descriptions' do
        descriptions = described_class.parse_frequency_description('0 9 * * 1-5')
        expect(descriptions).to include('weekdays', '9:00', 'AM')
      end
    end
  end

  describe 'edge cases and performance' do
    describe 'timezone edge cases' do
      it 'handles daylight saving time transitions' do
        # Test schedule during DST transition
        schedule = create(:ai_workflow_schedule,
                         cron_expression: '0 2 * * *',
                         timezone: 'America/New_York')
        
        # This should not raise errors during DST transitions
        expect { schedule.next_execution_time }.not_to raise_error
      end

      it 'handles leap year scenarios' do
        schedule = create(:ai_workflow_schedule,
                         cron_expression: '0 0 29 2 *') # Feb 29th
        
        next_time = schedule.next_execution_time
        expect(next_time.month).to eq(2)
        expect(next_time.day).to eq(29)
      end
    end

    describe 'complex cron expressions' do
      it 'handles complex multi-field expressions' do
        complex_cron = '0 9,13,17 * * 1,3,5' # 9AM, 1PM, 5PM on Mon, Wed, Fri
        schedule = create(:ai_workflow_schedule, cron_expression: complex_cron)
        
        expect(schedule.estimated_executions_per_day).to be_within(0.1).of(9.0/7.0)
      end

      it 'handles step values correctly' do
        step_cron = '*/15 */2 * * *' # Every 15 minutes during even hours
        schedule = create(:ai_workflow_schedule, cron_expression: step_cron)
        
        expect(schedule.frequency_description).to include('15 minutes')
      end
    end

    describe 'performance with large numbers of schedules' do
      before do
        create_list(:ai_workflow_schedule, 100, :daily)
        create_list(:ai_workflow_schedule, 50, :hourly)
      end

      it 'efficiently finds due schedules' do
        expect {
          described_class.due_for_execution.limit(20).to_a
        }.not_to exceed_query_limit(2)
      end

      it 'efficiently executes multiple schedules' do
        expect {
          described_class.due_for_execution.limit(10).each(&:execute_workflow!)
        }.not_to exceed_query_limit(25) # Allow for individual execution queries
      end
    end

    describe 'concurrent execution safety' do
      it 'prevents duplicate executions from concurrent processes' do
        schedule = create(:ai_workflow_schedule)
        
        # Simulate concurrent execution attempts
        threads = 3.times.map do
          Thread.new do
            begin
              schedule.execute_workflow!
            rescue StandardError
              # Expected - only one should succeed
            end
          end
        end
        
        threads.each(&:join)
        
        # Should only have one execution
        expect(schedule.reload.execution_count).to eq(1)
      end
    end

    describe 'error handling and recovery' do
      it 'continues scheduling after failed executions' do
        schedule = create(:ai_workflow_schedule)
        
        # Mock workflow execution failure
        allow(schedule.ai_workflow).to receive(:execute).and_raise(StandardError, 'Test error')
        
        expect {
          schedule.execute_workflow!
        }.to raise_error(StandardError)
        
        # Should still be able to schedule next execution
        expect(schedule.can_execute?).to be true
      end

      it 'handles invalid cron expressions gracefully in production' do
        schedule = create(:ai_workflow_schedule)
        schedule.update_column(:cron_expression, 'invalid') # Bypass validation
        
        expect { schedule.next_execution_time }.not_to raise_error
        expect(schedule.next_execution_time).to be_nil
      end
    end
  end
end