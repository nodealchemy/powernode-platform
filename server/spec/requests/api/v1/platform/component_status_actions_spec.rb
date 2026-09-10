# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A9 — the drawer's read endpoints
# (design §6, C3).
RSpec.describe "Api::V1::Platform component status drawer reads", type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: [ "platform.status.read" ]) }
  let(:stranger) { create(:user, account: account, permissions: []) }

  let(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: ::Platform::ComponentStatus::DOWN,
                                       remediation: remediation_payload)
  end

  let(:remediation_payload) do
    { "state" => "awaiting_operator", "signal_kind" => "instance.silent", "fingerprint" => "fp-1",
      "approval_request_id" => nil, "last_outcome" => nil, "stuck" => false, "runbook" => nil }
  end

  def body = JSON.parse(response.body)

  def get_drawer(path, user: reader, id: component.id)
    get "/api/v1/platform/component_statuses/#{id}/#{path}", headers: auth_headers_for(user)
  end

  # The runbook registry and the remediation registry are process-wide, so a
  # spec that registers into either must put them back.
  around do |example|
    saved_lanes = ::Platform::Remediation::Registry.lanes.dup
    saved_entries = ::Platform::Runbook::Registry.registered_entries.dup
    saved_sources = ::Platform::Runbook::Registry.registered_sources.dup
    ::Platform::Runbook::Registry.reset!
    ::Platform::Remediation::Registry.reset!
    example.run
  ensure
    ::Platform::Runbook::Registry.reset!
    ::Platform::Remediation::Registry.reset!
    saved_lanes.each { |kind, lane| ::Platform::Remediation::Registry.register_lane(kind, lane) }
    saved_entries.each { |kind, entry| ::Platform::Runbook::Registry.register(kind, entry) }
    saved_sources.each { |source| ::Platform::Runbook::Registry.register_source(source) }
  end

  shared_examples "a drawer read" do |path|
    it "401s without authentication" do
      get "/api/v1/platform/component_statuses/#{component.id}/#{path}"

      expect(response).to have_http_status(:unauthorized)
    end

    it "403s a user who does not hold platform.status.read" do
      get_drawer(path, user: stranger)

      expect(response).to have_http_status(:forbidden)
    end

    it "200s a reader who does — the other arm" do
      get_drawer(path)

      expect(response).to have_http_status(:ok)
    end

    it "404s a component belonging to another account" do
      theirs = create(:platform_component_status, account: create(:account),
                                                  component_kind: "docker_host", component_ref: "theirs")

      get_drawer(path, id: theirs.id)

      expect(response).to have_http_status(:not_found)
    end

    it "404s an id that does not exist" do
      get_drawer(path, id: SecureRandom.uuid)

      expect(response).to have_http_status(:not_found)
    end

    it "reads a SHARED component, which belongs to no tenant" do
      shared = create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                           component_ref: "breaker-1")

      get_drawer(path, id: shared.id)

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET :id/runbook" do
    it_behaves_like "a drawer read", "runbook"

    it "renders the registered runbook for the row's routed signal kind" do
      ::Platform::Runbook::Registry.register("instance.silent",
                                             "doc" => "docs/runbooks/silent-instance.md#triage")

      get_drawer("runbook")

      expect(body["data"]["signal_kind"]).to eq("instance.silent")
      expect(body["data"]["runbook"]).to include(
        "kind" => "doc", "path" => "docs/runbooks/silent-instance.md", "anchor" => "triage"
      )
    end

    # The other arm, and a distinction the drawer has to render differently:
    # a signal WAS routed and no runbook is registered for it.
    it "reports NotRegistered when the routed kind has no runbook" do
      get_drawer("runbook")

      expect(body["data"]["signal_kind"]).to eq("instance.silent")
      expect(body["data"]["runbook"]).to include("kind" => "none", "reason" => "NotRegistered")
    end

    # …and NOTHING routed the component at all, which sends an operator
    # looking for a document that was never supposed to exist if it is
    # collapsed into the case above.
    it "reports NoRoutedSignal when nothing routed the component" do
      component.update!(remediation: { "state" => "none", "signal_kind" => nil })

      get_drawer("runbook")

      expect(body["data"]["signal_kind"]).to be_nil
      expect(body["data"]["runbook"]).to include(
        "kind" => "none", "known" => false, "reason" => "NoRoutedSignal"
      )
    end
  end

  describe "GET :id/remediation_route" do
    it_behaves_like "a drawer read", "remediation_route"

    # A lane that answers is passed through in its own words — the drawer
    # renders the lane's reason, not a core paraphrase of it.
    it "reports what the routed lane says, without acting" do
      lane = Class.new do
        def self.lane_key = "test_lane"

        def describe(_component, _kind, account: nil)
          { state: ::Platform::ComponentStatus::REMEDIATION_AWAITING_OPERATOR,
            lane_key: "test_lane", policy: "approval_required", consent: "granted",
            disruption: "restart", environment_ceiling: "dev", blast_radius: 3,
            can_proceed: false, reason: "consent budget exhausted" }
        end
      end.new
      ::Platform::Remediation::Registry.register_lane("instance.silent", lane)

      get_drawer("remediation_route")

      route = body["data"]["route"]
      expect(body["data"]["routed"]).to be(true)
      expect(route["state"]).to eq(::Platform::ComponentStatus::REMEDIATION_AWAITING_OPERATOR)
      expect(route["can_proceed"]).to be(false)
      expect(route["reason"]).to eq("consent budget exhausted")
      expect(route["blast_radius"]).to eq(3)
    end

    it "reports not_actuatable when no lane owns the routed kind — the other arm" do
      get_drawer("remediation_route")

      expect(body["data"]["routed"]).to be(true)
      expect(body["data"]["route"]["state"])
        .to eq(::Platform::ComponentStatus::REMEDIATION_NOT_ACTUATABLE)
      expect(body["data"]["route"]["reason"]).to eq(::Platform::RemediationRouter::NO_LANE)
    end

    # "Nothing routed this" is not "no lane owns that kind". Routing a nil
    # through the router would answer NoLaneForSignal and send an operator
    # looking for a missing lane.
    it "says NoRoutedSignal rather than NoLaneForSignal when nothing routed it" do
      component.update!(remediation: { "state" => "none", "signal_kind" => nil })

      get_drawer("remediation_route")

      expect(body["data"]["routed"]).to be(false)
      expect(body["data"]["reason"]).to eq("NoRoutedSignal")
      expect(body["data"]).not_to have_key("route")
    end

    it "does not construct a proceed" do
      expect(::Platform::Remediation::ApprovalRequestService).not_to receive(:new)

      get_drawer("remediation_route")

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET :id/events" do
    it_behaves_like "a drawer read", "events"

    it "returns this component's history, newest first" do
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-1", occurred_at: 2.hours.ago,
                                     from_verdict: "ok", to_verdict: "degraded")
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-1", occurred_at: 5.minutes.ago,
                                     from_verdict: "degraded", to_verdict: "down")

      get_drawer("events")

      events = body["data"]["events"]
      expect(events.size).to eq(2)
      expect(events.first["to_verdict"]).to eq("down")
      expect(events.first["occurred_at"]).to be_present
    end

    it "does not return another component's events — the other arm" do
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-2")

      get_drawer("events")

      expect(body["data"]["events"]).to eq([])
    end

    # Keyed on (kind, ref), not on the row id: a component that is reaped and
    # re-created is the same thing to an operator and must keep its history.
    it "keeps history across a reap and re-create" do
      create(:platform_status_event, account: account, component_kind: "docker_host",
                                     component_ref: "host-1", component_status_id: nil)

      get_drawer("events")

      expect(body["data"]["events"].size).to eq(1)
    end

    it "paginates" do
      3.times { |n| create(:platform_status_event, account: account, component_kind: "docker_host",
                                                   component_ref: "host-1", occurred_at: n.minutes.ago) }

      get "/api/v1/platform/component_statuses/#{component.id}/events?per_page=2&page=1",
          headers: auth_headers_for(reader)

      expect(body["data"]["events"].size).to eq(2)
      expect(body["meta"]["pagination"]["total_count"]).to eq(3)
    end
  end
end
