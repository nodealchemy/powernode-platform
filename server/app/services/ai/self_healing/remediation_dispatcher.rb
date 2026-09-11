# frozen_string_literal: true

module Ai
  module SelfHealing
    class RemediationDispatcher
      MAX_ACTIONS_PER_HOUR = 5

      class << self
        # THE ONE READER of the self_healing_remediation flag (B5b). The guard
        # below and the self-healing page's display ask here, and B5b's provider
        # remediation lane must too, so the flag cannot mean one thing to the
        # actuator and another to the screen.
        def enabled?
          Shared::FeatureFlagService.enabled?(:self_healing_remediation)
        end

        def dispatch(account:, trigger_source:, trigger_event:, context: {})
          return unless enabled?
          return if rate_limited?(account.id)

          action = determine_action(trigger_event, context)
          return unless action
          return unless auditable?(action)
          return if unparseable_provider_target?(action, context)
          return if acted_on_target_this_window?(account, action, context)

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

        # Fail CLOSED: an action Ai::RemediationLog will not accept cannot be
        # audited, and this dispatcher mutates production agents with no operator
        # in the loop — the audit row is the only record that it acted at all. So
        # an unauditable remediation must not run.
        #
        # This is checked BEFORE execute_action because that is the only point at
        # which refusing still means something. Once the model pin has been
        # rewritten, raising on the audit write would surface the problem but
        # would not undo the mutation, and would take the caller's own bookkeeping
        # down with it. Fail-closed before acting; after acting, see the rescue in
        # log_remediation.
        def auditable?(action)
          return true if Ai::RemediationLog::ACTION_TYPES.include?(action)

          Rails.logger.error(
            "[RemediationDispatcher] Refusing unauditable remediation #{action.inspect}: " \
            "not in Ai::RemediationLog::ACTION_TYPES, no action taken"
          )
          false
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

        # WHAT "TRIM" MEANS HERE, stated because the previous implementation was
        # underspecified as well as broken (IMP-ee359823f419). It filtered and
        # wrote `ai_agent_id` and `is_active` on ai_agent_short_term_memories,
        # which has `agent_id` and no active flag, so every invocation raised
        # before trimming anything — and even repaired, "deactivate expired
        # entries" would have been a no-op, since the model's `active` scope
        # already hides expired rows from the readers that use it.
        #
        # So the trim is DELETION, delegated to the seam that already owns it:
        # Ai::Memory::MaintenanceService#cleanup_expired(agent:) deletes the
        # agent's expired rows and force-expires those past STM_MAX_AGE_DAYS.
        # Reusing it keeps this from becoming a second writer with its own
        # drifting copy of the query, and the measured outcome is the row count
        # it deletes.
        #
        # WHAT THIS DOES AND DOES NOT REDUCE, precisely. NOT context via
        # Ai::Memory::ContextInjectorService: that is the only assembler of
        # memory into an agent's prompt, it is hard-capped at
        # DEFAULT_TOKEN_BUDGET, and none of its injectors reads short-term
        # memory at all.
        #
        # NOR, ANY LONGER, context via the tool-result path. This comment used
        # to rest on Ai::Tools::MemoryTool#search_memory selecting short-term
        # rows with no `.active` filter, which made expired rows reachable
        # context until something deleted them. IMP-63da66a05a4f added that
        # filter, so search_memory no longer serves an expired row at all and
        # deleting one removes nothing the model could still have seen through
        # it. The context-reduction claim died with the bug it depended on.
        #
        # What remains is real but narrower: this reclaims table rows and the
        # storage behind them, and it is the only actuator that retires expired
        # short-term memory on demand rather than waiting for the decay sweep.
        # Justify it on that, not on prompt size.
        #
        # If a future reader is tempted to restore the context argument, the
        # test is whether some UNFILTERED reader of ai_agent_short_term_memories
        # still feeds a model. At the time of writing the remaining unfiltered
        # sites are counts and deletes (MemoryTool#memory_stats,
        # RouterService#short_term_stats / #delete_short_term, and the `before`
        # / `after` counts below) — none of which put row CONTENT in a prompt.
        def execute_context_trim(account, context)
          execution_id = context[:execution_id]
          return { status: "skipped", message: "No execution specified" } unless execution_id

          execution = Ai::AgentExecution.find_by(id: execution_id, account_id: account.id)
          return { status: "skipped", message: "Execution not found" } unless execution

          agent = execution.agent
          return { status: "skipped", message: "Agent not found" } unless agent

          before = Ai::AgentShortTermMemory.for_agent(agent.id).count
          deleted = Ai::Memory::MaintenanceService.new(account: account)
                                                 .cleanup_expired(agent: agent)
                                                 .fetch(:deleted, 0)
          after = Ai::AgentShortTermMemory.for_agent(agent.id).count

          {
            status: "success",
            message: "Trimmed #{deleted} short-term memory rows for agent #{agent.name} " \
                     "(#{before} -> #{after} rows)"
          }
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

        # PER-TARGET GUARD (B5b). The only guard before this was the per-account
        # hourly cap above, so two dispatches for the SAME provider inside one
        # window both acted: a breaker that re-opens, or two predictive runs (and
        # B5b's lane apply will be a third caller). Refused when this account
        # already logged this action against this target inside the rate
        # limiter's own window
        # (RemediationLog.in_last_hour). No new number.
        #
        # The target is what #capture_state records as before_state, so the
        # identity compared is the one the audit row already carries. Both sides
        # are the uuid-cast id (#provider_target), never the raw text: the action
        # resolves the provider through that same cast, so an UPPERCASE,
        # hyphenless or {braced} spelling of one id must be one target, not a
        # way past the guard. An action with no provider target
        # (alert_escalation, context_trim) is not deduped here; the per-account
        # cap still bounds it.
        def acted_on_target_this_window?(account, action, context)
          target = capture_state(action, context)[:provider_id]
          return false if target.blank?

          prior = Ai::RemediationLog.by_account(account.id).in_last_hour.by_action_type(action)
                                    .where("before_state ->> 'provider_id' = ?", target.to_s)
          return false unless prior.exists?

          Rails.logger.warn(
            "[RemediationDispatcher] Refusing #{action} for provider #{target}: already dispatched in this window"
          )
          true
        end

        # The provider id an action names, exactly as the caller sent it.
        def raw_provider_target(action, context)
          case action
          when "provider_failover" then context[:provider_id]
          when "model_downgrade" then context[:source_id] || context[:provider_id]
          end
        end

        # That id as the uuid type reads it: the same cast Ai::Provider.find_by(id:)
        # applies when the action resolves the provider, so every spelling the
        # action would accept becomes the one canonical string. nil when the action
        # names no provider, or names one the type rejects.
        def provider_target(action, context)
          raw = raw_provider_target(action, context)
          raw.nil? ? nil : Ai::Provider.type_for_attribute(:id).cast(raw)
        end

        # An id the uuid type rejects names no provider. Acting on it could only
        # log a skip under a key no later dispatch would ever match, so it is
        # refused before acting and nothing is logged. A blank id is not this
        # case: the action's own "No provider specified" skip still handles it.
        def unparseable_provider_target?(action, context)
          return false if raw_provider_target(action, context).blank?
          return false unless provider_target(action, context).nil?

          Rails.logger.warn("[RemediationDispatcher] Refusing #{action}: provider id is not a UUID")
          true
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
          # The provider id is stored uuid-cast (#provider_target), so the audit row
          # carries the key the per-target guard compares.
          when "provider_failover"
            { provider_id: provider_target(action, context), circuit_state: context[:circuit_state] }
          when "model_downgrade"
            { provider_id: provider_target(action, context) }
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
        # Deliberately still swallows, and deliberately no wider than before. By
        # the time this runs the remediation has already executed and changed
        # state; raising cannot undo it, and would additionally lose the caller's
        # result. The unauditable case that made this rescue dangerous is now
        # refused up front by auditable?, so what remains here is an infrastructure
        # failure — for which the best available outcome is that the row it could
        # not write is reconstructable from the log line.
        rescue => e
          Rails.logger.error(
            "[RemediationDispatcher] Failed to log remediation: #{e.class}: #{e.message} " \
            "(account=#{account&.id} #{trigger_source}/#{trigger_event} " \
            "action_type=#{action_type} result=#{result})"
          )
        end
      end
    end
  end
end
