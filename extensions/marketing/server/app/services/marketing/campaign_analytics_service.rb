# frozen_string_literal: true

module Marketing
  class CampaignAnalyticsService
    def initialize(account)
      @account = account
    end

    # Overview metrics across all campaigns
    def overview(date_range: nil)
      campaigns = @account.marketing_campaigns
      metrics = scoped_metrics(date_range)

      {
        campaigns: {
          total: campaigns.count,
          active: campaigns.active.count,
          completed: campaigns.completed.count
        },
        totals: aggregate_totals(metrics),
        rates: aggregate_rates(metrics),
        budget: {
          total_budget_cents: campaigns.sum(:budget_cents),
          total_spent_cents: campaigns.sum(:spent_cents),
          remaining_cents: campaigns.sum(:budget_cents) - campaigns.sum(:spent_cents)
        }
      }
    end

    # Detailed metrics for a single campaign
    def campaign_detail(campaign_id)
      campaign = @account.marketing_campaigns.find(campaign_id)
      metrics = campaign.campaign_metrics.order(metric_date: :asc)

      {
        campaign: campaign.campaign_summary,
        totals: aggregate_totals(metrics),
        rates: aggregate_rates(metrics),
        by_channel: channel_breakdown(metrics),
        time_series: time_series_data(metrics),
        content_performance: content_performance(campaign)
      }
    end

    # Channel-level analytics
    def channels
      metrics = all_metrics

      Marketing::CampaignContent::CHANNELS.each_with_object({}) do |channel, result|
        channel_metrics = metrics.by_channel(channel)
        next if channel_metrics.empty?

        result[channel] = {
          totals: aggregate_totals(channel_metrics),
          rates: aggregate_rates(channel_metrics),
          campaign_count: channel_metrics.select(:campaign_id).distinct.count
        }
      end
    end

    # ROI analysis
    def roi(date_range: nil)
      metrics = scoped_metrics(date_range)

      total_cost = metrics.sum(:cost_cents)
      total_revenue = metrics.sum(:revenue_cents)
      overall_roi = total_cost > 0 ? ((total_revenue - total_cost).to_f / total_cost * 100).round(2) : 0.0

      campaign_rois = @account.marketing_campaigns
                              .joins(:campaign_metrics)
                              .group("marketing_campaigns.id", "marketing_campaigns.name")
                              .select(
                                "marketing_campaigns.id",
                                "marketing_campaigns.name",
                                "SUM(marketing_campaign_metrics.cost_cents) as total_cost",
                                "SUM(marketing_campaign_metrics.revenue_cents) as total_revenue"
                              )

      {
        overall: {
          total_cost_cents: total_cost,
          total_revenue_cents: total_revenue,
          roi_percentage: overall_roi,
          net_profit_cents: total_revenue - total_cost
        },
        by_campaign: campaign_rois.map do |row|
          cost = row.total_cost.to_i
          revenue = row.total_revenue.to_i
          {
            campaign_id: row.id,
            campaign_name: row.name,
            cost_cents: cost,
            revenue_cents: revenue,
            roi_percentage: cost > 0 ? ((revenue - cost).to_f / cost * 100).round(2) : 0.0
          }
        end
      }
    end

    # Top performing campaigns
    def top_performers(limit: 10, metric: "conversions")
      valid_metrics = %w[conversions revenue_cents clicks opens engagements]
      metric = "conversions" unless valid_metrics.include?(metric)

      campaigns = @account.marketing_campaigns
                          .joins(:campaign_metrics)
                          .group("marketing_campaigns.id")
                          .select(
                            "marketing_campaigns.*",
                            "SUM(marketing_campaign_metrics.#{metric}) as total_metric"
                          )
                          .order("total_metric DESC")
                          .limit(limit)

      campaigns.map do |campaign|
        {
          campaign: campaign.campaign_summary,
          metric_name: metric,
          metric_value: campaign.total_metric.to_i
        }
      end
    end

    private

    def all_metrics
      Marketing::CampaignMetric.joins(:campaign)
                               .where(marketing_campaigns: { account_id: @account.id })
    end

    def scoped_metrics(date_range = nil)
      metrics = all_metrics
      return metrics unless date_range

      if date_range[:start_date] && date_range[:end_date]
        metrics.by_date_range(date_range[:start_date], date_range[:end_date])
      else
        metrics
      end
    end

    def aggregate_totals(metrics)
      {
        sends: metrics.sum(:sends),
        deliveries: metrics.sum(:deliveries),
        opens: metrics.sum(:opens),
        unique_opens: metrics.sum(:unique_opens),
        clicks: metrics.sum(:clicks),
        conversions: metrics.sum(:conversions),
        bounces: metrics.sum(:bounces),
        unsubscribes: metrics.sum(:unsubscribes),
        impressions: metrics.sum(:impressions),
        engagements: metrics.sum(:engagements),
        reach: metrics.sum(:reach),
        revenue_cents: metrics.sum(:revenue_cents),
        cost_cents: metrics.sum(:cost_cents)
      }
    end

    def aggregate_rates(metrics)
      totals = aggregate_totals(metrics)

      deliveries = totals[:deliveries]
      sends = totals[:sends]
      clicks = totals[:clicks]
      impressions = totals[:impressions]
      cost = totals[:cost_cents]
      revenue = totals[:revenue_cents]

      {
        open_rate: deliveries > 0 ? (totals[:unique_opens].to_f / deliveries * 100).round(2) : 0.0,
        click_rate: deliveries > 0 ? (clicks.to_f / deliveries * 100).round(2) : 0.0,
        conversion_rate: clicks > 0 ? (totals[:conversions].to_f / clicks * 100).round(2) : 0.0,
        bounce_rate: sends > 0 ? (totals[:bounces].to_f / sends * 100).round(2) : 0.0,
        unsubscribe_rate: deliveries > 0 ? (totals[:unsubscribes].to_f / deliveries * 100).round(2) : 0.0,
        engagement_rate: impressions > 0 ? (totals[:engagements].to_f / impressions * 100).round(2) : 0.0,
        roi: cost > 0 ? ((revenue - cost).to_f / cost * 100).round(2) : 0.0
      }
    end

    def channel_breakdown(metrics)
      metrics.group_by(&:channel).transform_values do |channel_metrics|
        {
          totals: aggregate_totals_from_records(channel_metrics),
          rates: aggregate_rates_from_records(channel_metrics)
        }
      end
    end

    def time_series_data(metrics)
      metrics.order(metric_date: :asc).map(&:metric_summary)
    end

    def content_performance(campaign)
      campaign.campaign_contents.map do |content|
        content.content_summary
      end
    end

    def aggregate_totals_from_records(records)
      {
        sends: records.sum(&:sends),
        deliveries: records.sum(&:deliveries),
        opens: records.sum(&:opens),
        clicks: records.sum(&:clicks),
        conversions: records.sum(&:conversions)
      }
    end

    def aggregate_rates_from_records(records)
      totals = aggregate_totals_from_records(records)
      deliveries = totals[:deliveries]
      clicks = totals[:clicks]

      {
        open_rate: deliveries > 0 ? (totals[:opens].to_f / deliveries * 100).round(2) : 0.0,
        click_rate: deliveries > 0 ? (clicks.to_f / deliveries * 100).round(2) : 0.0,
        conversion_rate: clicks > 0 ? (totals[:conversions].to_f / clicks * 100).round(2) : 0.0
      }
    end
  end
end
