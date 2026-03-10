# frozen_string_literal: true

module Trading
  module ExternalData
    class Base
      def initialize(cache: nil)
        @cache = cache || {}
      end

      # Override in subclasses — fetch data relevant to a market question
      def fetch_for_market(market_question, metadata = {})
        raise NotImplementedError, "#{self.class}#fetch_for_market must be implemented"
      end

      # Override in subclasses — check if this data source applies to a question
      def applicable?(question)
        raise NotImplementedError, "#{self.class}#applicable? must be implemented"
      end

      # Override in subclasses — cache TTL in seconds
      def cache_ttl
        3600  # 1 hour default
      end

      private

      def cached_fetch(cache_key, &block)
        if @cache[cache_key] && @cache[cache_key][:fetched_at] &&
           (Time.now - @cache[cache_key][:fetched_at]) < cache_ttl
          return @cache[cache_key][:data]
        end

        data = yield
        @cache[cache_key] = { data: data, fetched_at: Time.now }
        data
      end

      def log(message, level: :info)
        if defined?(Rails)
          Rails.logger.send(level, "[ExternalData::#{self.class.name.split('::').last}] #{message}")
        elsif defined?(PowernodeWorker)
          PowernodeWorker.application.logger.send(level, "[ExternalData::#{self.class.name.split('::').last}] #{message}")
        end
      end
    end
  end
end
