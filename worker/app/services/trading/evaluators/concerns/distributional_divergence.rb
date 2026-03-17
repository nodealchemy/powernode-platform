# frozen_string_literal: true

module Trading
  module Evaluators
    module Concerns
      # KL-divergence based distributional arbitrage detection.
      #
      # Groups correlated markets into clusters (by event_ticker from the
      # pair_registry) and detects distributional mispricings that pairwise
      # spread checks miss.
      #
      # D_KL(P‖Q) = Σ Pᵢ·ln(Pᵢ/Qᵢ)
      #
      # Where:
      #   P = empirical distribution from normalized market prices
      #   Q = theoretical distribution from constraint relationships
      #
      # High D_KL → the market-implied joint distribution diverges from the
      # theoretical one → systematic mispricing across the cluster.
      #
      # Depends on pair_registry for market grouping and fetch_pair_price
      # (from CombinatorialArbitrage) for price lookups.
      module DistributionalDivergence
        # Minimum number of markets in a cluster for divergence analysis
        MIN_CLUSTER_SIZE = 3

        # Epsilon for log calculations to avoid log(0)
        EPSILON = 1e-10

        # Detect distributional mispricings across a cluster of related markets.
        # Returns signals for the most mispriced legs.
        #
        # @param market_price [Float] current price of this market
        # @return [Array<Hash>] divergence-based trading signals
        def check_distributional_divergence(market_price)
          signals = []
          clusters = build_market_clusters
          return signals if clusters.empty?

          if clusters.any?
            log("KL-divergence: #{clusters.size} cluster(s), sizes: #{clusters.map { |k, v| "#{k}=#{v.size}" }.first(5).join(', ')}")
          end

          min_divergence = param("min_kl_divergence", 0.05)
          max_signals = param("max_divergence_signals", 2)

          clusters.each do |event_key, cluster|
            next if cluster.size < MIN_CLUSTER_SIZE
            next unless cluster.key?(strategy_pair) # Only analyze clusters we belong to

            # Build empirical distribution from market prices
            empirical = build_empirical_distribution(cluster)
            next if empirical.size < MIN_CLUSTER_SIZE

            # Build theoretical distribution from constraints
            theoretical = build_theoretical_distribution(cluster, empirical)
            next if theoretical.empty?

            # Compute KL-divergence
            divergence = kl_divergence(empirical, theoretical)
            next if divergence < min_divergence

            # Find the most mispriced legs
            leg_scores = score_mispriced_legs(empirical, theoretical, cluster)

            # Only signal for our own market's mispricing
            my_score = leg_scores[strategy_pair]
            next unless my_score && my_score[:divergence_contribution] > min_divergence * 0.5

            direction = my_score[:implied_direction]
            edge = my_score[:edge_estimate]
            next if edge <= 0

            signals << build_signal(
              type: "entry",
              direction: direction,
              confidence: divergence_confidence(divergence, cluster.size),
              strength: (divergence / 0.2).clamp(0.0, 1.0),
              reasoning: "KL-divergence arbitrage: D_KL=#{divergence.round(4)} across " \
                         "#{cluster.size} markets (event: #{event_key}). " \
                         "#{strategy_pair} is #{my_score[:direction_label]} by " \
                         "#{(my_score[:price_gap].abs * 100).round(1)}%",
              indicators: {
                kl_divergence: divergence.round(4),
                cluster_size: cluster.size,
                event_key: event_key,
                edge: edge,
                price_gap: my_score[:price_gap],
                empirical_prob: my_score[:empirical],
                theoretical_prob: my_score[:theoretical],
                distributional_arb: true
              }
            )

            break if signals.size >= max_signals
          end

          signals
        end

        # Compute KL-divergence D_KL(P||Q).
        #
        # @param p [Hash] empirical distribution { key => probability }
        # @param q [Hash] theoretical distribution { key => probability }
        # @return [Float] KL-divergence (non-negative, 0 = identical)
        def kl_divergence(p, q)
          all_keys = (p.keys + q.keys).uniq
          d_kl = 0.0

          all_keys.each do |key|
            pi = [p[key] || EPSILON, EPSILON].max
            qi = [q[key] || EPSILON, EPSILON].max
            d_kl += pi * Math.log(pi / qi)
          end

          [d_kl, 0.0].max
        end

        private

        # Group markets from pair_registry by event_ticker.
        # Only includes YES pairs for clean probability interpretation.
        #
        # @return [Hash] { event_ticker => { pair => { price:, info: } } }
        def build_market_clusters
          clusters = {}
          return clusters unless @pair_registry.is_a?(Hash)

          @pair_registry.each do |pair, info|
            event = info["event_ticker"] || info[:event_ticker] ||
                    info["slug"] || info[:slug]
            next unless event

            # Only include YES pairs for clean probability interpretation
            next unless pair.to_s.end_with?("/YES")

            clusters[event] ||= {}
            price = if pair == strategy_pair
                      current_price
                    else
                      fetch_pair_price(pair)
                    end
            next unless price && price > 0 && price < 1

            clusters[event][pair] = {
              price: price,
              gamma_price: (info["gamma_price"] || info[:gamma_price])&.to_f,
              question: info["question"] || info[:question]
            }
          end

          clusters
        end

        # Build empirical probability distribution from market prices.
        # Normalizes prices to sum to 1.0.
        #
        # @return [Hash] { pair => normalized_probability }
        def build_empirical_distribution(cluster)
          raw_probs = {}
          cluster.each do |pair, data|
            # Prefer gamma prices (more accurate for illiquid markets)
            price = data[:gamma_price] && data[:gamma_price] > 0 ? data[:gamma_price] : data[:price]
            raw_probs[pair] = price
          end

          return {} if raw_probs.empty?

          total = raw_probs.values.sum
          return {} if total <= 0

          raw_probs.transform_values { |p| p / total }
        end

        # Build theoretical probability distribution from logical constraints.
        #
        # For mutually exclusive outcomes: starts from maximum entropy (uniform)
        # then adjusts based on known constraints. The divergence between this
        # and the empirical distribution quantifies mispricing.
        #
        # @return [Hash] { pair => theoretical_probability }
        def build_theoretical_distribution(cluster, empirical)
          n = cluster.size
          return {} if n == 0

          # Start with maximum entropy (uniform) distribution
          theoretical = {}
          uniform_prob = 1.0 / n
          cluster.each_key { |pair| theoretical[pair] = uniform_prob }

          # Adjust with cached constraints if available
          known_constraints = strategy_config["known_constraints"] || []
          if known_constraints.any?
            apply_constraint_adjustments(theoretical, known_constraints, cluster)
          end

          # Re-normalize after adjustments
          total = theoretical.values.sum
          theoretical.transform_values! { |p| p / total } if total > 0 && total != 1.0

          theoretical
        end

        # Adjust theoretical distribution based on known logical constraints.
        def apply_constraint_adjustments(theoretical, constraints, cluster)
          cluster_pairs = cluster.keys.to_set

          constraints.each do |constraint|
            pair = constraint["pair"]
            direction = constraint["direction"]
            confidence = (constraint["confidence"] || 0.5).to_f

            next unless cluster_pairs.include?(pair) || cluster_pairs.include?(strategy_pair)

            case direction
            when "a_implies_b"
              # P(B) >= P(A), shift B's theoretical probability up
              if cluster_pairs.include?(pair)
                current_a = theoretical[strategy_pair] || 0
                theoretical[pair] = [theoretical[pair] || 0, current_a].max * (1.0 + confidence * 0.2)
              end
            when "b_implies_a"
              # P(A) >= P(B), shift A's theoretical probability up
              if cluster_pairs.include?(strategy_pair)
                current_b = theoretical[pair] || 0
                theoretical[strategy_pair] = [theoretical[strategy_pair] || 0, current_b].max * (1.0 + confidence * 0.2)
              end
            end
          end
        end

        # Score each market leg's contribution to the total divergence.
        #
        # @return [Hash] { pair => { divergence_contribution:, edge_estimate:, ... } }
        def score_mispriced_legs(empirical, theoretical, cluster)
          scores = {}
          total_raw_price = cluster.values.sum { |d| d[:price] }

          cluster.each do |pair, data|
            p_i = empirical[pair] || EPSILON
            q_i = theoretical[pair] || EPSILON

            # Per-element KL contribution: p_i * ln(p_i / q_i)
            contribution = (p_i * Math.log(p_i / q_i)).abs

            # Price gap: how far the market price is from theoretical fair value
            theoretical_price = q_i * total_raw_price
            actual_price = data[:price]
            price_gap = actual_price - theoretical_price

            if price_gap > 0
              direction = "short"
              direction_label = "overpriced"
            else
              direction = "long"
              direction_label = "underpriced"
            end

            # Conservative edge: capture 50% of the gap
            edge_estimate = price_gap.abs * 0.5

            scores[pair] = {
              divergence_contribution: contribution,
              edge_estimate: edge_estimate,
              price_gap: price_gap,
              implied_direction: direction,
              direction_label: direction_label,
              empirical: p_i,
              theoretical: q_i,
              market_price: actual_price
            }
          end

          scores
        end

        def divergence_confidence(divergence, cluster_size)
          base = 0.4

          # Higher divergence → higher confidence
          div_bonus = [divergence * 2.0, 0.3].min

          # Larger clusters → higher confidence (more data points)
          size_bonus = [Math.log2([cluster_size, 2].max) * 0.05, 0.15].min

          (base + div_bonus + size_bonus).clamp(0.3, 0.85)
        end
      end
    end
  end
end
