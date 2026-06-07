# frozen_string_literal: true

require "rails_helper"

# Request specs for the semantic data-source discovery endpoint (Phase 2a):
#
#   POST /api/v1/ai/data_sources/discover
#
# Served by Api::V1::Ai::DataSourcesController#discover, which validates the
# query, delegates ranking to Ai::DataSources::SemanticDiscoveryService, and
# renders { query, count, results } where each result is a serialized data
# source merged with its blended :score and per-signal :signals breakdown.
#
# Authorization: requires ai.data_sources.read (validate_permissions).
#
# HERMETIC: SemanticDiscoveryService is stubbed so no embedding backend or
# pgvector query ever runs — these specs assert the controller's authorization,
# validation, and response shape against a known ranking, not the live
# embedding/blend pipeline (covered by the service unit specs).
RSpec.describe "Api::V1::Ai::DataSource Discover", type: :request do
  let(:account) { create(:account) }
  let(:reader) { user_with_permissions("ai.data_sources.read", account: account) }

  let!(:source_a) do
    create(:ai_data_source, account: account, slug: "open-meteo",
           source_type: "open_meteo", name: "Open-Meteo")
  end
  let!(:source_b) do
    create(:ai_data_source, account: account, slug: "fred",
           source_type: "fred", name: "FRED")
  end

  let(:discover_path) { "/api/v1/ai/data_sources/discover" }

  # A deterministic ranking the stubbed service hands back: source_a first
  # (higher blended score), source_b second.
  let(:ranking) do
    [
      {
        data_source: source_a,
        score: 0.91,
        signals: { semantic: 0.95, effectiveness: 0.8, health: 1.0, recency: 0.7 }
      },
      {
        data_source: source_b,
        score: 0.42,
        signals: { semantic: 0.40, effectiveness: 0.5, health: 0.0, recency: 0.5 }
      }
    ]
  end

  # Stub the discovery service instance so the controller exercises only its
  # own validation + serialization, with a known ranking.
  def stub_discovery(result)
    fake = instance_double(Ai::DataSources::SemanticDiscoveryService, discover: result)
    allow(Ai::DataSources::SemanticDiscoveryService).to receive(:new).and_return(fake)
    fake
  end

  describe "POST /discover (happy path)" do
    it "returns { query, count, results } ranked by the service" do
      stub_discovery(ranking)

      post discover_path, params: { query: "hourly precipitation forecast" },
           headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["query"]).to eq("hourly precipitation forecast")
      expect(data["count"]).to eq(2)
      expect(data["results"].length).to eq(2)
      # Order is preserved from the (pre-ranked) service output.
      expect(data["results"].map { |r| r["slug"] }).to eq(%w[open-meteo fred])
    end

    it "carries effectiveness_score, score, and the per-signal signals on each result" do
      stub_discovery(ranking)

      post discover_path, params: { query: "weather" },
           headers: auth_headers_for(reader), as: :json

      top = json_response_data["results"].first
      # effectiveness_score comes from serialize_data_source (the source's
      # rolled-up score), distinct from the blended ranking :score.
      expect(top).to include("effectiveness_score", "score", "signals")
      expect(top["score"]).to eq(0.91)
      expect(top["signals"]).to eq(
        "semantic" => 0.95, "effectiveness" => 0.8, "health" => 1.0, "recency" => 0.7
      )
      # Serialized source identity is present alongside the ranking fields.
      expect(top).to include("id" => source_a.id, "slug" => "open-meteo", "source_type" => "open_meteo")
    end

    it "passes the query, clamped limit, and cast rerank flag into the service" do
      fake = instance_double(Ai::DataSources::SemanticDiscoveryService, discover: [])
      expect(Ai::DataSources::SemanticDiscoveryService).to receive(:new).and_return(fake)
      expect(fake).to receive(:discover).with(
        query: "equity prices",
        limit: 50,        # 999 clamped down to the 50 max
        rerank: true      # "true" cast to boolean
      ).and_return([])

      post discover_path,
           params: { query: "equity prices", limit: 999, rerank: "true" },
           headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:success)
    end

    it "returns an empty result set without error when nothing matches" do
      stub_discovery([])

      post discover_path, params: { query: "no such source" },
           headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["count"]).to eq(0)
      expect(data["results"]).to eq([])
    end
  end

  describe "POST /discover (validation)" do
    it "returns 422 when query is missing" do
      # The service must never be consulted for an invalid request.
      expect(Ai::DataSources::SemanticDiscoveryService).not_to receive(:new)

      post discover_path, headers: auth_headers_for(reader), as: :json

      expect_error_response("query is required", 422)
    end

    it "returns 422 when query is blank" do
      expect(Ai::DataSources::SemanticDiscoveryService).not_to receive(:new)

      post discover_path, params: { query: "   " },
           headers: auth_headers_for(reader), as: :json

      expect_error_response("query is required", 422)
    end
  end

  describe "authorization" do
    it "forbids a user without ai.data_sources.read" do
      expect(Ai::DataSources::SemanticDiscoveryService).not_to receive(:new)

      post discover_path, params: { query: "weather" },
           headers: auth_headers_for(user_without_permissions(account: account)), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(json_response["success"]).to be false
    end

    include_examples "requires permission", :post,
                     "/api/v1/ai/data_sources/discover", "ai.data_sources.read",
                     params: { query: "weather" }

    include_examples "requires authentication", :post,
                     "/api/v1/ai/data_sources/discover",
                     params: { query: "weather" }
  end
end
