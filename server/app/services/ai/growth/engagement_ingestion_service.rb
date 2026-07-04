# frozen_string_literal: true

module Ai
  module Growth
    # Reads a published post's current engagement (likes/reposts/replies/
    # impressions, where the provider exposes them) through the governed
    # Ai::DataSources::QueryService pipeline (kill flag, quota, cache, SSRF,
    # redaction, audit — same pipeline every other data-source read uses) and
    # records one Ai::PostEngagementSnapshot — a point in the post's engagement
    # time-series.
    #
    # The metrics endpoint is discovered off the post's own data source by an
    # opt-in metadata flag (metadata["engagement_metrics"] => true), the same
    # metadata-driven idiom captures_published_post/side_effecting already use
    # elsewhere in Ai::DataSources — so wiring a new provider's metrics
    # endpoint is a template/config change, never a change here.
    #
    # One #ingest! call = one snapshot. Cadence ("periodically thereafter") is
    # the caller's concern: .due_posts/.sweep! below expose a bounded,
    # config-driven entry point (poll interval + per-run limit resolve off
    # Account#settings, mirroring Ai::RoiMetric.calculate_for_account's
    # settings-driven baseline) for a scheduler to invoke.
    class EngagementIngestionService
      # Per-provider dig-path into the metrics endpoint's canonical record. A
      # source_type absent from this map still gets a snapshot (raw_metrics
      # only, mapped columns nil) — adding a new provider's field mapping is a
      # config addition here, not a QueryService/model change.
      FIELD_MAPS = {
        "x_com" => {
          likes_count: %w[public_metrics like_count],
          reposts_count: %w[public_metrics retweet_count],
          replies_count: %w[public_metrics reply_count],
          impressions_count: %w[public_metrics impression_count]
        }.freeze
      }.freeze

      SETTINGS_KEY = "growth_analytics"
      DEFAULT_REFRESH_INTERVAL_SECONDS = 3600 # 1 hour
      DEFAULT_SWEEP_LIMIT = 100

      def initialize(published_post)
        @post = published_post
        @data_source = published_post.data_source
      end

      # Governed-fetch the post's metrics endpoint and record one snapshot.
      # @return [Ai::PostEngagementSnapshot, nil] nil when skipped (retired /
      #   misconfigured source, no metrics endpoint configured, or the
      #   governed fetch itself failed).
      def ingest!
        return nil unless eligible_source?

        endpoint = metrics_endpoint
        return nil unless endpoint

        envelope = Ai::DataSources::QueryService.new(
          data_source: @data_source, endpoint: endpoint,
          params: { "id" => @post.external_id }
        ).call
        return nil unless envelope[:success]

        record = Array(envelope[:data]).first
        return nil unless record.is_a?(Hash)

        create_snapshot(record)
      end

      # Published posts due for a fresh engagement read: no snapshot yet, or
      # the latest one is older than the account's configured refresh
      # interval. Bounded by +limit+ so a sweep cannot fan out unbounded.
      def self.due_posts(account, limit: DEFAULT_SWEEP_LIMIT)
        cutoff = refresh_interval_seconds(account).seconds.ago
        Ai::PublishedPost.for_account(account)
                         .left_joins(:engagement_snapshots)
                         .group(:id)
                         .having(
                           "MAX(ai_post_engagement_snapshots.captured_at) IS NULL " \
                           "OR MAX(ai_post_engagement_snapshots.captured_at) < ?", cutoff
                         )
                         .limit(limit)
      end

      # Ingest every due post for an account, one snapshot each. Skips (does
      # not raise for) any post whose source is retired/misconfigured or has
      # no metrics endpoint — #ingest! already returns nil for those.
      def self.sweep!(account, limit: DEFAULT_SWEEP_LIMIT)
        due_posts(account, limit: limit).filter_map { |post| new(post).ingest! }
      end

      def self.refresh_interval_seconds(account)
        configured = account&.settings&.dig(SETTINGS_KEY, "engagement_refresh_interval_seconds")
        configured.present? ? configured.to_i : DEFAULT_REFRESH_INTERVAL_SECONDS
      end

      private

      # Excludes retired (inactive) and misconfigured (no usable credential
      # when auth is required) sources — never dispatches a governed fetch for
      # either.
      def eligible_source?
        return false unless @data_source&.is_active?
        return false if @data_source.requires_auth && @data_source.active_credential.nil?

        true
      end

      def metrics_endpoint
        @data_source.endpoints.detect { |ep| engagement_metrics_flag?(ep) }
      end

      def engagement_metrics_flag?(endpoint)
        meta = endpoint.metadata.is_a?(Hash) ? endpoint.metadata.stringify_keys : {}
        ActiveModel::Type::Boolean.new.cast(meta["engagement_metrics"])
      end

      def create_snapshot(record)
        @post.engagement_snapshots.create!(
          account_id: @post.account_id,
          captured_at: Time.current,
          raw_metrics: record,
          **extract_fields(record)
        )
      end

      def extract_fields(record)
        map = FIELD_MAPS[@data_source.source_type.to_s] || {}
        map.transform_values { |path| dig_path(record, path) }
      end

      def dig_path(record, path)
        path.reduce(record) do |node, key|
          break nil unless node.is_a?(Hash)

          node[key] || node[key.to_sym]
        end
      end
    end
  end
end
