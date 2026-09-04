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
          # Allow predictive monitor to hint at preferred action
          return context[:action_hint] if context[:preemptive] && context[:action_hint]

          case trigger_event
          when "circuit_breaker_opened"
            context[:service_type] == "provider" ? "provider_failover" : "alert_escalation"
          when "repeated_failures"
            "alert_escalation"
          when "provider_degradation"
            "provider_failover"
          when "execution_degradation"
            "model_downgrade"
          when "cost_anomaly"
            "alert_escalation"
          when "context_overflow"
            "context_trim"
          end
        end

        def execute_action(action, account:, context:)
          case action
          when "provider_failover"
            execute_provider_failover(account, context)
          when "model_downgrade"
            execute_model_downgrade(account, context)
          when "context_trim"
            execute_context_trim(account, context)
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
          backup = Ai::Provider.where(account: account, provider_type: provider.provider_type)
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

        def execute_model_downgrade(account, context)
          provider_id = context[:source_id] || context[:provider_id]
          return { status: "skipped", message: "No provider specified" } unless provider_id

          # Find agents on the degraded provider and switch to a lower-tier model
          agents = Ai::Agent.where(account: account, ai_provider_id: provider_id, status: "active")
                            .includes(:provider)
          return { status: "skipped", message: "No agents to downgrade" } if agents.empty?

          provider = Ai::Provider.find_by(id: provider_id)
          return { status: "skipped", message: "Provider not found" } unless provider

          downgraded = 0
          agents.each do |agent|
            # An agent's model is NOT a column — it is the pin at
            # mcp_metadata.model_config.model, read through #resolved_model so an
            # unpinned agent reports the model it would actually run.
            current_model = agent.resolved_model
            next unless current_model

            # Try to find a cheaper/faster model on the same provider
            economy_model = find_economy_model(provider, current_model)
            next unless economy_model

            # Writing the pin means writing mcp_metadata, which fires
            # Ai::Agent#auto_resolve_provider_from_model. The downgrade target
            # always comes from THIS provider's own supported_models, so the
            # model's family matches the agent's provider and that callback
            # short-circuits — the row never has to find a provider elsewhere.
            agent.update!(
              mcp_metadata: (agent.mcp_metadata || {}).deep_merge(
                "model_config" => { "model" => economy_model }
              ),
              metadata: (agent.metadata || {}).merge(
                "self_healing" => {
                  # The model in effect when this downgrade ran — what an
                  # operator restores the pin to.
                  "original_model" => current_model,
                  "downgraded_at" => Time.current.iso8601,
                  "downgrade_reason" => "predictive_self_healing"
                }
              )
            )
            downgraded += 1
          end

          { status: "success", message: "Downgraded #{downgraded} agents to economy models" }
        end

        def execute_context_trim(account, context)
          execution_id = context[:execution_id]
          return { status: "skipped", message: "No execution specified" } unless execution_id

          # Trim context for the execution's agent
          execution = Ai::AgentExecution.find_by(id: execution_id, account_id: account.id)
          return { status: "skipped", message: "Execution not found" } unless execution

          agent = execution.agent
          return { status: "skipped", message: "Agent not found" } unless agent

          # Clear short-term memory to reduce context size
          cleared = Ai::AgentShortTermMemory.where(ai_agent_id: agent.id, is_active: true)
                                             .where("expires_at < ?", Time.current)
                                             .update_all(is_active: false)

          { status: "success", message: "Trimmed #{cleared} expired memory entries for agent #{agent.name}" }
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

        # The cheapest model this provider supports at a STRICTLY lower capability
        # tier than the current one. Tiering and pricing both come from
        # Ai::ModelTiers (family floor, escalated by live Ai::ModelPricing bands) —
        # the platform's single price ladder — so this needs no per-provider price
        # bookkeeping of its own and no hardcoded model names. There is no
        # Ai::ProviderModel table; a provider's models are its supported_models
        # jsonb, whose entries may be a Hash or a bare String (ModelTiers.id_for
        # normalizes both). nil ⇒ the provider lists nothing cheaper, which the
        # caller treats as "leave this agent alone".
        def find_economy_model(provider, current_model)
          current_rank = Ai::ModelTiers::ORDER.index(Ai::ModelTiers.classify(current_model)).to_i

          candidates = Array(provider.supported_models).filter_map do |entry|
            model_id = Ai::ModelTiers.id_for(entry).presence
            next if model_id.nil? || model_id == current_model

            rank = Ai::ModelTiers::ORDER.index(Ai::ModelTiers.classify(model_id)).to_i
            next if rank >= current_rank

            [ rank, Ai::ModelTiers.price_for(model_id).to_f, model_id ]
          end

          # Lowest tier first, then cheapest, then id — deterministic.
          candidates.min&.last
        end

        def capture_state(action, context)
          case action
          when "provider_failover"
            { provider_id: context[:provider_id], circuit_state: context[:circuit_state] }
          when "model_downgrade"
            { provider_id: context[:source_id] || context[:provider_id] }
          when "context_trim"
            { execution_id: context[:execution_id] }
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
