# frozen_string_literal: true

require "rails_helper"

RSpec.describe Powernode::TrustedProxyCidrs do
  describe ".parse" do
    it "returns [] for a blank or nil value" do
      expect(described_class.parse(nil)).to eq([])
      expect(described_class.parse("")).to eq([])
    end

    it "parses a single valid entry" do
      result = described_class.parse("10.0.0.0/8")

      expect(result).to eq([ IPAddr.new("10.0.0.0/8") ])
    end

    it "parses multiple comma-separated entries, stripping whitespace" do
      result = described_class.parse(" 10.0.0.0/8 , 192.168.1.1 ")

      expect(result).to eq([ IPAddr.new("10.0.0.0/8"), IPAddr.new("192.168.1.1") ])
    end

    it "drops blank entries from a trailing or doubled comma without raising" do
      result = described_class.parse("10.0.0.0/8,,192.168.1.1,")

      expect(result).to eq([ IPAddr.new("10.0.0.0/8"), IPAddr.new("192.168.1.1") ])
    end

    it "logs and skips an individual invalid entry rather than raising" do
      logged = []

      result = described_class.parse("10.0.0.0/8,not-an-ip", logger: ->(msg) { logged << msg })

      expect(result).to eq([ IPAddr.new("10.0.0.0/8") ])
      expect(logged.join).to match(/not-an-ip/)
    end

    it "returns [] when every entry is invalid, without raising" do
      expect { described_class.parse("not-an-ip", logger: ->(_msg) {}) }.not_to raise_error
      expect(described_class.parse("not-an-ip", logger: ->(_msg) {})).to eq([])
    end

    it "defaults to Kernel#warn when no logger is given, and does not raise" do
      expect {
        described_class.parse("not-an-ip")
      }.to output(/TRUSTED_PROXY_CIDRS.*not-an-ip/).to_stderr
    end
  end
end
