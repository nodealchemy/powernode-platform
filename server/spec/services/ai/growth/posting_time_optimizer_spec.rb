# frozen_string_literal: true

require "rails_helper"

# Growth analytics (G2): PostingTimeOptimizer recommends the best posting
# windows (hour-of-day / day-of-week) PER PROVIDER, ranked by observed mean
# engagement, gated by a configurable minimum sample size per window.
# Fixture-driven — no HTTP, no QueryService.
RSpec.describe Ai::Growth::PostingTimeOptimizer, type: :service do
  let(:account) { create(:account) }

  def post_at(hour:, wday_date:, likes:)
    published_at = Time.zone.parse(wday_date).change(hour: hour)
    post = create(:ai_published_post, account: account, source_type: "x_com", published_at: published_at)
    create(:ai_post_engagement_snapshot, published_post: post, account: account,
           likes_count: likes, reposts_count: 0, replies_count: 0, captured_at: published_at + 1.hour)
    post
  end

  describe "#recommendations" do
    it "ranks hour-of-day windows by mean engagement, highest first, above the min-sample bar" do
      # Hour 9: 3 posts (meets default min sample of 3), mean engagement 10.
      3.times { |n| post_at(hour: 9, wday_date: "2026-06-0#{n + 1}", likes: 10) }
      # Hour 21: 3 posts, mean engagement 20 — should rank above hour 9.
      3.times { |n| post_at(hour: 21, wday_date: "2026-06-0#{n + 4}", likes: 20) }
      # Hour 3: only 1 post — below the default min-sample bar of 3, excluded entirely.
      post_at(hour: 3, wday_date: "2026-06-07", likes: 999)

      result = described_class.new(account: account, time_range: 365.days).recommendations
      hours = result["x_com"][:recommended_hours]

      expect(hours.map { |h| h[:window] }).to eq([ 21, 9 ])
      expect(hours.first).to include(window: 21, sample_size: 3, mean_engagement: 20.0)
      expect(hours.map { |h| h[:window] }).not_to include(3)
    end

    it "ranks day-of-week windows the same way" do
      3.times { post_at(hour: 10, wday_date: "2026-06-01", likes: 5) }  # Monday
      3.times { post_at(hour: 10, wday_date: "2026-06-02", likes: 50) } # Tuesday

      result = described_class.new(account: account, time_range: 365.days).recommendations
      days = result["x_com"][:recommended_days]

      expect(days.first[:window]).to eq("Tuesday")
      expect(days.first[:mean_engagement]).to eq(50.0)
    end

    it "groups independently per provider" do
      3.times { |n| post_at(hour: 9, wday_date: "2026-06-0#{n + 1}", likes: 10) }
      3.times do |n|
        published_at = Time.zone.parse("2026-06-0#{n + 4}").change(hour: 14)
        post = create(:ai_published_post, account: account, source_type: "mastodon", published_at: published_at)
        create(:ai_post_engagement_snapshot, published_post: post, account: account, likes_count: 30,
               captured_at: published_at + 1.hour)
      end

      result = described_class.new(account: account, time_range: 365.days).recommendations

      expect(result.keys).to contain_exactly("x_com", "mastodon")
      expect(result["x_com"][:sample_size]).to eq(3)
      expect(result["mastodon"][:sample_size]).to eq(3)
    end

    it "respects account-configured min sample size and top-window count" do
      account.update!(settings: { "growth_analytics" => { "posting_time_min_samples" => 1, "posting_time_top_windows" => 1 } })
      post_at(hour: 3, wday_date: "2026-06-07", likes: 999)
      3.times { |n| post_at(hour: 9, wday_date: "2026-06-0#{n + 1}", likes: 10) }

      result = described_class.new(account: account, time_range: 365.days).recommendations
      hours = result["x_com"][:recommended_hours]

      expect(hours.size).to eq(1)
      expect(hours.first[:window]).to eq(3) # sample_size 1 now clears the bar, and wins on mean_engagement
    end

    it "returns no windows when nothing meets the minimum sample size" do
      post_at(hour: 9, wday_date: "2026-06-01", likes: 10)

      result = described_class.new(account: account, time_range: 365.days).recommendations

      expect(result["x_com"][:recommended_hours]).to eq([])
      expect(result["x_com"][:recommended_days]).to eq([])
    end
  end
end
