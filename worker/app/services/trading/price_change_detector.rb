# frozen_string_literal: true

module Trading
  # Detects significant price movements from WebSocket feeds and publishes
  # wakeup signals to Redis so strategy runners can react early instead of
  # waiting for their full tick_interval to elapse.
  #
  # Maintains a per-pair rolling window of the last triggered price. When a
  # new price arrives that exceeds the threshold, it publishes a wakeup key
  # with a short TTL (debounce) to prevent thundering herd.
  class PriceChangeDetector
    # Configurable per strategy type — maps to how quickly each type should react
    REACTIVITY_TIERS = {
      "instant" => {
        strategy_types: %w[arbitrage combinatorial_arbitrage cross_platform_arbitrage],
        price_threshold: 0.003,   # 0.3%
        parity_threshold: 0.003,  # 0.3% parity gap change
        max_frequency: 2,         # seconds between wakeups
      },
      "fast" => {
        strategy_types: %w[momentum mean_reversion market_making prediction_market_making longshot_fading],
        price_threshold: 0.015,   # 1.5%
        parity_threshold: 0.01,
        max_frequency: 5,
      },
      "standard" => {
        strategy_types: %w[llm_probability agent_ensemble sentiment_analysis],
        price_threshold: 0.03,    # 3%
        parity_threshold: 0.02,
        max_frequency: 15,
      },
      "slow" => {
        strategy_types: %w[weather_model_alpha news_reactive whale_copying],
        price_threshold: 0.05,    # 5%
        parity_threshold: 0.03,
        max_frequency: 60,
      }
    }.freeze

    # Reverse lookup: strategy_type → tier name
    STRATEGY_TIER = REACTIVITY_TIERS.each_with_object({}) do |(tier, config), map|
      config[:strategy_types].each { |st| map[st] = tier }
    end.freeze

    WAKE_KEY_PREFIX = "trading:wake"
    WAKE_CHANNEL = "trading:price_events"

    def initialize
      @last_triggered = {} # pair => price at last trigger
      @mutex = Mutex.new
    end

    # Called by WebSocket clients on every price update.
    # Checks significance and publishes wakeup if threshold crossed.
    #
    # @param pair [String] e.g. "BTC-2025-04-01/YES"
    # @param price [Float] current price
    # @param parity_gap [Float, nil] YES+NO deviation from $1.00
    # @param venue_slug [String] e.g. "polymarket"
    def on_price_update(pair:, price:, parity_gap: nil, venue_slug: nil)
      return if price.nil? || price <= 0

      significant_tiers = check_significance(pair, price, parity_gap)
      return if significant_tiers.empty?

      publish_wakeup!(pair, price, significant_tiers, venue_slug)
    end

    # Check if a wakeup is pending for a given pair at a specific tier.
    # Used by strategy runners to decide whether to wake up early.
    #
    # @param pair [String]
    # @param tier [String] reactivity tier name
    # @return [Boolean]
    def self.wake_pending?(pair, tier = nil)
      key = if tier
              "#{WAKE_KEY_PREFIX}:#{tier}:#{pair}"
            else
              "#{WAKE_KEY_PREFIX}:*:#{pair}"
            end

      if tier
        Sidekiq.redis { |conn| conn.exists?(key) }
      else
        # Check any tier
        REACTIVITY_TIERS.keys.any? do |t|
          Sidekiq.redis { |conn| conn.exists?("#{WAKE_KEY_PREFIX}:#{t}:#{pair}") }
        end
      end
    rescue StandardError
      false
    end

    # Get the tier for a strategy type
    def self.tier_for(strategy_type)
      STRATEGY_TIER[strategy_type] || "standard"
    end

    private

    def check_significance(pair, price, parity_gap)
      @mutex.synchronize do
        last = @last_triggered[pair]
        return all_tiers if last.nil? # First price — significant for all

        price_change_pct = (price - last).abs / [last.abs, 0.01].max

        significant = []
        REACTIVITY_TIERS.each do |tier_name, config|
          is_significant = price_change_pct >= config[:price_threshold]

          # Parity gap significance (for YES/NO pairs)
          if parity_gap && config[:parity_threshold]
            is_significant ||= parity_gap.abs >= config[:parity_threshold]
          end

          significant << tier_name if is_significant
        end

        # Update last triggered price if any tier was significant
        @last_triggered[pair] = price if significant.any?

        significant
      end
    end

    def all_tiers
      REACTIVITY_TIERS.keys
    end

    def publish_wakeup!(pair, price, tiers, venue_slug)
      Sidekiq.redis do |conn|
        tiers.each do |tier|
          config = REACTIVITY_TIERS[tier]
          key = "#{WAKE_KEY_PREFIX}:#{tier}:#{pair}"
          # SET NX with TTL = max_frequency — debounces rapid updates
          conn.set(key, price.to_s, nx: true, ex: config[:max_frequency])
        end

        # Also publish to a channel for any listeners doing pub/sub
        event = {
          pair: pair,
          price: price,
          tiers: tiers,
          venue_slug: venue_slug,
          at: Time.now.to_f
        }.to_json
        conn.publish(WAKE_CHANNEL, event)
      end
    rescue StandardError
      # Non-critical — strategy will still evaluate on its normal interval
    end
  end
end
