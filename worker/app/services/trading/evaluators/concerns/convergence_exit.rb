# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Models edge decay as a market approaches resolution and triggers exits
      # when remaining edge falls below the cost of holding + exiting.
      #
      # Edge decays as: edge_remaining = edge_0 * (hours_left / total_hours) ^ alpha
      # With alpha < 1, decay is slow early and accelerates near settlement.
      #
      # Depends on DepthAware (included in Base) for accurate exit cost estimation.
      module ConvergenceExit
        # Check whether a position should be exited due to convergence pressure.
        #
        # @param position [Hash] open position from context
        # @param hours_left [Float, nil] hours until market settlement
        # @return [Hash, nil] exit signal hash or nil if no exit needed
        def convergence_exit_check(position, hours_left)
          return nil unless position && hours_left && hours_left > 0

          alpha = param("convergence_alpha", 0.7)
          opp_cost_annual = param("opportunity_cost_annual", 0.05)
          min_hours_held = param("convergence_min_hours", 1.0)

          # Must have been held for minimum time
          opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil
          return nil unless opened_at

          hours_held = (Time.current - opened_at) / 3600.0
          return nil if hours_held < min_hours_held

          # Recover entry edge from last entry indicators
          entry_edge = extract_entry_edge
          return nil unless entry_edge && entry_edge > 0

          # Total time horizon: hours held + hours remaining
          total_hours = hours_held + hours_left

          remaining = expected_remaining_edge(
            current_edge: entry_edge,
            hours_left: hours_left,
            total_hours: total_hours,
            alpha: alpha
          )

          exit_cost = estimate_signal_cost
          hourly_opp_cost = opp_cost_annual / (365.25 * 24.0)
          opp_cost = hourly_opp_cost * hours_left

          if should_exit_convergence?(remaining_edge: remaining, exit_cost: exit_cost, opportunity_cost: opp_cost)
            side = position["side"] || "long"
            {
              type: "exit",
              direction: side,
              confidence: convergence_confidence(remaining, exit_cost),
              strength: 0.6,
              reasoning: "Convergence exit: remaining edge #{(remaining * 100).round(2)}% " \
                         "(decayed from #{(entry_edge * 100).round(2)}%) < exit cost " \
                         "#{(exit_cost * 100).round(2)}% + opportunity cost #{(opp_cost * 100).round(3)}% " \
                         "with #{hours_left.round(1)}h to settlement",
              indicators: {
                edge: remaining,
                entry_edge: entry_edge,
                remaining_edge: remaining,
                exit_cost: exit_cost,
                opportunity_cost: opp_cost,
                hours_left: hours_left,
                hours_held: hours_held.round(2),
                convergence_alpha: alpha,
                exit_reason: "convergence"
              }
            }
          end
        end

        # Model edge decay over time.
        #
        # Uses power-law decay: edge(t) = edge_0 * (t_remaining / t_total)^alpha
        # With alpha=0.7: slow initial decay, accelerating as settlement nears.
        #
        # @return [Float] expected remaining edge as a fraction
        def expected_remaining_edge(current_edge:, hours_left:, total_hours:, alpha: nil)
          alpha ||= param("convergence_alpha", 0.7)
          return 0.0 if total_hours <= 0 || hours_left <= 0

          time_fraction = (hours_left / total_hours).clamp(0.0, 1.0)
          current_edge * (time_fraction**alpha)
        end

        # Determine if convergence exit should trigger.
        #
        # Exit when: remaining_edge < exit_cost + opportunity_cost
        def should_exit_convergence?(remaining_edge:, exit_cost:, opportunity_cost: 0.0)
          remaining_edge < (exit_cost + opportunity_cost)
        end

        private

        def extract_entry_edge
          edge = @last_entry_indicators["edge"] || @last_entry_indicators[:edge]
          return edge.to_f.abs if edge

          edge_pct = @last_entry_indicators["edge_pct"] || @last_entry_indicators[:edge_pct]
          return (edge_pct.to_f / 100.0).abs if edge_pct

          nil
        end

        def convergence_confidence(remaining_edge, exit_cost)
          return 0.9 if remaining_edge <= 0

          # Higher confidence when remaining edge is much smaller than exit cost
          ratio = exit_cost > 0 ? remaining_edge / exit_cost : 1.0
          if ratio < 0.5
            0.85
          elsif ratio < 0.8
            0.75
          else
            0.65
          end
        end
      end
    end
  end
end
