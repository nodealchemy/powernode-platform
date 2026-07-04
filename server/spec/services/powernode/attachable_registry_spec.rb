# frozen_string_literal: true

require "rails_helper"

RSpec.describe Powernode::AttachableRegistry do
  around do |example|
    saved = described_class.registered_types.to_h { |t| [ t, described_class.resolve(t) ] }
    example.run
  ensure
    described_class.reset!
    saved.each { |type, resolver| described_class.register(type, resolver) }
  end

  describe ".register / .resolve" do
    it "stores and returns a resolver callable for a type" do
      resolver = ->(account, id) { [ account, id ] }
      described_class.register("Some::Thing", resolver)

      expect(described_class.resolve("Some::Thing")).to eq(resolver)
      expect(described_class.resolve("Some::Thing").call(:acct, "id-1")).to eq([ :acct, "id-1" ])
    end

    it "accepts a block form" do
      described_class.register("Some::Blocky") { |account, id| "#{account}:#{id}" }

      expect(described_class.resolve("Some::Blocky").call("a", "b")).to eq("a:b")
    end

    it "replaces an existing resolver for the same type" do
      described_class.register("Some::Dupe") { "first" }
      described_class.register("Some::Dupe") { "second" }

      expect(described_class.resolve("Some::Dupe").call).to eq("second")
    end

    it "returns nil for an unregistered type" do
      expect(described_class.resolve("Never::Registered")).to be_nil
    end

    it "raises when neither a resolver nor block is given" do
      expect { described_class.register("Some::Bad") }.to raise_error(ArgumentError)
    end
  end

  describe ".reset!" do
    it "clears all registered resolvers" do
      described_class.register("Some::Temp") { "x" }
      described_class.reset!

      expect(described_class.resolve("Some::Temp")).to be_nil
    end
  end
end
