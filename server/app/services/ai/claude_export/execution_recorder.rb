# frozen_string_literal: true

module Ai
  module ClaudeExport
    # The body of platform.record_agent_execution (HIER-P1C): a Claude Code
    # run of a platform agent — Agent(subagent_type: "<slug>") on one of the
    # committed .claude/agents/powernode/ skeletons — reports back and lands as
    # ONE Ai::AgentExecution on the TARGET agent, executed by the calling
    # session's mcp_client identity. Statistics come only from execution rows:
    # the row is minted `running` and then transitioned to its terminal status
    # so the model's OWN after_update hooks (trust evaluation,
    # Ai::AgentModelPerformance.record!) run unchanged — this class never
    # touches trust or model-performance tables directly.
    #
    # EXECUTOR ATTRIBUTION lives in execution_context (jsonb, already on the
    # row) — `source: claude_code`, `executor_agent_id`, `executor_ref`,
    # `run_key` — rather than a new column: every reader that needs the kind
    # asks AgentExecution#claude_code_run?, and nothing else on the platform
    # keys on the executor, so a column would be a migration for one predicate.
    #
    # IDEMPOTENCY rides the existing UNIQUE ai_agent_executions.execution_id:
    # the row's execution_id is a digest of (account, run_key), so a retry of
    # the same report finds and updates the row through an indexed lookup —
    # no jsonb scan, no new index. Another account's identical run_key is a
    # different row. A row that already reached a terminal status keeps it: a
    # retry updates metrics, never re-fires the terminal hooks (which would
    # double-count the run).
    #
    # MODEL MAPPING (item 2): the reported Claude Code model id is credited to
    # the account's credentialed Anthropic provider when one exists (so the
    # empirical signal reaches Ai::AgentModelSelector for a model the platform
    # can also run), else to a synthetic, INACTIVE "claude-code" provider row
    # scoped out of platform routing by Ai::Provider.platform_routable — the
    # selector must never pick a Claude Code-only model for a platform run.
    #
    # BOUNDARY RULE (item 3): a Claude Code run counts toward model statistics
    # and the trust score and NEVER toward autonomy budgets, consent ceilings
    # or approval accounting. Cost is written at create time, and
    # AgentExecution#propagate_cost_to_budget additionally refuses a
    # claude_code_run? row, so even a retry that changes the cost cannot
    # debit an Ai::AgentBudget.
    class ExecutionRecorder
      SOURCE = ::Ai::AgentExecution::CLAUDE_CODE_SOURCE
      OUTCOMES = %w[completed failed cancelled].freeze
      MAX_DIGEST_CHARS = 500
      EXECUTION_ID_PREFIX = "cc-"
      SYNTHETIC_PROVIDER_SLUG = "claude-code"
      SYNTHETIC_PROVIDER_NAME = "Claude Code (local sessions)"
      # RFC 2606 reserved TLD: this provider row never serves a request; the
      # endpoint exists only because Ai::Provider validates one.
      SYNTHETIC_PROVIDER_ENDPOINT = "https://claude-code.invalid"
      # Anthropic is the only provider family Claude Code runs; the credentialed
      # provider lookup keys on Ai::Provider#provider_type.
      PROVIDER_TYPE = "anthropic"

      class Refusal < StandardError; end

      # @param account [Account] the calling session's account
      # @param user [User, nil] the calling principal (nil for an instance principal)
      # @param executor_agent [Ai::Agent, nil] the session's mcp_client identity
      # @param executor_ref [String, nil] a principal descriptor when no agent exists
      def initialize(account:, user: nil, executor_agent: nil, executor_ref: nil)
        @account = account
        @user = user
        @executor_agent = executor_agent
        @executor_ref = executor_ref
      end

      # @return [Hash] the recorded row's summary
      # @raise [Refusal] on an unresolvable or invalid report
      def record(params)
        report = normalize(params)
        target = resolve_target(report[:agent_slug])
        provider = provider_for
        digest = redacted_digest(report[:task_digest])

        execution_id = execution_id_for(report[:run_key])
        execution = ::Ai::AgentExecution.find_by(execution_id: execution_id)
        created = execution.nil?

        ::Ai::AgentExecution.transaction do
          execution ||= mint(target, provider, report, digest, execution_id)
          finish(execution, report, digest)
        end

        summary(execution, target, provider, report, created)
      end

      private

      attr_reader :account

      def normalize(params)
        tokens = params[:tokens].respond_to?(:to_unsafe_h) ? params[:tokens].to_unsafe_h : params[:tokens]
        tokens = tokens.is_a?(Hash) ? tokens.transform_keys(&:to_s) : {}
        outcome = params[:outcome].to_s.strip.downcase
        raise Refusal, "outcome must be one of #{OUTCOMES.join('/')}" unless OUTCOMES.include?(outcome)

        run_key = params[:run_key].to_s.strip
        raise Refusal, "run_key is required (session id + subagent run id)" if run_key.empty?

        model = params[:model].to_s.strip
        raise Refusal, "model is required (the Claude Code model id that served the run)" if model.empty?

        {
          agent_slug: params[:agent_slug].to_s.strip,
          model: model,
          outcome: outcome,
          duration_ms: [ params[:duration_ms].to_i, 0 ].max,
          input_tokens: [ tokens["input"].to_i, 0 ].max,
          output_tokens: [ tokens["output"].to_i, 0 ].max,
          cost_usd: params[:cost_usd].presence && [ params[:cost_usd].to_f, 0.0 ].max,
          task_digest: params[:task_digest].to_s,
          run_key: run_key
        }
      end

      # Override-aware (Ai::Agent.resolve_for): the account's clone of a
      # canonical wins over the global row, exactly as get_agent resolves the
      # skeleton's bootstrap call.
      def resolve_target(slug)
        raise Refusal, "agent_slug is required" if slug.empty?

        target = ::Ai::Agent.resolve_for(account.id, slug: slug)
        raise Refusal, "No platform agent matches agent_slug: #{slug}" unless target
        if target.mcp_client?
          raise Refusal, "#{slug} is an mcp_client identity, not a platform agent definition — a run is recorded " \
                         "against the agent that was spawned, never against a session"
        end

        target
      end

      def provider_for
        credentialed_anthropic_provider || synthetic_provider
      end

      def credentialed_anthropic_provider
        credentialed = ::Ai::ProviderCredential.where(account_id: account.id, is_active: true).select(:ai_provider_id)
        account.ai_providers.active.platform_routable
               .where(provider_type: PROVIDER_TYPE, id: credentialed)
               .ordered_by_priority.first
      end

      # One inactive row per account, minted by the platform on the caller's
      # behalf (a bookkeeping scope, not a routing target): it carries no
      # credential, is is_active:false and is excluded by platform_routable, so
      # the create is deliberately not laddered behind ai.providers.create —
      # see the open question in the task record.
      #
      # `supported_models` stays empty on purpose:
      # Ai::AgentModelSelector enumerates candidates from it, and an inactive
      # provider is already outside its candidate set; platform_routable closes
      # the fallback arm too.
      def synthetic_provider
        account.ai_providers.find_by(slug: SYNTHETIC_PROVIDER_SLUG) || account.ai_providers.create!(
          name: SYNTHETIC_PROVIDER_NAME,
          slug: SYNTHETIC_PROVIDER_SLUG,
          provider_type: PROVIDER_TYPE,
          description: "Synthetic scope for Claude Code runs of platform agents reported through " \
                       "platform.record_agent_execution. Not a platform routing candidate.",
          api_base_url: SYNTHETIC_PROVIDER_ENDPOINT,
          api_endpoint: SYNTHETIC_PROVIDER_ENDPOINT,
          capabilities: %w[text_generation chat],
          supported_models: [],
          configuration_schema: { "type" => "object", "properties" => {} },
          requires_auth: false,
          is_active: false,
          metadata: { "execution_source" => SOURCE, "synthetic" => true }
        )
      rescue ActiveRecord::RecordNotUnique
        account.ai_providers.find_by!(slug: SYNTHETIC_PROVIDER_SLUG)
      end

      # The task digest is caller-supplied prose (a prompt excerpt): capped, then
      # through the core PII path (the shell-output sanitizer lives in the
      # system extension and cannot be referenced from core), then capped AGAIN
      # — a placeholder can be LONGER than the text it replaces ("1.2.3.4" ->
      # "[REDACTED:IP_ADDRESS]"), so redaction can push a capped string back
      # over the ceiling the parameter advertises.
      def redacted_digest(text)
        capped = text.to_s.strip.truncate(MAX_DIGEST_CHARS, omission: "…")
        return "" if capped.empty?

        redacted = ::Ai::Security::PiiRedactionService.new(account: account)
                                                      .redact(text: capped, context: { source_type: "ClaudeCodeRun" }, log: false)[:redacted_text]
        redacted.to_s.truncate(MAX_DIGEST_CHARS, omission: "…")
      rescue StandardError => e
        Rails.logger.warn("[ClaudeExport::ExecutionRecorder] digest redaction failed, dropping digest: #{e.class}: #{e.message}")
        ""
      end

      def execution_id_for(run_key)
        "#{EXECUTION_ID_PREFIX}#{Digest::SHA256.hexdigest("#{account.id}:#{run_key}")}"
      end

      # Ai::AgentExecution#user is a required belongs_to, but the reporting
      # principal is frequently NOT a User: the SubagentStop hook reaches the
      # proxy as an mTLS instance principal. Attribution then falls back to a
      # DETERMINISTIC account user (oldest first, id-tiebroken) rather than
      # whatever `users.first` returns for that query plan, and the real
      # principal is preserved verbatim in execution_context["executor_ref"].
      # An account with no users at all is refused by name instead of raising
      # an opaque RecordInvalid.
      def attributed_user
        @attributed_user ||= @user || account.users.order(:created_at, :id).first ||
                             raise(Refusal, "Account #{account.id} has no user to attribute the run to; " \
                                            "record_agent_execution needs one resolvable principal")
      end

      def mint(target, provider, report, digest, execution_id)
        now = Time.current
        ::Ai::AgentExecution.create!(
          account: account,
          agent: target,
          user: attributed_user,
          provider: provider,
          execution_id: execution_id,
          status: "running",
          started_at: now - (report[:duration_ms] / 1000.0),
          input_parameters: { "task_digest" => digest, "source" => SOURCE },
          # Cost lands on create, never through the status update — see the
          # class comment (boundary rule).
          cost_usd: cost_for(report),
          execution_context: {
            "source" => SOURCE,
            "executor_kind" => SOURCE,
            "executor_agent_id" => @executor_agent&.id,
            "executor_ref" => @executor_ref,
            "run_key" => report[:run_key],
            "reported_model" => report[:model],
            "triggered_at" => now.iso8601
          }
        )
      end

      # The terminal transition the model's hooks key on. An already-finished
      # row keeps its status (a retry updates metrics only).
      def finish(execution, report, digest)
        attrs = {
          duration_ms: report[:duration_ms],
          tokens_used: report[:input_tokens] + report[:output_tokens],
          cost_usd: cost_for(report),
          input_parameters: execution.input_parameters.merge("task_digest" => digest),
          performance_metrics: {
            "model" => report[:model],
            "prompt_tokens" => report[:input_tokens],
            "completion_tokens" => report[:output_tokens],
            "executor_kind" => SOURCE
          },
          output_data: { "model_used" => report[:model] }
        }

        unless execution.finished?
          attrs[:status] = report[:outcome]
          attrs[:completed_at] = Time.current
          attrs[:error_message] = error_message_for(report[:outcome])
        end

        execution.update!(attrs)
      end

      def error_message_for(outcome)
        case outcome
        when "failed" then "Claude Code run reported failed"
        when "cancelled" then "Claude Code run cancelled"
        end
      end

      # Reported cost when given, else the platform's own price ladder for the
      # served model (0.0 when no pricing is synced — the same fallback a
      # platform execution gets from AgentExecution#calculate_cost).
      def cost_for(report)
        return report[:cost_usd] if report[:cost_usd]

        ::Ai::CostCalculationService.calculate(
          model_id: report[:model],
          prompt_tokens: report[:input_tokens],
          completion_tokens: report[:output_tokens]
        )
      end

      def summary(execution, target, provider, report, created)
        {
          id: execution.id,
          execution_id: execution.execution_id,
          created: created,
          status: execution.status,
          agent_id: target.id,
          agent_slug: target.slug,
          provider_id: provider.id,
          provider_slug: provider.slug,
          model: report[:model],
          model_tier: ::Ai::ModelTiers.classify(report[:model]).to_s,
          executor_kind: SOURCE,
          executor_agent_id: @executor_agent&.id,
          tokens_used: execution.tokens_used,
          cost_usd: execution.cost_usd.to_f,
          run_key: report[:run_key]
        }
      end
    end
  end
end
