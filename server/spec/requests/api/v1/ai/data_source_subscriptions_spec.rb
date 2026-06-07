# frozen_string_literal: true

require "rails_helper"

# Request specs for the Phase 3 nested data-source SUBSCRIPTION surface, served by
# Api::V1::Ai::DataSourcesController via the Ai::DataSourceEndpoints concern:
#
#   GET    /api/v1/ai/data_sources/:data_source_id/subscriptions
#   POST   /api/v1/ai/data_sources/:data_source_id/subscriptions
#   DELETE /api/v1/ai/data_sources/:data_source_id/subscriptions/:subscription_id
#
# Permission map (validate_permissions):
#   subscriptions_index                    -> ai.data_sources.read
#   subscriptions_create / _destroy        -> ai.data_sources.stream
#
# The create body is { subscription: { endpoint_id, poll_frequency, params } };
# the cadence defaults to "hourly" and an unknown poll_frequency is a 422. The
# create is idempotent on the (source, endpoint) pair — a second POST for the same
# endpoint updates the existing subscription (200) rather than creating a new one.
#
# HERMETIC: the DataSource after_commit KG sync is stubbed so factory creates do
# not reach the embedding backend / Redis under DatabaseCleaner :deletion. No
# subscription path performs an outbound fetch (the monitor loop is server-side
# and out of scope here).
RSpec.describe "Api::V1::Ai::DataSource Subscriptions", type: :request do
  let(:account) { create(:account) }
  let(:reader)  { user_with_permissions("ai.data_sources.read", account: account) }
  let(:streamer) do
    user_with_permissions("ai.data_sources.read", "ai.data_sources.stream", account: account)
  end

  let!(:data_source) { create(:ai_data_source, account: account, slug: "open-meteo") }
  let!(:endpoint)    { create(:ai_data_source_endpoint, data_source: data_source, slug: "forecast") }
  let(:base_path)    { "/api/v1/ai/data_sources/#{data_source.id}/subscriptions" }

  before do
    allow_any_instance_of(Ai::DataSourceGraph::BridgeService).to receive(:sync_data_source)
  end

  # --------------------------------------------------------------------------
  # GET /subscriptions (index) — ai.data_sources.read
  # --------------------------------------------------------------------------
  describe "GET /subscriptions (index)" do
    let!(:subscription) do
      data_source.subscriptions.create!(
        endpoint: endpoint, poll_frequency: "hourly", status: "active"
      )
    end

    it "lists subscriptions for the source as { items, count } with the summary shape" do
      get base_path, headers: auth_headers_for(reader), as: :json

      expect_success_response
      data = json_response_data
      expect(data["count"]).to eq(1)
      sub = data["items"].first
      expect(sub["id"]).to eq(subscription.id)
      expect(sub["data_source_id"]).to eq(data_source.id)
      expect(sub["endpoint_id"]).to eq(endpoint.id)
      expect(sub["poll_frequency"]).to eq("hourly")
      expect(sub["status"]).to eq("active")
      expect(sub).to include(
        "params", "next_poll_at", "last_polled_at",
        "last_checksum", "last_etag", "consecutive_failures", "agent_id"
      )
    end

    it "returns an empty list (count 0) when the source has no subscriptions" do
      other = create(:ai_data_source, account: account, slug: "fred")

      get "/api/v1/ai/data_sources/#{other.id}/subscriptions",
          headers: auth_headers_for(reader), as: :json

      expect_success_response
      expect(json_response_data["count"]).to eq(0)
      expect(json_response_data["items"]).to eq([])
    end

    it "returns 404 for an unknown parent source" do
      get "/api/v1/ai/data_sources/#{SecureRandom.uuid}/subscriptions",
          headers: auth_headers_for(reader), as: :json

      expect_error_response("Data source not found", 404)
    end

    it "does not expose subscriptions under another account's source" do
      other = create(:ai_data_source, account: create(:account))

      get "/api/v1/ai/data_sources/#{other.id}/subscriptions",
          headers: auth_headers_for(reader), as: :json

      expect_error_response("Data source not found", 404)
    end

    it "forbids users without ai.data_sources.read" do
      get base_path, headers: auth_headers_for(user_without_permissions(account: account)), as: :json
      expect(response).to have_http_status(:forbidden)
    end

    include_examples "requires authentication", :get,
                     "/api/v1/ai/data_sources/placeholder/subscriptions"
  end

  # --------------------------------------------------------------------------
  # POST /subscriptions (create) — ai.data_sources.stream
  # --------------------------------------------------------------------------
  describe "POST /subscriptions (create)" do
    let(:valid_params) do
      { subscription: { endpoint_id: endpoint.id, poll_frequency: "5min" } }
    end

    it "creates a subscription with the stream grant and returns the summary (201)" do
      expect do
        post base_path, params: valid_params, headers: auth_headers_for(streamer), as: :json
      end.to change { data_source.subscriptions.count }.by(1)

      expect(response).to have_http_status(:created)
      sub = json_response_data["subscription"]
      expect(sub["endpoint_id"]).to eq(endpoint.id)
      expect(sub["poll_frequency"]).to eq("5min")
      expect(sub["status"]).to eq("active")
      # Non-manual cadence arms next_poll_at so the monitor picks it up.
      expect(sub["next_poll_at"]).to be_present
    end

    it "defaults the cadence to hourly when poll_frequency is omitted" do
      post base_path, params: { subscription: { endpoint_id: endpoint.id } },
           headers: auth_headers_for(streamer), as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["subscription"]["poll_frequency"]).to eq("hourly")
    end

    it "persists per-poll params from the body" do
      post base_path,
           params: { subscription: { endpoint_id: endpoint.id, poll_frequency: "hourly",
                                     params: { "latitude" => 40.7, "longitude" => -74.0 } } },
           headers: auth_headers_for(streamer), as: :json

      expect(response).to have_http_status(:created)
      expect(json_response_data["subscription"]["params"]).to eq("latitude" => 40.7, "longitude" => -74.0)
    end

    it "is idempotent on the (source, endpoint) pair — a second POST updates, not duplicates (200)" do
      post base_path, params: { subscription: { endpoint_id: endpoint.id, poll_frequency: "hourly" } },
           headers: auth_headers_for(streamer), as: :json
      expect(response).to have_http_status(:created)
      created_id = json_response_data["subscription"]["id"]

      expect do
        post base_path, params: { subscription: { endpoint_id: endpoint.id, poll_frequency: "daily" } },
             headers: auth_headers_for(streamer), as: :json
      end.not_to change { data_source.subscriptions.count }

      expect(response).to have_http_status(:ok)
      sub = json_response_data["subscription"]
      expect(sub["id"]).to eq(created_id)
      expect(sub["poll_frequency"]).to eq("daily")
    end

    it "returns 422 for an invalid poll_frequency" do
      post base_path,
           params: { subscription: { endpoint_id: endpoint.id, poll_frequency: "every_blue_moon" } },
           headers: auth_headers_for(streamer), as: :json

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
      expect(json_response["success"]).to be false
      expect(json_response["error"]).to match(/poll_frequency/i)
      expect(data_source.subscriptions.count).to eq(0)
    end

    it "returns 404 when the endpoint is not found under the source" do
      post base_path, params: { subscription: { endpoint_id: SecureRandom.uuid, poll_frequency: "hourly" } },
           headers: auth_headers_for(streamer), as: :json

      expect_error_response("Endpoint not found", 404)
    end

    it "forbids a read-only user (no stream grant) from creating" do
      post base_path, params: valid_params, headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(data_source.subscriptions.count).to eq(0)
    end

    include_examples "requires authentication", :post,
                     "/api/v1/ai/data_sources/placeholder/subscriptions"
  end

  # --------------------------------------------------------------------------
  # DELETE /subscriptions/:subscription_id (destroy) — ai.data_sources.stream
  # --------------------------------------------------------------------------
  describe "DELETE /subscriptions/:subscription_id (destroy)" do
    let!(:subscription) do
      data_source.subscriptions.create!(endpoint: endpoint, poll_frequency: "hourly", status: "active")
    end
    let(:member_path) { "#{base_path}/#{subscription.id}" }

    it "cancels (deletes) a subscription with the stream grant" do
      expect do
        delete member_path, headers: auth_headers_for(streamer), as: :json
      end.to change { data_source.subscriptions.count }.by(-1)

      expect_success_response
      expect(json_response_data["message"]).to match(/cancelled/i)
    end

    it "returns 404 for an unknown subscription under the source" do
      delete "#{base_path}/#{SecureRandom.uuid}", headers: auth_headers_for(streamer), as: :json

      expect_error_response("Subscription not found", 404)
    end

    it "forbids a read-only user (no stream grant) from cancelling" do
      delete member_path, headers: auth_headers_for(reader), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(Ai::DataSourceSubscription.exists?(subscription.id)).to be true
    end

    include_examples "requires authentication", :delete,
                     "/api/v1/ai/data_sources/placeholder/subscriptions/placeholder"
  end
end
