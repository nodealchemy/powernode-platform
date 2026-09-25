# frozen_string_literal: true

module Ai
  # Token usage per model and call site over a recent window, read from the
  # counts TrackedWorkerLlmClient stores on Ai::AgentExecution#performance_metrics.
  # A call site is the agent that made the call plus the client method
  # (complete / complete_structured / complete_with_tools).
  #
  # It answers the questions later prompt changes are measured against: how much
  # input is served from cache versus written to it, and how often a route stops
  # at max_tokens or is refused. Executions that predate the Phase 0 capture
  # count 0 cache writes and no stop reason.
  class UsageReportService
    COLUMNS = %i[model call_site calls input cache_read cache_creation output max_tokens_stops refusals].freeze

    # finish_reason values that mean "cut off by the output cap": Anthropic's
    # stop_reason and OpenAI's finish_reason spell it differently.
    MAX_TOKENS_REASONS = %w[max_tokens length].freeze

    def initialize(days:, account: nil)
      @days = Integer(days)
      raise ArgumentError, "days must be positive" unless @days.positive?

      @account = account
    end

    # @return [Array<Hash>] one row per model x call site, most input first
    def rows
      scope.group(Arel.sql(MODEL), Arel.sql(CALL_SITE))
           .order(Arel.sql("SUM(#{metric('prompt_tokens')}) DESC"))
           .pluck(*select_list)
           .map { |values| COLUMNS.zip(values).to_h }
    end

    def totals
      rows.each_with_object(Hash.new(0)) do |row, sum|
        (COLUMNS - %i[model call_site]).each { |col| sum[col] += row[col].to_i }
      end
    end

    private

    MODEL = "COALESCE(ai_agent_executions.performance_metrics->>'model', " \
            "ai_agent_executions.input_parameters->>'model', 'unknown')"
    CALL_SITE = "COALESCE(ai_agents.slug, ai_agents.name) || ' #' || " \
                "COALESCE(ai_agent_executions.input_parameters->>'method', '?')"
    private_constant :MODEL, :CALL_SITE

    def scope
      base = ::Ai::AgentExecution.joins(:agent).where(ai_agent_executions: { created_at: @days.days.ago.. })
      @account ? base.where(ai_agent_executions: { account_id: @account.id }) : base
    end

    def metric(key)
      "COALESCE((ai_agent_executions.performance_metrics->>'#{key}')::bigint, 0)"
    end

    def select_list
      finish = "ai_agent_executions.performance_metrics->>'finish_reason'"
      max_tokens = MAX_TOKENS_REASONS.map { |r| ActiveRecord::Base.connection.quote(r) }.join(", ")
      [
        MODEL,
        CALL_SITE,
        "COUNT(*)",
        "SUM(#{metric('prompt_tokens')})",
        "SUM(#{metric('cached_tokens')})",
        "SUM(#{metric('cache_creation_tokens')})",
        "SUM(#{metric('completion_tokens')})",
        "COUNT(*) FILTER (WHERE #{finish} IN (#{max_tokens}))",
        "COUNT(*) FILTER (WHERE ai_agent_executions.performance_metrics->>'refused' = 'true' OR #{finish} = 'refusal')"
      ].map { |sql| Arel.sql(sql) }
    end
  end
end
