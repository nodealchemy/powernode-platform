# frozen_string_literal: true

module Ai
  module Growth
    # Audience insights (G2): aggregates observed engagement
    # (Ai::PostEngagementSnapshot, via Ai::Growth::EngagementDataset) by
    # provider, time-of-day, day-of-week, and content length — four
    # independent breakdowns over the SAME underlying rows, each answering
    # "which values of this one dimension get more engagement" without
    # cross-tabulating them (that finer per-provider x hour/day breakdown is
    # Ai::Growth::PostingTimeOptimizer's job). Read-only: no new storage, no
    # side effects — every number here is a live aggregate over G1's ingested
    # time-series.
    class AudienceInsightsService
      SETTINGS_KEY = "growth_analytics"

      # Content-length buckets, in ascending max_chars order; the last bucket
      # is a catch-all named LONG_BUCKET_NAME for anything past every
      # configured threshold. Override via
      # account.settings["growth_analytics"]["content_length_buckets"] —
      # same array-of-{name,max_chars} shape.
      DEFAULT_CONTENT_LENGTH_BUCKETS = [
        { "name" => "short", "max_chars" => 80 },
        { "name" => "medium", "max_chars" => 200 }
      ].freeze
      LONG_BUCKET_NAME = "long"

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # @return [Hash] the four breakdowns plus the overall sample size.
      def summary
        rows = dataset.rows

        {
          sample_size: rows.size,
          by_provider: aggregate_by(rows) { |row| row.provider },
          by_hour_of_day: aggregate_by(rows) { |row| row.published_at.hour },
          by_day_of_week: aggregate_by(rows) { |row| row.published_at.strftime("%A") },
          by_content_length: aggregate_by(rows) { |row| content_bucket(row.content) }
        }
      end

      private

      def dataset
        EngagementDataset.new(account: @account, time_range: @time_range)
      end

      def aggregate_by(rows)
        rows.group_by { |row| yield(row) }.transform_values { |group| aggregate(group) }
      end

      def aggregate(group)
        {
          post_count: group.size,
          total_likes: group.sum(&:likes),
          total_reposts: group.sum(&:reposts),
          total_replies: group.sum(&:replies),
          total_impressions: group.sum(&:impressions),
          avg_engagement: (group.sum(&:engagement_score).to_f / group.size).round(2)
        }
      end

      def content_bucket(content)
        length = content.to_s.length
        bucket = content_length_buckets.find { |b| length <= b["max_chars"].to_i }
        bucket ? bucket["name"] : LONG_BUCKET_NAME
      end

      def content_length_buckets
        configured = @account&.settings&.dig(SETTINGS_KEY, "content_length_buckets")
        configured.presence || DEFAULT_CONTENT_LENGTH_BUCKETS
      end
    end
  end
end
