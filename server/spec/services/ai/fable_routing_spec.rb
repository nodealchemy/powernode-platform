# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::FableRouting do
  describe ".enabled_for?" do
    it "defaults OFF when nothing is configured (framework deploys INERT)" do
      expect(described_class.enabled_for?(create(:account))).to be(false)
    end

    it "is enabled when Account#settings sets the flag true" do
      account = create(:account, settings: { "fable_routing_enabled" => true })
      expect(described_class.enabled_for?(account)).to be(true)
    end

    it "accepts stringy truthy values and symbol keys" do
      expect(described_class.enabled_for?(create(:account, settings: { "fable_routing_enabled" => "true" }))).to be(true)
      expect(described_class.enabled_for?(create(:account, settings: { fable_routing_enabled: "yes" }))).to be(true)
    end

    it "honors an explicit account false over an enabled global default" do
      SiteSetting.set("fable_routing_enabled", true, setting_type: "boolean")
      account = create(:account, settings: { "fable_routing_enabled" => false })
      expect(described_class.enabled_for?(account)).to be(false)
    end

    it "falls back to the global SiteSetting when the account has no override" do
      SiteSetting.set("fable_routing_enabled", true, setting_type: "boolean")
      expect(described_class.enabled_for?(create(:account))).to be(true)
    end

    it "is nil-safe" do
      expect(described_class.enabled_for?(nil)).to be(false)
    end
  end

  describe ".setting" do
    it "reads an arbitrary Account#settings key (string or symbol)" do
      account = create(:account, settings: { "fable_routing_agent_types" => %w[code_assistant] })
      expect(described_class.setting(account, "fable_routing_agent_types")).to eq(%w[code_assistant])
    end

    it "returns nil when unset" do
      expect(described_class.setting(create(:account), "fable_routing_agent_types")).to be_nil
    end
  end
end
