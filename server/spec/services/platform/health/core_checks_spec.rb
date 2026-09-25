# frozen_string_literal: true

require "rails_helper"

# The ONE set of core service checks (database, redis, sidekiq, disk, memory,
# cpu). The maintenance health endpoint, the AI monitoring health service and
# the core_service status contributor all read these — before fc-43/47 each
# carried its own copy.
#
# The readings land on shared status rows every member can see, so they carry
# counts and an exception CLASS only: never a raw error message, a queue name
# or a memory figure (fc-47 review M2).
RSpec.describe Platform::Health::CoreChecks do
  describe ".database" do
    it "reports healthy with a response time and the connection pool" do
      result = described_class.database

      expect(result[:status]).to eq("healthy")
      expect(result[:response_time_ms]).to be_a(Numeric)
      expect(result[:connection_pool]).to include(:size, :connections, :busy, :idle)
    end

    it "reports unhealthy with the exception class, and logs the message instead of returning it" do
      allow(ActiveRecord::Base.connection).to receive(:execute)
        .and_raise(ActiveRecord::ConnectionNotEstablished, "password authentication failed for user x")
      allow(Rails.logger).to receive(:warn)

      expect(described_class.database).to eq(status: "unhealthy", error_class: "ActiveRecord::ConnectionNotEstablished")
      expect(Rails.logger).to have_received(:warn).with(/password authentication failed/)
    end
  end

  describe ".redis" do
    let(:client) { instance_double(Redis) }

    it "reads the memoized app client by default, and never opens one of its own" do
      allow(Powernode::Redis).to receive(:client).and_return(client)
      allow(Powernode::Redis).to receive(:new_client)
      allow(client).to receive(:ping).and_return("PONG")
      allow(client).to receive(:info).and_return("used_memory_human" => "12M", "connected_clients" => "7")

      result = described_class.redis

      expect(result).to include(status: "healthy", connected_clients: 7)
      expect(result[:response_time_ms]).to be_a(Numeric)
      expect(Powernode::Redis).not_to have_received(:new_client)
    end

    it "reads a client it is handed" do
      allow(client).to receive(:ping).and_return("PONG")
      allow(client).to receive(:info).and_return("connected_clients" => "3")

      expect(described_class.redis(client: client)).to include(status: "healthy", connected_clients: 3)
    end

    it "carries no memory figure" do
      allow(client).to receive(:ping).and_return("PONG")
      allow(client).to receive(:info).and_return("used_memory_human" => "12M", "connected_clients" => "7")

      expect(described_class.redis(client: client)).not_to have_key(:used_memory)
    end

    it "reports unhealthy with the exception class only when redis is unreachable" do
      allow(client).to receive(:ping).and_raise(Redis::CannotConnectError, "refused at 10.0.0.5:6379")

      expect(described_class.redis(client: client)).to eq(status: "unhealthy", error_class: "Redis::CannotConnectError")
    end
  end

  # Sidekiq runs in the worker app; this app stays Sidekiq-free, so its state
  # is read from the process registry Sidekiq keeps in the worker's Redis,
  # never through the gem.
  describe ".sidekiq" do
    let(:client) { instance_double(Redis, close: nil) }
    let(:now) { Time.zone.parse("2026-09-25 12:00:00") }

    before do
      allow(Powernode::Redis).to receive(:new_worker_client).and_return(client)
      allow(client).to receive(:get).with("stat:processed").and_return("10")
      allow(client).to receive(:get).with("stat:failed").and_return("1")
      allow(client).to receive(:smembers).with("queues").and_return(%w[default mailers])
      allow(client).to receive(:llen).with("queue:default").and_return(3)
      allow(client).to receive(:llen).with("queue:mailers").and_return(0)
    end

    # identity => seconds since its last heartbeat (nil: no beat at all)
    def with_processes(beats)
      allow(client).to receive(:smembers).with("processes").and_return(beats.keys)
      beats.each do |identity, age|
        allow(client).to receive(:hget).with(identity, "beat").and_return(age && (now - age).to_f.to_s)
      end
    end

    it "is healthy with a live worker, and carries counts only: no queue names" do
      with_processes("worker-1:123" => 5)

      travel_to(now) do
        expect(described_class.sidekiq).to eq(
          status: "healthy", processes: 1, stale_processes: 0, processed: 10, failed: 1,
          enqueued: 3, queue_count: 2, last_seen_at: (now - 5).utc.iso8601
        )
      end
    end

    it "does not count a crashed worker whose identity is still registered" do
      with_processes("worker-1:123" => 600)

      travel_to(now) do
        expect(described_class.sidekiq).to include(
          status: "unhealthy", processes: 0, stale_processes: 1, last_seen_at: (now - 600).utc.iso8601
        )
      end
    end

    it "counts only the live identities when one of two has crashed" do
      with_processes("worker-1:123" => 5, "worker-2:456" => 600)

      travel_to(now) do
        expect(described_class.sidekiq).to include(status: "healthy", processes: 1, stale_processes: 1)
      end
    end

    it "is unhealthy with no registered worker, and carries no last_seen_at" do
      with_processes({})

      travel_to(now) do
        result = described_class.sidekiq
        expect(result).to include(status: "unhealthy", processes: 0, stale_processes: 0)
        expect(result).not_to have_key(:last_seen_at)
      end
    end

    it "is unknown, never healthy, with the exception class only, when the worker redis cannot be read" do
      allow(client).to receive(:smembers).and_raise(Redis::CannotConnectError, "refused at 10.0.0.5:6379")

      expect(described_class.sidekiq).to eq(status: "unknown", error_class: "Redis::CannotConnectError")
    end

    it "is unknown when the worker redis times out" do
      allow(client).to receive(:smembers).and_raise(Redis::TimeoutError, "timed out")

      expect(described_class.sidekiq).to eq(status: "unknown", error_class: "Redis::TimeoutError")
    end

    it "closes the client it opened, on success and on failure" do
      with_processes("worker-1:123" => 5)
      travel_to(now) { described_class.sidekiq }

      allow(client).to receive(:smembers).and_raise(Redis::TimeoutError, "timed out")
      described_class.sidekiq

      expect(client).to have_received(:close).twice
    end

    it "never loads the Sidekiq gem" do
      with_processes("worker-1:123" => 5)
      travel_to(now) { described_class.sidekiq }

      expect(defined?(::Sidekiq::Stats)).to be_nil
    end
  end

  describe ".disk" do
    it "warns at 80% used" do
      stat = double(bytes_free: 15 * 1.gigabyte, bytes_total: 100 * 1.gigabyte)
      allow(Sys::Filesystem).to receive(:stat).with("/").and_return(stat)

      expect(described_class.disk).to eq(status: "warning", used_percentage: 85.0, free_gb: 15)
    end

    it "is unknown, never healthy, when it cannot be read" do
      allow(Sys::Filesystem).to receive(:stat).and_raise(Errno::ENOENT)

      expect(described_class.disk).to eq(status: "unknown")
    end
  end

  describe ".memory" do
    it "reads /proc/meminfo and warns at 80% used" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/meminfo").and_return("MemTotal: 1000000 kB\nMemAvailable: 100000 kB\n")

      expect(described_class.memory).to eq(status: "warning", used_percentage: 90.0, used_mb: 879, total_mb: 977)
    end

    it "is unknown when meminfo cannot be read" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/meminfo").and_raise(Errno::ENOENT)

      expect(described_class.memory).to eq(status: "unknown")
    end
  end

  describe ".cpu" do
    it "reads /proc/loadavg and warns at a 1-minute load of 2 or more" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/loadavg").and_return("2.50 1.00 0.50 1/100 1234\n")

      expect(described_class.cpu).to eq(status: "warning", load_1min: 2.5, load_5min: 1.0, load_15min: 0.5)
    end

    it "is unknown when loadavg cannot be read" do
      allow(File).to receive(:read).and_call_original
      allow(File).to receive(:read).with("/proc/loadavg").and_raise(Errno::ENOENT)

      expect(described_class.cpu).to eq(status: "unknown")
    end
  end

  describe ".all" do
    before do
      described_class::SERVICES.each { |s| allow(described_class).to receive(s).and_return(status: "healthy") }
    end

    it "measures every service, keyed in a fixed order" do
      expect(described_class::SERVICES).to eq(%i[database redis sidekiq disk memory cpu])
      expect(described_class.all.keys).to eq(described_class::SERVICES)
    end

    it "measures only the services it is asked for, and does not touch the rest" do
      expect(described_class.all(only: %i[disk cpu]).keys).to eq(%i[disk cpu])
      expect(described_class).not_to have_received(:database)
      expect(described_class).not_to have_received(:sidekiq)
    end
  end
end
