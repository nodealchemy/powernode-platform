# frozen_string_literal: true

module Ai
  module Growth
    # Posting-time optimization (G2): recommends the best posting windows
    # (hour-of-day and day-of-week) PER PROVIDER, ranked by observed mean
    # engagement (Ai::Growth::EngagementDataset) — never a static rule, the
    # ranking is entirely data-driven off what has actually landed for this
    # account's connected providers. A window is only recommended once it has
    # a configurable minimum sample size (account.settings) — otherwise a
    # single lucky/unlucky post would look like a trend.
    class PostingTimeOptimizer
      SETTINGS_KEY = "growth_analytics"
      DEFAULT_MIN_SAMPLES_PER_WINDOW = 3
      DEFAULT_TOP_WINDOWS = 3

      def initialize(account:, time_range: 90.days)
        @account = account
        @time_range = time_range
      end

      # @return [Hash] provider => { sample_size:, recommended_hours: [...],
      #   recommended_days: [...] }, each recommendation a
      #   { window:, sample_size:, mean_engagement: } hash, highest
      #   mean_engagement first.
      def recommendations
        dataset.rows.group_by(&:provider).transform_values do |provider_rows|
          {
            sample_size: provider_rows.size,
            recommended_hours: ranked_windows(provider_rows) { |row| row.published_at.hour },
            recommended_days: ranked_windows(provider_rows) { |row| row.published_at.strftime("%A") }
          }
        end
      end

      private

      def dataset
        EngagementDataset.new(account: @account, time_range: @time_range)
      end

      def ranked_windows(rows)
        rows.group_by { |row| yield(row) }
            .filter_map { |window, group| window_stat(window, group) if group.size >= min_samples }
            .sort_by { |stat| -stat[:mean_engagement] }
            .first(top_n)
      end

      def window_stat(window, group)
        {
          window: window,
          sample_size: group.size,
          mean_engagement: (group.sum(&:engagement_score).to_f / group.size).round(2)
        }
      end

      def min_samples
        configured = @account&.settings&.dig(SETTINGS_KEY, "posting_time_min_samples")
        configured.present? ? configured.to_i : DEFAULT_MIN_SAMPLES_PER_WINDOW
      end

      def top_n
        configured = @account&.settings&.dig(SETTINGS_KEY, "posting_time_top_windows")
        configured.present? ? configured.to_i : DEFAULT_TOP_WINDOWS
      end
    end
  end
end
