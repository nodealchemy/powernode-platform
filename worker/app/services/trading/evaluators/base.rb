# frozen_string_literal: true

module Trading
  module Evaluators
    # Worker-side strategy evaluator base class.
    #
    # Unlike server-side Trading::Strategies::Base which depends on ActiveRecord
    # models, evaluators operate on plain Hash data fetched from the Data API.
    # They produce signal Hashes that the server processes into orders.
    #
    # Subclasses implement #evaluate and return an Array of signal Hashes.
    class Base
      attr_reader :strategy_data, :market_data, :positions, :params,
                  :price_history, :allocated_capital, :parity_data, :spot_price_data, :last_entry_indicators,
                  :last_llm_cost
      attr_accessor :trading_context

      # @param context [Hash] the full evaluation context from DataFetcher#strategy_evaluation_context
      # @param llm_client [LlmProxyClient] direct LLM client (calls providers, not server)
      # @param data_fetcher [Trading::DataFetcher] for additional data lookups
      def initialize(context, llm_client: nil, data_fetcher: nil)
        @strategy_data = context["strategy"] || {}
        @market_data = context["market_data"] || {}
        @positions = context["positions"] || []
        @params = @strategy_data["parameters"] || {}
        @provider_config = context["provider_config"]
        @agent_id = context["agent_id"]
        @trading_context = context["trading_context"]
        @market_question = context["market_question"]
        @pair_registry = context["pair_registry"] || {}
        @price_history = context["price_history"] || []
        @allocated_capital = (context["allocated_capital"] || 0.0).to_f
        @market_expiry_raw = context["market_expiry"]
        @parity_data = context["parity_data"] || {}
        @spot_price_data = context["spot_price"] || {}
        @last_entry_indicators = context["last_entry_indicators"] || {}
        @llm_client = llm_client
        @data_fetcher = data_fetcher
      end

      # Subclasses override this to generate trading signals.
      # Returns Array of signal Hashes.
      def evaluate
        []
      end

      # Registry of evaluator classes by strategy type.
      # Returns nil for unregistered types (strategy is skipped).
      def self.for_type(strategy_type)
        registry[strategy_type]
      end

      def self.registry
        @registry ||= {}
      end

      def self.register(strategy_type)
        Base.registry[strategy_type] = self
      end

      # Default tick cost — subclasses accumulate in @total_cost via last_llm_cost.
      def tick_cost_usd
        @total_cost || 0.0
      end

      protected

      def param(key, default = nil)
        @params.fetch(key.to_s, default)
      end

      def current_price
        (@market_data["last_price"] || @market_data[:last_price]).to_f
      end

      def bid_price
        (@market_data["bid"] || @market_data[:bid]).to_f
      end

      def ask_price
        (@market_data["ask"] || @market_data[:ask]).to_f
      end

      def spread
        return nil unless bid_price > 0 && ask_price > 0
        ask_price - bid_price
      end

      def spread_pct
        return nil unless spread && bid_price > 0
        spread / bid_price
      end

      def has_open_position?
        @positions.any?
      end

      def current_position
        @positions.max_by { |p| p["opened_at"] || "" }
      end

      def strategy_pair
        @strategy_data["pair"]
      end

      def strategy_id
        @strategy_data["id"]
      end

      def account_id
        @strategy_data["account_id"]
      end

      def last_tick_at
        raw = @strategy_data["last_tick_at"]
        raw ? Time.parse(raw) : nil
      rescue ArgumentError
        nil
      end

      def market_expiry
        @market_expiry_raw ? Time.parse(@market_expiry_raw) : nil
      rescue ArgumentError
        nil
      end

      def strategy_config
        @strategy_data["config"] || {}
      end

      def agent_model
        @provider_config&.dig("model") || param("llm_model", "claude-haiku-4-5-20251001")
      end

      # Make an LLM call with structured output (JSON schema enforced).
      # Calls the AI provider directly from the worker — no server round-trip.
      # Cost is captured in @last_llm_cost before parsing strips it.
      def llm_complete_structured(messages:, schema:, model: nil, temperature: 0.3)
        @last_llm_cost = 0.0
        return nil unless @llm_client && @provider_config

        response = @llm_client.complete_structured(
          provider_config: @provider_config,
          messages: messages,
          schema: schema,
          model: model || agent_model,
          temperature: temperature
        )

        @last_llm_cost = extract_cost(response)
        parse_structured_response(response)
      end

      # Make a standard LLM completion call.
      def llm_complete(messages:, model: nil, **opts)
        return nil unless @llm_client && @provider_config

        @llm_client.complete(
          provider_config: @provider_config,
          messages: messages,
          model: model || agent_model,
          **opts
        )
      end

      # Calculate LLM cost from a response for cost tracking.
      def extract_cost(response)
        return 0.0 unless response.is_a?(Hash)
        (response["cost"] || 0.0).to_f
      end

      def build_signal(type:, direction:, confidence:, strength: nil, reasoning: nil, indicators: {})
        edge = indicators[:edge]&.abs || indicators[:edge_pct]&.abs&./(100.0)
        estimated_cost = estimate_signal_cost
        net_edge = edge ? edge - estimated_cost : nil
        urgency = classify_urgency(net_edge)

        {
          type: type,
          direction: direction,
          confidence: confidence.clamp(0.0, 1.0),
          strength: strength&.clamp(0.0, 1.0),
          reasoning: reasoning,
          indicators: indicators,
          urgency: urgency
        }
      end

      def classify_urgency(net_edge)
        return "medium" unless net_edge

        if net_edge > 0.10
          "high"
        elsif net_edge > 0.05
          "medium"
        elsif net_edge > 0.02
          "low"
        else
          "skip"
        end
      end

      def estimate_signal_cost
        spread_cost = spread_pct || 0.005
        spread_cost + 0.0
      end

      def parse_structured_response(response)
        return nil unless response

        content = response.is_a?(Hash) ? response["content"] : response
        return nil unless content

        if content.is_a?(Hash)
          content.deep_symbolize_keys
        elsif content.is_a?(String) && !content.empty?
          JSON.parse(content, symbolize_names: true)
        end
      rescue JSON::ParserError
        nil
      end

      def log(message, level: :info)
        PowernodeWorker.application.logger.send(level, "[Trading::Evaluators::#{self.class.name.split('::').last}] #{message}")
      end
    end
  end
end
