# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignMetric, type: :model do
  subject { build(:marketing_campaign_metric) }

  describe "associations" do
    it { is_expected.to belong_to(:campaign).class_name("Marketing::Campaign") }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:channel) }
    it { is_expected.to validate_presence_of(:metric_date) }
  end

  describe "scopes" do
    let(:campaign) { create(:marketing_campaign) }

    it "filters by channel" do
      email_metric = create(:marketing_campaign_metric, campaign: campaign, channel: "email")
      social_metric = create(:marketing_campaign_metric, :social, campaign: campaign, metric_date: Date.yesterday)

      expect(described_class.by_channel("email")).to include(email_metric)
      expect(described_class.by_channel("email")).not_to include(social_metric)
    end

    it "filters by date range" do
      recent = create(:marketing_campaign_metric, campaign: campaign, metric_date: Date.current)
      old = create(:marketing_campaign_metric, campaign: campaign, metric_date: 1.month.ago.to_date, channel: "twitter")

      results = described_class.by_date_range(1.week.ago.to_date, Date.current)
      expect(results).to include(recent)
      expect(results).not_to include(old)
    end
  end

  describe "derived metrics" do
    let(:metric) { build(:marketing_campaign_metric, deliveries: 1000, unique_opens: 250, clicks: 100, conversions: 20, sends: 1000, bounces: 50, unsubscribes: 5, impressions: 5000, engagements: 500, revenue_cents: 50_000, cost_cents: 10_000) }

    it "calculates open rate" do
      expect(metric.open_rate).to eq(25.0)
    end

    it "calculates click rate" do
      expect(metric.click_rate).to eq(10.0)
    end

    it "calculates conversion rate" do
      expect(metric.conversion_rate).to eq(20.0)
    end

    it "calculates bounce rate" do
      expect(metric.bounce_rate).to eq(5.0)
    end

    it "calculates unsubscribe rate" do
      expect(metric.unsubscribe_rate).to eq(0.5)
    end

    it "calculates engagement rate" do
      expect(metric.engagement_rate).to eq(10.0)
    end

    it "calculates ROI" do
      expect(metric.roi).to eq(400.0)
    end
  end

  describe "derived metrics with zero values" do
    let(:metric) { build(:marketing_campaign_metric, :zero_metrics) }

    it "returns 0.0 for all rates when denominators are zero" do
      expect(metric.open_rate).to eq(0.0)
      expect(metric.click_rate).to eq(0.0)
      expect(metric.conversion_rate).to eq(0.0)
      expect(metric.bounce_rate).to eq(0.0)
      expect(metric.unsubscribe_rate).to eq(0.0)
      expect(metric.engagement_rate).to eq(0.0)
      expect(metric.roi).to eq(0.0)
    end
  end

  describe "#metric_summary" do
    let(:metric) { create(:marketing_campaign_metric) }

    it "returns summary with rates included" do
      summary = metric.metric_summary
      expect(summary).to include(:id, :channel, :metric_date, :sends, :deliveries, :open_rate, :click_rate, :roi)
    end
  end
end
