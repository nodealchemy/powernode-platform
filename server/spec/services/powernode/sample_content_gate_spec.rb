# frozen_string_literal: true

require "rails_helper"

# IMP-f1f96c292991 — 2026-09-13 operator ruling: sample/demo content (the 5
# business example agents, hobby/showcase node templates + their exclusive
# modules, the local-qemu dev provider, and role modules used only by smoke
# seeds) goes behind ONE deployment-wide SiteSetting, default OFF. This is
# that single gate, read by both the core seed (autonomy_data_seed.rb) and
# the system extension's seeds (account_bootstrap_service.rb,
# role_modules_seed.rb, node_module_catalog.rb).
RSpec.describe Powernode::SampleContentGate do
  describe ".enabled?" do
    it "defaults to false when the SiteSetting row does not exist" do
      expect(SiteSetting.find_by(key: described_class::SETTING_KEY)).to be_nil
      expect(described_class.enabled?).to be(false)
    end

    it "is false when the SiteSetting is explicitly false" do
      SiteSetting.set(described_class::SETTING_KEY, "false", setting_type: "boolean")
      expect(described_class.enabled?).to be(false)
    end

    it "is true only when the SiteSetting is explicitly true" do
      SiteSetting.set(described_class::SETTING_KEY, "true", setting_type: "boolean")
      expect(described_class.enabled?).to be(true)
    end

    it "fails closed (false) rather than raising if the lookup errors" do
      allow(SiteSetting).to receive(:get).and_raise(StandardError, "synthetic DB error")
      expect(described_class.enabled?).to be(false)
    end
  end
end
