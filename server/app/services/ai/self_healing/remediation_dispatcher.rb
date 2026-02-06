# frozen_string_literal: true

module Ai
  module SelfHealing
    class RemediationDispatcher
      MAX_ACTIONS_PER_HOUR = 5

      class << self
        def dispatch(account:, trigger_source:, trigger_event:, context: {})
          return unless Shared::FeatureFlagService.enabled?(:self_healing_remediation)
          return if rate_limited?(account.id)

          action = determine_action(trigger_event, context)
          return unless action

          before_state = capture_state(action, context)

          result = execute_action(action, account: account, context: context)

          after_state = capture_state(action, context)

          log_remediation(
            account: account,
            trigger_source: trigger_source,
            trigger_event: trigger_event,
            action_type: action,
            action_config: context,
            before_state: before_state,
            after_state: after_state,
            result: result[:status],
            result_message: result[:message]
          )
        end

        private

        def determine_action(trigger_event, context)
          case trigger_event
          when "circuit_breaker_opened"
            context[:service_type] == "provider" ? "provider_failover" : "alert_escalation"
          when "workflow_node_failed"
            transient_error?(context[:error_class]) ? "workflow_retry" : "alert_escalation"
          when "repeated_failures"
            "alert_escalation"
          when "stuck_execution"
            "workflow_retry"
          end
        end

        def execute_action(action, account:, context:)
          case action
          when "provider_failover"
            execute_provider_failover(account, context)
          when "workflow_retry"
            execute_workflow_retry(account, context)
          when "alert_escalation"
            execute_alert_escalation(account, context)
          else
            { status: "skipped", message: "Unknown action: #{action}" }
          end
        rescue => e
          Rails.logger.error "[RemediationDispatcher] Action #{action} failed: #{e.message}"
          { status: "failure", message: e.message }
        end

        def execute_provider_failover(account, context)
          provider_id = context[:provider_id]
          return { status: "skipped", message: "No provider specified" } unless provider_id

          provider = Ai::Provider.find_by(id: provider_id)
          return { status: "skipped", message: "Provider not found" } unless provider

          # Find agents using this provider and switch to backup
          agents = Ai::Agent.where(account: account, ai_provider_id: provider_id, status: "active")
          backup = Ai::Provider.where(provider_type: provider.provider_type)
                               .where.not(id: provider_id)
                               .first

          return { status: "skipped", message: "No backup provider available" } unless backup

          switched = 0
          agents.each do |agent|
            backup_cred = Ai::ProviderCredential.where(account: account, ai_provider_id: backup.id)
                                                 .active.healthy.first
            next unless backup_cred

            agent.update!(ai_provider_id: backup.id)
            switched += 1
          end

          { status: "success", message: "Switched #{switched} agents to #{backup.name}" }
        end

        def execute_workflow_retry(account, context)
          execution_id = context[:execution_id] || context[:node_execution_id]
          return { status: "skipped", message: "No execution specified" } unless execution_id

          workflow_run = Ai::WorkflowRun.find_by(id: execution_id)
          return { status: "skipped", message: "Workflow run not found" } unless workflow_run

          recovery = Ai::WorkflowRecoveryService.new(workflow_run: workflow_run, account: account)
          recovery.attempt_retry(execution_id)

          { status: "success", message: "Retry initiated for execution #{execution_id}" }
        rescue => e
          { status: "failure", message: "Retry failed: #{e.message}" }
        end

        def execute_alert_escalation(account, context)
          # Broadcast via WebSocket
          ActionCable.server.broadcast(
            "ai_monitoring_#{account.id}",
            {
              type: "remediation_alert",
              trigger: context[:trigger_event],
              source: context[:trigger_source],
              message: context[:message] || "Self-healing alert escalation",
              severity: context[:severity] || "warning",
              timestamp: Time.current.iso8601
            }
          )

          { status: "success", message: "Alert escalated via WebSocket" }
        end

        def rate_limited?(account_id)
          count = Ai::RemediationLog.hourly_count(account_id)
          if count >= MAX_ACTIONS_PER_HOUR
            Rails.logger.warn "[RemediationDispatcher] Rate limited for account #{account_id} (#{count}/#{MAX_ACTIONS_PER_HOUR})"
            true
          else
            false
          end
        end

        def transient_error?(error_class)
          return false unless error_class

          transient_errors = %w[
            Timeout::Error Net::ReadTimeout Net::OpenTimeout
            Faraday::TimeoutError Faraday::ConnectionFailed
            HTTP::TimeoutError HTTP::ConnectionError
          ]
          transient_errors.include?(error_class.to_s)
        end

        def capture_state(action, context)
          case action
          when "provider_failover"
            { provider_id: context[:provider_id], circuit_state: context[:circuit_state] }
          when "workflow_retry"
            { execution_id: context[:execution_id], status: context[:status] }
          when "alert_escalation"
            { severity: context[:severity], source: context[:trigger_source] }
          else
            {}
          end
        end

        def log_remediation(account:, trigger_source:, trigger_event:, action_type:, action_config:, before_state:, after_state:, result:, result_message:)
          Ai::RemediationLog.create!(
            account: account,
            trigger_source: trigger_source,
            trigger_event: trigger_event,
            action_type: action_type,
            action_config: action_config,
            before_state: before_state,
            after_state: after_state,
            result: result,
            result_message: result_message,
            executed_at: Time.current
          )
        rescue => e
          Rails.logger.error "[RemediationDispatcher] Failed to log remediation: #{e.message}"
        end
      end
    end
  end
end
