# frozen_string_literal: true

require 'rails_helper'

# IMP-8880bc817ea3 — generic container-lifecycle hook registry (the ruled
# core seam for the OVN container-fabric lane). Core owns the registry and
# the handler contract; extensions register handlers at boot. With nothing
# registered (core mode) every notify is a no-op, so core behavior is
# unchanged in core-only assemblies.
RSpec.describe Devops::ContainerLifecycleRegistry do
  # The registry is process-global and extensions register real handlers at
  # boot — snapshot and restore so these examples neither see nor clobber
  # boot-time registrations.
  around do |example|
    snapshot = described_class.handlers.dup
    described_class.reset!
    example.run
  ensure
    described_class.reset!
    snapshot.each { |name, handler| described_class.register(name, handler) }
  end

  let(:container) { build_stubbed(:devops_docker_container) }

  describe '.register' do
    it 'registers a block handler by name' do
      described_class.register(:probe) { |_event, _container| }
      expect(described_class.registered?(:probe)).to be(true)
      expect(described_class.names).to eq([:probe])
    end

    it 'registers a callable argument' do
      handler = ->(_event, _container) {}
      described_class.register(:probe, handler)
      expect(described_class.registered?(:probe)).to be(true)
    end

    it 'replaces an existing handler under the same name' do
      calls = []
      described_class.register(:probe) { |_e, _c| calls << :first }
      described_class.register(:probe) { |_e, _c| calls << :second }
      described_class.notify(:created, container)
      expect(calls).to eq([:second])
    end

    it 'rejects a handler that does not respond to #call' do
      expect { described_class.register(:probe, :not_callable) }
        .to raise_error(ArgumentError, /call/)
    end
  end

  describe '.unregister' do
    it 'removes the named handler' do
      described_class.register(:probe) { |_e, _c| }
      described_class.unregister(:probe)
      expect(described_class.registered?(:probe)).to be(false)
    end
  end

  describe '.notify' do
    it 'is a no-op with nothing registered (core-mode purity)' do
      expect { described_class.notify(:created, container) }.not_to raise_error
    end

    it 'invokes every registered handler with (event, container)' do
      received = []
      described_class.register(:a) { |event, c| received << [:a, event, c] }
      described_class.register(:b) { |event, c| received << [:b, event, c] }

      described_class.notify(:created, container)

      expect(received).to contain_exactly(
        [:a, :created, container],
        [:b, :created, container]
      )
    end

    it 'supports the :removed event' do
      events = []
      described_class.register(:probe) { |event, _c| events << event }
      described_class.notify(:removed, container)
      expect(events).to eq([:removed])
    end

    it 'rejects events outside the declared contract' do
      expect { described_class.notify(:started, container) }
        .to raise_error(ArgumentError, /event/)
    end

    # Hook failures must never break container lifecycle: the container
    # already exists (or is already gone) by the time hooks run.
    it 'isolates a raising handler — logs and still runs the others' do
      ran = []
      described_class.register(:boom) { |_e, _c| raise 'hook exploded' }
      described_class.register(:after) { |_e, _c| ran << :after }

      expect(Rails.logger).to receive(:error).with(/boom.*hook exploded/)
      expect { described_class.notify(:created, container) }.not_to raise_error
      expect(ran).to eq([:after])
    end
  end
end
