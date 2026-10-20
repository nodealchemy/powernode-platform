# frozen_string_literal: true

require "rails_helper"

# IMP-daecbb8a050e — POWERNODE_WORKER_REDIS_URL names the Sidekiq Redis on the
# server side, so a deployment whose worker does not sit on DB 1 (a
# module-composed hub runs Sidekiq on DB 0 in phase 1) can say so once and have
# every server-side worker-Redis path follow: the Sidekiq health checks, job
# metrics, the composite health probe and System::WorkerJobEnqueuer.
#
# Before this, worker_url had no override at all: it always rewrote the general
# URL's /N to /1, so on a hub every enqueue landed in a database nothing reads
# and the process registry read from there was always empty ("Sidekiq down").
#
# SIDEKIQ_REDIS_URL is the deprecated alias (WorkerJobEnqueuer used to read it).
RSpec.describe "Powernode::Redis.worker_url override precedence" do
  let(:general_url) { "redis://redis.example:6379/0" }

  # Real ENV rather than a stub on ENV#[], as in the lane-isolation spec. The
  # test-daemon variables are cleared so a parallel run resolves the same URLs.
  def with_env(values)
    values = {
      "TEST_ENV_NUMBER" => nil, "TEST_REDIS_LANE" => nil,
      "TEST_REDIS_PORT" => nil, "TEST_REDIS_DATABASES" => nil,
      "POWERNODE_WORKER_REDIS_URL" => nil, "SIDEKIQ_REDIS_URL" => nil
    }.merge(values)
    previous = values.keys.to_h { |k| [ k, ENV.key?(k) ? ENV[k] : :absent ] }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    previous.each { |k, v| v == :absent ? ENV.delete(k) : ENV[k] = v }
  end

  # A production process: no test-lane rewrite.
  def as_production
    original = Rails.instance_variable_get(:@_env)
    Rails.instance_variable_set(:@_env, ActiveSupport::EnvironmentInquirer.new("production"))
    yield
  ensure
    Rails.instance_variable_set(:@_env, original)
  end

  before do
    allow(Admin::SystemSettings).to receive(:redis_config).and_return({ "url" => general_url })
    allow(Rails.logger).to receive(:warn).and_call_original
    Powernode::Redis.reconfigure!
    Powernode::Redis.instance_variable_set(:@deprecated_worker_url_env_warned, nil)
  end

  after do
    Powernode::Redis.reconfigure!
    Powernode::Redis.instance_variable_set(:@deprecated_worker_url_env_warned, nil)
  end

  context "in production" do
    it "passes an override without a /<db> through untouched (no lane rewrite outside test)" do
      with_env("POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6379") do
        as_production { expect(Powernode::Redis.worker_url).to eq("redis://worker.example:6379") }
      end
    end

    it "derives DB 1 from the general URL when neither variable is set (installer hosts, unchanged)" do
      with_env({}) do
        as_production { expect(Powernode::Redis.worker_url).to eq("redis://redis.example:6379/1") }
      end
      expect(Rails.logger).not_to have_received(:warn).with(/SIDEKIQ_REDIS_URL/)
    end

    it "honors POWERNODE_WORKER_REDIS_URL verbatim, without a warning" do
      with_env("POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6380/0") do
        as_production { expect(Powernode::Redis.worker_url).to eq("redis://worker.example:6380/0") }
      end
      expect(Rails.logger).not_to have_received(:warn).with(/SIDEKIQ_REDIS_URL/)
    end

    it "treats a blank POWERNODE_WORKER_REDIS_URL as unset" do
      with_env("POWERNODE_WORKER_REDIS_URL" => "  ") do
        as_production { expect(Powernode::Redis.worker_url).to eq("redis://redis.example:6379/1") }
      end
    end

    it "honors the deprecated SIDEKIQ_REDIS_URL alias and warns exactly once per process" do
      with_env("SIDEKIQ_REDIS_URL" => "redis://legacy.example:6379/0") do
        as_production do
          2.times { expect(Powernode::Redis.worker_url).to eq("redis://legacy.example:6379/0") }
        end
      end
      expect(Rails.logger).to have_received(:warn)
        .with(/SIDEKIQ_REDIS_URL is deprecated.*POWERNODE_WORKER_REDIS_URL/).once
    end

    it "prefers POWERNODE_WORKER_REDIS_URL over the alias, and warns that the alias is ignored" do
      with_env("POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6379/0",
               "SIDEKIQ_REDIS_URL" => "redis://legacy.example:6379/1") do
        as_production { expect(Powernode::Redis.worker_url).to eq("redis://worker.example:6379/0") }
      end
      expect(Rails.logger).to have_received(:warn).with(/SIDEKIQ_REDIS_URL is deprecated.*ignored/).once
    end

    it "builds the worker client on the override" do
      allow(::Redis).to receive(:new).and_call_original
      with_env("POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6380/0") do
        as_production { Powernode::Redis.new_worker_client.close }
      end
      expect(::Redis).to have_received(:new).with(hash_including(url: "redis://worker.example:6380/0"))
    end
  end

  # The override must not let a spec reach a real shared database: in the test
  # env it is lane-rewritten exactly like the derived URL.
  context "in the test env" do
    it "keeps the override's host but moves it onto this lane's worker database" do
      with_env("POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6380/0") do
        expect(Powernode::Redis.worker_url)
          .to eq("redis://worker.example:6380/#{Powernode::Redis.test_worker_database}")
      end
      expect([ 0, 1, 2 ]).not_to include(Powernode::Redis.test_worker_database)
    end

    it "lane-rewrites the deprecated alias too" do
      with_env("SIDEKIQ_REDIS_URL" => "redis://legacy.example:6379/0") do
        expect(Powernode::Redis.worker_url)
          .to eq("redis://legacy.example:6379/#{Powernode::Redis.test_worker_database}")
      end
    end

    # isolate_test_database cannot place these, and passing them through would
    # land a spec on DB 0 of the named daemon.
    [ "redis://worker.example:6379", "redis://worker.example:6379/", "redis://worker.example:6379/0?ssl=false" ].each do |bad|
      it "refuses an override whose database cannot be located (#{bad})" do
        with_env("POWERNODE_WORKER_REDIS_URL" => bad) do
          expect { Powernode::Redis.worker_url }.to raise_error(ArgumentError, /trailing \/<db>/)
          expect { Powernode::Redis.new_worker_client }.to raise_error(ArgumentError, /trailing \/<db>/)
        end
      end
    end

    it "refuses such an alias value too" do
      with_env("SIDEKIQ_REDIS_URL" => "redis://legacy.example:6379") do
        expect { Powernode::Redis.worker_url }.to raise_error(ArgumentError, /trailing \/<db>/)
      end
    end

    it "points at the dedicated test daemon whatever the override says" do
      with_env("TEST_ENV_NUMBER" => "_p1", "TEST_REDIS_LANE" => "0", "TEST_REDIS_PORT" => "6380",
               "TEST_REDIS_DATABASES" => "64", "POWERNODE_WORKER_REDIS_URL" => "redis://worker.example:6379/0") do
        expect(Powernode::Redis.worker_url).to eq("redis://127.0.0.1:6380/62")
      end
    end
  end
end
