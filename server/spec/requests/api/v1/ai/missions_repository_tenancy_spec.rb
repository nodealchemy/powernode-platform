# frozen_string_literal: true

require "rails_helper"

# D2 review F1 — a mission may only carry a repository its OWN account owns.
# Before this, POST/PATCH built from unscoped params, so account A could save a
# mission pointing at account B's repository; a delegated task on that mission
# then committed into B's repository with B's credential. Refused at the door
# (controller) and, independently, by the model — the refusal reads as
# not-found either way, so it does not confirm that another account's
# repository exists.
RSpec.describe "Api::V1::Ai::Missions repository tenancy", type: :request do
  let(:user) { user_with_permissions("ai.missions.read", "ai.missions.manage") }
  let(:account) { user.account }
  let(:headers) { auth_headers_for(user) }
  let(:own_repository) { create(:git_repository, account: account) }
  let(:foreign_repository) { create(:git_repository, account: create(:account)) }

  before { allow(WorkerJobService).to receive(:enqueue_job).and_return(true) }

  def create_params(repository)
    { name: "Tenancy", mission_type: "development", objective: "Build", repository_id: repository.id }
  end

  describe "POST /api/v1/ai/missions" do
    it "refuses another account's repository and creates nothing" do
      expect do
        post "/api/v1/ai/missions", headers: headers, params: create_params(foreign_repository), as: :json
      end.not_to change(Ai::Mission, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/repository not found/i)
    end

    # The door answers before the model: with otherwise-invalid params the reply
    # is ONLY the not-found, so it reveals nothing else about the request.
    it "refuses at the door, before model validation" do
      post "/api/v1/ai/missions", headers: headers,
                                  params: create_params(foreign_repository).merge(name: ""), as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("Repository not found")
    end

    it "accepts the account's own repository" do
      post "/api/v1/ai/missions", headers: headers, params: create_params(own_repository), as: :json

      expect(response).to have_http_status(:created)
      expect(Ai::Mission.find(json_response_data.dig("mission", "id")).repository_id).to eq(own_repository.id)
    end
  end

  describe "PATCH /api/v1/ai/missions/:id" do
    let!(:mission) { create(:ai_mission, account: account, created_by: user, repository: own_repository) }

    it "refuses re-pointing a mission at another account's repository" do
      patch "/api/v1/ai/missions/#{mission.id}", headers: headers,
                                                  params: { repository_id: foreign_repository.id }, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/repository not found/i)
      expect(mission.reload.repository_id).to eq(own_repository.id)
    end

    it "refuses at the door, before model validation" do
      patch "/api/v1/ai/missions/#{mission.id}", headers: headers,
                                                  params: { repository_id: foreign_repository.id, deployed_port: 1 },
                                                  as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("Repository not found")
      expect(mission.reload.repository_id).to eq(own_repository.id)
    end

    it "accepts re-pointing it at another of the account's own repositories" do
      other_own = create(:git_repository, account: account)

      patch "/api/v1/ai/missions/#{mission.id}", headers: headers, params: { repository_id: other_own.id }, as: :json

      expect(response).to have_http_status(:ok)
      expect(mission.reload.repository_id).to eq(other_own.id)
    end
  end
end
