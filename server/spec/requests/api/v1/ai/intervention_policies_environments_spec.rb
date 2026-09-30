# frozen_string_literal: true

require "rails_helper"

# conditions["environments"] through the policy API (IMP-5d3471cd75e4): a
# comma-separated string is stored as a list of slugs, an unknown slug is refused
# with the slug named, and the panel's multi-select reads the account's
# environments from GET /intervention_policies/environments.
RSpec.describe "Intervention-policy environment conditions", type: :request do
  let(:account)  { create(:account) }
  let(:operator) { user_with_permissions("ai.intervention_policies.manage", account: account) }
  let(:no_perms) { user_with_permissions(account: account) }

  def headers(user = operator)
    auth_headers_for(user).merge("Content-Type" => "application/json")
  end

  let(:body) { { scope: "global", action_category: "dev.task_requeue", policy: "block", priority: 10 } }

  describe "POST /api/v1/ai/intervention_policies" do
    it "stores a comma-separated environments string as an array" do
      post "/api/v1/ai/intervention_policies",
           params: body.merge(conditions: { environments: "staging, ops" }).to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(json_response.dig("data", "conditions", "environments")).to eq(%w[staging ops])
      row = Ai::InterventionPolicy.find_by!(account: account, action_category: "dev.task_requeue")
      expect(row.conditions["environments"]).to eq(%w[staging ops])
    end

    it "refuses an unknown slug, naming it, and writes nothing" do
      post "/api/v1/ai/intervention_policies",
           params: body.merge(conditions: { environments: "staging,qa-lab" }).to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(json_response["error"]).to include("qa-lab")
      expect(Ai::InterventionPolicy.where(account: account)).to be_empty
    end
  end

  describe "PATCH /api/v1/ai/intervention_policies/:id" do
    it "lets an unrelated update through on a row naming a since-deleted environment" do
      row = Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: "dev.task_requeue",
                                           policy: "block", priority: 10, conditions: { "environments" => %w[staging ops] })
      Ai::Environment.find_by!(account: account, slug: "ops").destroy!

      patch "/api/v1/ai/intervention_policies/#{row.id}", params: { is_active: false }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(row.reload.is_active).to be false
    end
  end

  describe "GET /api/v1/ai/intervention_policies/environments" do
    it "lists this account's environments in ladder order, and no other account's" do
      create(:ai_environment, account: create(:account), slug: "only-theirs")

      get "/api/v1/ai/intervention_policies/environments", headers: headers

      expect(response).to have_http_status(:ok)
      environments = json_response.dig("data", "environments")
      expect(environments.map { |e| e["slug"] }).to eq(%w[dev ci staging ops prod])
      expect(environments.first.keys).to match_array(%w[slug name tier])
    end

    it "is refused without the policy permission" do
      get "/api/v1/ai/intervention_policies/environments", headers: headers(no_perms)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
