# frozen_string_literal: true

require "rails_helper"

# IMP-ab3fc7bd9499 — the shared Symbol-keyed handler-registry shape extracted
# from Ai::Land::SecurityScannerRegistry and Devops::ContainerLifecycleRegistry.
# Extending modules keep their own constant name, their own ArgumentError noun
# and — critically — their own @handlers store.
RSpec.describe Powernode::HandlerRegistry do
  # Anonymous extenders: nothing here can touch a real registry's state.
  let(:registry) { Module.new { extend Powernode::HandlerRegistry } }

  let(:nouned_registry) do
    Module.new do
      extend Powernode::HandlerRegistry

      class << self
        private

        def handler_noun
          "widget handler"
        end
      end
    end
  end

  describe ".register" do
    it "registers a callable argument under the symbolized name and returns the name" do
      handler = ->(*) {}
      expect(registry.register("probe", handler)).to eq(:probe)
      expect(registry.handlers[:probe]).to eq(handler)
    end

    it "registers a block handler" do
      registry.register(:probe) { |*| :called }
      expect(registry.handlers[:probe].call).to eq(:called)
    end

    it "replaces an existing handler under the same name" do
      registry.register(:probe) { |*| :first }
      registry.register(:probe) { |*| :second }
      expect(registry.names).to eq([ :probe ])
      expect(registry.handlers[:probe].call).to eq(:second)
    end

    it "rejects a handler that does not respond to #call" do
      expect { registry.register(:probe, "not callable") }
        .to raise_error(ArgumentError, "handler for :probe must respond to #call")
    end

    it "uses the extending module's own error noun" do
      expect { nouned_registry.register(:probe, :not_callable) }
        .to raise_error(ArgumentError, "widget handler for :probe must respond to #call")
    end
  end

  describe ".unregister" do
    it "removes the named handler and returns it" do
      handler = ->(*) {}
      registry.register(:probe, handler)
      expect(registry.unregister("probe")).to eq(handler)
      expect(registry.registered?(:probe)).to be(false)
    end
  end

  describe ".registered?" do
    it "symbolizes the lookup key" do
      registry.register(:probe) { |*| }
      expect(registry.registered?("probe")).to be(true)
      expect(registry.registered?(:missing)).to be(false)
    end
  end

  describe ".names" do
    it "lists the registered handler names as symbols" do
      registry.register(:a) { |*| }
      registry.register(:b) { |*| }
      expect(registry.names).to eq(%i[a b])
    end
  end

  describe ".handlers" do
    it "is public and defaults to an empty hash" do
      expect(registry.handlers).to eq({})
      expect(registry.respond_to?(:handlers)).to be(true)
    end
  end

  describe ".reset!" do
    it "clears the extending module's handlers" do
      registry.register(:probe) { |*| }
      registry.reset!
      expect(registry.names).to eq([])
    end
  end

  describe "per-extender state isolation" do
    it "keeps @handlers on the extending module, not on the shared module" do
      other = Module.new { extend Powernode::HandlerRegistry }
      registry.register(:only_mine) { |*| }

      expect(other.names).to eq([])
      expect(registry.names).to eq([ :only_mine ])

      other.reset!
      expect(registry.registered?(:only_mine)).to be(true)
    end
  end

  describe "public API surface" do
    it "does not expose the noun hook as a public method" do
      expect(registry.respond_to?(:handler_noun)).to be(false)
      expect(nouned_registry.respond_to?(:handler_noun)).to be(false)
    end
  end
end
