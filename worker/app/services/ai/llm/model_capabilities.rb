# frozen_string_literal: true

module Ai
  module Llm
    # Generic, dependency-free model-capability resolver keyed by model id/prefix.
    #
    # Prefix-based classification, mirroring the convention in
    # server/app/models/ai/model_tiers.rb. This module is DUPLICATED verbatim in the
    # worker and the server (two separate Rails apps that each mirror the Anthropic
    # request-builder logic — there is no shared lib across apps). Keep the two copies
    # in sync: server/app/services/ai/llm/model_capabilities.rb.
    #
    # Why it exists: current-generation Claude models REJECT (HTTP 400) request
    # parameters that older models accept, so the request builder must decide per
    # model which parameters are legal:
    #   - Fable 5 / Mythos 5 / Opus 4.7 / Opus 4.8 / Sonnet 5 reject sampling params
    #     (temperature/top_p/top_k) AND thinking.budget_tokens.
    #   - Fable 5 / Mythos 5 additionally reject an explicit `thinking` block of any
    #     kind (thinking is ALWAYS on): both {type:"enabled",...} and
    #     {type:"disabled"} are 400s. The `thinking` param must be OMITTED, or set to
    #     {type:"adaptive"} (or {type:"adaptive",display:"summarized"} to surface a
    #     reasoning summary). Depth is controlled ONLY by output_config.effort.
    module ModelCapabilities
      # Capability profile for models restricted to the adaptive-only reasoning
      # surface: no sampling params, thinking always-on (adaptive only, never
      # enabled/disabled), effort-controlled depth, no assistant prefill, and a
      # 1M-token context / 128K-token max-output envelope.
      REASONING_ADAPTIVE_ONLY = {
        sampling_params: false,
        thinking_mode: :adaptive_only,
        effort: true,
        prefill: false,
        max_output: 128_000,
        context_window: 1_000_000
      }.freeze

      # Everything else routed through the Anthropic builder — opus-4-6 / sonnet-4-6 /
      # haiku / older Claude, plus openai / grok / ollama that reuse this code path.
      # Preserves today's permissive behavior so nothing regresses. max_output /
      # context_window are left nil ("unknown — the caller keeps its own default").
      PERMISSIVE_DEFAULT = {
        sampling_params: true,
        thinking_mode: :configurable,
        effort: false,
        prefill: true,
        max_output: nil,
        context_window: nil
      }.freeze

      # Prefixes whose models use the adaptive-only reasoning surface. Prefix-based,
      # mirroring Ai::ModelTiers. `claude-fable` / `claude-mythos` cover the -5 ids and
      # any future point releases; the opus/sonnet entries are the current reasoning
      # tier that shares the same request restrictions.
      ADAPTIVE_ONLY_PREFIXES = %w[
        claude-fable
        claude-mythos
        claude-opus-4-7
        claude-opus-4-8
        claude-sonnet-5
      ].freeze

      module_function

      # The frozen capability profile Hash for a model id.
      def profile(model_id)
        mid = model_id.to_s
        return REASONING_ADAPTIVE_ONLY if ADAPTIVE_ONLY_PREFIXES.any? { |prefix| mid.start_with?(prefix) }

        PERMISSIVE_DEFAULT
      end

      # Whether temperature / top_p / top_k may be sent for this model.
      def supports_sampling_params?(model_id) = profile(model_id)[:sampling_params]

      # :adaptive_only | :configurable | :none — how the `thinking` param must be built.
      def thinking_mode(model_id) = profile(model_id)[:thinking_mode]

      # Whether output_config.effort is accepted for this model.
      def supports_effort?(model_id) = profile(model_id)[:effort]

      # Whether a trailing assistant-prefill turn is legal for this model.
      def supports_prefill?(model_id) = profile(model_id)[:prefill]

      # Max output tokens (nil when unknown — caller keeps its own default).
      def max_output_tokens(model_id) = profile(model_id)[:max_output]

      # Context window in tokens (nil when unknown).
      def context_window(model_id) = profile(model_id)[:context_window]
    end
  end
end
