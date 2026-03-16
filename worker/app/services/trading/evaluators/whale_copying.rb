# frozen_string_literal: true

module Trading
  module Evaluators
    class WhaleCopying < Base
      register "whale_copying"

      def evaluate
        signals = []
        market_price = current_price
        return signals unless market_price
        return signals unless @llm_client && @provider_config

        @total_cost = 0.0

        # Cooldown check (bypassed in training)
        unless training?
          cooldown = param("cooldown_seconds", 60)
          if !has_open_position? && last_tick_at && last_tick_at > (Time.current - cooldown)
            return signals
          end
        end

        # Fetch whale activities: ExternalData → LLM fallback chain
        activities = fetch_whale_activities
        if activities.nil? || activities.empty?
          return check_exit_conditions(signals)
        end

        # Record external data source for learning tag enrichment
        record_external_data("whale_alert")

        # LLM Call 1: Classify activities (genuine trades vs transfers/staking/bridges)
        if param("use_llm_classification", true)
          classified = classify_activities(activities)
          return check_exit_conditions(signals) if classified.empty?
        else
          # Without LLM classification, treat all activities as trades
          classified = activities.map do |a|
            {
              is_trade: true,
              trade_type: "swap",
              direction: a[:direction] || "buy",
              token: a[:token] || "USDC",
              amount_usd: a[:amount_usd].to_f,
              confidence: 0.5,
              reasoning: "Unclassified whale transfer"
            }
          end
        end

        # Filter by classification confidence and minimum USD
        min_confidence = param("classification_confidence", 0.70)
        min_usd = param("min_whale_tx_usd", 100_000)
        trades = classified.select do |c|
          c[:is_trade] && c[:confidence].to_f >= min_confidence && c[:amount_usd].to_f >= min_usd
        end
        return check_exit_conditions(signals) if trades.empty?

        # Pick the strongest trade signal
        best_trade = trades.max_by { |t| t[:amount_usd].to_f * t[:confidence].to_f }
        return check_exit_conditions(signals) unless best_trade

        # LLM Call 2: Score whale conviction
        conviction = score_conviction(best_trade)
        return check_exit_conditions(signals) unless conviction

        # Store whale activity history (rolling window, like sentiment_analysis)
        store_whale_history(best_trade.merge(conviction: conviction))

        # Generate entry signal if conviction meets threshold and no open position
        min_conviction = param("min_conviction", 0.60)
        if !has_open_position? && conviction[:conviction_score].to_f >= min_conviction
          direction = conviction[:direction] || best_trade[:direction] || "long"
          edge = conviction[:conviction_score].to_f * param("conviction_to_edge_multiplier", 0.15)

          signals << build_signal(
            type: "entry",
            direction: direction,
            confidence: conviction[:conviction_score].to_f.clamp(0.0, 1.0),
            strength: conviction[:size_magnitude].to_f.clamp(0.0, 1.0),
            reasoning: "Whale activity: #{best_trade[:trade_type]} #{best_trade[:direction]} " \
                       "$#{best_trade[:amount_usd].to_f.round(0)} #{best_trade[:token]} — " \
                       "#{conviction[:reasoning]}",
            indicators: {
              whale_conviction: conviction[:conviction_score],
              whale_direction: direction,
              whale_reputation: conviction[:whale_reputation],
              trade_type: best_trade[:trade_type],
              amount_usd: best_trade[:amount_usd],
              classification_confidence: best_trade[:confidence],
              trades_found: trades.size,
              edge: edge
            }
          )
        end

        check_exit_conditions(signals)
        signals
      rescue StandardError => e
        log("Evaluation failed: #{e.message}", level: :warn)
        []
      end

      private

      # Fetch whale activities: ExternalData API → LLM fallback
      def fetch_whale_activities
        # Try external data from DataFetcher (which calls WhaleAlertClient)
        if @data_fetcher
          question = @market_question || strategy_pair
          external = @data_fetcher.fetch_external_data(question, whale_metadata)
          whale_data = external[:whale_activity]

          if whale_data && whale_data[:activities]&.any?
            # Filter by max activity age
            max_age = param("max_activity_age_minutes", 30).to_i * 60
            cutoff = Time.current - max_age

            filtered = whale_data[:activities].select do |a|
              next true if training? # Skip age filter in training
              ts = a[:timestamp] || a["timestamp"]
              ts ? (Time.parse(ts.to_s) > cutoff rescue true) : true
            end

            return filtered if filtered.any?
          end
        end

        # LLM fallback: generate synthetic whale assessment (training mode / no API key)
        generate_whale_assessment_via_llm
      end

      # Metadata hash for WhaleAlertClient
      def whale_metadata
        {
          chain: param("etherscan_chain", "polygon"),
          etherscan_api_key: param("etherscan_api_key"),
          watched_wallets: param("watched_wallets", []),
          min_whale_tx_usd: param("min_whale_tx_usd", 100_000)
        }
      end

      # LLM fallback: ask the model about whale sentiment for this market
      def generate_whale_assessment_via_llm
        question = @market_question || strategy_pair

        price_context = if price_history&.size.to_i > 3
          recent = price_history.last(5).map { |s| (s["close"] || s[:close]).to_f }
          "Recent prices: #{recent.map { |p| "#{(p * 100).round(1)}¢" }.join(', ')}"
        else
          "Limited price history available."
        end

        system_prompt = "You are an on-chain intelligence analyst specializing in whale wallet tracking " \
                        "for prediction markets. Assess whether large bettors (whales) are likely active " \
                        "on this market based on the question topic, current price levels, and market dynamics."

        # Inject learning context
        system_prompt += build_learning_prompt_context

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Market: #{question}\nCurrent price: #{(current_price * 100).round(1)}¢\n#{price_context}\n\nAssess likely whale activity and trading direction." }
          ],
          schema: {
            type: "object",
            properties: {
              whale_activity_detected: { type: "boolean" },
              activities: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    wallet_label: { type: "string" },
                    action: { type: "string", enum: %w[buy sell] },
                    token: { type: "string" },
                    estimated_usd: { type: "number" },
                    confidence: { type: "number" },
                    reasoning: { type: "string" }
                  },
                  required: %w[wallet_label action token estimated_usd confidence reasoning],
                  additionalProperties: false
                }
              }
            },
            required: %w[whale_activity_detected activities],
            additionalProperties: false
          },
          temperature: 0.3
        )

        @total_cost += last_llm_cost
        return nil unless response.is_a?(Hash) && response[:whale_activity_detected]

        # Convert LLM assessment to activity format
        Array(response[:activities]).map do |a|
          {
            wallet: a[:wallet_label] || "unknown",
            direction: a[:action] || "buy",
            token: a[:token] || "USDC",
            amount_usd: a[:estimated_usd].to_f,
            confidence: a[:confidence].to_f,
            reasoning: a[:reasoning],
            source: "llm_assessment",
            timestamp: Time.current.iso8601
          }
        end
      rescue StandardError => e
        log("LLM whale assessment fallback failed: #{e.message}", level: :warn)
        nil
      end

      # LLM Call 1: Classify whale activities (trade vs transfer/staking/bridge)
      def classify_activities(activities)
        return [] if activities.empty?

        system_prompt = "Classify each whale wallet transaction. Determine if it is a genuine trade " \
                        "(swap, prediction market bet) or a non-trade action (transfer, staking, LP, bridge). " \
                        "For prediction markets on Polymarket (Polygon), USDC transfers to CTF exchange " \
                        "contracts are bets. Assess direction and confidence."

        # Inject learning context
        system_prompt += build_learning_prompt_context

        activity_text = activities.each_with_index.map do |a, i|
          "[#{i}] Wallet: #{(a[:wallet] || a["wallet"]).to_s[0, 12]}... | " \
          "Direction: #{a[:direction] || a["direction"]} | " \
          "Token: #{a[:token] || a["token"]} | " \
          "Amount: $#{(a[:amount_usd] || a["amount_usd"]).to_f.round(0)} | " \
          "#{a[:reasoning] || a["reasoning"] || ""}"
        end.join("\n")

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Classify these whale transactions for market: #{@market_question || strategy_pair}\n\n#{activity_text}" }
          ],
          schema: {
            type: "object",
            properties: {
              activities: {
                type: "array",
                items: {
                  type: "object",
                  properties: {
                    index: { type: "integer" },
                    is_trade: { type: "boolean" },
                    trade_type: { type: "string", enum: %w[swap transfer staking lp bridge prediction_bet unknown] },
                    direction: { type: "string", enum: %w[buy sell neutral] },
                    token: { type: "string" },
                    amount_usd: { type: "number" },
                    confidence: { type: "number" },
                    reasoning: { type: "string" }
                  },
                  required: %w[index is_trade trade_type direction confidence reasoning],
                  additionalProperties: false
                }
              }
            },
            required: %w[activities],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost
        return [] unless response.is_a?(Hash) && response[:activities].is_a?(Array)

        response[:activities].filter_map do |c|
          idx = c[:index].to_i
          next unless idx >= 0 && idx < activities.size

          original = activities[idx]
          c.merge(
            amount_usd: c[:amount_usd] || (original[:amount_usd] || original["amount_usd"]).to_f,
            token: c[:token] || original[:token] || original["token"] || "USDC"
          )
        end
      rescue StandardError => e
        log("Activity classification failed: #{e.message}", level: :warn)
        []
      end

      # LLM Call 2: Score whale conviction strength
      def score_conviction(best_trade)
        system_prompt = "Score the conviction strength of this whale trade. Consider: " \
                        "transaction size relative to market, timing patterns, wallet reputation " \
                        "(smart money vs degen), and whether the trade signals strong directional conviction."

        # Inject experience replay context
        if @trading_context.is_a?(Hash)
          replays = @trading_context["experience_replays"] || @trading_context[:experience_replays]
          system_prompt += "\n\nPast whale trade outcomes:\n#{replays}" if replays.present?
        end

        history = load_whale_history
        if history.any?
          recent = history.last(5).map { |h| "#{h['direction'] || h[:direction]}: $#{(h['amount_usd'] || h[:amount_usd]).to_f.round(0)}" }.join(", ")
          system_prompt += "\n\nRecent whale activity pattern: #{recent}"
        end

        response = llm_complete_structured(
          messages: [
            { role: "system", content: system_prompt },
            { role: "user", content: "Trade: #{best_trade[:trade_type]} #{best_trade[:direction]} " \
                                     "$#{best_trade[:amount_usd].to_f.round(0)} #{best_trade[:token]}\n" \
                                     "Classification confidence: #{best_trade[:confidence]}\n" \
                                     "Market: #{@market_question || strategy_pair}\n" \
                                     "Current price: #{(current_price * 100).round(1)}¢\n" \
                                     "Reasoning: #{best_trade[:reasoning]}" }
          ],
          schema: {
            type: "object",
            properties: {
              conviction_score: { type: "number", description: "0-1 whale conviction strength" },
              direction: { type: "string", enum: %w[long short] },
              size_magnitude: { type: "number", description: "0-1 normalized transaction size" },
              whale_reputation: { type: "string", enum: %w[smart_money institutional degen unknown] },
              reasoning: { type: "string" }
            },
            required: %w[conviction_score direction size_magnitude reasoning],
            additionalProperties: false
          },
          temperature: 0.2
        )

        @total_cost += last_llm_cost
        return nil unless response.is_a?(Hash) && response[:conviction_score]

        response
      rescue StandardError => e
        log("Conviction scoring failed: #{e.message}", level: :warn)
        nil
      end

      # Check exit conditions: max hold, stop loss, take profit, whale reversal
      def check_exit_conditions(signals)
        return signals unless has_open_position?

        position = current_position
        return signals unless position

        entry_price = (position["entry_price"] || 0).to_f
        side = position["side"] || "long"
        pnl_pct = entry_price > 0 ? ((current_price - entry_price) / entry_price * 100 * (side == "short" ? -1 : 1)) : 0

        # Stop loss
        stop_loss = param("stop_loss_pct", 5.0)
        if pnl_pct <= -stop_loss
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.9, strength: 0.9,
            reasoning: "Whale copying stop-loss: PnL #{pnl_pct.round(2)}% exceeds -#{stop_loss}% limit",
            indicators: { pnl_pct: pnl_pct, edge: 0 }
          )
          return signals
        end

        # Take profit
        take_profit = param("take_profit_pct", 10.0)
        if pnl_pct >= take_profit
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.85, strength: 0.8,
            reasoning: "Whale copying take-profit: PnL #{pnl_pct.round(2)}% exceeds +#{take_profit}% target",
            indicators: { pnl_pct: pnl_pct, edge: 0 }
          )
          return signals
        end

        # Max hold time
        opened_at = position["opened_at"] ? Time.parse(position["opened_at"]) : nil
        max_hold = param("max_hold_seconds", 7200).to_i
        if opened_at && opened_at < (Time.current - max_hold)
          signals << build_signal(
            type: "exit", direction: side,
            confidence: 0.6, strength: 0.5,
            reasoning: "Max hold time expired (#{max_hold / 60} minutes)",
            indicators: { pnl_pct: pnl_pct, hold_seconds: (Time.current - opened_at).to_i }
          )
          return signals
        end

        # Whale reversal detection: if recent whale history shows opposing direction
        history = load_whale_history
        if history.size >= 2
          recent_directions = history.last(3).map { |h| h["direction"] || h[:direction] }
          position_aligned = side == "long" ? "buy" : "sell"
          reversed = recent_directions.count { |d| d != position_aligned } >= 2

          if reversed
            signals << build_signal(
              type: "exit", direction: side,
              confidence: 0.7, strength: 0.6,
              reasoning: "Whale reversal detected: recent activity shifted against position",
              indicators: { pnl_pct: pnl_pct, recent_directions: recent_directions }
            )
          end
        end

        signals
      end

      # Store whale activity to strategy config (rolling window)
      def store_whale_history(activity)
        return unless @data_fetcher

        history = strategy_config["whale_history"] || []
        history << {
          direction: activity[:direction],
          amount_usd: activity[:amount_usd],
          trade_type: activity[:trade_type],
          conviction: activity[:conviction]&.slice(:conviction_score, :direction, :whale_reputation),
          timestamp: Time.current.iso8601
        }

        # Keep rolling window based on max_activity_age_minutes
        window = param("max_activity_age_minutes", 30).to_i * 60
        cutoff = Time.current - window
        history = history.select do |h|
          ts = h[:timestamp] || h["timestamp"]
          ts ? (Time.parse(ts.to_s) > cutoff rescue true) : true
        end

        @data_fetcher.update_strategy_config(
          strategy_id: strategy_id,
          config_updates: { "whale_history" => history.last(50) }
        )
      rescue StandardError => e
        log("Failed to store whale history: #{e.message}", level: :warn)
      end

      # Load whale activity history from strategy config
      def load_whale_history
        strategy_config["whale_history"] || []
      end

      # Build learning context sections for LLM prompts
      def build_learning_prompt_context
        return "" unless @trading_context.is_a?(Hash)

        context = ""

        learnings = @trading_context["compound_learnings"] || @trading_context[:compound_learnings]
        context += "\n\nPatterns from past whale trades:\n#{learnings}" if learnings.present?

        warnings = @trading_context["reflexion_warnings"] || @trading_context[:reflexion_warnings]
        context += "\n\nWarnings from past failures:\n#{warnings}" if warnings.present?

        replays = @trading_context["experience_replays"] || @trading_context[:experience_replays]
        context += "\n\nPast trade examples:\n#{replays}" if replays.present?

        context
      end
    end
  end
end
