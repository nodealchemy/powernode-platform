# frozen_string_literal: true

require "rails_helper"

RSpec.describe Powernode::ExtensionRegistry do
  # The registry is a process-global singleton; snapshot and restore @extensions so each
  # example is isolated and synthetic extensions never leak into the rest of the suite.
  around do |example|
    snapshot = described_class.instance_variable_get(:@extensions)&.dup || {}
    described_class.instance_variable_set(:@extensions, {})
    example.run
  ensure
    described_class.instance_variable_set(:@extensions, snapshot)
  end

  # A features_module that owns a fixed set of features and honors the nil-for-unowned
  # contract: true when licensed, false when owned-but-unavailable, nil when not owned.
  let(:owning_features) do
    Module.new do
      def self.available?(feature, account: nil)
        case feature.to_sym
        when :alpha, :beta then true
        when :locked then false
        end
      end
    end
  end

  # A misbehaving features_module that returns a blanket true for EVERY feature (mimics the
  # system extension). It must never poison resolution because it declares no capabilities.
  let(:blanket_true_features) do
    Module.new do
      def self.available?(_feature, account: nil)
        true
      end
    end
  end

  describe ".register" do
    it "stores capabilities symbolized and frozen" do
      described_class.register(slug: "demo", engine: :engine, capabilities: %w[alpha beta])

      caps = described_class.capabilities_for("demo")
      expect(caps).to contain_exactly(:alpha, :beta)
      expect(caps).to be_frozen
    end

    it "defaults capabilities and providers to empty when omitted" do
      described_class.register(slug: "bare", engine: :engine)

      expect(described_class.capabilities_for("bare")).to eq([])
      expect(described_class.provider(:anything)).to be_nil
    end

    it "symbolizes provider keys" do
      impl = Object.new
      described_class.register(slug: "demo", engine: :engine, providers: { "thing" => impl })

      expect(described_class.provider(:thing)).to be(impl)
    end
  end

  describe ".provides?" do
    before { described_class.register(slug: "demo", engine: :engine, capabilities: [ :alpha ]) }

    it "is true when a loaded extension declares the capability" do
      expect(described_class.provides?(:alpha)).to be(true)
    end

    it "normalizes string and symbol forms" do
      expect(described_class.provides?("alpha")).to be(true)
    end

    it "is false when no extension declares it" do
      expect(described_class.provides?(:nope)).to be(false)
    end

    it "is declaration-only and ignores features_module" do
      described_class.register(slug: "sys", engine: :engine, features_module: blanket_true_features)

      # sys declares NO capabilities, so its blanket-true module provides nothing.
      expect(described_class.provides?(:unowned)).to be(false)
    end
  end

  describe ".provider" do
    it "returns the registered implementation" do
      impl = ->(x) { x }
      described_class.register(slug: "demo", engine: :engine, providers: { calc: impl })

      expect(described_class.provider(:calc)).to be(impl)
    end

    it "constantizes string class names lazily" do
      described_class.register(slug: "demo", engine: :engine, providers: { svc: "String" })

      expect(described_class.provider(:svc)).to eq(String)
    end

    it "returns nil when no extension registers the key (core-mode default)" do
      expect(described_class.provider(:absent)).to be_nil
    end

    it "returns the first registered provider when several extensions register the key" do
      first = Object.new
      second = Object.new
      described_class.register(slug: "a", engine: :engine, providers: { key: first })
      described_class.register(slug: "b", engine: :engine, providers: { key: second })

      expect(described_class.provider(:key)).to be(first)
    end
  end

  describe ".feature_available?" do
    it "returns the owning extension's decision for a declared capability" do
      described_class.register(
        slug: "biz", engine: :engine, capabilities: %i[alpha beta locked], features_module: owning_features
      )

      expect(described_class.feature_available?(:alpha)).to be(true)
    end

    it "propagates a false decision (owned but unavailable) rather than treating it as nil" do
      described_class.register(
        slug: "biz", engine: :engine, capabilities: [ :locked ], features_module: owning_features
      )

      expect(described_class.feature_available?(:locked)).to be(false)
    end

    it "returns false for a feature no loaded extension declares" do
      described_class.register(
        slug: "biz", engine: :engine, capabilities: [ :alpha ], features_module: owning_features
      )

      expect(described_class.feature_available?(:gamma)).to be(false)
    end

    it "ignores a blanket-true features_module lacking the capability (poison regression)" do
      # Mimics the system extension (blanket true, no capabilities) loaded alongside a real owner.
      described_class.register(slug: "system", engine: :engine, features_module: blanket_true_features)
      described_class.register(
        slug: "biz", engine: :engine, capabilities: [ :alpha ], features_module: owning_features
      )

      # :unowned is declared by nobody → false, NOT system's blanket true.
      expect(described_class.feature_available?(:unowned)).to be(false)
      # :alpha is owned by biz → biz's decision, regardless of iteration order.
      expect(described_class.feature_available?(:alpha)).to be(true)
    end
  end

  # Genericity contract: a brand-new, never-before-seen extension plugs into core's generic
  # seams with ZERO core changes — both presence and behavior resolve.
  describe "generic extension contract" do
    it "resolves capability and provider for a synthetic future extension" do
      ticketing = Class.new do
        def self.open_count(_account)
          42
        end
      end
      described_class.register(
        slug: "support_desk",
        engine: :engine,
        capabilities: [ :ticketing ],
        providers: { ticketing: ticketing }
      )

      expect(Shared::FeatureGateService.capability_present?(:ticketing)).to be(true)
      expect(described_class.provider(:ticketing).open_count(:acct)).to eq(42)
    end
  end
end
