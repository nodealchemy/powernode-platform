# frozen_string_literal: true

require "rails_helper"

# A8 (component status plane). The `integration_health` MCP verb buckets
# `Devops::IntegrationInstance#health_status`, whose only writer (`#update_health!`)
# had ZERO call sites: the worker sweep PATCHed a `health_metrics` jsonb blob and
# never touched the three columns, so the verb was permanently `{unknown: N}` and
# the auto-pause the schedule advertises could never fire.
#
# This is the seam that closes it: the worker asks the server to probe, and the
# SERVER owns both the probe and the persistence (the worker is HTTP-only and its
# mTLS principal cannot reach the operator-auth `/api/v1/devops/...` endpoints the
# old job called — that job logged "endpoint unreachable" and returned early on
# every sweep).
RSpec.describe "Api::V1::Internal::Devops::IntegrationHealth", type: :request do
  let(:account) { create(:account) }
  let(:template) { create(:devops_integration_template) }
  let(:instance) do
    create(:devops_integration_instance, account: account, template: template,
                                         status: "active", health_status: nil,
                                         last_health_check_at: nil, consecutive_failures: 0)
  end

  # Worker auth via InternalBaseController (mTLS CN = worker node_instance_id)
  let(:internal_worker) { create(:worker, account: account) }
  let(:internal_headers) do
    { "X-Forwarded-Tls-Client-Cert-Info" => CGI.escape(%(Subject="CN=#{internal_worker.node_instance_id}")) }
  end

  def probe!(target = instance)
    post probe_api_v1_internal_devops_integration_health_path(target), headers: internal_headers
  end

  def stub_probe(success:, message: nil)
    allow(Devops::ExecutionService).to receive(:test_connection)
      .and_return({ success: success, message: message, tested_at: Time.current })
  end

  describe "POST /api/v1/internal/devops/integration_health/:id/probe" do
    context "when the probe fails" do
      before { stub_probe(success: false, message: "connection refused") }

      it "persists the derivation onto the COLUMNS the verb reads" do
        expect { probe! }.to change { instance.reload.consecutive_failures }.from(0).to(1)

        expect(instance.health_status).to eq("degraded")
        expect(instance.last_health_check_at).to be_present
        expect(instance.last_error).to eq("connection refused")
      end

      it "does not pause on the SECOND consecutive failure" do
        instance.update!(consecutive_failures: 0)
        2.times { probe! }

        instance.reload
        expect(instance.consecutive_failures).to eq(2)
        expect(instance.status).to eq("active")
        expect(instance.health_status).to eq("degraded")
      end

      it "pauses the ROW on the third consecutive failure and marks it unhealthy" do
        3.times { probe! }

        instance.reload
        expect(instance.consecutive_failures).to eq(3)
        expect(instance.status).to eq("paused")
        expect(instance.health_status).to eq("unhealthy")
      end

      it "honours a SiteSetting threshold instead of the built-in default" do
        SiteSetting.set(Devops::IntegrationInstance::HEALTH_FAILURE_THRESHOLD_SETTING, 2,
                        setting_type: "integer")

        2.times { probe! }

        instance.reload
        expect(instance.consecutive_failures).to eq(2)
        expect(instance.status).to eq("paused")
        expect(instance.health_status).to eq("unhealthy")
      end
    end

    context "when the probe succeeds" do
      it "resets the failure streak and records healthy" do
        instance.update!(consecutive_failures: 2, health_status: "degraded", last_error: "old")
        stub_probe(success: true, message: "ok")

        probe!

        instance.reload
        expect(instance.consecutive_failures).to eq(0)
        expect(instance.health_status).to eq("healthy")
        expect(instance.last_health_check_at).to be_present
        expect(instance.last_error).to be_nil
        expect(instance.status).to eq("active")
      end
    end

    # GUARD THE DECISION, not the mechanism: a non-active integration is not a
    # thing to probe, and must never be dragged out of paused/disabled by a sweep.
    context "when the integration is not active" do
      it "skips a paused integration without writing the health columns" do
        instance.update!(status: "paused", consecutive_failures: 0, last_health_check_at: nil)
        stub_probe(success: false, message: "boom")

        probe!

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).dig("data", "applied")).to be false
        instance.reload
        expect(instance.consecutive_failures).to eq(0)
        expect(instance.last_health_check_at).to be_nil
        expect(Devops::ExecutionService).not_to have_received(:test_connection)
      end
    end

    context "tenancy" do
      let(:other_account) { create(:account) }
      let(:foreign_instance) do
        create(:devops_integration_instance, account: other_account, name: "victim-integration",
                                             status: "active", consecutive_failures: 0,
                                             last_health_check_at: nil)
      end

      it "neither mutates nor discloses another account's integration" do
        stub_probe(success: false, message: "boom")

        probe!(foreign_instance)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include("victim-integration")
        foreign_instance.reload
        expect(foreign_instance.consecutive_failures).to eq(0)
        expect(foreign_instance.last_health_check_at).to be_nil
        expect(foreign_instance.status).to eq("active")
      end
    end

    # Worker-receiver discipline: a 500 here would trigger a Sidekiq retry storm.
    it "acks with 2xx when the probe itself raises" do
      allow(Devops::ExecutionService).to receive(:test_connection).and_raise(StandardError, "executor exploded")

      probe!

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "applied")).to be false
    end

    it "rejects an unauthenticated request" do
      post probe_api_v1_internal_devops_integration_health_path(instance)

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/internal/devops/integration_health" do
    it "lists only the calling worker's ACTIVE integrations" do
      instance
      create(:devops_integration_instance, account: account, status: "paused")
      create(:devops_integration_instance, account: create(:account), status: "active", name: "foreign-active")

      get api_v1_internal_devops_integration_health_index_path, headers: internal_headers

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).dig("data", "instances").map { |i| i["id"] }
      expect(ids).to eq([ instance.id ])
      expect(response.body).not_to include("foreign-active")
    end

    it "rejects an unauthenticated request" do
      get api_v1_internal_devops_integration_health_index_path

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
