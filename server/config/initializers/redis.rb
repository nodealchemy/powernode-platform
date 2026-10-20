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
    # Seconds. See new_worker_client.
    WORKER_CONNECT_TIMEOUT = 2
    WORKER_READ_TIMEOUT = 2

    # See worker_url.
    WORKER_REDIS_URL_ENV = "POWERNODE_WORKER_REDIS_URL"
    DEPRECATED_WORKER_REDIS_URL_ENV = "SIDEKIQ_REDIS_URL"

    TEST_LANE_STRIDE = 2
    TEST_DATABASE_FLOOR = 3
    # Lanes a default 16-database daemon affords (the worktree lanes). See .max_test_lanes for the
    # figure on a daemon with more databases.
    MAX_TEST_LANES = ((TEST_WORKER_DATABASE - TEST_DATABASE_FLOOR) / TEST_LANE_STRIDE) + 1

    # Opt-in dedicated test daemon (scripts/test-redis.sh), used by the parallel suite
    # (scripts/parallel-rspec.sh). Both default to "unset", which keeps every serial and worktree
    # run byte-identical: the application's configured daemon, 16 databases, the lanes above.
    #
    #   TEST_REDIS_PORT       loopback port of the dedicated daemon. When set, every test URL is
    #                         rebuilt as redis://127.0.0.1:<port>/<db> (that daemon has no password
    #                         and no TLS, so the application's credentials are not sent to it).
    #   TEST_REDIS_DATABASES  how many logical databases that daemon was started with (`databases`).
    #                         Lane 0 takes the top pair (count-1, count-2), so a bigger daemon means
    #                         more lanes without ever overlapping the 15/14 pair of the shared one.
    DEFAULT_TEST_REDIS_DATABASES = TEST_DATABASE + 1

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
                "integer in 0..#{max_test_lanes - 1}, or unset it in the bare checkout."
        end
        return 0 if ENV["TEST_ENV_NUMBER"].to_s.strip.empty?

        raise ArgumentError,
              "TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER'].inspect} gives this process its own " \
              "postgres database but no redis lane, so it would share redis database " \
              "#{TEST_DATABASE} with every other lane and flush their keys at :suite. Declare " \
              "TEST_REDIS_LANE=<0..#{max_test_lanes - 1}> (unique among concurrent lanes) in " \
              "server/.env.test.local. scripts/prepare-worktree.sh writes one for new worktrees."
      end

      # Logical databases the daemon behind the test URLs has. 16 unless TEST_REDIS_DATABASES says
      # otherwise; a smaller figure than the default is refused, because the 15/14 pair of lane 0
      # would then not exist.
      def test_databases
        declared = ENV["TEST_REDIS_DATABASES"].to_s.strip
        return DEFAULT_TEST_REDIS_DATABASES if declared.empty?

        count = declared.match?(/\A\d+\z/) ? Integer(declared, 10) : 0
        if count < DEFAULT_TEST_REDIS_DATABASES
          raise ArgumentError,
                "TEST_REDIS_DATABASES=#{declared.inspect} is not a database count of at least " \
                "#{DEFAULT_TEST_REDIS_DATABASES}. Set it to the `databases` value of the test daemon."
        end
        count
      end

      # Port of the dedicated test daemon, or nil when the application's own daemon is used.
      # Only ever honoured in the test env: an exported TEST_REDIS_PORT must not redirect (or strip TLS
      # from) the connection of a dev or production process.
      def test_port
        return nil unless Rails.env.test?

        declared = ENV["TEST_REDIS_PORT"].to_s.strip
        return nil if declared.empty?
        unless declared.match?(/\A[1-9]\d{0,4}\z/)
          raise ArgumentError, "TEST_REDIS_PORT=#{declared.inspect} is not a TCP port number."
        end
        if declared == "6379"
          raise ArgumentError, "TEST_REDIS_PORT=6379 is the shared daemon; use the dedicated test daemon (scripts/test-redis.sh)."
        end

        Integer(declared, 10)
      end

      # Lanes this process's test daemon affords (6 on a default 16-database one).
      def max_test_lanes
        top_worker = TEST_WORKER_DATABASE + (test_databases - DEFAULT_TEST_REDIS_DATABASES)
        ((top_worker - TEST_DATABASE_FLOOR) / TEST_LANE_STRIDE) + 1
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

      # Explicit, short timeouts: the worker Redis is read by status sweeps and
      # request paths, and one that accepts the TCP connection but never
      # answers must fail fast rather than hold the caller open.
      def new_worker_client
        ::Redis.new(
          url: worker_url,
          connect_timeout: WORKER_CONNECT_TIMEOUT,
          read_timeout: WORKER_READ_TIMEOUT,
          write_timeout: WORKER_READ_TIMEOUT
        )
      end

      def url
        config = resolved_config
        isolate_test_database(AdminSetting.redis_url_from_config(config), test_database)
      rescue StandardError
        isolate_test_database(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"), test_database)
      end

      # The Redis the worker's Sidekiq reads. Precedence:
      #   1. POWERNODE_WORKER_REDIS_URL — canonical; names the role on both the
      #      server and the worker side.
      #   2. SIDEKIQ_REDIS_URL — deprecated alias (System::WorkerJobEnqueuer used
      #      to read it); honored with a one-time warning.
      #   3. The general URL with its database rewritten to /1, the canonical
      #      Sidekiq database (0 general / 1 Sidekiq / 2 ActionCable).
      # A module-composed hub runs Sidekiq on /0 until the phase-2 layout
      # migration, and its rails-start.sh exports (1) to say so (IMP-daecbb8a050e).
      # In the test env every branch is lane-rewritten, so an override cannot
      # point a spec at a live queue; an override whose database cannot be
      # located is refused there rather than passed through (outside the
      # fallback rescue below, so the refusal is not swallowed).
      def worker_url
        override = worker_url_override
        return isolated_worker_override(override) if override

        derived_worker_url
      end

      def reconfigure!
        @client&.close rescue nil
        @client = nil
        @resolved_config = nil
      end

      private

      def derived_worker_url
        isolate_test_database(url.sub(/\/\d+\z/, "/1"), test_worker_database)
      rescue StandardError
        isolate_test_database("redis://localhost:6379/1", test_worker_database)
      end

      # isolate_test_database leaves a URL it cannot place untouched. For an
      # override in the test env that would fail open (redis://host:6379 with
      # no /N is DB 0, a live database), so refuse it instead. The dedicated
      # test daemon replaces the whole URL, so it needs no database to locate.
      def isolated_worker_override(override)
        if Rails.env.test? && !test_port && !override.match?(%r{/\d+\z})
          raise ArgumentError,
                "#{WORKER_REDIS_URL_ENV}/#{DEPRECATED_WORKER_REDIS_URL_ENV} has no trailing /<db> " \
                "(got a URL without one, with a trailing slash or a query string), so the test env " \
                "cannot move it onto this lane's worker database. Give it an explicit /<db>, or unset it."
        end

        isolate_test_database(override, test_worker_database)
      end

      def worker_url_override
        canonical = ENV[WORKER_REDIS_URL_ENV].to_s.strip
        deprecated = ENV[DEPRECATED_WORKER_REDIS_URL_ENV].to_s.strip
        warn_deprecated_worker_url_env(ignored: canonical.present?) if deprecated.present?

        canonical.presence || deprecated.presence
      end

      # Once per process: worker_url runs on every health sweep and enqueue.
      def warn_deprecated_worker_url_env(ignored:)
        return if @deprecated_worker_url_env_warned

        @deprecated_worker_url_env_warned = true
        consequence = ignored ? "it is ignored because #{WORKER_REDIS_URL_ENV} is also set" : "it is still honored for now"
        Rails.logger&.warn(
          "[Powernode::Redis] #{DEPRECATED_WORKER_REDIS_URL_ENV} is deprecated; set " \
          "#{WORKER_REDIS_URL_ENV} instead (#{consequence})."
        )
      end

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
        if lane >= max_test_lanes
          raise ArgumentError,
                "TEST_ENV_NUMBER=#{ENV['TEST_ENV_NUMBER'].inspect} is lane #{lane}, but only lanes " \
                "0..#{max_test_lanes - 1} have a redis database of their own (0/1/2 belong to the " \
                "application). Run fewer lanes, or give each lane its own redis."
        end

        # A bigger daemon (TEST_REDIS_DATABASES) lifts the whole lane-0 pair by its extra databases.
        base + (test_databases - DEFAULT_TEST_REDIS_DATABASES) - (lane * TEST_LANE_STRIDE)
      end

      def isolate_test_database(url_str, database)
        return url_str unless Rails.env.test?

        # The dedicated test daemon (TEST_REDIS_PORT) replaces the whole URL: it has its own port,
        # no password and no TLS, so nothing about the application's configured daemon applies.
        return "redis://127.0.0.1:#{test_port}/#{database}" if test_port
        return url_str if url_str.blank?

        url_str.sub(%r{/\d+\z}, "/#{database}")
      end

      # Goes through Admin::SystemSettings, not AdminSetting.redis_config
      # directly (fc-38 decision #3) — the password is encrypted at rest, and
      # only Admin::SystemSettings.redis_config decrypts it. This builds the
      # app's ACTUAL Redis connection, so reading the raw AdminSetting blob
      # here would silently connect with no password once the plaintext was
      # migrated out of it.
      def resolved_config
        @resolved_config ||= Admin::SystemSettings.redis_config
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
        opts[:ssl] = config["ssl"] if config["ssl"] && !test_port
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
