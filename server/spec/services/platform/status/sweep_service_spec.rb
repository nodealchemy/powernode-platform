# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A1 — the sweep and the reap arm.
RSpec.describe Platform::Status::SweepService do
  let(:account) { create(:account) }
  let(:registry) { Platform::Status::Registry }
  let(:condition) { Platform::Status::Condition }

  # A contributor over plain structs: this increment must be provable with no
  # real fleet, no extension and no sensor.
  # rubocop:disable RSpec/LeakyConstantDeclaration
  FakeRecord = Struct.new(:id, :name, :up, keyword_init: true)

  class FakeContributor < Platform::Status::Contributor
    attr_accessor :records, :raise_on_enumerate, :raise_on_record, :scoped, :edges

    def initialize(records: [], scoped: true)
      super()
      @records = records
      @scoped = scoped
      @edges = {}
      @raise_on_enumerate = false
      @raise_on_record = nil
    end

    def kind = "fake_kind"
    def account_scoped? = @scoped
    def ref_for(record) = record.id
    def display_name_for(record) = record.name

    def each_component(_account)
      raise "enumeration exploded" if @raise_on_enumerate

      @records.each { |record| yield record }
    end

    def conditions_for(record)
      raise "conditions exploded" if @raise_on_record == record.id

      [ Platform::Status::Condition.build(type: "Reachable", status: record.up,
                                          reason: record.up ? "Responding" : "Timeout") ]
    end

    def dependencies_for(record) = Array(@edges[record.id])
  end
  # rubocop:enable RSpec/LeakyConstantDeclaration

  around do |example|
    saved = registry.contributors
    registry.reset!
    example.run
  ensure
    registry.reset!
    saved.each { |kind, contributor| registry.register(kind, contributor) }
  end

  def record(id, up: true)
    FakeRecord.new(id: id, name: "Component #{id}", up: up)
  end

  describe "the sweep interval" do
    it "reads the SiteSetting and falls back to the documented default, both arms" do
      expect(described_class.sweep_interval_seconds).to eq(described_class::DEFAULT_SWEEP_INTERVAL_SECONDS)

      SiteSetting.create!(key: described_class::SWEEP_INTERVAL_SETTING, value: "120", setting_type: "integer")
      expect(described_class.sweep_interval_seconds).to eq(120)
      expect(described_class.reap_after_seconds).to eq(120 * described_class::REAP_AFTER_SWEEPS)
    end

    it "ignores a non-positive setting rather than reaping everything instantly" do
      SiteSetting.create!(key: described_class::SWEEP_INTERVAL_SETTING, value: "0", setting_type: "integer")

      expect(described_class.sweep_interval_seconds).to eq(described_class::DEFAULT_SWEEP_INTERVAL_SECONDS)
    end
  end

  describe "a registered kind" do
    it "writes one row per component, with the derived verdict and the contributor's presentation" do
      registry.register("fake_kind", FakeContributor.new(records: [ record("a"), record("b", up: false) ]))

      summary = described_class.run_once!(account)

      rows = Platform::ComponentStatus.for_account(account).for_kind("fake_kind").order(:component_ref)
      expect(rows.pluck(:component_ref, :verdict)).to eq([ %w[a ok], %w[b degraded] ])
      expect(rows.first.display_name).to eq("Component a")
      expect(rows.first.last_seen_sweep_at).to be_present
      expect(rows.first.presentation["icon"]).to be_present

      expect(summary[:kinds]["fake_kind"]).to include(count: 2, errors: 0)
    end

    it "upserts rather than duplicating, and preserves an unchanged condition's transition time" do
      contributor = FakeContributor.new(records: [ record("a", up: false) ])
      registry.register("fake_kind", contributor)

      described_class.run_once!(account, now: 2.hours.ago)
      first = Platform::ComponentStatus.find_by!(component_ref: "a")
      original_transition = first.conditions.first["last_transition_at"]

      described_class.run_once!(account)
      expect(Platform::ComponentStatus.where(component_ref: "a").count).to eq(1)

      unchanged = first.reload.conditions.first
      expect(unchanged["last_transition_at"]).to eq(original_transition)

      # And the other arm: flipping the underlying fact moves the timestamp.
      contributor.records = [ record("a", up: true) ]
      described_class.run_once!(account)
      expect(first.reload.conditions.first["last_transition_at"]).not_to eq(original_transition)
    end

    it "returns the transitions and emits NO events itself — A2 is the single producer" do
      contributor = FakeContributor.new(records: [ record("a") ])
      registry.register("fake_kind", contributor)

      first_run = described_class.run_once!(account)
      expect(first_run[:transitions].map { |t| t.values_at(:component_ref, :from, :to) }).to eq([ [ "a", nil, "ok" ] ])

      # A second pass with nothing changed reports NO transition.
      expect(described_class.run_once!(account)[:transitions]).to be_empty

      contributor.records = [ record("a", up: false) ]
      changed = described_class.run_once!(account)
      expect(changed[:transitions].map { |t| t.values_at(:from, :to) }).to eq([ %w[ok degraded] ])
      expect(changed[:kinds]["fake_kind"][:transitions]).to eq(1)
    end
  end

  describe "a contributor that raises" do
    it "marks a single failing component not_measured/ContributorError and keeps its siblings" do
      contributor = FakeContributor.new(records: [ record("a"), record("boom") ])
      contributor.raise_on_record = "boom"
      registry.register("fake_kind", contributor)

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("ok")
      failed = Platform::ComponentStatus.find_by!(component_ref: "boom")
      expect(failed.verdict).to eq("not_measured")
      expect(failed.conditions.first["reason"]).to eq("ContributorError")
      expect(failed.conditions.first["evidence"]["exception_class"]).to eq("RuntimeError")
    end

    it "lands a failing ENUMERATION on one wildcard row and never aborts the other kinds" do
      broken = FakeContributor.new
      broken.raise_on_enumerate = true
      registry.register("fake_kind", broken)

      healthy = FakeContributor.new(records: [ record("h") ])
      allow(healthy).to receive(:kind).and_return("healthy_kind")
      registry.register("healthy_kind", healthy)

      summary = described_class.run_once!(account)

      wildcard = Platform::ComponentStatus.find_by!(component_kind: "fake_kind",
                                                    component_ref: Platform::ComponentStatus::WILDCARD_REF)
      expect(wildcard.verdict).to eq("not_measured")
      expect(wildcard.conditions.first["reason"]).to eq("ContributorError")
      expect(summary[:kinds]["fake_kind"][:errors]).to eq(1)

      # The other kind still ran — the whole point.
      expect(Platform::ComponentStatus.find_by!(component_kind: "healthy_kind").verdict).to eq("ok")
      expect(summary[:kinds]["healthy_kind"]).to include(count: 1, errors: 0)
    end

    it "does not preserve a stale ok when it fails to look" do
      contributor = FakeContributor.new(records: [ record("a") ])
      registry.register("fake_kind", contributor)
      described_class.run_once!(account)
      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("ok")

      contributor.raise_on_record = "a"
      described_class.run_once!(account)

      expect(Platform::ComponentStatus.find_by!(component_ref: "a").verdict).to eq("not_measured")
    end
  end

  describe "a non-account-scoped kind" do
    it "writes a NULL-account row that no per-account rollup sees" do
      registry.register("shared_kind", FakeContributor.new(records: [ record("primary") ], scoped: false))

      described_class.run_once!(account)

      row = Platform::ComponentStatus.find_by!(component_kind: "shared_kind")
      expect(row.account_id).to be_nil
      expect(Platform::ComponentStatus.shared).to contain_exactly(row)
      expect(Platform::ComponentStatus.for_account(account)).not_to include(row)

      # A second account's sweep re-writes the SAME row rather than a second one.
      described_class.run_once!(create(:account))
      expect(Platform::ComponentStatus.where(component_kind: "shared_kind").count).to eq(1)
    end
  end

  describe "the reap arm" do
    it "deletes a row not seen for three sweeps and spares one seen two sweeps ago" do
      registry.register("fake_kind", FakeContributor.new(records: [ record("a") ]))
      interval = described_class.sweep_interval_seconds

      gone = create(:platform_component_status, account: account, component_kind: "fake_kind",
                                                component_ref: "gone",
                                                last_seen_sweep_at: (interval * 4).seconds.ago)
      recent = create(:platform_component_status, account: account, component_kind: "fake_kind",
                                                  component_ref: "recent",
                                                  last_seen_sweep_at: (interval * 2).seconds.ago)

      summary = described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(gone.id)).to be(false)
      expect(Platform::ComponentStatus.exists?(recent.id)).to be(true)
      expect(summary[:reaped]).to eq(1)
    end

    it "reaps a kind that is no longer registered, by the same age rule" do
      stale = create(:platform_component_status, account: account, component_kind: "retired_kind",
                                                 last_seen_sweep_at: 1.day.ago)
      young = create(:platform_component_status, account: account, component_kind: "retired_kind",
                                                 last_seen_sweep_at: Time.current)

      described_class.run_once!(account)

      # Aged out because nothing refreshes it...
      expect(Platform::ComponentStatus.exists?(stale.id)).to be(false)
      # ...but a freshly written row of an unregistered kind survives, so a
      # late-registering extension is not raced to death on boot.
      expect(Platform::ComponentStatus.exists?(young.id)).to be(true)
    end

    it "never reaps another account's rows" do
      other = create(:account)
      theirs = create(:platform_component_status, account: other, last_seen_sweep_at: 1.day.ago)

      described_class.run_once!(account)

      expect(Platform::ComponentStatus.exists?(theirs.id)).to be(true)
    end
  end
end
