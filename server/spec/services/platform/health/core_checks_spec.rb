# frozen_string_literal: true

require "rails_helper"

# The ONE set of core service checks (database, redis, sidekiq, disk, memory,
# cpu). The maintenance health endpoint, the AI monitoring health service and
# the core_service status contributor all read these — before fc-43/47 each
# carried its own copy.
RSpec.describe Platform::Health::CoreChecks do
  describe ".database" do
    it "reports healthy with a response time and the connection pool" do
      result = described_class.database

      expect(result[:status]).to eq("healthy")
      expect(result[:response_time_ms]).to be_a(Numeric)
      expect(result[:connection_pool]).to include(:size, :connections, :busy, :idle)
    end

    it "reports unhealthy with the error when the query fails" do
      allow(ActiveRecord::Base.connection).to receive(:execute).and_raise(ActiveRecord::ConnectionNotEstablished, "no db")

      expect(described_class.database).to eq(status: "unhealthy", error: "no db")
    end
  end

  describe ".redis" do
    let(:client) { instance_double(Redis) }

    before { allow(Powernode::Redis).to receive(:new_client).and_return(client) }

    it "reports healthy with memory and client counts" do
      allow(client).to receive(:ping).and_return("PONG")
      allow(client).to receive(:info).and_return("used_memory_human" => "12M", "connected_clients" => "7")

      expect(described_class.redis).to include(status: "healthy", used_memory: "12M", connected_clients: 7)
      expect(described_class.redis[:response_time_ms]).to be_a(Numeric)
    end

    it "reports unhealthy with the error when redis is unreachable" do
      allow(client).to receive(:ping).and_raise(Redis::CannotConnectError, "refused")

      expect(described_class.redis).to eq(status: "unhealthy", error: "refused")
    end
  end

  # Sidekiq runs in the worker app; this app stays Sidekiq-free, so its state
  # is read from the process registry and counters Sidekiq keeps in the
  # worker's Redis, never through the gem.
  describe ".sidekiq" do
    let(:client) { instance_double(Redis) }

    before do
      allow(Powernode::Redis).to receive(:new_worker_client).and_return(client)
      allow(client).to receive(:get).with("stat:processed").and_return("10")
      allow(client).to receive(:get).with("stat:failed").and_return("1")
      allow(client).to receive(:llen).with("queue:default").and_return(3)
      allow(client).to receive(:llen).with("queue:mailers").and_return(0)
    end

    def with_processes(members)
      allow(client).to receive(:smembers).with("processes").and_return(members)
      allow(client).to receive(:smembers).with("queues").and_return(%w[default mailers])
    end

    it "is healthy with a worker process running, and carries the counters" do
      with_processes(%w[worker-1:123])

      expect(described_class.sidekiq).to eq(
        status: "healthy", processes: 1, processed: 10, failed: 1, enqueued: 3,
        queues: { "default" => 3, "mailers" => 0 }
      )
    end

    it "is unhealthy with no worker process: nothing is running the queues" do
      with_processes([])

      expect(described_class.sidekiq).to include(status: "unhealthy", processes: 0)
    end

    it "is unknown, never healthy, when the worker redis cannot be read" do
      allow(client).to receive(:smembers).and_raise(Redis::CannotConnectError, "refused")

      expect(described_class.sidekiq).to eq(status: "unknown", error: "refused")
    end

    it "never loads the Sidekiq gem" do
      with_processes(%w[worker-1:123])
      described_class.sidekiq

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
    it "measures every service, keyed in a fixed order" do
      expect(described_class::SERVICES).to eq(%i[database redis sidekiq disk memory cpu])
      allow(described_class).to receive(:database).and_return(status: "healthy")
      allow(described_class).to receive(:redis).and_return(status: "healthy")
      allow(described_class).to receive(:sidekiq).and_return(status: "healthy")
      allow(described_class).to receive(:disk).and_return(status: "healthy")
      allow(described_class).to receive(:memory).and_return(status: "healthy")
      allow(described_class).to receive(:cpu).and_return(status: "healthy")

      expect(described_class.all.keys).to eq(described_class::SERVICES)
    end
  end
end
