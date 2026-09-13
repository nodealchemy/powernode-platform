# frozen_string_literal: true

# Shared fakes for the component status plane's specs.
#
# NAMESPACED ON PURPOSE (A1 review L4). These started as `FakeRecord` and
# `FakeContributor` assigned inside a `describe` block, which lands them on
# `Object` — and this codebase has a recorded duplicate-constant-clobber
# incident. Track B and Track C specs will want exactly these names, so they
# live here, under one namespace, defined once.
module PlatformStatusSpecSupport
  # `up` is tri-state: true (healthy), false (degraded), :down (total loss),
  # so a spec can reach every rung of the ladder without a bespoke contributor.
  FakeRecord = Struct.new(:id, :name, :up, :held, keyword_init: true)

  # A contributor over plain structs. The whole status plane is provable with
  # no fleet, no extension and no sensor, which is what keeps these specs fast
  # and what makes the seam's genericity a demonstrated property rather than a
  # claim.
  class FakeContributor < Platform::Status::Contributor
    attr_accessor :records, :raise_on_enumerate, :raise_on_record, :edges

    def initialize(kind: "fake_kind", records: [], scoped: true)
      super()
      @kind = kind
      @records = records
      @scoped = scoped
      @edges = {}
      @raise_on_enumerate = false
      @raise_on_record = nil
    end

    def kind = @kind
    def account_scoped? = @scoped
    def ref_for(record) = record.id
    def display_name_for(record) = record.name || record.id

    def each_component(_account)
      raise "enumeration exploded" if @raise_on_enumerate

      @records.each { |record| yield record }
    end

    def conditions_for(record)
      raise "conditions exploded" if @raise_on_record == record.id

      conditions = [ reachable_condition(record) ]
      conditions << held_condition if record.held
      conditions
    end

    def dependencies_for(record) = Array(@edges[record.id])

    private

    def reachable_condition(record)
      Platform::Status::Condition.build(
        type: "Reachable",
        status: record.up == true,
        reason: record.up == true ? "Responding" : "Timeout",
        severity: record.up == :down ? "down" : nil
      )
    end

    def held_condition
      Platform::Status::Condition.build(type: "Held", status: true, reason: "Cordoned")
    end
  end

  # Registers a contributor and returns it. Callers are responsible for the
  # registry snapshot/restore (see `around` in the specs).
  def register_fake_kind(kind: "fake_kind", records: [], scoped: true)
    contributor = FakeContributor.new(kind: kind, records: records, scoped: scoped)
    Platform::Status::Registry.register(kind, contributor)
    contributor
  end

  def fake_record(id, up: true, held: false, name: nil)
    FakeRecord.new(id: id, name: name || "Component #{id}", up: up, held: held)
  end

  # The registry and the emitter seam are process-global. Snapshot and restore
  # rather than leaving them empty, so a spec cannot silently delete what the
  # application registered at boot and leave a later spec measuring nothing.
  def self.around_clean_registries(example)
    saved_contributors = Platform::Status::Registry.contributors
    saved_emitters = Platform::Status::Emitters.handlers.dup
    Platform::Status::Registry.reset!
    Platform::Status::Emitters.reset!
    example.run
  ensure
    Platform::Status::Registry.reset!
    Platform::Status::Emitters.reset!
    saved_contributors.each { |kind, contributor| Platform::Status::Registry.register(kind, contributor) }
    saved_emitters.each { |name, handler| Platform::Status::Emitters.register(name, handler) }
  end
end

RSpec.configure do |config|
  config.include PlatformStatusSpecSupport, :platform_status
  config.around(:each, :platform_status) do |example|
    PlatformStatusSpecSupport.around_clean_registries(example)
  end
end
