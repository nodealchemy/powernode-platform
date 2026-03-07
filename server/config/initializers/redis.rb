# frozen_string_literal: true

module Powernode
  module Redis
    class << self
      def client
        @client ||= new_client
      end

      def new_client
        ::Redis.new(client_options)
      end

      def new_worker_client
        ::Redis.new(url: worker_url)
      end

      def url
        config = resolved_config
        AdminSetting.redis_url_from_config(config)
      rescue StandardError
        ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      end

      def worker_url
        # Worker uses DB 1
        base = url
        base.sub(/\/\d+\z/, "/1")
      rescue StandardError
        "redis://localhost:6379/1"
      end

      def reconfigure!
        @client&.close rescue nil
        @client = nil
        @resolved_config = nil
      end

      private

      def resolved_config
        @resolved_config ||= AdminSetting.redis_config
      rescue StandardError
        # DB not available during boot/migrations
        default_fallback_config
      end

      def client_options
        config = resolved_config
        url_str = AdminSetting.redis_url_from_config(config)

        opts = { url: url_str }
        opts[:connect_timeout] = config["connect_timeout"] if config["connect_timeout"]
        opts[:read_timeout] = config["read_timeout"] if config["read_timeout"]
        opts[:write_timeout] = config["write_timeout"] if config["write_timeout"]
        opts[:ssl] = config["ssl"] if config["ssl"]
        opts
      rescue StandardError
        { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
      end

      def default_fallback_config
        {
          "host" => ENV.fetch("REDIS_HOST", "localhost"),
          "port" => ENV.fetch("REDIS_PORT", 6379).to_i,
          "database" => ENV.fetch("REDIS_DB", 0).to_i,
          "password" => ENV.fetch("REDIS_PASSWORD", nil),
          "ssl" => false,
          "url" => ENV.fetch("REDIS_URL", nil),
          "connect_timeout" => 5,
          "read_timeout" => 5,
          "write_timeout" => 5,
          "pool_size" => 5
        }
      end
    end
  end
end

# Set Rails.application.config.redis_client after initialization
Rails.application.config.after_initialize do
  Rails.application.config.redis_client = Powernode::Redis.client
rescue StandardError => e
  Rails.logger.warn "Powernode::Redis: Could not initialize shared client: #{e.message}"
end
