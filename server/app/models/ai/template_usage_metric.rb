# frozen_string_literal: true

module Ai
  class TemplateUsageMetric < ApplicationRecord
    self.table_name = "ai_template_usage_metrics"

    # Associations
    belongs_to :agent_template, class_name: "Ai::AgentTemplate", foreign_key: "agent_template_id"

    # Validations
    validates :metric_date, presence: true, uniqueness: { scope: :agent_template_id }
    validates :total_installations, numericality: { greater_than_or_equal_to: 0 }
    validates :new_installations, numericality: { greater_than_or_equal_to: 0 }
    validates :total_executions, numericality: { greater_than_or_equal_to: 0 }
    validates :gross_revenue, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :for_period, ->(start_date, end_date) { where(metric_date: start_date..end_date) }
    scope :recent, ->(days = 30) { where("metric_date >= ?", days.days.ago.to_date) }
    scope :ordered, -> { order(metric_date: :desc) }

    # Class methods
    class << self
      def record_daily_metrics(template, date = Date.current)
        metric = find_or_initialize_by(
          agent_template: template,
          metric_date: date
        )

        installations = template.installations
        transactions = template.marketplace_transactions.where(
          "DATE(created_at) = ?", date
        ).where(status: "completed")

        metric.assign_attributes(
          total_installations: installations.count,
          new_installations: installations.where("DATE(created_at) = ?", date).count,
          uninstallations: installations.where("DATE(deleted_at) = ?", date).count,
          active_installations: installations.active.count,
          total_executions: calculate_executions(template, date),
          gross_revenue: transactions.sum(:gross_amount_usd),
          publisher_revenue: transactions.sum(:publisher_amount_usd),
          platform_commission: transactions.sum(:commission_amount_usd),
          average_rating: template.average_rating,
          new_reviews: template.reviews.where("DATE(created_at) = ?", date).count,
          total_reviews: template.review_count
        )

        metric.save!
        metric
      end

      def aggregate_for_template(template, days: 30)
        metrics = template.usage_metrics.recent(days)

        {
          total_installations: metrics.sum(:new_installations),
          total_uninstallations: metrics.sum(:uninstallations),
          net_installations: metrics.sum(:new_installations) - metrics.sum(:uninstallations),
          total_executions: metrics.sum(:total_executions),
          gross_revenue: metrics.sum(:gross_revenue),
          publisher_revenue: metrics.sum(:publisher_revenue),
          platform_commission: metrics.sum(:platform_commission),
          average_rating: metrics.average(:average_rating)&.round(2),
          total_reviews: template.review_count,
          page_views: metrics.sum(:page_views),
          unique_visitors: metrics.sum(:unique_visitors),
          average_conversion_rate: metrics.average(:conversion_rate)&.round(2),
          daily_metrics: metrics.ordered.limit(days).map(&:summary)
        }
      end

      def top_performing(limit: 10, period: 30)
        Ai::AgentTemplate
          .joins(:usage_metrics)
          .where("ai_template_usage_metrics.metric_date >= ?", period.days.ago.to_date)
          .group("ai_agent_templates.id")
          .select(
            "ai_agent_templates.*",
            "SUM(ai_template_usage_metrics.new_installations) as total_new_installs",
            "SUM(ai_template_usage_metrics.gross_revenue) as total_revenue"
          )
          .order("total_new_installs DESC")
          .limit(limit)
      end

      private

      def calculate_executions(template, date)
        # This would need to be connected to actual execution tracking
        # Placeholder for now
        template.installations.where(status: "active").sum(:executions_count)
      end
    end

    # Instance methods
    def summary
      {
        date: metric_date,
        installations: {
          total: total_installations,
          new: new_installations,
          uninstalls: uninstallations,
          active: active_installations
        },
        executions: total_executions,
        revenue: {
          gross: gross_revenue,
          publisher: publisher_revenue,
          commission: platform_commission
        },
        engagement: {
          page_views: page_views,
          unique_visitors: unique_visitors,
          conversion_rate: conversion_rate
        },
        ratings: {
          average: average_rating,
          new_reviews: new_reviews,
          total_reviews: total_reviews
        }
      }
    end
  end
end
