# frozen_string_literal: true

module Ai
  module Routing
    # Resolves the reasoning-effort value (output_config.effort) for an LLM call
    # on an effort-capable (adaptive-only) model.
    #
    # Precedence: explicit pin > complexity-derived > DEFAULT_EFFORT.
    #   * explicit pin — an operator-set effort on the agent (mcp_metadata
    #     model_config.effort) or the loop (configuration.effort).
    #   * complexity-derived — Ai::Routing::TaskComplexityClassifierService maps
    #     the task to trivial/simple/moderate/complex/expert; COMPLEXITY_TO_EFFORT
    #     maps that to low/medium/high/xhigh/max. Uses classify_preview (NO DB
    #     write) so per-task routing stays cheap.
    #   * default — DEFAULT_EFFORT ("high").
    #
    # Returns nil for models that do NOT accept output_config.effort (per
    # Ai::Llm::ModelCapabilities.supports_effort?), so the caller simply omits the
    # param and legacy models are unchanged.
    #
    # Pure/stateless mapping utility: the DECISION to populate effort lives with
    # the caller (Ai::Ralph::TaskExecutor#resolve_effort) — this only computes the
    # value. Effort is LIVE for every effort-capable model (not gated by the Fable
    # framework switch).
    class EffortMapper
      COMPLEXITY_TO_EFFORT = {
        "trivial"  => "low",
        "simple"   => "medium",
        "moderate" => "high",
        "complex"  => "xhigh",
        "expert"   => "max"
      }.freeze

      DEFAULT_EFFORT = "high"
      VALID_EFFORTS = %w[low medium high xhigh max].freeze
      DEFAULT_TASK_TYPE = "agent_task"

      def self.resolve(account:, model:, pinned_effort: nil, task_type: nil, messages: [], tools: [])
        new(account: account, model: model).resolve(
          pinned_effort: pinned_effort, task_type: task_type, messages: messages, tools: tools
        )
      end

      # Same precedence (pin > complexity-derived > default) against an ALREADY
      # classified complexity level — so a caller that has already run one
      # classification (e.g. Ai::Routing::TaskTierResolver) derives effort without
      # a second classify. Returns nil for non-effort-capable models. Single source
      # of truth for the mapping (COMPLEXITY_TO_EFFORT / DEFAULT_EFFORT / VALID_EFFORTS).
      def self.effort_for_level(model:, complexity_level:, pinned_effort: nil)
        return nil unless ::Ai::Llm::ModelCapabilities.supports_effort?(model.to_s)

        pinned = pinned_effort.to_s.strip.downcase
        return pinned if VALID_EFFORTS.include?(pinned)

        COMPLEXITY_TO_EFFORT[complexity_level.to_s] || DEFAULT_EFFORT
      end

      def initialize(account:, model:)
        @account = account
        @model = model.to_s
      end

      # @return [String, nil] effort value, or nil when the model is not effort-capable.
      def resolve(pinned_effort: nil, task_type: nil, messages: [], tools: [])
        return nil unless ::Ai::Llm::ModelCapabilities.supports_effort?(@model)

        normalize(pinned_effort) ||
          derive_from_complexity(task_type, messages, tools) ||
          DEFAULT_EFFORT
      end

      private

      def normalize(effort)
        e = effort.to_s.strip.downcase
        VALID_EFFORTS.include?(e) ? e : nil
      end

      def derive_from_complexity(task_type, messages, tools)
        return nil if Array(messages).empty?

        result = ::Ai::Routing::TaskComplexityClassifierService
                 .new(account: @account)
                 .classify_preview(
                   task_type: (task_type.presence || DEFAULT_TASK_TYPE),
                   messages: messages,
                   tools: Array(tools)
                 )
        COMPLEXITY_TO_EFFORT[result[:complexity_level]]
      rescue StandardError => e
        Rails.logger.warn("[EffortMapper] complexity classify failed: #{e.class}: #{e.message}")
        nil
      end
    end
  end
end
