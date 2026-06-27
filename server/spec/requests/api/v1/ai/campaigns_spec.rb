# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Ai::Campaigns", type: :request do
  let(:user) { user_with_permissions("ai.campaigns.read", "ai.campaigns.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }

  def start_campaign(name: "X")
    ::Ai::DevLoop::CampaignDriver.new(account: account, user: user).start(name: name)[:campaign]
  end

  describe "POST /api/v1/ai/campaigns" do
    it "starts a campaign with its dedicated dev-loop" do
      post "/api/v1/ai/campaigns", headers: headers,
           params: { name: "Audit billing", decision_authority: "trusted" }, as: :json
      expect_success_response
      data = json_response_data
      expect(data["name"]).to eq("Audit billing")
      expect(data["status"]).to eq("active")
      expect(data["loops"].first["branch"]).to start_with("campaign/")
    end
  end

  describe "GET /api/v1/ai/campaigns" do
    it "lists the account's campaigns and filters by status" do
      start_campaign(name: "A")
      get "/api/v1/ai/campaigns", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["campaigns"].length).to eq(1)

      get "/api/v1/ai/campaigns?status=completed", headers: headers, as: :json
      expect_success_response
      expect(json_response_data["campaigns"]).to be_empty
    end
  end

  describe "GET /api/v1/ai/campaigns/:id" do
    it "returns detail with open questions, decisions, and loops" do
      campaign = start_campaign
      campaign.park_question!(question: "Free-tier pricing policy?")
      campaign.record_decision!(decision_type: "remove", title: "drop dead code")

      get "/api/v1/ai/campaigns/#{campaign.id}", headers: headers, as: :json
      expect_success_response
      data = json_response_data
      expect(data["open_questions"].length).to eq(1)
      expect(data["recent_decisions"].length).to eq(1)
      expect(data["loops"].length).to eq(1)
    end
  end

  describe "answering a question + stopping" do
    it "answers a parked question then stops the campaign" do
      campaign = start_campaign
      question = campaign.park_question!(question: "Stripe or PayPal?")

      post "/api/v1/ai/campaigns/#{campaign.id}/answer_question", headers: headers,
           params: { question_id: question.id, answer: "Stripe Connect" }, as: :json
      expect_success_response
      expect(question.reload.status).to eq("answered")

      post "/api/v1/ai/campaigns/#{campaign.id}/stop", headers: headers,
           params: { summary: "shipped" }, as: :json
      expect_success_response
      expect(campaign.reload.status).to eq("completed")
    end
  end

  describe "authorization" do
    it "forbids a user lacking ai.campaigns.read" do
      other = user_with_permissions("ai.goals.manage")
      get "/api/v1/ai/campaigns", headers: auth_headers_for(other), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
