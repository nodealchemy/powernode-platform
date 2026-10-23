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
    # can also run), else to the account's SEEDED, INACTIVE "claude-code"
    # provider scope (Ai::ClaudeExport::ProviderScopeSeeder) scoped out of
    # platform routing by Ai::Provider.platform_routable — the selector must
    # never pick a Claude Code-only model for a platform run. This class only
    # RESOLVES that scope: the report path is reachable by any
    # ai.agents.execute holder, and that grant must not mint provider rows, so
    # a missing scope is refused by name (MissingProviderScope) instead.
    #
    # ASSEMBLY (skills-first agents, PRE-2). A report carrying the assembly_id a
    # session got from assemble_task links that assembly's Ai::RoutingDecision to
    # the execution (agent_execution_id; the first execution to claim it wins) and
    # writes ONE Ai::SkillUsageRecord per selected skill that still exists, on the
    # target agent and the execution, so a Claude Code run credits the skills it
    # used. The assembly must be this account's, a "task_assembly" decision, made
    # for the agent being reported — anything else is refused BEFORE a row is
    # written. Idempotent with the run: a retry finds each usage row and adds none.
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
      # The synthetic scope's identity lives with its seeder; the slug is
      # re-exported because readers key on the recorder.
      SYNTHETIC_PROVIDER_SLUG = ProviderScopeSeeder::SLUG
      # Anthropic is the only provider family Claude Code runs; the credentialed
      # provider lookup keys on Ai::Provider#provider_type.
      PROVIDER_TYPE = ProviderScopeSeeder::PROVIDER_TYPE

      # A refusal carries a machine-readable `reason` and `details` beside its
      # message, so the MCP verb (and a caller) can act on it without parsing prose.
      class Refusal < StandardError
        attr_reader :reason, :details

        def initialize(message = nil, reason: nil, details: {})
          super(message)
          @reason = reason
          @details = details
        end
      end

      # A canonical (global, account_id NULL) is a read-only template: a run is
      # never attributed to it. Raised when no account shadow can be minted to
      # attribute the run to, instead of falling back to the global row.
      class GlobalRowRefused < Refusal; end
      # A Refusal (the MCP verb reports it as an error rather than raising)
      # for the operator-fixable case: the account has no seeded scope.
      class MissingProviderScope < Refusal; end

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
        assembly = resolve_assembly(report[:assembly_id], target)
        provider = provider_for
        digest = redacted_digest(report[:task_digest])

        execution_id = execution_id_for(report[:run_key])
        execution = ::Ai::AgentExecution.find_by(execution_id: execution_id)
        created = execution.nil?
        credited = 0

        ::Ai::AgentExecution.transaction do
          execution ||= mint(target, provider, report, digest, execution_id)
          finish(execution, report, digest)
          credited = assembly ? credit_assembly(assembly, execution, target, report) : 0
        end

        summary(execution, target, provider, report, created, assembly, credited)
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

        # `input` is the whole input footprint; cache_read and cache_creation
        # are the parts of it served from and written to the prompt cache
        # (.claude/hooks/subagent-report.sh). Clamped so they never exceed it.
        input_tokens = [ tokens["input"].to_i, 0 ].max
        cache_read = tokens["cache_read"].to_i.clamp(0, input_tokens)
        cache_creation = tokens["cache_creation"].to_i.clamp(0, input_tokens - cache_read)

        {
          agent_slug: params[:agent_slug].to_s.strip,
          model: model,
          outcome: outcome,
          duration_ms: [ params[:duration_ms].to_i, 0 ].max,
          input_tokens: input_tokens,
          output_tokens: [ tokens["output"].to_i, 0 ].max,
          cached_tokens: cache_read,
          cache_creation_tokens: cache_creation,
          cost_usd: params[:cost_usd].presence && [ params[:cost_usd].to_f, 0.0 ].max,
          task_digest: params[:task_digest].to_s,
          run_key: run_key,
          assembly_id: params[:assembly_id].to_s.strip.presence
        }
      end

      # The agent the run attaches to is ALWAYS an account-scoped row. A global
      # canonical is a read-only template (the operator's shadow rule): the run
      # goes to the account's shadow of it, minted on first use through
      # Ai::Agents::AccountPrincipalResolver (clone with cloned_from_id,
      # source_version, source_snapshot). The resolver's `acting` path would hand
      # back the canonical itself when nothing can be minted; this writer never
      # takes that fallback, it refuses with a structured reason and writes
      # nothing.
      def resolve_target(slug)
        raise Refusal, "agent_slug is required" if slug.empty?

        target = ::Ai::Agent.resolve_for(account.id, slug: slug)
        raise Refusal, "No platform agent matches agent_slug: #{slug}" unless target
        if target.mcp_client?
          raise Refusal, "#{slug} is an mcp_client identity, not a platform agent definition — a run is recorded " \
                         "against the agent that was spawned, never against a session"
        end

        return target unless target.global?

        shadow = ::Ai::Agents::AccountPrincipalResolver.for(canonical_slug: target.slug, account: account, user: @user)
        if shadow.nil? || shadow.global?
          raise GlobalRowRefused.new(
            "Refused: #{slug} is a global canonical (a read-only template) and no account shadow could be minted " \
            "for account #{account.id} (reason: no_mintable_principal — the account needs a user to own the " \
            "shadow and a provider to run it on). Nothing was recorded.",
            reason: "no_mintable_principal",
            details: { agent_slug: slug, account_id: account.id, canonical_id: target.id }
          )
        end

        shadow
      end

      # The Ai::RoutingDecision assemble_task persisted, or nil when the report
      # names none. Refused unless it is this account's task assembly for the
      # agent being reported.
      def resolve_assembly(assembly_id, target)
        return nil if assembly_id.blank?

        assembly = if assembly_id.match?(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/)
          ::Ai::RoutingDecision.find_by(id: assembly_id, account_id: account.id, request_type: ::Ai::Assembly::Service::REQUEST_TYPE)
        end
        raise Refusal, "No task assembly #{assembly_id} for this account (assemble_task returns the assembly_id)" unless assembly

        assembled_for = assembly.request_metadata["agent_slug"]
        if assembled_for != target.slug
          raise Refusal, "Assembly #{assembly_id} was made for #{assembled_for}, not #{target.slug}; pass the assembly_id of this agent's own assemble_task"
        end

        assembly
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

      # The account's seeded scope (one inactive row per account, a
      # bookkeeping scope, not a routing target). Resolve only — never create:
      # the seed (every account at seed time) and Accounts::ProvisionService
      # (accounts created after first boot) own the row.
      def synthetic_provider
        ProviderScopeSeeder.find_for(account) || raise(
          MissingProviderScope,
          "Account #{account.id} has no `#{SYNTHETIC_PROVIDER_SLUG}` provider scope to record a Claude Code run " \
          "under and no credentialed Anthropic provider; it is seeded by #{ProviderScopeSeeder::SEED_FILE} " \
          "(a fresh install: `rails db:seed`; an established one, where db:seed is first-boot only: " \
          "`#{ProviderScopeSeeder::REMEDY_TASK}`)"
        )
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
            "cached_tokens" => report[:cached_tokens],
            "cache_creation_tokens" => report[:cache_creation_tokens],
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

      USAGE_OUTCOMES = { "completed" => "success", "failed" => "failure", "cancelled" => "partial" }.freeze

      # Link the assembly to the execution and credit its skills. The first
      # execution to claim an assembly links it (and fills in its outcome); a
      # retry of the same run finds every usage row and adds none.
      # @return [Integer] the skills credited by this execution (new or existing)
      def credit_assembly(assembly, execution, target, report)
        # Claim the assembly atomically: only the first execution to report it
        # links it and credits its skills. A retry of that same run (same
        # execution) re-enters here and stays idempotent; a SECOND run with the
        # same assembly_id is recorded as a run but credits nothing.
        claimed = ::Ai::RoutingDecision.where(id: assembly.id, agent_execution_id: nil).update_all(agent_execution_id: execution.id, updated_at: Time.current) == 1
        assembly.reload
        record_assembly_outcome(assembly, report) if claimed
        return 0 unless assembly.agent_execution_id == execution.id

        slugs = Array(assembly.request_metadata["selected"]).filter_map { |entry| entry["slug"].presence }.uniq
        skills = ::Ai::Skill.for_account(account.id).where(slug: slugs).account_override_first.to_a.uniq(&:slug)
        skills.count do |skill|
          usage = ::Ai::SkillUsageRecord.find_or_initialize_by(account_id: account.id, ai_skill_id: skill.id, execution_id: execution.id)
          next true unless usage.new_record?

          usage.update!(
            ai_agent_id: target.id, execution_type: "Ai::AgentExecution", outcome: USAGE_OUTCOMES.fetch(execution.status, "partial"),
            duration_ms: report[:duration_ms],
            metadata: { "source" => SOURCE, "assembly_id" => assembly.id, "run_key" => report[:run_key] }
          )
          true
        end
      end

      def record_assembly_outcome(assembly, report)
        outcome = { "completed" => "succeeded", "failed" => "failed", "cancelled" => "cancelled" }[report[:outcome]]
        return unless outcome

        assembly.record_outcome!(outcome: outcome, cost_usd: cost_for(report), latency_ms: report[:duration_ms],
                                 tokens_used: report[:input_tokens] + report[:output_tokens], latency_seam: "agent_execution")
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
          completion_tokens: report[:output_tokens],
          cached_tokens: report[:cached_tokens],
          cache_creation_tokens: report[:cache_creation_tokens]
        )
      end

      def summary(execution, target, provider, report, created, assembly = nil, credited = 0)
        {
          assembly_id: assembly&.id,
          skills_credited: credited,
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
