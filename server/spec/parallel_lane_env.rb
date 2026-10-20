# frozen_string_literal: true

# Per-process lane environment for the opt-in parallel suite (scripts/parallel-rspec.sh).
#
# parallel_tests starts N rspec processes and hands them TEST_ENV_NUMBER "", "2", "3"... That is the
# wrong namespace here: database.yml turns it into powernode_test, powernode_test2, ... and the
# worktrees already own powernode_test2/3/4 on the shared cluster. This file runs BEFORE Rails
# (`--require` in .rspec_parallel) and renames each process onto a lane of its own:
#
#   parallel_tests "" , 2 , 3 ... N   ->   TEST_ENV_NUMBER __p1 , __p2 , __p3 ... __pN     (powernode_test__pK)
#                                           TEST_REDIS_LANE  0 ,  1 ,  2 ... N-1       (dedicated daemon)
#
# It is inert unless parallel_tests started the process (PARALLEL_TEST_GROUPS is set), so a plain
# `bundle exec rspec`, a worktree lane and CI never see it do anything. It also REFUSES, rather than
# degrades, when its preconditions are missing: the shared 5432 cluster (a purge there would hit the
# worktree databases) and the application's Redis daemon (6 lanes, every one claimed).
module ParallelLaneEnv
  # The main checkout's prefix. A second worktree running at the same time declares its own through
  # PARALLEL_LANE_PREFIX (scripts/parallel-rspec.sh derives it) and a disjoint range of redis lanes
  # through TEST_REDIS_LANE_BASE. The accepted shapes are exactly `__p` and `__w<6 hex>p`: lane names
  # reach dropdb, and neither can equal a worktree suffix ("", 2, 3, 4, _tmpfs, _<slug>): prepare-worktree.sh
  # squeezes runs of "_" in a slug, so a slug never contains "__" (a worktree named "p1" is "_p1", not "__p1").
  LANE_PREFIX = "__p"
  PREFIX_FORMAT = /\A__(?:p|w[0-9a-f]{6}p)\z/
  SHARED_PG_PORT = "5432"

  class << self
    # The ENV overrides this process needs, as a Hash ({} when nothing applies). Pure: takes the
    # environment as an argument so it can be exercised without touching the real ENV.
    def lane_env(env)
      return {} if env["PARALLEL_TEST_GROUPS"].to_s.strip.empty?
      prefix = lane_prefix(env)
      base = redis_lane_base(env)
      return {} if env["TEST_ENV_NUMBER"].to_s.match?(/\A#{prefix}\d+\z/)

      require_tmpfs_cluster!(env)
      require_test_redis!(env)

      index = process_index(env["TEST_ENV_NUMBER"])
      { "TEST_ENV_NUMBER" => "#{prefix}#{index}", "TEST_REDIS_LANE" => (base + index - 1).to_s }
    end

    # Applies lane_env to ENV (the real one by default). Returns the overrides applied.
    def apply!(env = ENV)
      overrides = lane_env(env.to_h)
      overrides.each { |k, v| env[k] = v }
      overrides
    end

    def lane_prefix(env)
      prefix = env.fetch("PARALLEL_LANE_PREFIX", LANE_PREFIX).to_s
      return prefix if prefix.match?(PREFIX_FORMAT)

      raise ArgumentError, "PARALLEL_LANE_PREFIX=#{prefix.inspect} is not __p or __w<6 hex>p"
    end

    def redis_lane_base(env)
      base = env.fetch("TEST_REDIS_LANE_BASE", "0").to_s.strip
      return Integer(base, 10) if base.match?(/\A\d+\z/)

      raise ArgumentError, "TEST_REDIS_LANE_BASE=#{base.inspect} is not a non-negative integer"
    end

    private

    # parallel_tests numbers the first process "" and the rest "2".."N".
    def process_index(number)
      number = number.to_s.strip
      return 1 if number.empty?
      return Integer(number, 10) if number.match?(/\A[1-9]\d*\z/)

      raise ArgumentError, "unexpected parallel_tests TEST_ENV_NUMBER #{number.inspect}"
    end

    def require_tmpfs_cluster!(env)
      port = env["DATABASE_PORT"].to_s.strip
      if port.empty?
        raise ArgumentError,
              "parallel run refused: DATABASE_PORT is not declared, so Rails would resolve the shared " \
              "5432 cluster. Run scripts/parallel-rspec.sh (it targets the tmpfs cluster)."
      end
      return unless port == SHARED_PG_PORT

      raise ArgumentError,
            "parallel run refused: DATABASE_PORT=#{SHARED_PG_PORT} is the shared cluster, whose " \
            "powernode_test2/3/4 databases belong to live worktrees. Use the tmpfs cluster."
    end

    def require_test_redis!(env)
      port = env["TEST_REDIS_PORT"].to_s.strip
      if port == "6379"
        raise ArgumentError, "parallel run refused: TEST_REDIS_PORT=6379 is the shared daemon. Use scripts/test-redis.sh (6380)."
      end
      return unless port.empty?

      raise ArgumentError,
            "parallel run refused: TEST_REDIS_PORT is not set. The shared Redis has 6 test lanes " \
            "and worktrees hold them; start the dedicated daemon with scripts/test-redis.sh."
    end
  end
end

ParallelLaneEnv.apply! if ENV.key?("PARALLEL_TEST_GROUPS")
