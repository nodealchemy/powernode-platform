# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::CampaignAnalyticsService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  let(:campaign) { create(:marketing_campaign, :active, account: account, budget_cents: 100_000, spent_cents: 30_000) }
  let!(:metric) { create(:marketing_campaign_metric, campaign: campaign, metric_date: Date.current) }

  describe "#overview" do
    it "returns aggregate overview" do
      result = service.overview
      expect(result[:campaigns][:total]).to be >= 1
      expect(result[:campaigns][:active]).to be >= 1
      expect(result[:totals]).to include(:sends, :deliveries, :opens, :clicks, :conversions)
      expect(result[:rates]).to include(:open_rate, :click_rate, :conversion_rate)
      expect(result[:budget]).to include(:total_budget_cents, :total_spent_cents, :remaining_cents)
    end

    it "supports date range filtering" do
      old_campaign = create(:marketing_campaign, :active, account: account)
      create(:marketing_campaign_metric, campaign: old_campaign, metric_date: 2.months.ago.to_date, channel: "twitter")

      result = service.overview(date_range: { start_date: 1.week.ago.to_date, end_date: Date.current })
      # Should only include metrics from the date range
      expect(result[:totals][:sends]).to eq(metric.sends)
    end
  end

  describe "#campaign_detail" do
    it "returns detailed metrics for a campaign" do
      result = service.campaign_detail(campaign.id)
      expect(result[:campaign]).to be_present
      expect(result[:totals]).to be_present
      expect(result[:rates]).to be_present
      expect(result[:by_channel]).to be_a(Hash)
      expect(result[:time_series]).to be_an(Array)
    end

    it "raises RecordNotFound for invalid campaign" do
      expect {
        service.campaign_detail(SecureRandom.uuid)
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#channels" do
    it "returns metrics broken down by channel" do
      result = service.channels
      expect(result).to include("email")
      expect(result["email"][:totals]).to include(:sends, :deliveries)
      expect(result["email"][:rates]).to include(:open_rate, :click_rate)
    end
  end

  describe "#roi" do
    it "calculates overall ROI" do
      result = service.roi
      expect(result[:overall]).to include(:total_cost_cents, :total_revenue_cents, :roi_percentage, :net_profit_cents)
      expect(result[:overall][:roi_percentage]).to be_a(Float)
    end

    it "returns per-campaign ROI breakdown" do
      result = service.roi
      expect(result[:by_campaign]).to be_an(Array)
      campaign_roi = result[:by_campaign].find { |c| c[:campaign_id] == campaign.id }
      expect(campaign_roi).to be_present
      expect(campaign_roi[:roi_percentage]).to be_a(Float)
    end
  end

  describe "#top_performers" do
    before do
      campaign2 = create(:marketing_campaign, :active, account: account)
      create(:marketing_campaign_metric, :high_performance, campaign: campaign2, metric_date: Date.current, channel: "twitter")
    end

    it "returns top campaigns by conversions" do
      result = service.top_performers(limit: 5, metric: "conversions")
      expect(result).to be_an(Array)
      expect(result.length).to be <= 5
      expect(result.first[:metric_name]).to eq("conversions")
    end

    it "supports different metrics" do
      result = service.top_performers(metric: "revenue_cents")
      expect(result.first[:metric_name]).to eq("revenue_cents")
    end

    it "defaults to conversions for invalid metric" do
      result = service.top_performers(metric: "invalid")
      expect(result.first[:metric_name]).to eq("conversions")
    end
  end
end
