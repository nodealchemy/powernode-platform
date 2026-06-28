# frozen_string_literal: true

require "rails_helper"

# Regression: analyze_all gated on account.feature_enabled?(:trajectory_analysis), but
# Account does not implement feature_enabled? (only Devops::Pipeline does) → NoMethodError
# → the daily trajectory cron 500s for the first account. The recommender already
# self-gates on the global trajectory_analysis flag + kill-switch, so the controller only
# needs the active?/kill-switch gate.
RSpec.describe "Api::V1::Internal::Ai::Trajectory", type: :request do
  include_context "internal api auth"

  before do
    allow_any_instance_of(Ai::Learning::ImprovementRecommender)
      .to receive(:generate_recommendations).and_return([])
  end

  it "processes active accounts without raising" do
    post "/api/v1/internal/ai/trajectory/analyze_all", headers: service_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["accounts_processed"]).to be >= 1
  end

  it "skips suspended accounts (kill-switch)" do
    internal_account.update!(ai_suspended: true)
    post "/api/v1/internal/ai/trajectory/analyze_all", headers: service_headers
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["data"]["accounts_processed"]).to eq(0)
  end
end
