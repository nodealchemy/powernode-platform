# frozen_string_literal: true

require "rails_helper"

# IMP-e041c835a40d — the worker→server surface of the OODA closure driver.
# The accounts endpoint is where "off" is decided (empty list while the
# cadence flag is at its OFF default), so the worker cron can tick blindly.
RSpec.describe "Api::V1::Internal::Ai::Autonomy closure driver", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account, is_active: true) }

  def agent_with_active_goal
    agent = create(:ai_agent, account: account, provider: provider, creator: user,
                   status: "active", name: "closure-#{SecureRandom.hex(3)}")
    Ai::AgentGoal.create!(account: account, agent: agent, title: "drive me",
                          goal_type: "maintenance", status: "active", priority: 3)
    agent
  end

  describe "GET /api/v1/internal/ai/closure_driver/accounts" do
    it "returns [] while the driver is disabled (the OFF default)" do
      agent_with_active_goal

      get "/api/v1/internal/ai/closure_driver/accounts", headers: worker_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]).to eq([])
    end

    it "returns accounts with active goals once enabled" do
      agent_with_active_goal
      SiteSetting.set(Ai::Autonomy::ClosureDriverService::ENABLED_SETTING, "true")

      get "/api/v1/internal/ai/closure_driver/accounts", headers: worker_headers

      expect(JSON.parse(response.body)["data"]).to eq([ account.id ])
    end
  end

  describe "POST /api/v1/internal/ai/closure_driver/run" do
    it "invokes the driver service for the account and reports its result" do
      driver = instance_double(Ai::Autonomy::ClosureDriverService,
                               run: { enabled: true, cycles_run: 2, cycles_failed: 0, skipped_over_budget: 0 })
      allow(Ai::Autonomy::ClosureDriverService).to receive(:new)
        .with(account: account).and_return(driver)

      post "/api/v1/internal/ai/closure_driver/run",
           params: { account_id: account.id }.to_json,
           headers: worker_headers.merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "cycles_run")).to eq(2)
    end
  end
end
