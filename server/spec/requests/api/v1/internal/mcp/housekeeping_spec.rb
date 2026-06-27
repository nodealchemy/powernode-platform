# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Internal::Mcp::Housekeeping", type: :request do
  include_context "internal api auth"

  describe "POST /api/v1/internal/mcp/housekeeping" do
    context "authenticated as the worker (mTLS)" do
      it "runs housekeeping and returns the prune summary" do
        # Seed one prunable artifact: an old, orphaned DCR app.
        app = create(:oauth_application, :mcp_client, created_at: 10.days.ago)

        post "/api/v1/internal/mcp/housekeeping", headers: service_headers

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        data = body["data"] || body
        expect(data).to include(
          "sessions_deleted", "access_tokens_deleted",
          "access_grants_deleted", "dcr_apps_deleted"
        )
        expect(data["dcr_apps_deleted"]).to be >= 1
        expect(OauthApplication.exists?(app.id)).to be false
      end
    end

    context "without worker authentication" do
      it "is rejected" do
        post "/api/v1/internal/mcp/housekeeping"
        expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
      end
    end
  end
end
