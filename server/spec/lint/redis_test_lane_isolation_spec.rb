# frozen_string_literal: true

require "rails_helper"

# Postgres gained per-lane isolation when config/database.yml started appending
# TEST_ENV_NUMBER to the database name. Redis did not: its test databases were
# bare constants, and rails_helper flushes the resolved database in a
# before(:suite) hook. Two lanes therefore held private schemas while sharing
# one Redis, and whichever started second flushed the first one's keys partway
# through its run — silently, because the victim does not error, it just loses
# cached state and fails somewhere unrelated (or passes vacuously where the
# code under test rescues a missing key).
#
# These examples pin the derivation itself rather than any one lane's numbers,
# so the property survives a change to the stride or the floor: what must hold
# is that distinct lanes never share a database and never reach the
# application's own.
RSpec.describe "Redis test-database lane isolation" do
  # Real ENV rather than a stub on ENV#[]: the derivation is allowed to read
  # the variable however it likes, and a stub would pin the reading mechanism
  # instead of the behaviour.
  def with_env(values)
    # Hermetic against a parallel run: these two select the dedicated test daemon (IMP-7e1c8b0f4849)
    # and would otherwise change what "the default daemon" examples below resolve to.
    values = { "TEST_REDIS_PORT" => nil, "TEST_REDIS_DATABASES" => nil }.merge(values)
    previous = values.keys.to_h { |k| [ k, ENV.key?(k) ? ENV[k] : :absent ] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end

  # A worktree: its own postgres database, and whatever redis lane it declares.
  def with_lane(lane, suffix: "_wt")
    with_env("TEST_ENV_NUMBER" => suffix, "TEST_REDIS_LANE" => lane&.to_s) { yield }
  end

  # The application's own databases, which no lane may ever be handed.
  APP_DATABASES = [ 0, 1, 2 ].freeze

  let(:lane_count) { Powernode::Redis::MAX_TEST_LANES }
  let(:lanes) { (0...lane_count).to_a }

  it "hands every lane a database pair that no other lane shares" do
    pairs = lanes.map do |lane|
      with_lane(lane) { [ Powernode::Redis.test_database, Powernode::Redis.test_worker_database ] }
    end

    assigned = pairs.flatten
    expect(assigned.uniq.size).to eq(assigned.size),
      "lanes share a redis database: #{lanes.zip(pairs).inspect}"
  end

  it "never hands a lane one of the application's own databases" do
    lanes.each do |lane|
      with_lane(lane) do
        expect(APP_DATABASES).not_to include(Powernode::Redis.test_database),
          "lane #{lane} resolved main onto an application database"
        expect(APP_DATABASES).not_to include(Powernode::Redis.test_worker_database),
          "lane #{lane} resolved worker onto an application database"
      end
    end
  end

  it "keeps the bare checkout on the databases the suite already used" do
    with_env("TEST_ENV_NUMBER" => nil, "TEST_REDIS_LANE" => nil) do
      expect(Powernode::Redis.test_lane).to eq(0)
      expect(Powernode::Redis.test_database).to eq(Powernode::Redis::TEST_DATABASE)
      expect(Powernode::Redis.test_worker_database).to eq(Powernode::Redis::TEST_WORKER_DATABASE)
    end
  end

  # The defect that made the first version of this change cosmetic: every slug
  # scripts/prepare-worktree.sh generates is digitless, so any rule that infers
  # a lane from the TEST_ENV_NUMBER string returns 0 for all of them and every
  # worktree keeps sharing one database. A lane must be declared, and a process
  # with a private postgres database and no declared lane must refuse.
  it "refuses a worktree that has its own postgres database but no declared lane" do
    %w[_ext_develop _parent_develop _pp _campaign_019f7cb5].each do |suffix|
      with_env("TEST_ENV_NUMBER" => suffix, "TEST_REDIS_LANE" => nil) do
        expect { Powernode::Redis.test_lane }
          .to raise_error(ArgumentError, /TEST_REDIS_LANE/),
              "#{suffix.inspect} silently resolved a lane instead of refusing"
      end
    end
  end

  it "never infers a lane from digits that happen to appear in the worktree name" do
    with_env("TEST_ENV_NUMBER" => "_campaign_019f7cb5", "TEST_REDIS_LANE" => "2") do
      expect(Powernode::Redis.test_lane).to eq(2)
    end
  end

  it "refuses a declared lane that is not a number" do
    with_env("TEST_ENV_NUMBER" => "_wt", "TEST_REDIS_LANE" => "l2") do
      expect { Powernode::Redis.test_lane }.to raise_error(ArgumentError, /not a lane number/)
    end
  end

  # The failure that matters is not "too many lanes" but a lane silently
  # wrapping onto a database another lane already owns, which would reinstate
  # the exact bug this change removes. Refusing loudly is the only safe
  # behaviour, and it must not be swallowed by the fallback rescues around the
  # URL builders.
  it "refuses a lane it has no database for instead of reusing one" do
    with_lane(lane_count) do
      expect { Powernode::Redis.test_database }.to raise_error(ArgumentError, /lane/)
    end
  end

  # Every URL builder carries a `rescue StandardError` fallback, and each
  # fallback resolves the lane too — so the refusal has to survive the handler
  # rather than being answered with a default URL on database 15. Stubbing
  # redis_url_from_config (not redis_config, which resolved_config's own rescue
  # absorbs) is what actually forces the handler to run.
  #
  # new_client and new_worker_client are the paths that matter: client_options
  # is private and is what Powernode::Redis.client — and therefore the
  # rails_helper flush and every service — goes through. Pinning #url alone
  # left a revert of the client_options handler undetected.
  it "refuses through every URL builder, including the ones the client uses" do
    with_lane(lane_count) do
      allow(AdminSetting).to receive(:redis_url_from_config).and_raise(StandardError, "unavailable")
      Powernode::Redis.reconfigure!

      expect { Powernode::Redis.url }.to raise_error(ArgumentError, /lane/)
      expect { Powernode::Redis.worker_url }.to raise_error(ArgumentError, /lane/)
      expect { Powernode::Redis.new_client }.to raise_error(ArgumentError, /lane/)
      expect { Powernode::Redis.new_worker_client }.to raise_error(ArgumentError, /lane/)
    end
  ensure
    Powernode::Redis.reconfigure!
  end

  # IMP-7e1c8b0f4849 — the dedicated parallel test daemon (scripts/test-redis.sh). It is opt-in
  # through two variables, and with both unset nothing above changes by a byte.
  describe "dedicated test daemon (TEST_REDIS_PORT / TEST_REDIS_DATABASES)" do
    def with_daemon(lane, databases: "64", port: "6380")
      with_env("TEST_ENV_NUMBER" => "_p#{lane + 1}", "TEST_REDIS_LANE" => lane.to_s,
               "TEST_REDIS_PORT" => port, "TEST_REDIS_DATABASES" => databases) { yield }
    end

    it "leaves the default daemon exactly as it was when neither variable is set" do
      with_env("TEST_ENV_NUMBER" => nil, "TEST_REDIS_LANE" => nil) do
        expect(Powernode::Redis.test_port).to be_nil
        expect(Powernode::Redis.test_databases).to eq(16)
        expect(Powernode::Redis.max_test_lanes).to eq(Powernode::Redis::MAX_TEST_LANES)
        expect(Powernode::Redis.url).not_to include("6380")
      end
    end

    it "points every URL at the loopback daemon and shifts lane 0 to the top of its range" do
      with_daemon(0) do
        expect(Powernode::Redis.url).to eq("redis://127.0.0.1:6380/63")
        expect(Powernode::Redis.worker_url).to eq("redis://127.0.0.1:6380/62")
      end
    end

    it "affords (databases - 6) / 2 + 1 lanes (30 on 64 databases), with no pair overlapping and none on 0/1/2" do
      with_daemon(0) do
        expect(Powernode::Redis.max_test_lanes).to eq(30)
        pairs = (0...30).map do |lane|
          with_daemon(lane) { [ Powernode::Redis.test_database, Powernode::Redis.test_worker_database ] }
        end
        flat = pairs.flatten
        expect(flat.uniq.size).to eq(flat.size)
        expect(flat.min).to be >= 3
      end
    end

    it "refuses the first lane past the daemon's range" do
      with_daemon(30) do
        expect { Powernode::Redis.test_database }.to raise_error(ArgumentError, /lane/)
      end
    end

    it "refuses a database count below the default and a malformed port" do
      with_daemon(0, databases: "8") { expect { Powernode::Redis.test_database }.to raise_error(ArgumentError, /TEST_REDIS_DATABASES/) }
      with_daemon(0, port: "63x80") { expect { Powernode::Redis.url }.to raise_error(ArgumentError, /TEST_REDIS_PORT/) }
    end

    it "ignores TEST_REDIS_PORT outside the test env (TLS and the configured URL are never dropped there)" do
      with_daemon(0) do
        original = Rails.instance_variable_get(:@_env)
        begin
          Rails.instance_variable_set(:@_env, ActiveSupport::StringInquirer.new("development"))
          expect(Powernode::Redis.test_port).to be_nil
          expect(Powernode::Redis.send(:isolate_test_database, "rediss://h:1/0", 15)).to eq("rediss://h:1/0")
        ensure
          Rails.instance_variable_set(:@_env, original)
        end
      end
    end

    it "refuses the shared daemon's port 6379" do
      with_daemon(0, port: "6379") { expect { Powernode::Redis.test_port }.to raise_error(ArgumentError, /6379/) }
    end
  end

  it "connects the running suite to the database its own lane resolves to" do
    expect(Powernode::Redis.client.connection[:db]).to eq(Powernode::Redis.test_database)
  end
end
