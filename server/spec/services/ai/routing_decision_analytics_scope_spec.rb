# frozen_string_literal: true

require "rails_helper"

# A task assembly (request_type "task_assembly") is a record of what a run was
# assembled from, not a routing choice. ONE scope (Ai::RoutingDecision.for_analytics)
# is what every analytics reader uses, so none of them can count one.
RSpec.describe "routing analytics readers exclude task assemblies", type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ "ai.routing.read", "ai.routing.manage", "ai.routing.optimize", "ai.analytics.read" ]) }
  let!(:routed) { create(:ai_routing_decision, account: account, request_type: "completion", cached_tokens: 5) }
  let!(:assembly) { create(:ai_routing_decision, account: account, request_type: "task_assembly", cached_tokens: 700) }

  before { allow_any_instance_of(Api::V1::Ai::ModelRouterController).to receive(:log_audit_event) }

  it "has one shared scope that drops assemblies and keeps other accounts' separate" do
    other = create(:ai_routing_decision, account: create(:account), request_type: "completion")

    expect(Ai::RoutingDecision.for_analytics(account)).to contain_exactly(routed)
    expect(Ai::RoutingDecision.for_analytics(account)).not_to include(other)
  end

  it "FinOps token analytics does not count an assembly's cached tokens" do
    summary = Ai::Finops::TokenAnalyticsService.new(account: account).usage_summary

    expect(summary[:cached_tokens]).to eq(5)
  end

  it "the decisions list leaves assemblies out" do
    get "/api/v1/ai/model_router/decisions", headers: auth_headers_for(user), as: :json

    ids = JSON.parse(response.body).dig("data", "decisions").map { |d| d["id"] }
    expect(ids).to eq([ routed.id ])
  end

  it "the decision detail does not serve an assembly (it is not a routing decision)" do
    get "/api/v1/ai/model_router/decisions/#{assembly.id}", headers: auth_headers_for(user), as: :json

    expect(response).to have_http_status(:not_found)
  end

  it "every routing-analytics reader goes through the shared scope" do
    source = File.read(Rails.root.join("app/services/ai/model_router_service/routing_analytics.rb"))

    expect(source.scan("RoutingDecision.for_account(@account)")).to be_empty
    expect(source.scan("RoutingDecision.for_analytics(@account)").size).to be >= 4
  end
end
