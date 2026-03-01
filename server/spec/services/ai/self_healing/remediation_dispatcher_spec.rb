# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SelfHealing::RemediationDispatcher, type: :service do
  let(:account) { create(:account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '.dispatch' do
    let(:trigger_source) { 'Ai::WorkflowRun' }
    let(:trigger_event) { 'circuit_breaker_opened' }
    let(:context) { { service_type: 'provider', provider_id: SecureRandom.uuid } }

    context 'when feature flag is disabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(false)
      end

      it 'returns nil without taking any action' do
        result = described_class.dispatch(
          account: account,
          trigger_source: trigger_source,
          trigger_event: trigger_event,
          context: context
        )

        expect(result).to be_nil
      end

      it 'does not create a remediation log' do
        expect {
          described_class.dispatch(
            account: account,
            trigger_source: trigger_source,
            trigger_event: trigger_event,
            context: context
          )
        }.not_to change(Ai::RemediationLog, :count)
      end
    end

    context 'when feature flag is enabled' do
      before do
        allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      end

      context 'when rate limited' do
        before do
          allow(Ai::RemediationLog).to receive(:hourly_count).with(account.id).and_return(5)
        end

        it 'returns nil without executing actions' do
          result = described_class.dispatch(
            account: account,
            trigger_source: trigger_source,
            trigger_event: trigger_event,
            context: context
          )

          expect(result).to be_nil
        end

        it 'logs a rate limit warning' do
          expect(Rails.logger).to receive(:warn).with(/Rate limited/)

          described_class.dispatch(
            account: account,
            trigger_source: trigger_source,
            trigger_event: trigger_event,
            context: context
          )
        end
      end

      context 'when not rate limited' do
        before do
          allow(Ai::RemediationLog).to receive(:hourly_count).with(account.id).and_return(0)
        end

        describe 'action determination' do
          context 'circuit_breaker_opened with provider service_type' do
            it 'determines provider_failover action' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'provider_failover')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'circuit_breaker_opened',
                context: { service_type: 'provider', provider_id: SecureRandom.uuid }
              )
            end
          end

          context 'circuit_breaker_opened with non-provider service_type' do
            it 'determines alert_escalation action' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'alert_escalation')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'circuit_breaker_opened',
                context: { service_type: 'cache' }
              )
            end
          end

          context 'workflow_node_failed with transient error' do
            it 'determines workflow_retry action for Timeout::Error' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'workflow_retry')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'workflow_node_failed',
                context: { error_class: 'Timeout::Error', execution_id: SecureRandom.uuid }
              )
            end

            it 'determines workflow_retry action for Faraday::TimeoutError' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'workflow_retry')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'workflow_node_failed',
                context: { error_class: 'Faraday::TimeoutError', execution_id: SecureRandom.uuid }
              )
            end
          end

          context 'workflow_node_failed with non-transient error' do
            it 'determines alert_escalation action' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'alert_escalation')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'workflow_node_failed',
                context: { error_class: 'ArgumentError' }
              )
            end
          end

          context 'repeated_failures event' do
            it 'determines alert_escalation action' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'alert_escalation')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'repeated_failures',
                context: {}
              )
            end
          end

          context 'stuck_execution event' do
            it 'determines workflow_retry action' do
              expect(Ai::RemediationLog).to receive(:create!).with(
                hash_including(action_type: 'workflow_retry')
              )

              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'stuck_execution',
                context: { execution_id: SecureRandom.uuid }
              )
            end
          end

          context 'unknown trigger_event' do
            it 'returns nil when action cannot be determined' do
              result = described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'unknown_event',
                context: {}
              )

              expect(result).to be_nil
            end
          end
        end

        describe 'provider failover execution' do
          let(:provider) { create(:ai_provider) }
          let(:backup_provider) { create(:ai_provider, provider_type: provider.provider_type) }
          let!(:agent) { create(:ai_agent, account: account, ai_provider_id: provider.id, status: 'active') }

          before do
            allow(Ai::Provider).to receive(:find_by).and_return(nil)
            allow(Ai::Provider).to receive(:find_by).with(id: provider.id).and_return(provider)
            allow(Ai::Provider).to receive(:where).and_call_original
          end

          it 'skips when no provider_id is specified' do
            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'skipped', result_message: 'No provider specified')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'circuit_breaker_opened',
              context: { service_type: 'provider' }
            )
          end

          it 'skips when provider is not found' do
            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'skipped', result_message: 'Provider not found')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'circuit_breaker_opened',
              context: { service_type: 'provider', provider_id: SecureRandom.uuid }
            )
          end
        end

        describe 'workflow retry execution' do
          it 'skips when no execution_id is specified' do
            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'skipped', result_message: 'No execution specified')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'stuck_execution',
              context: {}
            )
          end

          it 'calls WorkflowRecoveryService with the execution_id' do
            execution_id = SecureRandom.uuid
            workflow_run = double('WorkflowRun', id: execution_id)
            allow(Ai::WorkflowRun).to receive(:find_by).with(id: execution_id).and_return(workflow_run)

            recovery_mock = double('WorkflowRecoveryService')
            allow(Ai::WorkflowRecoveryService).to receive(:new).and_return(recovery_mock)
            allow(recovery_mock).to receive(:attempt_retry).with(execution_id)

            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'success')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'stuck_execution',
              context: { execution_id: execution_id }
            )
          end

          it 'handles WorkflowRecoveryService failures' do
            execution_id = SecureRandom.uuid
            workflow_run = double('WorkflowRun', id: execution_id)
            allow(Ai::WorkflowRun).to receive(:find_by).with(id: execution_id).and_return(workflow_run)

            recovery_mock = double('WorkflowRecoveryService')
            allow(Ai::WorkflowRecoveryService).to receive(:new).and_return(recovery_mock)
            allow(recovery_mock).to receive(:attempt_retry).and_raise(StandardError, 'Recovery failed')

            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'failure', result_message: 'Retry failed: Recovery failed')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'stuck_execution',
              context: { execution_id: execution_id }
            )
          end
        end

        describe 'alert escalation execution' do
          it 'broadcasts via ActionCable' do
            expect(ActionCable.server).to receive(:broadcast).with(
              "ai_monitoring_#{account.id}",
              hash_including(
                type: 'remediation_alert',
                severity: 'warning'
              )
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'repeated_failures',
              context: { trigger_event: 'repeated_failures', trigger_source: trigger_source }
            )
          end

          it 'uses custom severity from context' do
            expect(ActionCable.server).to receive(:broadcast).with(
              "ai_monitoring_#{account.id}",
              hash_including(severity: 'critical')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'repeated_failures',
              context: { severity: 'critical' }
            )
          end
        end

        describe 'remediation logging' do
          it 'creates a remediation log entry on success' do
            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'repeated_failures',
                action_type: 'alert_escalation',
                result: 'success',
                executed_at: an_instance_of(ActiveSupport::TimeWithZone)
              )
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'repeated_failures',
              context: {}
            )
          end

          it 'logs before_state and after_state' do
            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(
                before_state: hash_including(:severity),
                after_state: hash_including(:severity)
              )
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'repeated_failures',
              context: { severity: 'warning', trigger_source: trigger_source }
            )
          end

          it 'handles logging failures gracefully' do
            allow(Ai::RemediationLog).to receive(:create!).and_raise(ActiveRecord::RecordInvalid)

            expect(Rails.logger).to receive(:error).with(/Failed to log remediation/)

            # Should not raise
            expect {
              described_class.dispatch(
                account: account,
                trigger_source: trigger_source,
                trigger_event: 'repeated_failures',
                context: {}
              )
            }.not_to raise_error
          end
        end

        describe 'action execution error handling' do
          it 'logs failure and captures error when execute_action raises' do
            # Force an unexpected error in the alert_escalation path
            allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, 'Broadcast down')

            expect(Rails.logger).to receive(:error).with(/Action alert_escalation failed/)

            expect(Ai::RemediationLog).to receive(:create!).with(
              hash_including(result: 'failure', result_message: 'Broadcast down')
            )

            described_class.dispatch(
              account: account,
              trigger_source: trigger_source,
              trigger_event: 'repeated_failures',
              context: {}
            )
          end
        end
      end
    end
  end

  describe 'MAX_ACTIONS_PER_HOUR' do
    it 'is set to 5' do
      expect(described_class::MAX_ACTIONS_PER_HOUR).to eq(5)
    end
  end

  describe 'transient error detection' do
    before do
      allow(Shared::FeatureFlagService).to receive(:enabled?).with(:self_healing_remediation).and_return(true)
      allow(Ai::RemediationLog).to receive(:hourly_count).and_return(0)
    end

    %w[
      Timeout::Error Net::ReadTimeout Net::OpenTimeout
      Faraday::TimeoutError Faraday::ConnectionFailed
      HTTP::TimeoutError HTTP::ConnectionError
    ].each do |error_class|
      it "recognizes #{error_class} as a transient error and triggers workflow_retry" do
        expect(Ai::RemediationLog).to receive(:create!).with(
          hash_including(action_type: 'workflow_retry')
        )

        described_class.dispatch(
          account: account,
          trigger_source: 'Ai::WorkflowRun',
          trigger_event: 'workflow_node_failed',
          context: { error_class: error_class, execution_id: SecureRandom.uuid }
        )
      end
    end

    it 'does not recognize non-transient errors as transient' do
      expect(Ai::RemediationLog).to receive(:create!).with(
        hash_including(action_type: 'alert_escalation')
      )

      described_class.dispatch(
        account: account,
        trigger_source: 'Ai::WorkflowRun',
        trigger_event: 'workflow_node_failed',
        context: { error_class: 'NoMethodError' }
      )
    end

    it 'does not recognize nil error_class as transient' do
      expect(Ai::RemediationLog).to receive(:create!).with(
        hash_including(action_type: 'alert_escalation')
      )

      described_class.dispatch(
        account: account,
        trigger_source: 'Ai::WorkflowRun',
        trigger_event: 'workflow_node_failed',
        context: { error_class: nil }
      )
    end
  end
end
