# frozen_string_literal: true

FactoryBot.define do
  # Ai::PublishedPost — provenance for a post published through a connected
  # data source's write endpoint. Normally created by
  # Ai::Growth::PublishedPostRecorder off a real QueryService write; the
  # factory lets engagement-ingestion specs seed one directly.
  factory :ai_published_post, class: "Ai::PublishedPost" do
    account
    data_source { association(:ai_data_source, account: account) }
    endpoint { association(:ai_data_source_endpoint, data_source: data_source) }
    source_type { "x_com" }
    sequence(:external_id) { |n| "external-post-#{n}" }
    content { "hello world" }
    published_at { Time.current }
    metadata { {} }
  end

  # Ai::PostEngagementSnapshot — one point in a published post's engagement
  # time-series.
  factory :ai_post_engagement_snapshot, class: "Ai::PostEngagementSnapshot" do
    association :published_post, factory: :ai_published_post
    account { published_post.account }
    likes_count { 0 }
    reposts_count { 0 }
    replies_count { 0 }
    impressions_count { 0 }
    raw_metrics { {} }
    captured_at { Time.current }
  end
end
