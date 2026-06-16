# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::FeatureGateService do
  describe ".extension_manifest_present?" do
    it "returns true when the extension's manifest exists" do
      expect(described_class.extension_manifest_present?("business")).to be true
    end

    it "returns false when the extension has no manifest" do
      expect(described_class.extension_manifest_present?("does-not-exist")).to be false
    end
  end

  describe ".extension_enabled?" do
    let(:slug) { "business" }

    context "when the manifest is absent" do
      it "returns false even if Flipper is enabled" do
        allow(described_class).to receive(:extension_manifest_present?).with(slug).and_return(false)
        allow(Flipper).to receive(:enabled?).and_return(true)

        expect(described_class.extension_enabled?(slug)).to be false
      end
    end

    context "when the slug is in the disabled state file" do
      it "returns false even if Flipper is enabled" do
        allow(described_class).to receive(:extension_manifest_present?).with(slug).and_return(true)
        allow(Shared::ExtensionStateStore).to receive(:disabled?).with(slug).and_return(true)
        allow(Flipper).to receive(:enabled?).and_return(true)

        expect(described_class.extension_enabled?(slug)).to be false
      end
    end

    context "when manifest is present and not disabled in state file" do
      before do
        allow(described_class).to receive(:extension_manifest_present?).with(slug).and_return(true)
        allow(Shared::ExtensionStateStore).to receive(:disabled?).with(slug).and_return(false)
      end

      it "returns true when Flipper says enabled" do
        allow(Flipper).to receive(:enabled?).with(:business_mode).and_return(true)

        expect(described_class.extension_enabled?(slug)).to be true
      end

      it "returns false when Flipper says disabled" do
        allow(Flipper).to receive(:enabled?).with(:business_mode).and_return(false)

        expect(described_class.extension_enabled?(slug)).to be false
      end
    end

    it "translates dashes in slug to underscores for the Flipper flag name" do
      allow(described_class).to receive(:extension_manifest_present?).with("supply-chain").and_return(true)
      allow(Shared::ExtensionStateStore).to receive(:disabled?).with("supply-chain").and_return(false)
      allow(Flipper).to receive(:enabled?).with(:supply_chain_mode).and_return(true)

      expect(described_class.extension_enabled?("supply-chain")).to be true
    end
  end

  describe ".capability_present?" do
    it "is true when a loaded extension declares the capability" do
      allow(Powernode::ExtensionRegistry).to receive(:provides?).with(:governance).and_return(true)
      expect(described_class.capability_present?(:governance)).to be true
    end

    it "is false when no loaded extension declares the capability" do
      allow(Powernode::ExtensionRegistry).to receive(:provides?).with(:governance).and_return(false)
      expect(described_class.capability_present?(:governance)).to be false
    end
  end

  describe ".core_feature?" do
    it "is true when no extension declares the feature (core owns it)" do
      allow(Powernode::ExtensionRegistry).to receive(:provides?).with(:billing).and_return(false)
      expect(described_class.core_feature?(:billing)).to be true
    end

    it "is false when an extension declares the feature" do
      allow(Powernode::ExtensionRegistry).to receive(:provides?).with(:billing).and_return(true)
      expect(described_class.core_feature?(:billing)).to be false
    end
  end
end
