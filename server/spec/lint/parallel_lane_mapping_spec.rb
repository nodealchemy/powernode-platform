# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec", "parallel_lane_env").to_s

# IMP-7e1c8b0f4849 — every parallel_tests process gets its OWN Postgres database and its OWN Redis
# lane, in a namespace the worktree lanes can never occupy. parallel_tests hands out TEST_ENV_NUMBER
# "", "2", "3"... which would land on the live worktree databases powernode_test2/3/4; the shim in
# spec/parallel_lane_env.rb renames them __p1..__pN and aims Redis at the dedicated daemon.
RSpec.describe "parallel test lane mapping" do
  # Suffixes the worktree lanes use, including the slug of a worktree literally named "p1" (prepare-worktree.sh
  # squeezes runs of "_", so a slug can never contain "__").
  let(:worktree_suffixes) { [ "", "2", "3", "4", "_tmpfs", "_p1", "_wt" ] }

  def with_env(values)
    previous = values.keys.to_h { |k| [ k, ENV.key?(k) ? ENV[k] : :absent ] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end

  let(:base_env) do
    { "PARALLEL_TEST_GROUPS" => "8", "DATABASE_PORT" => "5433", "TEST_REDIS_PORT" => "6380", "TEST_ENV_NUMBER" => "" }
  end

  def lane_env(number, overrides = {})
    ParallelLaneEnv.lane_env(base_env.merge("TEST_ENV_NUMBER" => number).merge(overrides))
  end

  it "maps parallel_tests' numbering ('' for the first process, then 2..N) onto __p1..__pN" do
    numbers = [ "" ] + (2..8).map(&:to_s)
    names = numbers.map { |n| lane_env(n).fetch("TEST_ENV_NUMBER") }
    expect(names).to eq((1..8).map { |k| "__p#{k}" })
  end

  it "never produces a database suffix a worktree lane uses" do
    names = ([ "" ] + (2..16).map(&:to_s)).map { |n| lane_env(n).fetch("TEST_ENV_NUMBER") }
    expect(names & worktree_suffixes).to be_empty
    expect(names.uniq.size).to eq(names.size)
  end

  it "declares a unique redis lane per process, starting at 0" do
    lanes = ([ "" ] + (2..8).map(&:to_s)).map { |n| lane_env(n).fetch("TEST_REDIS_LANE") }
    expect(lanes).to eq((0..7).map(&:to_s))
  end

  it "resolves distinct redis databases per lane, clear of the application's 0/1/2" do
    with_env("TEST_REDIS_PORT" => "6380", "TEST_REDIS_DATABASES" => "64") do
      pairs = (0...8).map do |k|
        with_env("TEST_ENV_NUMBER" => "__p#{k + 1}", "TEST_REDIS_LANE" => k.to_s) do
          [ Powernode::Redis.test_database, Powernode::Redis.test_worker_database ]
        end
      end
      flat = pairs.flatten
      expect(flat.uniq.size).to eq(flat.size)
      expect(flat.min).to be > 2
      expect(pairs.first).to eq([ 63, 62 ])
    end
  end

  it "is inert outside a parallel_tests process (serial runs are untouched)" do
    expect(ParallelLaneEnv.lane_env(base_env.merge("PARALLEL_TEST_GROUPS" => nil))).to eq({})
  end

  it "refuses to map onto the shared 5432 cluster" do
    expect { lane_env("", "DATABASE_PORT" => "5432") }.to raise_error(ArgumentError, /shared/i)
    expect { lane_env("", "DATABASE_PORT" => nil) }.to raise_error(ArgumentError, /DATABASE_PORT/)
  end

  it "refuses to map without the dedicated redis daemon (the shared one has only 6 lanes, all spoken for)" do
    expect { lane_env("", "TEST_REDIS_PORT" => nil) }.to raise_error(ArgumentError, /TEST_REDIS_PORT/)
  end

  it "refuses the shared redis daemon's port" do
    expect { lane_env("", "TEST_REDIS_PORT" => "6379") }.to raise_error(ArgumentError, /6379/)
  end

  it "is idempotent: an already-mapped process maps to itself" do
    expect(lane_env("__p3")).to eq({})
  end

  # Two worktrees may run scripts/parallel-rspec.sh at once: each gets a lane PREFIX (databases) and a
  # redis lane BASE (a range of the shared test daemon), and neither may overlap the other.
  describe "per-worktree namespaces" do
    let(:other) { { "PARALLEL_LANE_PREFIX" => "__w1a2b3cp", "TEST_REDIS_LANE_BASE" => "8" } }
    let(:numbers) { [ "" ] + (2..8).map(&:to_s) }

    it "keeps the main checkout on _pK / lanes 0.. when nothing is declared" do
      expect(lane_env("2")).to eq("TEST_ENV_NUMBER" => "__p2", "TEST_REDIS_LANE" => "1")
    end

    it "maps a second prefix onto its own database names and redis lane range" do
      mine = numbers.map { |n| lane_env(n) }
      theirs = numbers.map { |n| lane_env(n, other) }
      expect(theirs.map { |h| h["TEST_ENV_NUMBER"] }).to eq((1..8).map { |k| "__w1a2b3cp#{k}" })
      expect(mine.map { |h| h["TEST_ENV_NUMBER"] } & theirs.map { |h| h["TEST_ENV_NUMBER"] }).to be_empty
      expect(mine.map { |h| h["TEST_REDIS_LANE"] } & theirs.map { |h| h["TEST_REDIS_LANE"] }).to be_empty
      expect(theirs.map { |h| h["TEST_REDIS_LANE"] }).to eq((8..15).map(&:to_s))
    end

    it "resolves disjoint redis databases for two concurrent runs" do
      dbs = lambda do |lanes|
        lanes.flat_map do |lane|
          with_env("TEST_REDIS_PORT" => "6380", "TEST_REDIS_DATABASES" => "64", "TEST_ENV_NUMBER" => "__p1", "TEST_REDIS_LANE" => lane) do
            [ Powernode::Redis.test_database, Powernode::Redis.test_worker_database ]
          end
        end
      end
      a = dbs.call((0...8).map(&:to_s))
      b = dbs.call((8...16).map(&:to_s))
      expect(a & b).to be_empty
    end

    it "treats an already-mapped process of the other prefix as mapped" do
      expect(lane_env("__w1a2b3cp3", other)).to eq({})
    end

    it "refuses a prefix that could name a worktree lane or reach dropdb unvetted" do
      [ "_tmpfs", "_2", "__p;x", "p", "_P", "_w1a2b3c", "" ].each do |bad|
        expect { lane_env("", "PARALLEL_LANE_PREFIX" => bad) }.to raise_error(ArgumentError, /PARALLEL_LANE_PREFIX/)
      end
    end

    it "refuses a non-integer redis lane base" do
      expect { lane_env("", "TEST_REDIS_LANE_BASE" => "x") }.to raise_error(ArgumentError, /TEST_REDIS_LANE_BASE/)
    end
  end
end
