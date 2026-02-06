# frozen_string_literal: true

require "rails_helper"

RSpec.describe Shared::FeatureFlagService do
  let(:account) { create(:account) }
  let(:mock_flipper) { class_double(Flipper) }

  before do
    allow(Flipper).to receive(:enabled?).and_return(false)
    allow(Flipper).to receive(:enable)
    allow(Flipper).to receive(:disable)
    allow(Flipper).to receive(:enable_percentage_of_actors)
    allow(Flipper).to receive(:features).and_return([])
  end

  describe ".enabled?" do
    context "without actor" do
      it "checks if flag is enabled globally" do
        allow(Flipper).to receive(:enabled?).with(:new_dashboard).and_return(true)

        expect(described_class.enabled?(:new_dashboard)).to be true
      end

      it "returns false when flag is disabled" do
        allow(Flipper).to receive(:enabled?).with(:new_dashboard).and_return(false)

        expect(described_class.enabled?(:new_dashboard)).to be false
      end
    end

    context "with actor" do
      it "checks if flag is enabled for the actor" do
        allow(Flipper).to receive(:enabled?).with(:beta_feature, account).and_return(true)

        expect(described_class.enabled?(:beta_feature, account)).to be true
      end

      it "returns false when flag is disabled for actor" do
        allow(Flipper).to receive(:enabled?).with(:beta_feature, account).and_return(false)

        expect(described_class.enabled?(:beta_feature, account)).to be false
      end
    end

    context "when Flipper raises an error" do
      it "returns false and logs the error" do
        allow(Flipper).to receive(:enabled?).and_raise(StandardError, "Redis connection failed")
        allow(Rails.logger).to receive(:error)

        result = described_class.enabled?(:some_flag)

        expect(result).to be false
        expect(Rails.logger).to have_received(:error).with(/Error checking flag/)
      end
    end
  end

  describe ".enable!" do
    context "without actor" do
      it "enables flag globally" do
        expect(Flipper).to receive(:enable).with(:new_feature)

        described_class.enable!(:new_feature)
      end
    end

    context "with actor" do
      it "enables flag for specific actor" do
        expect(Flipper).to receive(:enable).with(:new_feature, account)

        described_class.enable!(:new_feature, account)
      end
    end
  end

  describe ".disable!" do
    context "without actor" do
      it "disables flag globally" do
        expect(Flipper).to receive(:disable).with(:old_feature)

        described_class.disable!(:old_feature)
      end
    end

    context "with actor" do
      it "disables flag for specific actor" do
        expect(Flipper).to receive(:disable).with(:old_feature, account)

        described_class.disable!(:old_feature, account)
      end
    end
  end

  describe ".enable_percentage!" do
    it "enables flag for a percentage of actors" do
      expect(Flipper).to receive(:enable_percentage_of_actors).with(:gradual_rollout, 25)

      described_class.enable_percentage!(:gradual_rollout, 25)
    end

    it "accepts 0 percent" do
      expect(Flipper).to receive(:enable_percentage_of_actors).with(:feature, 0)

      described_class.enable_percentage!(:feature, 0)
    end

    it "accepts 100 percent" do
      expect(Flipper).to receive(:enable_percentage_of_actors).with(:feature, 100)

      described_class.enable_percentage!(:feature, 100)
    end
  end

  describe ".all_flags" do
    it "returns all feature flags with their status" do
      mock_feature = instance_double("Flipper::Feature",
        name: :new_dashboard,
        enabled?: true,
        gate_values: double(to_h: { boolean: true, groups: [], actors: [], percentage_of_actors: nil, percentage_of_time: nil })
      )

      allow(Flipper).to receive(:features).and_return([mock_feature])

      result = described_class.all_flags

      expect(result).to be_an(Array)
      expect(result.length).to eq(1)
      expect(result.first[:name]).to eq(:new_dashboard)
      expect(result.first[:enabled]).to be true
      expect(result.first[:gate_values]).to be_a(Hash)
    end

    it "returns empty array when no flags exist" do
      allow(Flipper).to receive(:features).and_return([])

      result = described_class.all_flags

      expect(result).to eq([])
    end

    it "returns empty array on error" do
      allow(Flipper).to receive(:features).and_raise(StandardError, "Store unavailable")
      allow(Rails.logger).to receive(:error)

      result = described_class.all_flags

      expect(result).to eq([])
      expect(Rails.logger).to have_received(:error).with(/Error listing flags/)
    end

    it "returns multiple flags" do
      features = [
        instance_double("Flipper::Feature",
          name: :flag_a,
          enabled?: true,
          gate_values: double(to_h: { boolean: true })
        ),
        instance_double("Flipper::Feature",
          name: :flag_b,
          enabled?: false,
          gate_values: double(to_h: { boolean: false })
        )
      ]

      allow(Flipper).to receive(:features).and_return(features)

      result = described_class.all_flags

      expect(result.length).to eq(2)
      expect(result.map { |f| f[:name] }).to contain_exactly(:flag_a, :flag_b)
    end
  end
end
