# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # Maintains running Bayesian probability estimates per market using a
      # Beta-Binomial conjugate model.
      #
      # Instead of recomputing probability from scratch each tick, the belief
      # tracker incrementally updates a posterior distribution with new evidence
      # (price movements, volume signals, model outputs).
      #
      # Prior: Beta(α₀, β₀) initialized from market price
      #   α₀ = price × prior_strength
      #   β₀ = (1 - price) × prior_strength
      #
      # Update: Each tick provides evidence that updates α and β
      # Posterior: E[p] = α / (α + β)
      #
      # State survives update_context (evaluator instances are reused across ticks
      # in training) because @_belief_states is an instance variable not reset by
      # update_context.
      module BayesianBelief
        # Get the current Bayesian posterior probability for this market.
        # Returns nil if no belief has been initialized.
        #
        # @return [Float, nil] posterior mean probability
        def bayesian_posterior
          state = current_belief_state
          return nil unless state

          state[:alpha] / (state[:alpha] + state[:beta])
        end

        # Get the posterior variance (uncertainty measure).
        # Higher variance = less confident in the estimate.
        #
        # @return [Float, nil] posterior variance
        def bayesian_variance
          state = current_belief_state
          return nil unless state

          a = state[:alpha]
          b = state[:beta]
          (a * b) / ((a + b)**2 * (a + b + 1))
        end

        # Number of observations incorporated into current belief.
        #
        # @return [Integer]
        def bayesian_observations
          state = current_belief_state
          state ? state[:observations] : 0
        end

        # Update the belief state with new evidence from current tick.
        # Should be called once per evaluation cycle.
        #
        # @param evidence_up [Float] strength of evidence supporting YES (0-1)
        # @param evidence_down [Float] strength of evidence supporting NO (0-1)
        # @param weight [Float] evidence weight multiplier (default 1.0)
        def update_belief(evidence_up: 0.0, evidence_down: 0.0, weight: 1.0)
          state = ensure_belief_state
          w = weight * param("bayesian_evidence_weight", 1.0)

          state[:alpha] += evidence_up * w
          state[:beta] += evidence_down * w
          state[:observations] += 1
          state[:last_updated] = Time.current

          # Decay: gradually reduce certainty to allow adaptation to regime changes.
          # Without decay, beliefs become increasingly rigid as observations accumulate.
          decay = param("bayesian_decay_rate", 0.995)
          if state[:observations] > 5 && decay < 1.0
            floor = param("bayesian_prior_strength", 10.0) * 0.5
            state[:alpha] = [state[:alpha] * decay, floor].max
            state[:beta] = [state[:beta] * decay, floor].max
          end
        end

        # Update belief from price movement (convenience method).
        # Price moving up → evidence for YES, price moving down → evidence for NO.
        #
        # @param previous_price [Float] price at previous tick
        # @param current_price [Float] price at current tick
        # @param volume_weight [Float] optional volume-based weight multiplier
        def update_belief_from_price(previous_price:, current_price:, volume_weight: 1.0)
          return if previous_price.nil? || previous_price <= 0

          delta = current_price - previous_price
          magnitude = delta.abs / [previous_price, 0.01].max

          # Scale evidence by magnitude: a 5% move is stronger evidence than a 0.1% move
          evidence = [magnitude * 10.0, 1.0].min

          if delta > 0
            update_belief(evidence_up: evidence, weight: volume_weight)
          elsif delta < 0
            update_belief(evidence_down: evidence, weight: volume_weight)
          end
          # No update on zero delta (no new information)
        end

        # Blend a raw probability estimate with the Bayesian posterior.
        # Weight shifts toward posterior as more observations accumulate.
        #
        # @param raw_estimate [Float] raw probability from model/market (0-1)
        # @param min_observations [Integer] minimum observations before blending
        # @return [Float] blended probability
        def bayesian_blend(raw_estimate, min_observations: nil)
          min_obs = min_observations || param("bayesian_min_observations", 3)
          posterior = bayesian_posterior
          return raw_estimate unless posterior

          obs = bayesian_observations
          return raw_estimate if obs < min_obs

          # Weight posterior more as observations increase (log-weighted)
          # At min_obs: ~0% posterior, at 50 obs: ~60% posterior
          max_weight = param("bayesian_max_posterior_weight", 0.7)
          posterior_weight = if obs <= min_obs
                              0.0
                            else
                              log_ratio = Math.log(obs.to_f / min_obs)
                              log_max = Math.log(50.0 / [min_obs, 1].max)
                              w = log_max > 0 ? log_ratio / log_max : 0.0
                              [w * max_weight, max_weight].min
                            end

          raw_weight = 1.0 - posterior_weight
          blended = raw_estimate * raw_weight + posterior * posterior_weight
          blended.clamp(0.001, 0.999)
        end

        # Reset the belief state for this market (e.g., after regime change detected).
        def reset_belief
          @_belief_states&.delete(belief_state_key)
        end

        private

        def current_belief_state
          @_belief_states&.dig(belief_state_key)
        end

        def ensure_belief_state
          @_belief_states ||= {}
          key = belief_state_key
          @_belief_states[key] ||= initialize_belief_prior
        end

        def belief_state_key
          strategy_pair || strategy_id || "default"
        end

        def initialize_belief_prior
          price = current_price
          price = 0.5 if price <= 0 || price >= 1

          strength = param("bayesian_prior_strength", 10.0)
          {
            alpha: price * strength,
            beta: (1.0 - price) * strength,
            observations: 0,
            initial_price: price,
            created_at: Time.current,
            last_updated: Time.current
          }
        end
      end
    end
  end
end
