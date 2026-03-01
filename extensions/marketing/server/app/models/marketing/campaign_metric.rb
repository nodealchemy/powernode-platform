# frozen_string_literal: true

module Marketing
  class CampaignMetric < ApplicationRecord
    # Associations
    belongs_to :campaign, class_name: "Marketing::Campaign", foreign_key: "campaign_id"

    # Validations
    validates :channel, presence: true
    validates :metric_date, presence: true
    validates :metric_date, uniqueness: { scope: [:campaign_id, :channel] }

    # JSON column defaults
    attribute :custom_metrics, :json, default: -> { {} }

    # Scopes
    scope :by_channel, ->(channel) { where(channel: channel) }
    scope :by_date_range, ->(start_date, end_date) { where(metric_date: start_date..end_date) }
    scope :recent, -> { order(metric_date: :desc) }

    # Derived metrics
    def open_rate
      return 0.0 if deliveries.zero?

      (unique_opens.to_f / deliveries * 100).round(2)
    end

    def click_rate
      return 0.0 if deliveries.zero?

      (clicks.to_f / deliveries * 100).round(2)
    end

    def conversion_rate
      return 0.0 if clicks.zero?

      (conversions.to_f / clicks * 100).round(2)
    end

    def bounce_rate
      return 0.0 if sends.zero?

      (bounces.to_f / sends * 100).round(2)
    end

    def unsubscribe_rate
      return 0.0 if deliveries.zero?

      (unsubscribes.to_f / deliveries * 100).round(2)
    end

    def engagement_rate
      return 0.0 if impressions.zero?

      (engagements.to_f / impressions * 100).round(2)
    end

    def roi
      return 0.0 if cost_cents.zero?

      ((revenue_cents - cost_cents).to_f / cost_cents * 100).round(2)
    end

    def metric_summary
      {
        id: id,
        channel: channel,
        metric_date: metric_date,
        sends: sends,
        deliveries: deliveries,
        opens: opens,
        unique_opens: unique_opens,
        clicks: clicks,
        conversions: conversions,
        bounces: bounces,
        unsubscribes: unsubscribes,
        impressions: impressions,
        engagements: engagements,
        reach: reach,
        revenue_cents: revenue_cents,
        cost_cents: cost_cents,
        open_rate: open_rate,
        click_rate: click_rate,
        conversion_rate: conversion_rate,
        engagement_rate: engagement_rate,
        roi: roi
      }
    end
  end
end
