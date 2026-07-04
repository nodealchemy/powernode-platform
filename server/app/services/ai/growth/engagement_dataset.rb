# frozen_string_literal: true

module Ai
  module Growth
    # Shared data-prep for growth-analytics aggregation (G2): one row per
    # published post in a time window, carrying its LATEST engagement
    # snapshot. Using the latest snapshot (rather than every historical poll)
    # keeps each post counted once — a post polled more often by
    # EngagementIngestionService would otherwise bias any mean/sum toward
    # itself. Both Ai::Growth::AudienceInsightsService and
    # Ai::Growth::PostingTimeOptimizer group these rows differently, so the
    # extraction lives here once rather than being duplicated in each.
    class EngagementDataset
      Row = Struct.new(:post, :snapshot, keyword_init: true) do
        def provider
          post.source_type
        end

        def published_at
          post.published_at
        end

        def content
          post.content
        end

        def likes
          snapshot.likes_count || 0
        end

        def reposts
          snapshot.reposts_count || 0
        end

        def replies
          snapshot.replies_count || 0
        end

        def impressions
          snapshot.impressions_count || 0
        end

        # "Engagement" = direct audience reactions (likes/reposts/replies).
        # impressions is reach/exposure, not reaction, so it is reported
        # alongside these aggregates but never folded into the score itself —
        # otherwise a provider that simply reports larger impression counts
        # would dominate any cross-provider ranking.
        def engagement_score
          likes + reposts + replies
        end
      end

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # @return [Array<Row>] one row per published post that has AT LEAST one
      #   engagement snapshot, in the window, with its latest snapshot
      #   attached. Posts never yet polled contribute nothing (there is no
      #   engagement to aggregate) rather than a zero-filled row.
      def rows
        posts = ::Ai::PublishedPost.for_account(@account)
                                   .where(published_at: @time_range.ago..Time.current)
                                   .includes(:engagement_snapshots)

        posts.filter_map do |post|
          snapshot = post.engagement_snapshots.max_by(&:captured_at)
          next unless snapshot

          Row.new(post: post, snapshot: snapshot)
        end
      end
    end
  end
end
