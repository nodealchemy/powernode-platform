# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Deliveries", type: :request do
  let(:user) { user_with_permissions("git.pipelines.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }

  describe "POST create" do
    it "triggers a canary delivery (records the staged plan)" do
      post "/api/v1/ai/deliveries", headers: headers, as: :json,
           params: { target_kind: "project", strategy: "canary", ref: "abc", dry_run: true }
      expect(response).to have_http_status(:created)
      data = json_response_data
      expect(data["strategy"]).to eq("canary")
      expect(data["steps"]).to be_present
    end

    it "422s a project delivery with a foreign/missing repository" do
      post "/api/v1/ai/deliveries", headers: headers, as: :json,
           params: { target_kind: "project", repository_id: SecureRandom.uuid, ref: "x" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "409s while AI is suspended (kill-switch)" do
      account.update!(ai_suspended: true)
      post "/api/v1/ai/deliveries", headers: headers, as: :json, params: { strategy: "canary", ref: "x" }
      expect(response).to have_http_status(:conflict)
    end
  end

  describe "GET index/show" do
    it "lists + shows the account's delivery runs" do
      run = account.ai_delivery_runs.create!(target_kind: "project", strategy: "canary", status: "planned")
      get "/api/v1/ai/deliveries", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["total_count"]).to eq(1)

      get "/api/v1/ai/deliveries/#{run.id}", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["id"]).to eq(run.id)
    end
  end

  it "403s without git.pipelines.manage" do
    get "/api/v1/ai/deliveries", headers: auth_headers_for(user_with_permissions), as: :json
    expect(response).to have_http_status(:forbidden)
  end
end
