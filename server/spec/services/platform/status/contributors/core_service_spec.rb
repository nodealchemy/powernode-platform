# frozen_string_literal: true

require "rails_helper"

# fc-47 — the `core_service` contributor: the platform's own services
# (database, redis, sidekiq, disk, memory, cpu) as components on /app/status in
# CORE mode, read from the one shared Platform::Health::CoreChecks. Before it,
# /app/status showed none of these without the system extension, and the only
# views were the Observability and Maintenance health tabs fc-47 deletes.
RSpec.describe Platform::Status::Contributors::CoreService do
  subject(:contributor) { described_class.new }

  let(:checks) { Platform::Health::CoreChecks }

  def readings(overrides = {})
    {
      database: { status: "healthy", response_time_ms: 1.2, connection_pool: { size: 5, connections: 2, busy: 1, idle: 1 } },
      redis: { status: "healthy", response_time_ms: 0.4, used_memory: "12M", connected_clients: 7 },
      sidekiq: { status: "healthy", processes: 1, processed: 10, failed: 0, enqueued: 0, queues: {} },
      disk: { status: "healthy", used_percentage: 40.0, free_gb: 60 },
      memory: { status: "healthy", used_percentage: 50.0, used_mb: 500, total_mb: 1000 },
      cpu: { status: "healthy", load_1min: 0.5, load_5min: 0.4, load_15min: 0.3 }
    }.merge(overrides)
  end

  def enumerate(account = nil)
    [].tap { |acc| contributor.each_component(account) { |record| acc << record } }
  end

  def only_condition(record) = contributor.conditions_for(record).first

  before { allow(checks).to receive(:all).and_return(readings) }

  describe "the contract" do
    it "answers the registry key" do
      expect(described_class::KIND).to eq("core_service")
      expect(contributor.kind).to eq("core_service")
    end

    it "is not account scoped: the services are shared by every tenant" do
      expect(contributor.account_scoped?).to be(false)
    end

    it "presents a string icon name, a label and a group order" do
      expect(contributor.presentation).to eq("icon" => "Server", "label" => "Core Service", "group_order" => 5)
    end

    it "declares no dependencies and no actions" do
      record = enumerate.first
      expect(contributor.dependencies_for(record)).to eq([])
      expect(contributor.actions_for(record)).to eq([])
    end
  end

  describe "#each_component" do
    it "yields one component per core service, measured once per sweep" do
      records = enumerate(create(:account))

      expect(records.map { |r| contributor.ref_for(r) }).to eq(%w[database redis sidekiq disk memory cpu])
      expect(records.map { |r| contributor.display_name_for(r) }).to eq(%w[Database Redis Sidekiq Disk Memory CPU])
      expect(checks).to have_received(:all).once
    end
  end

  describe "#conditions_for" do
    def condition_for(service, reading)
      allow(checks).to receive(:all).and_return(readings(service => reading))
      record = enumerate.find { |r| contributor.ref_for(r) == service.to_s }
      only_condition(record)
    end

    it "is healthy, with the reading as evidence and no status key in it" do
      condition = condition_for(:redis, { status: "healthy", response_time_ms: 0.4, used_memory: "12M", connected_clients: 7 })

      expect(condition).to include("type" => "Healthy", "status" => true, "reason" => "Healthy")
      expect(condition["evidence"]).to eq("response_time_ms" => 0.4, "used_memory" => "12M", "connected_clients" => 7)
    end

    it "is degraded on a warning" do
      condition = condition_for(:disk, { status: "warning", used_percentage: 85.0, free_gb: 15 })

      expect(condition).to include("status" => false, "severity" => "degraded", "reason" => "Warning")
    end

    it "is down, with the error as the message, when the service is unhealthy" do
      condition = condition_for(:database, { status: "unhealthy", error: "no db" })

      expect(condition).to include("status" => false, "severity" => "down", "reason" => "Unhealthy", "message" => "no db")
    end

    it "is unknown (not measured), never healthy, when the check could not read it" do
      condition = condition_for(:cpu, { status: "unknown" })

      expect(condition).to include("status" => "unknown", "reason" => "NotObserved")
    end

    it "is unknown for a status token it does not recognise" do
      condition = condition_for(:memory, { status: "bogus" })

      expect(condition).to include("status" => "unknown", "reason" => "NotObserved")
    end
  end

  it "is registered by the core glob" do
    expect(Platform::Status::Contributors.contributor_classes).to include(described_class)
  end
end
