# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Marketing::Public::LeadsController", type: :request do
  describe "POST /api/v1/marketing/public/leads/waitlist" do
    let(:endpoint) { "/api/v1/marketing/public/leads/waitlist" }

    it "creates a new waitlist signup with valid email" do
      expect {
        post endpoint, params: { email: "new@example.com", source: "homepage" }, as: :json
      }.to change(Marketing::WaitlistSignup, :count).by(1)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).fetch("data")
      expect(data).to include("email" => "new@example.com", "status" => "pending")
      expect(data["id"]).to be_present
    end

    it "is idempotent — duplicate email returns success without creating a new row" do
      create(:marketing_waitlist_signup, email: "dup@example.com")

      expect {
        post endpoint, params: { email: "dup@example.com" }, as: :json
      }.not_to change(Marketing::WaitlistSignup, :count)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body).fetch("data")
      expect(data["already_subscribed"]).to be true
    end

    it "rejects invalid email format" do
      post endpoint, params: { email: "not-an-email" }, as: :json
      expect(response.status).to eq(422)
    end

    it "rejects missing email" do
      post endpoint, params: {}, as: :json
      expect(response.status).to eq(422)
    end

    it "downcases email on save" do
      post endpoint, params: { email: "MIXED@Example.COM" }, as: :json
      expect(response).to have_http_status(:ok)
      expect(Marketing::WaitlistSignup.last.email).to eq("mixed@example.com")
    end

    it "captures UTM parameters in metadata JSONB" do
      post endpoint, params: {
        email: "utm@example.com",
        utm_source: "twitter",
        utm_medium: "social",
        utm_campaign: "launch-2026"
      }, as: :json

      expect(response).to have_http_status(:ok)
      signup = Marketing::WaitlistSignup.find_by(email: "utm@example.com")
      expect(signup.metadata).to include(
        "utm_source"   => "twitter",
        "utm_medium"   => "social",
        "utm_campaign" => "launch-2026"
      )
    end

    it "is publicly accessible without authentication" do
      # No auth headers — should still succeed (skip_before_action :authenticate_request)
      post endpoint, params: { email: "anon@example.com" }, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
