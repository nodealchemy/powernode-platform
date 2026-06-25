# frozen_string_literal: true

require "rails_helper"

# cleanup_messages is a worker-internal maintenance endpoint (AiTeamMessageCleanupJob)
# that purges per-retention-policy messages for the caller's account. It must
# require WORKER auth — a regular user (even a fully-permissioned one) must not be
# able to POST it to trigger their account's message cleanup.
RSpec.describe "Api::V1::Ai::TeamRolesChannels#cleanup_messages worker gate", type: :request do
  let(:account) { create(:account) }
  let(:path) { "/api/v1/ai/teams/cleanup_messages" }

  let(:user) { create(:user, account: account, permissions: ["ai.teams.manage", "ai.teams.execute"]) }
  let(:worker) { create(:worker, account: account) }

  def worker_headers(w)
    payload = {
      sub: w.id,
      account_id: w.account_id,
      type: "worker",
      permissions: w.permission_names,
      version: Security::JwtService::CURRENT_TOKEN_VERSION
    }
    { "Authorization" => "Bearer #{Security::JwtService.encode(payload)}", "Content-Type" => "application/json" }
  end

  it "forbids a user token (even one holding ai.teams.manage + ai.teams.execute)" do
    post path, headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "allows a worker token (the scheduled cleanup job)" do
    post path, headers: worker_headers(worker), as: :json

    expect(response).not_to have_http_status(:forbidden)
  end
end
