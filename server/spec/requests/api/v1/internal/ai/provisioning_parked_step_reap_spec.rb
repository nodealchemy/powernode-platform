# frozen_string_literal: true

require "rails_helper"

# IMP-842b56d3a5d4 — the worker→server door onto the parked-step janitor.
#
# The reaper itself is covered by
# spec/services/ai/provisioning/skill_composition_runner_parked_reaper_spec.rb;
# what matters here is that the sweep is REACHABLE from a cron. A reaper with
# no caller is inert, and an inert janitor is indistinguishable from a clean
# fleet — which is exactly how SystemTaskReaperJob spent five weeks reporting
# "0, 0" while a backlog grew.
RSpec.describe "Api::V1::Internal::Ai::Autonomy parked-step reap", type: :request do
  let(:account)       { create(:account) }
  let(:system_worker) { create(:worker, :system_worker, account: account) }
  let(:worker_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{system_worker.node_instance_id}")) }
  end

  describe "POST /api/v1/internal/ai/provisioning/parked_steps/reap" do
    it "answers with the sweep's counts when nothing is stranded" do
      post "/api/v1/internal/ai/provisioning/parked_steps/reap", headers: worker_headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["examined"]).to eq(0)
      expect(data["resumed"]).to eq(0)
    end

    it "delegates to the runner's reaper" do
      allow(Ai::Provisioning::SkillCompositionRunner)
        .to receive(:reap_parked_steps).and_return(examined: 3, resumed: 2)

      post "/api/v1/internal/ai/provisioning/parked_steps/reap", headers: worker_headers

      expect(Ai::Provisioning::SkillCompositionRunner).to have_received(:reap_parked_steps)
      expect(JSON.parse(response.body)["data"]["resumed"]).to eq(2)
    end
  end
end
