# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignContentGeneratorService do
  let(:campaign) { create(:marketing_campaign) }
  let(:service) { described_class.new(campaign) }

  describe "#generate" do
    it "creates a single content variant" do
      contents = service.generate(channel: "email")
      expect(contents.length).to eq(1)
      expect(contents.first).to be_persisted
      expect(contents.first.ai_generated).to be true
      expect(contents.first.channel).to eq("email")
      expect(contents.first.status).to eq("draft")
    end

    it "creates multiple variants" do
      contents = service.generate(channel: "email", variant_count: 3)
      expect(contents.length).to eq(3)
      expect(contents.map(&:variant_name).uniq.length).to eq(3)
    end

    it "raises error for unsupported channel" do
      expect {
        service.generate(channel: "invalid_channel")
      }.to raise_error(described_class::GenerationError, /Unsupported channel/)
    end

    it "uses provided options" do
      contents = service.generate(
        channel: "email",
        options: { subject: "Custom Subject", cta_text: "Buy Now" }
      )
      expect(contents.first.subject).to eq("Custom Subject")
      expect(contents.first.cta_text).to eq("Buy Now")
    end

    it "generates content for Twitter with platform defaults" do
      contents = service.generate(channel: "twitter")
      expect(contents.first.platform_specific).to include("max_length" => 280)
    end

    it "generates content for LinkedIn with platform defaults" do
      contents = service.generate(channel: "linkedin")
      expect(contents.first.platform_specific).to include("max_length" => 3000)
    end
  end

  describe "#generate_multi_channel" do
    it "generates content for multiple channels" do
      results = service.generate_multi_channel(channels: %w[email twitter])
      expect(results.keys).to contain_exactly("email", "twitter")
      expect(results["email"].length).to eq(1)
      expect(results["twitter"].length).to eq(1)
    end

    it "generates multiple variants per channel" do
      results = service.generate_multi_channel(channels: %w[email twitter], variant_count: 2)
      expect(results["email"].length).to eq(2)
      expect(results["twitter"].length).to eq(2)
    end
  end
end
