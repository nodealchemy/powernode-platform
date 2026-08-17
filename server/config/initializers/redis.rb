# frozen_string_literal: true

module Powernode
  module Redis
    # Logical Redis databases reserved for RAILS_ENV=test.
    #
    # The suite shares one Redis daemon with whatever else runs on the box, and
    # it does NOT clean up after itself. Every example that touches a cache
    # writes under the account it just built, the DB rolls that account back,
    # and the Redis keys outlive it with nobody left who could ever read them.
    #
    # Measured on dev-cell 2026-08-17, with the suite pointed at db 0 alongside
    # development: 425,484 orphaned keys / 10.6 GB resident, spread across
    # ~82,000 distinct account UUIDs, on an instance whose database contained
    # exactly ONE account. That was ~68% of a 15.5 GB node's RAM held by
    # garbage, and it took the node down. See TEST_WORKER_DATABASE below for
    # the half of this that is worse than wasted memory.
    #
    # 15/14 are the top of the default 16-database range, chosen to stay clear
    # of the app's own 0 (cache/general) / 1 (worker) / 2 (ActionCable).
    TEST_DATABASE = 15
    # Sidekiq's queues live in the worker database, so a suite sharing it does
    # not merely leak keys — it can enqueue real jobs into the queue a live
    # worker is draining. Isolate it on the same principle.
    TEST_WORKER_DATABASE = 14

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
        isolate_test_database(AdminSetting.redis_url_from_config(config), TEST_DATABASE)
      rescue StandardError
        isolate_test_database(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), TEST_DATABASE)
      end

      def worker_url
        # Worker uses DB 1
        base = url
        isolate_test_database(base.sub(/\/\d+\z/, "/1"), TEST_WORKER_DATABASE)
      rescue StandardError
        isolate_test_database("redis://localhost:6379/1", TEST_WORKER_DATABASE)
      end

      def reconfigure!
        @client&.close rescue nil
        @client = nil
        @resolved_config = nil
      end

      private

      # Rewrite a redis:// URL's database component onto a test-only database.
      #
      # Applied at every seam that produces a URL rather than at one chokepoint,
      # because #url and #client_options each resolve their own (client_options
      # re-derives from AdminSetting so it can attach timeouts) and each has a
      # rescue fallback that produces a URL of its own. Isolation that covers
      # only the happy path is not isolation — the fallback is exactly what runs
      # when AdminSetting is unavailable, which is common in specs.
      #
      # Returns the URL untouched outside RAILS_ENV=test, and on any URL whose
      # database component cannot be located (leaves an unexpected shape alone
      # rather than corrupting it).
      def isolate_test_database(url_str, database)
        return url_str unless Rails.env.test?
        return url_str if url_str.blank?

        url_str.sub(%r{/\d+\z}, "/#{database}")
      end

      def resolved_config
        @resolved_config ||= AdminSetting.redis_config
      rescue StandardError
        # DB not available during boot/migrations
        default_fallback_config
      end

      def client_options
        config = resolved_config
        url_str = isolate_test_database(AdminSetting.redis_url_from_config(config), TEST_DATABASE)

        opts = { url: url_str }
        opts[:connect_timeout] = config["connect_timeout"] if config["connect_timeout"]
        opts[:read_timeout] = config["read_timeout"] if config["read_timeout"]
        opts[:write_timeout] = config["write_timeout"] if config["write_timeout"]
        opts[:ssl] = config["ssl"] if config["ssl"]
        opts
      rescue StandardError
        { url: isolate_test_database(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), TEST_DATABASE) }
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
