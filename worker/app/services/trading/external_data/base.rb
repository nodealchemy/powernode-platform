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

      protected

      # Shared HTTP GET → JSON helper for all external data clients.
      # Handles SSL, timeouts, User-Agent, JSON parsing, and error logging.
      def http_get_json(url, headers: {})
        uri = URI(url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == "https")
        http.open_timeout = 10
        http.read_timeout = 15

        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = ENV.fetch("NOAA_USER_AGENT", "PowernodeWorker")
        request["Accept"] = "application/json"
        headers.each { |k, v| request[k] = v }

        response = http.request(request)
        return nil unless response.code.to_i == 200

        JSON.parse(response.body)
      rescue => e
        log("HTTP GET failed for #{uri.host}#{uri.path}: #{e.message}", level: :error)
        nil
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
