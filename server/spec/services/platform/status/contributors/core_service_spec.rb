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
      redis: { status: "healthy", response_time_ms: 0.4, connected_clients: 7 },
      sidekiq: { status: "healthy", processes: 1, stale_processes: 0, processed: 10, failed: 0, enqueued: 0, queue_count: 1 },
      disk: { status: "healthy", used_percentage: 40.0, free_gb: 60 },
      memory: { status: "healthy", used_percentage: 50.0, used_mb: 500, total_mb: 1000 },
      cpu: { status: "healthy", load_1min: 0.5, load_5min: 0.4, load_15min: 0.3 }
    }.merge(overrides)
  end

  def enumerate(account = nil)
    [].tap { |acc| contributor.each_component(account) { |record| acc << record } }
  end

  def only_condition(record) = contributor.conditions_for(record).first

  before do
    Rails.cache.delete_matched("#{described_class::CACHE_KEY}*")
    allow(checks).to receive(:all) { |only: checks::SERVICES| readings.slice(*only) }
    # Core mode by default: no other contributor claims a core service. A
    # checked-out extension may register one that does; see the claim specs.
    allow(Platform::Status::Registry).to receive(:contributors).and_return({ "core_service" => contributor }.freeze)
  end

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
      condition = condition_for(:redis, { status: "healthy", response_time_ms: 0.4, connected_clients: 7 })

      expect(condition).to include("type" => "Healthy", "status" => true, "reason" => "Healthy")
      expect(condition["evidence"]).to eq("response_time_ms" => 0.4, "connected_clients" => 7)
    end

    it "is degraded on a warning" do
      condition = condition_for(:disk, { status: "warning", used_percentage: 85.0, free_gb: 15 })

      expect(condition).to include("status" => false, "severity" => "degraded", "reason" => "Warning")
    end

    it "is down, naming the exception class, when the service is unhealthy" do
      condition = condition_for(:database, { status: "unhealthy", error_class: "ActiveRecord::ConnectionNotEstablished" })

      expect(condition).to include(
        "status" => false, "severity" => "down", "reason" => "Unhealthy",
        "message" => "Database is unhealthy (ActiveRecord::ConnectionNotEstablished)"
      )
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

  # fc-47 review H2: the checks open sockets, and the sweep runs once per
  # account every interval. They are measured at most once per interval and
  # every account's sweep reads that one measurement.
  describe "measurement cadence" do
    let(:accounts) { create_list(:account, 3) }

    it "probes once across every account's sweep in one interval" do
      accounts.each { |account| enumerate(account) }

      expect(checks).to have_received(:all).once
    end

    it "probes again once the sweep interval has passed" do
      enumerate(accounts.first)
      travel(Platform::Status::SweepService.sweep_interval_seconds.seconds + 1.second) { enumerate(accounts.last) }

      expect(checks).to have_received(:all).twice
    end

    it "probes once when run through the sweep itself for several accounts" do
      accounts.each { |account| Platform::Status::SweepService.run_once!(account) }

      expect(checks).to have_received(:all).once
    end
  end

  # fc-47 review M4: a registered contributor that already reports a core
  # service (the system extension reports postgres, redis and sidekiq from
  # its own probe) claims it, and core does not add a second row for it.
  # Core names no contributor: it reads the claim off whatever is registered.
  describe "services another registered contributor reports" do
    let(:claimer) do
      Class.new(Platform::Status::Contributor) do
        def kind = "zz_core_service_claimer"
        def each_component(_account) = nil
        def reports_core_services = %w[database redis sidekiq]
      end.new
    end

    # The registry as seen by the contributor, controlled per example: in this
    # tree a checked-out extension may claim services of its own.
    def registered(contributors)
      allow(Platform::Status::Registry).to receive(:contributors).and_return(contributors.freeze)
    end

    it "reports all six services when nothing else claims any" do
      registered("core_service" => contributor)

      expect(enumerate.map { |r| contributor.ref_for(r) }).to eq(%w[database redis sidekiq disk memory cpu])
      expect(checks).to have_received(:all).with(only: checks::SERVICES)
    end

    it "leaves out, and does not measure, the services a registered contributor reports" do
      registered("core_service" => contributor, "zz_core_service_claimer" => claimer)

      expect(enumerate.map { |r| contributor.ref_for(r) }).to eq(%w[disk memory cpu])
      expect(checks).to have_received(:all).with(only: %i[disk memory cpu])
    end

    it "ignores a contributor that does not answer the claim" do
      registered("core_service" => contributor, "zz_plain" => Object.new.tap { |o| o.define_singleton_method(:each_component) { |_| nil } })

      expect(enumerate.size).to eq(6)
    end
  end

  it "is registered by the core glob" do
    expect(Platform::Status::Contributors.contributor_classes).to include(described_class)
  end
end
