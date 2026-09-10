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
        expect { probe! }.to change { instance.reload.probe_failure_streak }.from(0).to(1)

        expect(instance.health_status).to eq("degraded")
        expect(instance.last_health_check_at).to be_present
        expect(instance.last_error).to eq("connection refused")
      end

      # ASSERT THE BODY, not only the row. Every other example here asserts the
      # persisted row, and that is exactly how a broken response body survived
      # review: `render_success(status:)` is the HTTP-status keyword, so the
      # row's status raised, the rescue answered `applied: false`, and the
      # worker (which reads `data["applied"]`) counted every probe as skipped.
      it "answers the worker with an APPLIED result and the probe streak" do
        probe!

        data = JSON.parse(response.body)["data"]
        expect(data).to include("applied" => true, "health_status" => "degraded",
                                "consecutive_probe_failures" => 1,
                                "instance_status" => "active", "paused" => false)
        expect(data).not_to have_key("error")
      end

      it "answers paused: true on the tick that pauses the row" do
        2.times { probe! }
        probe!

        data = JSON.parse(response.body)["data"]
        expect(data).to include("applied" => true, "paused" => true,
                                "health_status" => "unhealthy", "instance_status" => "paused")
      end

      it "does not pause on the SECOND consecutive failure" do
        2.times { probe! }

        instance.reload
        expect(instance.probe_failure_streak).to eq(2)
        expect(instance.status).to eq("active")
        expect(instance.health_status).to eq("degraded")
      end

      it "pauses the ROW on the third consecutive failure and marks it unhealthy" do
        3.times { probe! }

        instance.reload
        expect(instance.probe_failure_streak).to eq(3)
        expect(instance.status).to eq("paused")
        expect(instance.health_status).to eq("unhealthy")
      end

      # Review F3: probes and executions are different questions and must not
      # share a counter. A probe streak must not touch the EXECUTION streak,
      # whose `>= 5` auto-error rung depends on it.
      it "leaves the EXECUTION failure counter alone" do
        instance.update!(consecutive_failures: 4)

        expect { 3.times { probe! } }.not_to change { instance.reload.consecutive_failures }
        expect(instance.consecutive_failures).to eq(4)
      end

      it "honours a SiteSetting threshold instead of the built-in default" do
        SiteSetting.set(Devops::IntegrationInstance::HEALTH_FAILURE_THRESHOLD_SETTING, 2,
                        setting_type: "integer")

        2.times { probe! }

        instance.reload
        expect(instance.probe_failure_streak).to eq(2)
        expect(instance.status).to eq("paused")
        expect(instance.health_status).to eq("unhealthy")
      end
    end

    context "when the probe succeeds" do
      it "resets the failure streak and records healthy" do
        instance.update!(health_metrics: { "consecutive_probe_failures" => 2 },
                         health_status: "degraded", last_error: "old")
        stub_probe(success: true, message: "ok")

        probe!

        instance.reload
        expect(instance.probe_failure_streak).to eq(0)
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
        instance.update!(status: "paused", last_health_check_at: nil)
        stub_probe(success: false, message: "boom")

        probe!

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body).dig("data", "applied")).to be false
        instance.reload
        expect(instance.probe_failure_streak).to eq(0)
        expect(instance.last_health_check_at).to be_nil
        expect(Devops::ExecutionService).not_to have_received(:test_connection)
      end
    end

    context "tenancy" do
      let(:other_account) { create(:account) }
      let(:foreign_instance) do
        create(:devops_integration_instance, account: other_account, name: "victim-integration",
                                             status: "active", last_health_check_at: nil)
      end

      # 404, not a distinguishable success: a 200 here for a foreign row and a
      # 404 for a nonexistent one would confirm the row exists on another
      # account. Enrolled in the namespace tenancy sweep too, so dropping the
      # anchor later fails a NAMED example there (review F4).
      it "neither mutates nor discloses another account's integration" do
        stub_probe(success: false, message: "boom")

        probe!(foreign_instance)

        expect(response).to have_http_status(:not_found)
        expect(response.body).not_to include("victim-integration")
        foreign_instance.reload
        expect(foreign_instance.probe_failure_streak).to eq(0)
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

    # Review F5: an offset-paginated sweep skips rows, because probing removes
    # auto-paused instances from the `active` scope and shifts every later
    # offset left. The cursor is asserted on BOTH arms: a full page hands back a
    # cursor to continue from, a short page hands back nil to stop.
    describe "cursor pagination" do
      it "returns a next_cursor on a full page and nil on the last one" do
        instances = Array.new(3) { create(:devops_integration_instance, account: account, status: "active") }
        ordered = instances.sort_by(&:id)

        get api_v1_internal_devops_integration_health_index_path(per_page: 2), headers: internal_headers
        first = JSON.parse(response.body)["data"]

        expect(first["instances"].map { |i| i["id"] }).to eq(ordered.first(2).map(&:id))
        expect(first["next_cursor"]).to eq(ordered[1].id)

        get api_v1_internal_devops_integration_health_index_path(per_page: 2, after: first["next_cursor"]),
            headers: internal_headers
        second = JSON.parse(response.body)["data"]

        expect(second["instances"].map { |i| i["id"] }).to eq([ ordered.last.id ])
        expect(second["next_cursor"]).to be_nil
      end

      it "does not skip a row when an earlier page's instance leaves the active scope" do
        instances = Array.new(3) { create(:devops_integration_instance, account: account, status: "active") }
        ordered = instances.sort_by(&:id)

        get api_v1_internal_devops_integration_health_index_path(per_page: 2), headers: internal_headers
        cursor = JSON.parse(response.body)["data"]["next_cursor"]

        # What a probe does mid-sweep: the first instance auto-pauses and drops
        # out of the scope. With offset pagination this shifts page 2 left and
        # the third row is never probed.
        ordered.first.update!(status: "paused")

        get api_v1_internal_devops_integration_health_index_path(per_page: 2, after: cursor),
            headers: internal_headers

        expect(JSON.parse(response.body)["data"]["instances"].map { |i| i["id"] }).to eq([ ordered.last.id ])
      end
    end

    it "rejects an unauthenticated request" do
      get api_v1_internal_devops_integration_health_index_path

      expect(response).to have_http_status(:unauthorized).or have_http_status(:forbidden)
    end
  end
end
