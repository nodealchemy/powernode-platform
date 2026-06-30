# frozen_string_literal: true

module Ai
  module Ralph
    # G13 — loop-readiness preflight. Operationalises the "four conditions for a
    # viable loop" (docs/reference/loop-engineering-parity.md → Operating doctrine)
    # as a gate a loop must pass BEFORE it activates, instead of a checklist nobody
    # enforces.
    #
    # Only conditions that can be enforced today without breaking valid loops are
    # BLOCKING; the rest are surfaced as warnings (token/cost caps → G5;
    # scope-in-bounds → G14, which warns when a loop's declared scope overlaps the
    # keep-manual denylist; secret-scrub/security → G15/G4 still pending). The single
    # blocking condition is "no objective gate": a loop with real verification
    # disabled (post-G1 the gate is on by default) must not run unless an operator
    # explicitly acknowledges the risk.
    class LoopReadinessService
      Result = Struct.new(:ready, :failures, :warnings, keyword_init: true) do
        def blocked?
          !ready
        end

        def to_h
          { ready: ready, failures: failures, warnings: warnings }
        end
      end

      def initialize(ralph_loop)
        @loop = ralph_loop
      end

      def evaluate
        failures = []
        warnings = []

        check_objective_gate(failures, warnings)
        check_hard_stops(warnings)
        check_runnable_env(warnings)
        check_scope(warnings)

        Result.new(ready: failures.empty?, failures: failures, warnings: warnings)
      end

      private

      # Condition 1 — an objective verification gate must be present. Post-G1 the
      # real test gate is on by default; if it's been disabled, refuse to run unless
      # the operator has explicitly acknowledged running without one.
      def check_objective_gate(failures, warnings)
        return if @loop.real_test_execution?

        if acknowledged_no_gate?
          warnings << "Running without an objective verification gate on operator acknowledgement (configuration.acknowledge_no_gate)."
        else
          failures << "No objective verification gate: real_test_execution is disabled. Enable it, " \
                      "or set configuration.acknowledge_no_gate=true to run without one."
        end
      end

      # Condition 2 — hard-stops. An iteration cap should always be set; metered
      # (platform-driven) loops should additionally carry a token/cost cap (G5).
      def check_hard_stops(warnings)
        warnings << "No iteration cap (max_iterations) is set." unless @loop.max_iterations.to_i.positive?

        return unless @loop.platform_driven?
        return if token_cap.present? || cost_cap.present?

        warnings << "Metered (platform-driven) loop has no token/cost cap configured (G5)."
      end

      # Condition 4 — runnable env. Sandbox verification checks the code out from
      # repository_url; without one a gated loop can't actually verify its commits.
      def check_runnable_env(warnings)
        return unless @loop.real_test_execution?
        return if @loop.repository_url.present?

        warnings << "No repository_url configured; the sandbox can't check out the code to verify commits."
      end

      # Condition 3 — scope in bounds (G14). When the loop declares a target scope,
      # warn (non-blocking) if any declared path overlaps the keep-manual denylist
      # (auth/crypto/payments/…). The doctrine is to keep those MANUAL; an autonomous
      # loop pointed at them should be flagged, not silently allowed. Sourced from the
      # single policy catalog so the gate and the guardrail share one list.
      def check_scope(warnings)
        manual = Ai::Loop::PolicyCatalog.manual_paths(declared_scope_paths)
        return if manual.empty?

        warnings << "Declared scope overlaps keep-manual paths (#{manual.join(', ')}); " \
                    "the loop-engineering doctrine keeps auth/crypto/payments and similar MANUAL (G14)."
      end

      # The loop's declared target scope, if any. Supports both
      # configuration["scope"]["paths"] and a flat configuration["target_paths"];
      # absent/blank ⇒ no declared scope (the check no-ops).
      def declared_scope_paths
        config = @loop.configuration || {}
        scoped = config.dig("scope", "paths")
        Array(scoped.presence || config["target_paths"]).map(&:to_s).reject(&:blank?)
      end

      def acknowledged_no_gate?
        @loop.configuration&.dig("acknowledge_no_gate") == true
      end

      def token_cap
        @loop.configuration&.dig("max_tokens")
      end

      def cost_cap
        @loop.configuration&.dig("max_cost")
      end
    end
  end
end
