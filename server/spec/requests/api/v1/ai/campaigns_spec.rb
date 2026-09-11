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
      expect(data["open_questions"]).to eq(1)
      expect(data["open_questions_list"].length).to eq(1)
      expect(data["recent_decisions"].length).to eq(1)
      expect(data["loops"].length).to eq(1)
      # Observability: detail surfaces the unified activity feed + heartbeat.
      expect(data).to have_key("activity")
      expect(data["activity"]).to be_an(Array).and(be_present)
      expect(data).to have_key("last_activity_at")
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

  describe "delegating the driver" do
    it "routes the campaign loop to claude_code and takes the lease" do
      campaign = start_campaign

      post "/api/v1/ai/campaigns/#{campaign.id}/delegate", headers: headers,
           params: { driver_kind: "claude_code", holder: "cc-sess" }, as: :json
      expect_success_response
      data = json_response_data
      expect(data["driver_kind"]).to eq("claude_code")
      expect(data["lease"]["holder"]).to eq("cc-sess")
      expect(campaign.ralph_loops.first.reload.driver_kind).to eq("claude_code")
    end

    it "422s an unknown driver_kind" do
      campaign = start_campaign
      post "/api/v1/ai/campaigns/#{campaign.id}/delegate", headers: headers,
           params: { driver_kind: "telepathy" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "authorization" do
    it "forbids a user lacking ai.campaigns.read" do
      other = user_with_permissions("ai.goals.manage")
      get "/api/v1/ai/campaigns", headers: auth_headers_for(other), as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  # The human door onto CampaignDriver#resume — the same service the MCP verb calls.
  describe "POST /api/v1/ai/campaigns/:id/resume" do
    let(:driver) { ::Ai::DevLoop::CampaignDriver.new(account: account, user: user) }

    # Auto-completed through the real path: two failed increments against max_failed 2.
    def auto_completed_campaign
      campaign = driver.start(name: "Resumable", stop_conditions: { max_failed: 2 })[:campaign]
      2.times { |i| driver.record_increment!(campaign, title: "broken #{i}", status: "failed") }
      expect(campaign.reload.status).to eq("completed") # precondition
      campaign
    end

    def resume(campaign, params, as_headers: headers)
      post "/api/v1/ai/campaigns/#{campaign.id}/resume", headers: as_headers, params: params, as: :json
    end

    def resume_decisions(campaign)
      campaign.campaign_decisions.where("metadata->>'action' = ?", "campaign_resume")
    end

    it "lets a permitted user resume and raise max_failed, recording them as the actor" do
      campaign = auto_completed_campaign

      resume(campaign, { reason: "two flaky failures; raise the cap", stop_conditions: { max_failed: 6 } })
      expect_success_response
      expect(json_response_data["campaign"]["status"]).to eq("active")
      expect(campaign.reload.status).to eq("active")
      expect(campaign.stop_conditions).to eq("min_acceptance_pct" => 50, "max_failed" => 6)

      decision = resume_decisions(campaign).sole
      expect(decision.user_id).to eq(user.id)
      expect(decision.rationale).to eq("two flaky failures; raise the cap")
      expect(decision.metadata).to include(
        "principal" => "user",
        "old_stop_conditions" => { "min_acceptance_pct" => 50, "max_failed" => 2 },
        "new_stop_conditions" => { "min_acceptance_pct" => 50, "max_failed" => 6 }
      )
    end

    it "403s a user without ai.campaigns.manage and changes nothing" do
      campaign = auto_completed_campaign
      reader = create(:user, account: account, permissions: %w[ai.campaigns.read])

      resume(campaign, { reason: "x", stop_conditions: { max_failed: 6 } }, as_headers: auth_headers_for(reader))
      expect(response).to have_http_status(:forbidden)
      expect(campaign.reload.status).to eq("completed")
      expect(resume_decisions(campaign)).to be_empty
    end

    it "422s a missing reason, a non-object, or a null or invalid stop value by name, changing nothing" do
      campaign = auto_completed_campaign

      resume(campaign, { stop_conditions: { max_failed: 6 } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("reason is required")

      resume(campaign, { reason: "probe", stop_conditions: "lots" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("stop_conditions must be an object")

      [{ max_failed: nil }, { max_failed: "6" }, { max_failed: 9, min_acceptance_pct: nil }, { max_failed: 0 }]
        .each do |conditions|
          resume(campaign, { reason: "probe", stop_conditions: conditions })
          expect(response).to have_http_status(:unprocessable_content), "#{conditions.inspect} -> #{response.status}"
          expect(json_response["error"]).to include("invalid stop condition")
        end

      expect(campaign.reload.status).to eq("completed")
      expect(campaign.stop_conditions).to eq("min_acceptance_pct" => 50, "max_failed" => 2)
      expect(resume_decisions(campaign)).to be_empty
    end

    it "422s an archived and an already-active campaign by name" do
      archived = create(:ai_campaign, account: account, status: "archived")
      resume(archived, { reason: "bring it back" })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("is archived")

      active = start_campaign(name: "Running")
      resume(active, { reason: "x", stop_conditions: { max_failed: 9 } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("is already active")
      expect(active.reload.stop_conditions).not_to include("max_failed" => 9)
    end

    it "refuses while the campaign's driver holds its lease, and goes through once it is released" do
      campaign = auto_completed_campaign
      driver.claim(campaign, holder: "driver-loop-1")

      resume(campaign, { reason: "self re-arm", stop_conditions: { max_failed: 50 } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("held by driver 'driver-loop-1'")
      expect(campaign.reload.status).to eq("completed")

      driver.release(campaign, holder: "driver-loop-1")
      resume(campaign, { reason: "operator, after the driver let go", stop_conditions: { max_failed: 50 } })
      expect_success_response
      expect(campaign.reload.status).to eq("active")
    end

    it "refuses the claim holder itself — a user whose own id holds the lease" do
      campaign = auto_completed_campaign
      driver.claim(campaign) # holder defaults to the user's id

      resume(campaign, { reason: "my own claim", stop_conditions: { max_failed: 50 } })
      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("held by driver '#{user.id}'")
      expect(campaign.reload.status).to eq("completed")
    end

    it "403s a worker token, even one whose worker holds ai.campaigns.manage" do
      campaign = auto_completed_campaign
      worker = create(:worker, account: account)
      allow_any_instance_of(Worker).to receive(:has_permission?).and_return(true)
      token = Security::JwtService.encode({ type: "worker", sub: worker.id }, 5.minutes.from_now)

      resume(campaign, { reason: "x", stop_conditions: { max_failed: 6 } },
             as_headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" })
      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("a user's own session")
      expect(campaign.reload.status).to eq("completed")
    end

    it "403s an impersonation session, whose actor is not the user it names" do
      campaign = auto_completed_campaign
      admin = create(:user, :admin, account: account)
      session = ImpersonationSession.create_session!(impersonator: admin, impersonated_user: user)
      payload = { type: "impersonation", session_id: session.id, sub: user.id, account_id: user.account_id,
                  version: Security::JwtService::CURRENT_TOKEN_VERSION }

      resume(campaign, { reason: "x", stop_conditions: { max_failed: 6 } },
             as_headers: { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}",
                           "Content-Type" => "application/json" })
      expect(response).to have_http_status(:forbidden)
      expect(json_response["error"]).to include("a user's own session")
      expect(campaign.reload.status).to eq("completed")
      expect(resume_decisions(campaign)).to be_empty
    end

    it "409s while the account's AI is suspended" do
      campaign = auto_completed_campaign
      account.update!(ai_suspended: true)

      resume(campaign, { reason: "x", stop_conditions: { max_failed: 6 } })
      expect(response).to have_http_status(:conflict)
      expect(campaign.reload.status).to eq("completed")
    end
  end
end
