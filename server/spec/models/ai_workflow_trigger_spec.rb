# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiWorkflowTrigger, type: :model do
  subject(:trigger) { build(:ai_workflow_trigger) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow) }
    it { is_expected.to have_many(:ai_workflow_runs).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:trigger_type) }
    it { is_expected.to validate_presence_of(:status) }
    # Note: configuration has default set by callback so we test it differently
    it { is_expected.to validate_length_of(:name).is_at_most(255) }

    it 'validates inclusion of trigger_type' do
      valid_types = %w[manual webhook schedule event api_call]

      valid_types.each do |type|
        workflow = create(:ai_workflow)
        # Create trigger with proper required fields for each type
        attrs = { ai_workflow: workflow, trigger_type: type, name: "Test #{type} trigger" }
        case type
        when 'manual'
          attrs[:configuration] = { 'require_confirmation' => false }
        when 'webhook'
          attrs[:webhook_url] = 'https://example.com/webhook'
          attrs[:configuration] = { 'method' => 'POST' }
        when 'schedule'
          attrs[:schedule_cron] = '0 9 * * *'
          attrs[:configuration] = { 'timezone' => 'UTC' }
        when 'event'
          attrs[:configuration] = { 'event_types' => ['user_created'] }
        when 'api_call'
          attrs[:configuration] = { 'require_authentication' => true }
        end
        trigger = build(:ai_workflow_trigger, **attrs)
        expect(trigger).to be_valid, "Expected #{type} to be valid but got errors: #{trigger.errors.full_messages.join(', ')}"
      end
    end

    it 'rejects invalid trigger_type' do
      trigger = build(:ai_workflow_trigger, trigger_type: 'invalid_type')
      expect(trigger).not_to be_valid
      expect(trigger.errors[:trigger_type]).to include('must be a valid trigger type')
    end

    it 'validates inclusion of status' do
      valid_statuses = %w[active paused disabled error]

      valid_statuses.each do |status|
        trigger = build(:ai_workflow_trigger, status: status)
        expect(trigger).to be_valid, "Expected #{status} to be valid"
      end
    end

    context 'schedule trigger validations' do
      it 'requires schedule_cron for schedule triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'schedule', schedule_cron: nil)
        trigger.configuration = { 'timezone' => 'UTC' }
        expect(trigger).not_to be_valid
        expect(trigger.errors[:schedule_cron]).to include('must be present for schedule triggers')
      end

      it 'validates cron expression format' do
        # 'invalid_cron' may pass as Fugit is lenient - test completely wrong format
        trigger = build(:ai_workflow_trigger, trigger_type: 'schedule', schedule_cron: '* * *')
        trigger.configuration = { 'timezone' => 'UTC' }
        expect(trigger).not_to be_valid
        expect(trigger.errors[:schedule_cron]).to include('is not a valid cron expression')
      end

      it 'accepts valid cron expressions' do
        valid_crons = ['0 9 * * *', '*/15 * * * *', '0 0 1 * *']

        valid_crons.each do |cron|
          trigger = build(:ai_workflow_trigger, trigger_type: 'schedule', schedule_cron: cron)
          trigger.configuration = { 'timezone' => 'UTC' }
          expect(trigger).to be_valid, "Expected '#{cron}' to be valid but got errors: #{trigger.errors.full_messages.join(', ')}"
        end
      end
    end

    context 'webhook trigger validations' do
      it 'validates HTTP method' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'webhook',
                        webhook_url: 'https://example.com/webhook')
        trigger.configuration = { 'method' => 'INVALID' }
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('method must be a valid HTTP method')
      end

      it 'accepts valid HTTP methods' do
        %w[GET POST PUT PATCH DELETE].each do |method|
          trigger = build(:ai_workflow_trigger, trigger_type: 'webhook',
                          webhook_url: 'https://example.com/webhook')
          trigger.configuration = { 'method' => method }
          expect(trigger).to be_valid, "Expected method #{method} to be valid but got errors: #{trigger.errors.full_messages.join(', ')}"
        end
      end
    end

    context 'event trigger validations' do
      it 'requires event_types for event triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event', configuration: {})
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must specify event_types array for event triggers')
      end

      it 'validates event_types is an array' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event')
        trigger.configuration = { 'event_types' => 'not_an_array' }
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include('must specify event_types array for event triggers')
      end

      it 'validates event types are recognized' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event')
        trigger.configuration = { 'event_types' => ['invalid_event_type'] }
        expect(trigger).not_to be_valid
        expect(trigger.errors[:configuration]).to include(match(/invalid event types/i))
      end
    end
  end

  describe 'scopes' do
    let!(:active_trigger) { create(:ai_workflow_trigger, status: 'active', is_active: true) }
    let!(:paused_trigger) { create(:ai_workflow_trigger, status: 'paused', is_active: false) }
    let!(:disabled_trigger) { create(:ai_workflow_trigger, status: 'disabled', is_active: false) }
    let!(:webhook_trigger) do
      create(:ai_workflow_trigger,
             trigger_type: 'webhook',
             webhook_url: 'https://example.com/webhook',
             configuration: { 'method' => 'POST' })
    end
    let!(:schedule_trigger) do
      create(:ai_workflow_trigger,
             trigger_type: 'schedule',
             schedule_cron: '0 9 * * *',
             configuration: { 'timezone' => 'UTC' })
    end
    let!(:event_trigger) { create(:ai_workflow_trigger, trigger_type: 'event', configuration: { 'event_types' => ['user_created'] }) }

    describe '.active' do
      it 'returns only active triggers with active status' do
        expect(described_class.active).to include(active_trigger)
        expect(described_class.active).not_to include(paused_trigger, disabled_trigger)
      end
    end

    describe '.inactive' do
      it 'returns triggers that are not active' do
        expect(described_class.inactive).to include(paused_trigger, disabled_trigger)
        expect(described_class.inactive).not_to include(active_trigger)
      end
    end

    describe '.by_type' do
      it 'filters triggers by type' do
        expect(described_class.by_type('webhook')).to include(webhook_trigger)
        expect(described_class.by_type('webhook')).not_to include(schedule_trigger, event_trigger)
      end
    end

    describe '.manual_triggers' do
      let!(:manual_trigger) { create(:ai_workflow_trigger, trigger_type: 'manual') }

      it 'returns only manual triggers' do
        expect(described_class.manual_triggers).to include(manual_trigger)
        expect(described_class.manual_triggers).not_to include(webhook_trigger)
      end
    end

    describe '.webhook_triggers' do
      it 'returns only webhook triggers' do
        expect(described_class.webhook_triggers).to include(webhook_trigger)
        expect(described_class.webhook_triggers).not_to include(schedule_trigger)
      end
    end

    describe '.schedule_triggers' do
      it 'returns only schedule triggers' do
        expect(described_class.schedule_triggers).to include(schedule_trigger)
        expect(described_class.schedule_triggers).not_to include(webhook_trigger)
      end
    end

    describe '.event_triggers' do
      it 'returns only event triggers' do
        expect(described_class.event_triggers).to include(event_trigger)
        expect(described_class.event_triggers).not_to include(webhook_trigger)
      end
    end

    describe '.due_for_execution' do
      let!(:due_schedule) do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'schedule',
                        schedule_cron: '0 9 * * *',
                        is_active: true,
                        status: 'active',
                        configuration: { 'timezone' => 'UTC' })
        trigger.update_column(:next_execution_at, 1.hour.ago)
        trigger
      end

      let!(:not_due_schedule) do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'schedule',
                        schedule_cron: '0 9 * * *',
                        is_active: true,
                        status: 'active',
                        configuration: { 'timezone' => 'UTC' })
        trigger.update_column(:next_execution_at, 1.hour.from_now)
        trigger
      end

      it 'returns schedule triggers that are due' do
        due_triggers = described_class.due_for_execution
        expect(due_triggers).to include(due_schedule)
        expect(due_triggers).not_to include(not_due_schedule)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'sets default configuration if not present' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'manual', configuration: nil)
        trigger.valid?
        expect(trigger.configuration).to be_present
      end
    end

    describe 'after_create' do
      it 'webhook_url is set for webhook triggers' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'webhook',
                        webhook_url: 'https://example.com/webhook',
                        configuration: { 'method' => 'POST' })
        expect(trigger.webhook_url).to be_present
      end
    end
  end

  describe 'instance methods' do
    describe 'type check methods' do
      it '#manual_trigger? returns true for manual triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'manual')
        expect(trigger.manual_trigger?).to be true
      end

      it '#webhook_trigger? returns true for webhook triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'webhook')
        expect(trigger.webhook_trigger?).to be true
      end

      it '#schedule_trigger? returns true for schedule triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'schedule')
        expect(trigger.schedule_trigger?).to be true
      end

      it '#event_trigger? returns true for event triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event')
        expect(trigger.event_trigger?).to be true
      end

      it '#api_call_trigger? returns true for api_call triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'api_call')
        expect(trigger.api_call_trigger?).to be true
      end
    end

    describe 'status check methods' do
      it '#active? returns true when status is active and is_active is true' do
        trigger = build(:ai_workflow_trigger, status: 'active', is_active: true)
        expect(trigger.active?).to be true
      end

      it '#active? returns false when status is not active' do
        trigger = build(:ai_workflow_trigger, status: 'paused', is_active: true)
        expect(trigger.active?).to be false
      end

      it '#paused? returns true for paused triggers' do
        trigger = build(:ai_workflow_trigger, status: 'paused')
        expect(trigger.paused?).to be true
      end

      it '#disabled? returns true for disabled triggers' do
        trigger = build(:ai_workflow_trigger, status: 'disabled')
        expect(trigger.disabled?).to be true
      end

      it '#has_error? returns true for error status' do
        trigger = build(:ai_workflow_trigger, status: 'error')
        expect(trigger.has_error?).to be true
      end
    end

    describe '#can_trigger?' do
      let(:workflow) { create(:ai_workflow, status: 'active') }

      it 'returns true for active triggers with executable workflows' do
        trigger = create(:ai_workflow_trigger, ai_workflow: workflow, status: 'active', is_active: true)
        allow(workflow).to receive(:can_execute?).and_return(true)
        expect(trigger.can_trigger?).to be true
      end

      it 'returns false for inactive triggers' do
        trigger = create(:ai_workflow_trigger, ai_workflow: workflow, status: 'paused', is_active: false)
        expect(trigger.can_trigger?).to be false
      end
    end

    describe '#next_execution_time' do
      it 'returns nil for non-schedule triggers' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'webhook',
                        webhook_url: 'https://example.com/webhook',
                        configuration: { 'method' => 'POST' })
        expect(trigger.next_execution_time).to be_nil
      end

      it 'calculates next execution time for schedule triggers' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'schedule',
                        schedule_cron: '0 9 * * *',
                        configuration: { 'timezone' => 'UTC' })

        next_time = trigger.next_execution_time
        expect(next_time).to be_a(Time)
        expect(next_time).to be > Time.current
      end
    end

    describe '#due_for_execution?' do
      it 'returns true when next_execution_at is in the past' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'schedule',
                        schedule_cron: '0 9 * * *',
                        status: 'active',
                        is_active: true,
                        configuration: { 'timezone' => 'UTC' })
        trigger.update_column(:next_execution_at, 1.hour.ago)

        expect(trigger.due_for_execution?).to be true
      end

      it 'returns false when next_execution_at is in the future' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'schedule',
                        schedule_cron: '0 9 * * *',
                        status: 'active',
                        is_active: true,
                        configuration: { 'timezone' => 'UTC' })
        trigger.update_column(:next_execution_at, 1.hour.from_now)

        expect(trigger.due_for_execution?).to be false
      end
    end

    describe '#webhook_endpoint' do
      it 'returns nil for non-webhook triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'manual')
        expect(trigger.webhook_endpoint).to be_nil
      end

      it 'returns webhook URL for webhook triggers' do
        trigger = create(:ai_workflow_trigger,
                        trigger_type: 'webhook',
                        webhook_url: 'https://example.com/webhook',
                        configuration: { 'method' => 'POST' })
        expect(trigger.webhook_endpoint).to be_present
      end
    end

    describe '#verify_webhook_signature' do
      let(:trigger) do
        create(:ai_workflow_trigger,
               trigger_type: 'webhook',
               webhook_url: 'https://example.com/webhook',
               configuration: { 'method' => 'POST' },
               webhook_secret: 'secret123')
      end

      it 'returns true when no webhook secret is set' do
        trigger.update!(webhook_secret: nil)
        expect(trigger.verify_webhook_signature('payload', 'any_signature')).to be true
      end

      it 'verifies signature correctly' do
        payload = '{"test": "data"}'
        expected_signature = OpenSSL::HMAC.hexdigest('SHA256', 'secret123', payload)

        expect(trigger.verify_webhook_signature(payload, expected_signature)).to be true
        expect(trigger.verify_webhook_signature(payload, 'wrong_signature')).to be false
      end
    end

    describe '#event_types' do
      it 'returns empty array for non-event triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'webhook')
        expect(trigger.event_types).to eq([])
      end

      it 'returns configured event types for event triggers' do
        trigger = build(:ai_workflow_trigger, trigger_type: 'event')
        trigger.configuration = { 'event_types' => ['user_created', 'payment_succeeded'] }
        expect(trigger.event_types).to eq(['user_created', 'payment_succeeded'])
      end
    end

    describe '#matches_event?' do
      let(:trigger) do
        create(:ai_workflow_trigger,
               trigger_type: 'event',
               status: 'active',
               is_active: true,
               configuration: { 'event_types' => ['user_created', 'payment_succeeded'] })
      end

      it 'returns true for matching event type' do
        expect(trigger.matches_event?('user_created')).to be true
      end

      it 'returns false for non-matching event type' do
        expect(trigger.matches_event?('unknown_event')).to be false
      end

      it 'returns false for inactive triggers' do
        trigger.update!(status: 'paused')
        expect(trigger.matches_event?('user_created')).to be false
      end
    end

    describe '#conditions_met?' do
      let(:trigger) { create(:ai_workflow_trigger) }

      it 'returns true when no conditions are set' do
        trigger.update!(conditions: {})
        expect(trigger.conditions_met?({}, {})).to be true
      end

      it 'evaluates conditions with AND logic' do
        trigger.update!(conditions: {
          'rules' => [
            { 'variable' => 'status', 'operator' => '==', 'value' => 'active' },
            { 'variable' => 'count', 'operator' => '>', 'value' => 5 }
          ],
          'logic' => 'AND'
        })

        expect(trigger.conditions_met?({ 'status' => 'active', 'count' => 10 })).to be true
        expect(trigger.conditions_met?({ 'status' => 'active', 'count' => 3 })).to be false
      end
    end

    describe 'status management methods' do
      let(:trigger) { create(:ai_workflow_trigger, status: 'paused', is_active: false) }

      describe '#activate!' do
        it 'activates the trigger' do
          trigger.activate!
          expect(trigger.reload.status).to eq('active')
          expect(trigger.is_active).to be true
        end
      end

      describe '#pause!' do
        it 'pauses the trigger' do
          trigger.update!(status: 'active')
          trigger.pause!
          expect(trigger.reload.status).to eq('paused')
        end
      end

      describe '#disable!' do
        it 'disables the trigger' do
          trigger.disable!
          expect(trigger.reload.status).to eq('disabled')
          expect(trigger.is_active).to be false
        end
      end

      describe '#reset_error!' do
        it 'resets error status to active' do
          trigger.update!(status: 'error', metadata: { 'error_message' => 'test error' })
          trigger.reset_error!

          expect(trigger.reload.status).to eq('active')
          expect(trigger.metadata).not_to have_key('error_message')
        end

        it 'does nothing if not in error status' do
          trigger.update!(status: 'active')
          trigger.reset_error!
          expect(trigger.reload.status).to eq('active')
        end
      end
    end

    describe '#execution_summary' do
      let(:trigger) { create(:ai_workflow_trigger) }

      it 'returns execution statistics' do
        summary = trigger.execution_summary

        expect(summary).to include(
          :total_triggers,
          :recent_triggers,
          :success_rate,
          :average_execution_time,
          :last_triggered,
          :next_execution,
          :status
        )
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles unicode in trigger data' do
      trigger = create(:ai_workflow_trigger,
                      name: 'Trigger spécial 🚀',
                      metadata: {
                        'description' => '日本語テスト',
                        'emoji_test' => '🌟⭐✨'
                      })

      expect(trigger.reload.name).to include('🚀')
      expect(trigger.metadata['emoji_test']).to include('🌟')
    end

    it 'handles timezone edge cases' do
      trigger = create(:ai_workflow_trigger,
                      trigger_type: 'schedule',
                      schedule_cron: '0 2 * * *',
                      configuration: { 'timezone' => 'America/New_York' })

      expect { trigger.reload.next_execution_time }.not_to raise_error
    end
  end
end
