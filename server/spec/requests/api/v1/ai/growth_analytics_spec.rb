# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::GrowthAnalytics", type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: [ "ai.analytics.read" ]) }
  let(:writer) { create(:user, account: account, permissions: [ "ai.analytics.read", "ai.data_sources.manage" ]) }
  let(:reader_headers) { auth_headers_for(reader) }
  let(:writer_headers) { auth_headers_for(writer) }

  describe "GET /api/v1/ai/growth/audience_insights" do
    it "returns an insights summary for a permitted user" do
      insights_service = instance_double(Ai::Growth::AudienceInsightsService, summary: { sample_size: 0 })
      allow(Ai::Growth::AudienceInsightsService).to receive(:new).and_return(insights_service)

      get "/api/v1/ai/growth/audience_insights", headers: reader_headers, as: :json

      expect_success_response
      expect(json_response_data["insights"]).to eq({ "sample_size" => 0 })
    end

    it "denies a user without ai.analytics.read" do
      no_access = create(:user, account: account, permissions: [])

      get "/api/v1/ai/growth/audience_insights", headers: auth_headers_for(no_access), as: :json

      expect_error_response("Permission denied: ai.analytics.read", 403)
    end
  end

  describe "GET /api/v1/ai/growth/posting_time_recommendations" do
    it "returns recommendations for a permitted user" do
      optimizer = instance_double(Ai::Growth::PostingTimeOptimizer, recommendations: {})
      allow(Ai::Growth::PostingTimeOptimizer).to receive(:new).and_return(optimizer)

      get "/api/v1/ai/growth/posting_time_recommendations", headers: reader_headers, as: :json

      expect_success_response
      expect(json_response_data["recommendations"]).to eq({})
    end
  end

  describe "POST /api/v1/ai/growth/cross_post" do
    it "denies a user without ai.data_sources.manage" do
      post "/api/v1/ai/growth/cross_post", params: { content: "hi", targets: [] },
                                            headers: reader_headers, as: :json

      expect_error_response("Permission denied: ai.data_sources.manage", 403)
    end

    it "dispatches the cross-post for a permitted user" do
      cross_post_service = instance_double(Ai::Growth::CrossPostService)
      allow(Ai::Growth::CrossPostService).to receive(:new).and_return(cross_post_service)
      allow(cross_post_service).to receive(:publish).and_return(
        { content: "hi", target_count: 1, published_count: 1, proposed_count: 0, failed_count: 0, results: [] }
      )

      post "/api/v1/ai/growth/cross_post",
           params: { content: "hi", targets: [ { data_source_id: "provider-a" } ] },
           headers: writer_headers, as: :json

      expect_success_response
      expect(json_response_data["published_count"]).to eq(1)
    end
  end
end
