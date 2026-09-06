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

    # Per-lane isolation. config/database.yml already appends TEST_ENV_NUMBER
    # to the postgres database name, so concurrent lanes get private schemas.
    # Redis did not follow, and rails_helper flushes the resolved database at
    # :suite — so two lanes sharing one database means whichever starts second
    # wipes the first one's keys mid-run. The victim does not raise; it loses
    # cached state and fails somewhere unrelated, or passes vacuously wherever
    # the code under test rescues a missing key.
    #
    # Lane N takes the pair (TEST_DATABASE, TEST_WORKER_DATABASE) shifted down
    # by N * TEST_LANE_STRIDE, so lane 0 keeps 15/14 exactly as before and no
    # lane's main database can ever land on another lane's worker. The floor is
    # 3 because 0/1/2 are the application's own (cache, worker, ActionCable);
    # the default 16-database range therefore affords six lanes, which is above
    # the worktree cap the fan-out script enforces.
    TEST_LANE_STRIDE = 2
    TEST_DATABASE_FLOOR = 3
    MAX_TEST_LANES = ((TEST_WORKER_DATABASE - TEST_DATABASE_FLOOR) / TEST_LANE_STRIDE) + 1

    class << self
      # The lane this process belongs to.
      #
      # Read from TEST_REDIS_LANE, an explicit integer, NOT inferred from the
      # TEST_ENV_NUMBER string. Inference was tried and is unsafe here: the
      # only producer of TEST_ENV_NUMBER in this repo is
      # scripts/prepare-worktree.sh, which writes "_<worktree-slug>" — and
      # every real worktree slug (ext_develop, parent_develop, pp) contains no
      # digits at all. Any digit-scraping rule therefore returns 0 for all of
      # them, silently handing every concurrent worktree the same redis
      # database and reinstating exactly the bug this derivation removes. A
      # slug that happens to carry digits is worse than useless: a campaign
      # branch named campaign-019f7cb5 would scrape "019".
      #
      # So a lane is declared, never guessed. An unset TEST_ENV_NUMBER is the
      # bare checkout and is lane 0. A TEST_ENV_NUMBER with no declared lane
      # REFUSES, because that process has a private postgres database and
      # would otherwise quietly share lane 0's redis with whoever else is
      # running.
      def test_lane
        declared = ENV["TEST_REDIS_LANE"].to_s.strip
        return Integer(declared, 10) if declared.match?(/\A\d+\z/)

        if declared.present?
          raise ArgumentError,
                "TEST_REDIS_LANE=#{declared.inspect} is not a lane number. Set it to an " \
                "integer in 0..#{MAX_TEST_LANES - 1}, or unset it in the bare checkout."
        end
        return 0 if ENV["TEST_ENV_NUMBER"].to_s.strip.empty?

        raise ArgumentError,
              "TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER'].inspect} gives this process its own " \
              "postgres database but no redis lane, so it would share redis database " \
              "#{TEST_DATABASE} with every other lane and flush their keys at :suite. Declare " \
              "TEST_REDIS_LANE=<0..#{MAX_TEST_LANES - 1}> (unique among concurrent lanes) in " \
              "server/.env.test.local. scripts/prepare-worktree.sh writes one for new worktrees."
      end

      def test_database
        lane_database(TEST_DATABASE)
      end

      def test_worker_database
        lane_database(TEST_WORKER_DATABASE)
      end

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
        isolate_test_database(AdminSetting.redis_url_from_config(config), test_database)
      rescue StandardError
        isolate_test_database(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), test_database)
      end

      def worker_url
        # Worker uses DB 1
        base = url
        isolate_test_database(base.sub(/\/\d+\z/, "/1"), test_worker_database)
      rescue StandardError
        isolate_test_database("redis://localhost:6379/1", test_worker_database)
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
      # Refuses rather than wrapping. A lane with no database of its own must
      # not quietly reuse one that another lane already owns — that is the bug
      # this derivation exists to remove, and it would come back silently.
      # The raise survives the fallback rescues in #url / #worker_url /
      # #client_options because those handlers resolve the lane too, so the
      # second raise happens inside the handler and escapes the method.
      def lane_database(base)
        # Outside RAILS_ENV=test nothing is isolated and #isolate_test_database
        # returns the URL untouched, so the lane is not merely unused there —
        # resolving it would let a stray TEST_REDIS_LANE in a dev or production
        # process raise out of Powernode::Redis.client at boot.
        return base unless Rails.env.test?

        lane = test_lane
        if lane >= MAX_TEST_LANES
          raise ArgumentError,
                "TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER'].inspect} is lane #{lane}, but only lanes " \
                "0..#{MAX_TEST_LANES - 1} have a redis database of their own (0/1/2 belong to the " \
                "application). Run fewer lanes, or give each lane its own redis."
        end

        base - (lane * TEST_LANE_STRIDE)
      end

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
        url_str = isolate_test_database(AdminSetting.redis_url_from_config(config), test_database)

        opts = { url: url_str }
        opts[:connect_timeout] = config["connect_timeout"] if config["connect_timeout"]
        opts[:read_timeout] = config["read_timeout"] if config["read_timeout"]
        opts[:write_timeout] = config["write_timeout"] if config["write_timeout"]
        opts[:ssl] = config["ssl"] if config["ssl"]
        opts
      rescue StandardError
        { url: isolate_test_database(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), test_database) }
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
