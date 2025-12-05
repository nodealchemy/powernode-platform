# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowTrigger, type: :model do
  subject(:trigger) { build(:ai_workflow_trigger) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to have_many(:executions).class_name('AiWorkflowRun').with_foreign_key('trigger_id').dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:ai_workflow) }
    it { is_expected.to validate_presence_of(:trigger_type) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_inclusion_of(:trigger_type).in_array(%w[webhook event schedule api data_change file_system time_based conditional complex_event]) }

    context 'webhook trigger validations' do
      it 'requires webhook_path for webhook triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'webhook', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must contain webhook_path for webhook triggers')
      end

      it 'validates webhook_path format' do
        trigger = build(:ai_workflow_trigger, :webhook_trigger, 
                       configuration: { webhook_path: 'invalid-path' })
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('webhook_path must start with /')
      end

      it 'validates signature verification settings' do
        config = {
          webhook_path: '/webhooks/test',
          signature_verification: true,
          signature_header: '',
          secret_key: ''
        }
        
        trigger = build(:ai_workflow_trigger, :webhook_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('signature_header and secret_key required when signature_verification is enabled')
      end

      it 'accepts valid webhook configuration' do
        trigger = build(:ai_workflow_trigger, :webhook_trigger)
        expect(trigger).to be_valid
      end
    end

    context 'event trigger validations' do
      it 'requires event_types for event triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must contain event_types for event triggers')
      end

      it 'validates event_types is an array' do
        config = { event_types: 'not_an_array' }
        trigger = build(:ai_workflow_trigger, :event_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('event_types must be an array')
      end

      it 'validates filter_conditions structure' do
        config = {
          event_types: ['user.created'],
          filter_conditions: 'invalid_structure'
        }
        
        trigger = build(:ai_workflow_trigger, :event_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('filter_conditions must be a hash')
      end
    end

    context 'schedule trigger validations' do
      it 'requires cron_expression for schedule triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'schedule', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must contain cron_expression for schedule triggers')
      end

      it 'validates cron_expression format' do
        config = { cron_expression: 'invalid_cron' }
        trigger = build(:ai_workflow_trigger, :schedule_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('invalid cron expression format')
      end

      it 'accepts valid cron expressions' do
        valid_crons = ['0 9 * * *', '*/15 * * * *', '0 0 1 * *']
        
        valid_crons.each do |cron|
          config = { cron_expression: cron, timezone: 'UTC' }
          trigger = build(:ai_workflow_trigger, :schedule_trigger, configuration: config)
          expect(trigger).to be_valid, "Expected '#{cron}' to be valid"
        end
      end
    end

    context 'api trigger validations' do
      it 'requires api_endpoints for api triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'api', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must contain api_endpoints for api triggers')
      end

      it 'validates rate_limiting structure' do
        config = {
          api_endpoints: ['/api/test'],
          rate_limiting: 'invalid_structure'
        }
        
        trigger = build(:ai_workflow_trigger, :api_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('rate_limiting must be a hash')
      end
    end

    context 'conditional trigger validations' do
      it 'requires conditions for conditional triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'conditional', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must contain conditions for conditional triggers')
      end

      it 'validates conditions structure' do
        config = { conditions: 'invalid_structure' }
        trigger = build(:ai_workflow_trigger, :conditional_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('conditions must contain operator and rules')
      end

      it 'validates data_sources configuration' do
        config = {
          conditions: { operator: 'AND', rules: [] },
          data_sources: 'invalid'
        }
        
        trigger = build(:ai_workflow_trigger, :conditional_trigger, configuration: config)
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('data_sources must be a hash')
      end
    end
  end

  describe 'scopes' do
    let!(:active_trigger) { create(:ai_workflow_trigger, is_active: true) }
    let!(:inactive_trigger) { create(:ai_workflow_trigger, is_active: false) }
    let!(:webhook_trigger) { create(:ai_workflow_trigger, :webhook_trigger) }
    let!(:event_trigger) { create(:ai_workflow_trigger, :event_trigger) }
    let!(:schedule_trigger) { create(:ai_workflow_trigger, :schedule_trigger) }

    describe '.active' do
      it 'returns only active triggers' do
        expect(described_class.active).to include(active_trigger)
        expect(described_class.active).not_to include(inactive_trigger)
      end
    end

    describe '.by_type' do
      it 'filters triggers by type' do
        expect(described_class.by_type('webhook')).to include(webhook_trigger)
        expect(described_class.by_type('webhook')).not_to include(event_trigger)
      end
    end

    describe '.for_workflow' do
      let(:workflow1) { create(:ai_workflow) }
      let(:workflow2) { create(:ai_workflow) }
      let!(:trigger1) { create(:ai_workflow_trigger, ai_workflow: workflow1) }
      let!(:trigger2) { create(:ai_workflow_trigger, ai_workflow: workflow2) }

      it 'filters triggers by workflow' do
        expect(described_class.for_workflow(workflow1)).to include(trigger1)
        expect(described_class.for_workflow(workflow1)).not_to include(trigger2)
      end
    end

    describe '.due_for_execution' do
      let!(:due_schedule) { create(:ai_workflow_trigger, :schedule_trigger,
                                  configuration: { cron_expression: '0 9 * * *', timezone: 'UTC' },
                                  last_triggered_at: 25.hours.ago) }
      let!(:not_due_schedule) { create(:ai_workflow_trigger, :schedule_trigger,
                                      last_triggered_at: 1.hour.ago) }

      it 'returns schedule triggers that are due' do
        due_triggers = described_class.due_for_execution
        expect(due_triggers).to include(due_schedule)
        expect(due_triggers).not_to include(not_due_schedule)
      end
    end

    describe '.webhook_endpoints' do
      it 'returns unique webhook paths' do
        create(:ai_workflow_trigger, :webhook_trigger, 
               configuration: { webhook_path: '/webhooks/github' })
        create(:ai_workflow_trigger, :webhook_trigger,
               configuration: { webhook_path: '/webhooks/slack' })
        
        endpoints = described_class.webhook_endpoints
        expect(endpoints).to include('/webhooks/github', '/webhooks/slack')
      end
    end
  end

  describe 'callbacks and lifecycle' do
    describe 'before_validation' do
      it 'normalizes trigger_type' do
        trigger = build(:ai_workflow_trigger, trigger_type: '  WEBHOOK  ')
        trigger.valid?
        expect(trigger.trigger_type).to eq('webhook')
      end

      it 'generates unique name if not provided' do
        trigger = build(:ai_workflow_trigger, name: nil, trigger_type: 'webhook')
        trigger.valid?
        expect(trigger.name).to match(/^Webhook Trigger/)
      end
    end

    describe 'after_create' do
      it 'registers webhook endpoint for webhook triggers' do
        expect_any_instance_of(described_class).to receive(:register_webhook_endpoint)
        create(:ai_workflow_trigger, :webhook_trigger)
      end

      it 'schedules next execution for schedule triggers' do
        expect_any_instance_of(described_class).to receive(:schedule_next_execution)
        create(:ai_workflow_trigger, :schedule_trigger)
      end

      it 'subscribes to events for event triggers' do
        expect_any_instance_of(described_class).to receive(:subscribe_to_events)
        create(:ai_workflow_trigger, :event_trigger)
      end
    end

    describe 'after_update' do
      it 'updates webhook registration when configuration changes' do
        trigger = create(:ai_workflow_trigger, :webhook_trigger)
        
        expect(trigger).to receive(:update_webhook_registration)
        trigger.update!(configuration: trigger.configuration.merge(webhook_path: '/new/path'))
      end

      it 'reschedules execution when schedule changes' do
        trigger = create(:ai_workflow_trigger, :schedule_trigger)
        
        expect(trigger).to receive(:reschedule_execution)
        trigger.update!(configuration: trigger.configuration.merge(cron_expression: '0 12 * * *'))
      end

      it 'cancels executions when deactivated' do
        trigger = create(:ai_workflow_trigger, is_active: true)
        
        expect(trigger).to receive(:cancel_pending_executions)
        trigger.update!(is_active: false)
      end
    end

    describe 'before_destroy' do
      it 'unregisters webhook endpoint' do
        trigger = create(:ai_workflow_trigger, :webhook_trigger)
        
        expect(trigger).to receive(:unregister_webhook_endpoint)
        trigger.destroy
      end

      it 'unsubscribes from events' do
        trigger = create(:ai_workflow_trigger, :event_trigger)
        
        expect(trigger).to receive(:unsubscribe_from_events)
        trigger.destroy
      end
    end
  end

  describe 'instance methods' do
    describe '#can_trigger?' do
      let(:trigger) { create(:ai_workflow_trigger, is_active: true) }

      it 'returns true for active triggers' do
        expect(trigger.can_trigger?).to be true
      end

      it 'returns false for inactive triggers' do
        trigger.update!(is_active: false)
        expect(trigger.can_trigger?).to be false
      end

      it 'checks rate limiting for high-frequency triggers' do
        trigger.update!(
          trigger_count: 1000,
          last_triggered_at: 30.seconds.ago,
          metadata: { rate_limit_per_minute: 60 }
        )
        
        expect(trigger.can_trigger?).to be false
      end

      it 'respects max triggers per day limit' do
        trigger.update!(
          trigger_count: 100,
          daily_trigger_count: 100,
          metadata: { max_triggers_per_day: 100 }
        )
        
        expect(trigger.can_trigger?).to be false
      end
    end

    describe '#trigger_workflow!' do
      let(:trigger) { create(:ai_workflow_trigger) }
      let(:trigger_data) { { event_type: 'test', data: { key: 'value' } } }

      it 'creates new workflow run' do
        expect {
          run = trigger.trigger_workflow!(trigger_data)
          expect(run.trigger_type).to eq(trigger.trigger_type)
          expect(run.trigger_context['trigger_id']).to eq(trigger.id)
          expect(run.trigger_context['trigger_data']).to eq(trigger_data)
        }.to change { trigger.ai_workflow.runs.count }.by(1)
      end

      it 'increments trigger counters' do
        expect {
          trigger.trigger_workflow!(trigger_data)
        }.to change { trigger.reload.trigger_count }.by(1)
         .and change { trigger.reload.daily_trigger_count }.by(1)
      end

      it 'updates last_triggered_at timestamp' do
        expect {
          trigger.trigger_workflow!(trigger_data)
        }.to change { trigger.reload.last_triggered_at }
      end

      it 'processes trigger data through configured mappings' do
        trigger.update!(configuration: trigger.configuration.merge(
          payload_transformation: {
            input_mapping: {
              'data.user_id' => 'workflow.input.user_id',
              'event_type' => 'workflow.input.event_type'
            }
          }
        ))
        
        run = trigger.trigger_workflow!(trigger_data)
        expect(run.input_variables['user_id']).to eq('value')
        expect(run.input_variables['event_type']).to eq('test')
      end

      it 'raises error when cannot trigger' do
        trigger.update!(is_active: false)
        
        expect {
          trigger.trigger_workflow!(trigger_data)
        }.to raise_error(StandardError, /cannot trigger/i)
      end

      it 'handles duplicate trigger prevention' do
        trigger.update!(configuration: trigger.configuration.merge(
          deduplication: {
            enabled: true,
            key_fields: ['event_type'],
            window_seconds: 60
          }
        ))
        
        # First trigger should succeed
        run1 = trigger.trigger_workflow!(trigger_data)
        expect(run1).to be_persisted
        
        # Duplicate within window should be prevented
        expect {
          trigger.trigger_workflow!(trigger_data)
        }.to raise_error(StandardError, /duplicate trigger/i)
      end
    end

    describe '#validate_trigger_data' do
      let(:trigger) { create(:ai_workflow_trigger, :webhook_trigger) }

      it 'validates required fields' do
        trigger.configuration[:payload_validation] = {
          required_fields: ['event_type', 'data']
        }
        
        invalid_data = { event_type: 'test' } # missing 'data'
        expect(trigger.validate_trigger_data(invalid_data)).to be false
        expect(trigger.last_validation_errors).to include('data')
      end

      it 'validates field types' do
        trigger.configuration[:payload_validation] = {
          field_types: {
            'timestamp' => 'iso8601',
            'count' => 'integer'
          }
        }
        
        invalid_data = { timestamp: 'invalid', count: 'not_a_number' }
        expect(trigger.validate_trigger_data(invalid_data)).to be false
      end

      it 'validates payload size limits' do
        trigger.configuration[:payload_validation] = {
          max_payload_size: 1024
        }
        
        large_data = { content: 'x' * 2048 }
        expect(trigger.validate_trigger_data(large_data)).to be false
        expect(trigger.last_validation_errors).to include('payload size')
      end

      it 'returns true for valid data' do
        trigger.configuration[:payload_validation] = {
          required_fields: ['event_type'],
          field_types: { 'event_type' => 'string' }
        }
        
        valid_data = { event_type: 'user.created', data: { user_id: 123 } }
        expect(trigger.validate_trigger_data(valid_data)).to be true
      end
    end

    describe '#should_trigger_for_event?' do
      let(:trigger) { create(:ai_workflow_trigger, :event_trigger) }

      it 'matches configured event types' do
        event_data = { event_type: 'workflow.completed', data: {} }
        expect(trigger.should_trigger_for_event?(event_data)).to be true
      end

      it 'applies filter conditions' do
        event_data = {
          event_type: 'workflow.completed',
          workflow: { status: 'success', account_id: 123 }
        }
        
        expect(trigger.should_trigger_for_event?(event_data)).to be true
        
        # Should not match with different status
        failed_event = event_data.merge(workflow: { status: 'failed', account_id: 123 })
        expect(trigger.should_trigger_for_event?(failed_event)).to be false
      end

      it 'applies conditional logic' do
        trigger.configuration[:conditional_logic] = {
          operator: 'AND',
          conditions: [
            { field: 'workflow.status', operator: 'equals', value: 'success' },
            { field: 'workflow.duration', operator: 'less_than', value: 300 }
          ]
        }
        
        matching_event = {
          event_type: 'workflow.completed',
          workflow: { status: 'success', duration: 250 }
        }
        
        non_matching_event = {
          event_type: 'workflow.completed',
          workflow: { status: 'success', duration: 400 }
        }
        
        expect(trigger.should_trigger_for_event?(matching_event)).to be true
        expect(trigger.should_trigger_for_event?(non_matching_event)).to be false
      end

      it 'respects debounce settings' do
        trigger.update!(
          configuration: trigger.configuration.merge(debounce_seconds: 60),
          last_triggered_at: 30.seconds.ago
        )
        
        event_data = { event_type: 'workflow.completed', data: {} }
        expect(trigger.should_trigger_for_event?(event_data)).to be false
      end
    end

    describe '#next_scheduled_execution' do
      let(:trigger) { create(:ai_workflow_trigger, :schedule_trigger,
                            configuration: { cron_expression: '0 9 * * *', timezone: 'UTC' }) }

      it 'calculates next execution time from cron expression' do
        next_time = trigger.next_scheduled_execution
        expect(next_time.hour).to eq(9)
        expect(next_time.min).to eq(0)
        expect(next_time).to be > Time.current
      end

      it 'returns nil for non-schedule triggers' do
        webhook_trigger = create(:ai_workflow_trigger, :webhook_trigger)
        expect(webhook_trigger.next_scheduled_execution).to be_nil
      end

      it 'respects timezone settings' do
        ny_trigger = create(:ai_workflow_trigger, :schedule_trigger,
                           configuration: { cron_expression: '0 9 * * *', timezone: 'America/New_York' })
        
        next_time = ny_trigger.next_scheduled_execution
        expect(next_time.zone).to match(/EST|EDT/)
      end
    end

    describe '#webhook_url' do
      let(:trigger) { create(:ai_workflow_trigger, :webhook_trigger) }

      it 'constructs full webhook URL' do
        url = trigger.webhook_url
        expect(url).to include(trigger.configuration['webhook_path'])
        expect(url).to start_with('http')
      end

      it 'includes signature information when enabled' do
        url = trigger.webhook_url(include_signature_info: true)
        expect(url).to include('signature_header')
      end
    end

    describe '#execution_statistics' do
      let(:trigger) { create(:ai_workflow_trigger) }

      before do
        create_list(:ai_workflow_run, 3, :completed, ai_workflow: trigger.ai_workflow, trigger_id: trigger.id)
        create_list(:ai_workflow_run, 2, :failed, ai_workflow: trigger.ai_workflow, trigger_id: trigger.id)
      end

      it 'calculates trigger execution statistics' do
        stats = trigger.execution_statistics
        
        expect(stats[:total_executions]).to eq(5)
        expect(stats[:successful_executions]).to eq(3)
        expect(stats[:failed_executions]).to eq(2)
        expect(stats[:success_rate]).to eq(0.6)
        expect(stats[:average_execution_time]).to be_present
      end

      it 'includes recent execution trends' do
        stats = trigger.execution_statistics(include_trends: true)
        expect(stats[:recent_executions_24h]).to be_present
        expect(stats[:recent_executions_7d]).to be_present
      end
    end

    describe '#trigger_summary' do
      let(:trigger) { create(:ai_workflow_trigger, :webhook_trigger) }

      it 'returns comprehensive trigger information' do
        summary = trigger.trigger_summary
        
        expect(summary).to include(
          :id,
          :name,
          :trigger_type,
          :is_active,
          :trigger_count,
          :last_triggered_at,
          :next_execution_time,
          :configuration_summary
        )
        
        expect(summary[:trigger_type]).to eq('webhook')
        expect(summary[:configuration_summary]).to include(:webhook_path)
      end
    end
  end

  describe 'class methods' do
    describe '.process_webhook_request' do
      let!(:webhook_trigger) { create(:ai_workflow_trigger, :webhook_trigger) }
      let(:request_data) { 
        {
          path: webhook_trigger.configuration['webhook_path'],
          method: 'POST',
          headers: { 'Content-Type' => 'application/json' },
          body: { event_type: 'push', data: { repo: 'test' } }
        }
      }

      it 'finds and triggers matching webhook' do
        expect {
          result = described_class.process_webhook_request(request_data)
          expect(result[:triggered]).to be true
          expect(result[:workflow_run]).to be_present
        }.to change { AiWorkflowRun.count }.by(1)
      end

      it 'validates webhook signature when required' do
        webhook_trigger.configuration['signature_verification'] = true
        webhook_trigger.save!
        
        # Without valid signature
        result = described_class.process_webhook_request(request_data)
        expect(result[:triggered]).to be false
        expect(result[:error]).to include('signature')
      end

      it 'returns error for unknown webhook paths' do
        unknown_request = request_data.merge(path: '/unknown/webhook')
        result = described_class.process_webhook_request(unknown_request)
        
        expect(result[:triggered]).to be false
        expect(result[:error]).to include('no matching trigger')
      end
    end

    describe '.process_system_event' do
      let!(:event_trigger) { create(:ai_workflow_trigger, :event_trigger) }
      let(:event_data) {
        {
          event_type: 'workflow.completed',
          workflow: { status: 'success', account_id: event_trigger.ai_workflow.account_id },
          timestamp: Time.current.iso8601
        }
      }

      it 'triggers matching event handlers' do
        expect {
          result = described_class.process_system_event(event_data)
          expect(result[:triggers_fired]).to eq(1)
          expect(result[:workflows_started]).to eq(1)
        }.to change { AiWorkflowRun.count }.by(1)
      end

      it 'handles multiple matching triggers' do
        create(:ai_workflow_trigger, :event_trigger, 
               ai_workflow: event_trigger.ai_workflow)
        
        result = described_class.process_system_event(event_data)
        expect(result[:triggers_fired]).to eq(2)
      end

      it 'applies event filtering correctly' do
        non_matching_event = event_data.merge(
          workflow: { status: 'failed', account_id: event_trigger.ai_workflow.account_id }
        )
        
        result = described_class.process_system_event(non_matching_event)
        expect(result[:triggers_fired]).to eq(0)
      end
    end

    describe '.execute_scheduled_triggers' do
      let!(:due_trigger) { create(:ai_workflow_trigger, :schedule_trigger,
                                 configuration: { cron_expression: '0 9 * * *', timezone: 'UTC' },
                                 last_triggered_at: 25.hours.ago) }
      let!(:not_due_trigger) { create(:ai_workflow_trigger, :schedule_trigger,
                                     last_triggered_at: 1.hour.ago) }

      it 'executes all due scheduled triggers' do
        expect {
          result = described_class.execute_scheduled_triggers
          expect(result[:triggers_executed]).to eq(1)
          expect(result[:workflows_started]).to eq(1)
        }.to change { AiWorkflowRun.count }.by(1)
      end

      it 'updates trigger timestamps' do
        described_class.execute_scheduled_triggers
        expect(due_trigger.reload.last_triggered_at).to be_within(1.minute).of(Time.current)
      end

      it 'handles execution failures gracefully' do
        allow_any_instance_of(AiWorkflow).to receive(:execute).and_raise(StandardError, 'Test error')
        
        expect {
          result = described_class.execute_scheduled_triggers
          expect(result[:errors]).to be_present
        }.not_to raise_error
      end
    end

    describe '.cleanup_old_triggers' do
      before do
        create_list(:ai_workflow_trigger, 3, updated_at: 6.months.ago, is_active: false)
        create_list(:ai_workflow_trigger, 2, updated_at: 1.week.ago, is_active: true)
      end

      it 'removes old inactive triggers' do
        expect {
          described_class.cleanup_old_triggers(90)
        }.to change { described_class.count }.by(-3)
      end

      it 'preserves active triggers regardless of age' do
        old_active = create(:ai_workflow_trigger, updated_at: 1.year.ago, is_active: true)
        
        described_class.cleanup_old_triggers(90)
        expect(described_class.exists?(old_active.id)).to be true
      end
    end
  end

  describe 'performance and edge cases' do
    describe 'high-frequency webhook handling' do
      let!(:trigger) { create(:ai_workflow_trigger, :webhook_trigger) }

      it 'handles rapid webhook requests safely' do
        threads = 10.times.map do
          Thread.new do
            trigger.trigger_workflow!({ event_type: 'test', timestamp: Time.current.to_i })
          end
        end
        
        results = threads.map(&:value)
        expect(results.all?(&:persisted?)).to be true
        expect(trigger.reload.trigger_count).to eq(10)
      end

      it 'applies rate limiting correctly' do
        trigger.update!(
          metadata: { rate_limit_per_minute: 2 },
          trigger_count: 0,
          last_triggered_at: 1.minute.ago
        )
        
        # First two should succeed
        2.times { trigger.trigger_workflow!({ event_type: 'test' }) }
        
        # Third should be rate limited
        expect {
          trigger.trigger_workflow!({ event_type: 'test' })
        }.to raise_error(StandardError, /rate limit/i)
      end
    end

    describe 'complex event pattern matching' do
      let(:trigger) { create(:ai_workflow_trigger, :complex_event_processing) }

      it 'matches complex event sequences' do
        # Simulate event sequence: login -> page views -> cart add
        events = [
          { event_type: 'user.login', user: { id: 123 }, timestamp: Time.current },
          { event_type: 'page.view', user: { id: 123 }, page: { type: 'product' }, timestamp: 1.minute.from_now },
          { event_type: 'page.view', user: { id: 123 }, page: { type: 'product' }, timestamp: 2.minutes.from_now },
          { event_type: 'page.view', user: { id: 123 }, page: { type: 'product' }, timestamp: 3.minutes.from_now },
          { event_type: 'cart.add', user: { id: 123 }, timestamp: 5.minutes.from_now }
        ]
        
        expect(trigger.should_trigger_for_event_sequence?(events)).to be true
      end
    end

    describe 'timezone and scheduling edge cases' do
      it 'handles daylight saving transitions' do
        trigger = create(:ai_workflow_trigger, :schedule_trigger,
                        configuration: {
                          cron_expression: '0 2 * * *',
                          timezone: 'America/New_York'
                        })
        
        # Should handle DST transition gracefully
        expect { trigger.next_scheduled_execution }.not_to raise_error
      end

      it 'handles leap year scheduling' do
        trigger = create(:ai_workflow_trigger, :schedule_trigger,
                        configuration: {
                          cron_expression: '0 0 29 2 *', # Feb 29th
                          timezone: 'UTC'
                        })
        
        next_time = trigger.next_scheduled_execution
        expect(next_time.month).to eq(2)
        expect(next_time.day).to eq(29)
      end
    end

    describe 'large payload handling' do
      let(:trigger) { create(:ai_workflow_trigger, :webhook_trigger) }

      it 'handles large webhook payloads efficiently' do
        large_payload = {
          event_type: 'data.sync',
          records: Array.new(1000) { |i| { id: i, data: "record_#{i}" * 100 } }
        }
        
        expect { trigger.trigger_workflow!(large_payload) }.not_to raise_error
        
        run = AiWorkflowRun.last
        expect(run.trigger_context['trigger_data']['records'].size).to eq(1000)
      end
    end

    describe 'unicode and special character handling' do
      it 'handles unicode in trigger data' do
        unicode_data = {
          event_type: 'message.received',
          content: '你好世界 🌍',
          emoji: '🚀🎉🔥',
          special_chars: '¡¿αβγ€£¥'
        }
        
        trigger = create(:ai_workflow_trigger, :webhook_trigger)
        run = trigger.trigger_workflow!(unicode_data)
        
        expect(run.trigger_context['trigger_data']['content']).to eq('你好世界 🌍')
        expect(run.reload.trigger_context['trigger_data']['emoji']).to eq('🚀🎉🔥')
      end
    end

    describe 'query performance with large datasets' do
      before do
        create_list(:ai_workflow_trigger, 200, :webhook_trigger)
        create_list(:ai_workflow_trigger, 100, :event_trigger)
        create_list(:ai_workflow_trigger, 50, :schedule_trigger)
      end

      it 'efficiently finds triggers for events' do
        expect {
          described_class.active
                        .by_type('event')
                        .includes(:ai_workflow)
                        .limit(20)
                        .to_a
        }.not_to exceed_query_limit(3)
      end

      it 'efficiently processes webhook lookups' do
        expect {
          described_class.where("configuration->>'webhook_path' = ?", '/webhooks/test')
                        .active
                        .first
        }.not_to exceed_query_limit(1)
      end
    end
  end
end