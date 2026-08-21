# frozen_string_literal: true

require "rails_helper"

# IMP-ab3fc7bd9499 — cross-registry guard for the shared handler-registry shape.
#
# Ai::Land::SecurityScannerRegistry and Devops::ContainerLifecycleRegistry share
# one implementation, but each memoizes its handler map on ITSELF. This spec
# passes on the pre-extraction code and must keep passing afterwards: it is the
# oracle for the single most likely way a shared mixin silently breaks these —
# one registry's writes (or its reset!) leaking into the other's store.
RSpec.describe "handler registry cross-registry isolation" do
  let(:registries) { [ Ai::Land::SecurityScannerRegistry, Devops::ContainerLifecycleRegistry ] }

  # Both registries are process-global and extensions register real handlers at
  # boot — snapshot and restore so these examples neither see nor clobber
  # boot-time registrations.
  around do |example|
    snapshots = registries.to_h { |registry| [ registry, registry.handlers.dup ] }
    registries.each(&:reset!)
    example.run
  ensure
    snapshots.each do |registry, snapshot|
      registry.reset!
      snapshot.each { |name, handler| registry.register(name, handler) }
    end
  end

  it "keeps each registry's handler store separate" do
    Ai::Land::SecurityScannerRegistry.register(:scanner_only) { |_ctx| [] }

    expect(Ai::Land::SecurityScannerRegistry.names).to eq([ :scanner_only ])
    expect(Devops::ContainerLifecycleRegistry.names).to eq([])
    expect(Devops::ContainerLifecycleRegistry.registered?(:scanner_only)).to be(false)
    expect(Devops::ContainerLifecycleRegistry.handlers).to eq({})
  end

  it "does not let one registry's reset! clear the other" do
    Ai::Land::SecurityScannerRegistry.register(:scanner_only) { |_ctx| [] }
    Devops::ContainerLifecycleRegistry.register(:lifecycle_only) { |_event, _container| }

    Devops::ContainerLifecycleRegistry.reset!

    expect(Devops::ContainerLifecycleRegistry.names).to eq([])
    expect(Ai::Land::SecurityScannerRegistry.registered?(:scanner_only)).to be(true)

    Ai::Land::SecurityScannerRegistry.reset!
    Devops::ContainerLifecycleRegistry.register(:lifecycle_only) { |_event, _container| }

    expect(Ai::Land::SecurityScannerRegistry.names).to eq([])
    expect(Devops::ContainerLifecycleRegistry.registered?(:lifecycle_only)).to be(true)
  end

  it "does not let one registry's unregister remove the other's same-named handler" do
    registries.each { |registry| registry.register(:shared_name) { |*| } }

    Ai::Land::SecurityScannerRegistry.unregister(:shared_name)

    expect(Ai::Land::SecurityScannerRegistry.registered?(:shared_name)).to be(false)
    expect(Devops::ContainerLifecycleRegistry.registered?(:shared_name)).to be(true)
  end

  it "keeps each registry's own ArgumentError noun" do
    expect { Ai::Land::SecurityScannerRegistry.register(:bad, "nope") }
      .to raise_error(ArgumentError, "scanner handler for :bad must respond to #call")

    expect { Devops::ContainerLifecycleRegistry.register(:bad, "nope") }
      .to raise_error(ArgumentError, "lifecycle handler for :bad must respond to #call")
  end

  it "keeps notify on the lifecycle registry only" do
    expect(Devops::ContainerLifecycleRegistry).to respond_to(:notify)
    expect(Devops::ContainerLifecycleRegistry::EVENTS).to eq(%i[created removed])
    expect(Ai::Land::SecurityScannerRegistry).not_to respond_to(:notify)
    expect(defined?(Ai::Land::SecurityScannerRegistry::EVENTS)).to be_nil
  end
end
