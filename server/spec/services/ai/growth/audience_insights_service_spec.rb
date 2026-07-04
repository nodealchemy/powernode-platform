# frozen_string_literal: true

require "rails_helper"

# Growth analytics (G2): AudienceInsightsService aggregates observed
# engagement by provider / time-of-day / day-of-week / content length over
# G1's ingested Ai::PostEngagementSnapshot time-series. Fixture-driven — no
# HTTP, no QueryService — this is a pure read aggregation.
RSpec.describe Ai::Growth::AudienceInsightsService, type: :service do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def post_with_snapshot(account:, source_type:, published_at:, content:, likes: 0, reposts: 0, replies: 0, impressions: 0, captured_at: nil)
    post = create(:ai_published_post, account: account, source_type: source_type,
                   published_at: published_at, content: content)
    create(:ai_post_engagement_snapshot, published_post: post, account: account,
           likes_count: likes, reposts_count: reposts, replies_count: replies,
           impressions_count: impressions, captured_at: captured_at || published_at + 1.hour)
    post
  end

  describe "#summary" do
    it "aggregates by provider, using each post's LATEST snapshot only" do
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago,
                          content: "hello", likes: 10, reposts: 2, replies: 1, impressions: 100)
      double_polled = post_with_snapshot(account: account, source_type: "mastodon", published_at: 1.day.ago,
                                          content: "world", likes: 1, reposts: 0, replies: 0, impressions: 5,
                                          captured_at: 2.days.ago)
      # A SECOND, more recent snapshot for the same post — only this one
      # should count toward the aggregate, not both.
      create(:ai_post_engagement_snapshot, published_post: double_polled, account: account,
             likes_count: 50, reposts_count: 5, replies_count: 5, impressions_count: 500,
             captured_at: 1.hour.ago)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:sample_size]).to eq(2)
      expect(result[:by_provider]["x_com"]).to include(
        post_count: 1, total_likes: 10, total_reposts: 2, total_replies: 1, avg_engagement: 13.0
      )
      # mastodon's post must reflect the LATEST snapshot (50/5/5), not the
      # earlier one (1/0/0).
      expect(result[:by_provider]["mastodon"]).to include(
        post_count: 1, total_likes: 50, total_reposts: 5, total_replies: 5, avg_engagement: 60.0
      )
    end

    it "aggregates by hour-of-day and day-of-week off published_at" do
      morning = Time.zone.parse("2026-06-01 09:00:00") # Monday
      evening = Time.zone.parse("2026-06-02 21:00:00") # Tuesday
      post_with_snapshot(account: account, source_type: "x_com", published_at: morning, content: "a", likes: 5)
      post_with_snapshot(account: account, source_type: "x_com", published_at: evening, content: "b", likes: 15)

      result = described_class.new(account: account, time_range: 365.days).summary

      expect(result[:by_hour_of_day][9][:total_likes]).to eq(5)
      expect(result[:by_hour_of_day][21][:total_likes]).to eq(15)
      expect(result[:by_day_of_week]["Monday"][:total_likes]).to eq(5)
      expect(result[:by_day_of_week]["Tuesday"][:total_likes]).to eq(15)
    end

    it "buckets by content length using the default thresholds" do
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago, content: "x" * 10, likes: 1)
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago, content: "x" * 150, likes: 1)
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago, content: "x" * 300, likes: 1)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:by_content_length]["short"][:post_count]).to eq(1)
      expect(result[:by_content_length]["medium"][:post_count]).to eq(1)
      expect(result[:by_content_length]["long"][:post_count]).to eq(1)
    end

    it "respects an account-configured content_length_buckets override" do
      account.update!(settings: { "growth_analytics" => { "content_length_buckets" => [ { "name" => "tiny", "max_chars" => 5 } ] } })
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago, content: "hi", likes: 1)
      post_with_snapshot(account: account, source_type: "x_com", published_at: 1.day.ago, content: "x" * 50, likes: 1)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:by_content_length]["tiny"][:post_count]).to eq(1)
      expect(result[:by_content_length]["long"][:post_count]).to eq(1)
    end

    it "excludes posts with no engagement snapshot yet" do
      create(:ai_published_post, account: account, source_type: "x_com", published_at: 1.day.ago)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:sample_size]).to eq(0)
      expect(result[:by_provider]).to eq({})
    end

    it "is account-scoped" do
      post_with_snapshot(account: other_account, source_type: "x_com", published_at: 1.day.ago, content: "not mine", likes: 99)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:sample_size]).to eq(0)
    end

    it "excludes posts published outside the time range" do
      post_with_snapshot(account: account, source_type: "x_com", published_at: 60.days.ago, content: "old", likes: 99)

      result = described_class.new(account: account, time_range: 30.days).summary

      expect(result[:sample_size]).to eq(0)
    end
  end
end
