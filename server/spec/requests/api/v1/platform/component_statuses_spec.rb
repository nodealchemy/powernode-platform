# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment A4 — the operator screen's read door.
#
# Oracles from design §8 row A4: a MEMBER can read it; the three-valued
# environment filter both ways; `not_measured` on the wire and `unknown`
# nowhere near it.
RSpec.describe "Api::V1::Platform::ComponentStatuses", type: :request do
  let(:account) { create(:account) }
  # The account's first user takes the owner role, so make one before the
  # member — otherwise the member example would be reading through an owner
  # grant and would pass with the permission removed.
  let!(:first_user) { create(:user, account: account) }
  let(:member) { create(:user, :member, account: account) }
  let(:headers) { auth_headers_for(member) }

  let(:plane_a) { account.environments.find_by!(slug: "dev") }
  let(:plane_b) { account.environments.find_by!(slug: "prod") }

  def component(*traits, **attrs)
    create(:platform_component_status, *traits, **{ account: account }.merge(attrs))
  end

  describe "authorization" do
    it "lets a MEMBER read the plane (design §6: not an admin-only page)" do
      component(component_ref: "visible")

      get "/api/v1/platform/component_statuses", headers: headers, as: :json

      expect_success_response
      expect(json_response_data["component_statuses"].map { |r| r["component_ref"] }).to include("visible")
    end

    it "refuses a user without platform.status.read with 403 and NO data" do
      component(component_ref: "secret-ish")
      stranger = create(:user, account: account, permissions: [])

      %w[index rollup].each_with_index do |_, i|
        path = i.zero? ? "/api/v1/platform/component_statuses" : "/api/v1/platform/component_statuses/rollup"
        get path, headers: auth_headers_for(stranger), as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response["success"]).to be false
        expect(json_response["data"]).to be_nil
        expect(response.body).not_to include("secret-ish")
      end
    end

    it "refuses show and impact for a user without the permission" do
      row = component
      stranger = create(:user, account: account, permissions: [])

      get "/api/v1/platform/component_statuses/#{row.id}", headers: auth_headers_for(stranger), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json_response["data"]).to be_nil

      get "/api/v1/platform/component_statuses/#{row.id}/impact", headers: auth_headers_for(stranger), as: :json
      expect(response).to have_http_status(:forbidden)
      expect(json_response["data"]).to be_nil
    end
  end

  describe "GET index" do
    it "returns this account's rows plus the shared ones and not another tenant's" do
      component(component_ref: "mine")
      create(:platform_component_status, :shared, component_ref: "shared-thing")
      create(:platform_component_status, account: create(:account), component_ref: "theirs")

      get "/api/v1/platform/component_statuses", headers: headers, as: :json

      expect_success_response
      rows = json_response_data["component_statuses"]
      expect(rows.map { |r| r["component_ref"] }).to contain_exactly("mine", "shared-thing")
      expect(rows.find { |r| r["component_ref"] == "shared-thing" }["shared"]).to be true
    end

    it "filters by kind — including and excluding arms" do
      component(component_kind: "ai_provider", component_ref: "openai")
      component(component_kind: "docker_host", component_ref: "host-1")

      get "/api/v1/platform/component_statuses?kind=ai_provider", headers: headers, as: :json

      refs = json_response_data["component_statuses"].map { |r| r["component_ref"] }
      expect(refs).to include("openai")
      expect(refs).not_to include("host-1")
    end

    it "filters by verdict — including and excluding arms" do
      component(component_ref: "broken", verdict: "down")
      component(component_ref: "fine", verdict: "ok")

      get "/api/v1/platform/component_statuses?verdict=down", headers: headers, as: :json

      refs = json_response_data["component_statuses"].map { |r| r["component_ref"] }
      expect(refs).to eq([ "broken" ])
      expect(refs).not_to include("fine")
    end

    it "refuses a verdict outside the ladder rather than ignoring the filter" do
      component(component_ref: "fine", verdict: "ok")

      get "/api/v1/platform/component_statuses?verdict=on_fire", headers: headers, as: :json

      expect(response).to have_http_status(:bad_request)
      expect(response.body).not_to include("fine")
    end

    describe "the three-valued environment filter" do
      before do
        component(component_ref: "in-a", environment: plane_a)
        component(component_ref: "in-b", environment: plane_b)
        component(component_ref: "planeless", environment: nil)
      end

      it "absent → every row" do
        get "/api/v1/platform/component_statuses", headers: headers, as: :json
        expect(json_response_data["component_statuses"].map { |r| r["component_ref"] })
          .to contain_exactly("in-a", "in-b", "planeless")
      end

      it "a plane → that plane PLUS the plane-less rows, labelled, and NEVER another plane's" do
        get "/api/v1/platform/component_statuses?environment=#{plane_a.slug}", headers: headers, as: :json

        rows = json_response_data["component_statuses"]
        expect(rows.map { |r| r["component_ref"] }).to contain_exactly("in-a", "planeless")
        expect(rows.map { |r| r["component_ref"] }).not_to include("in-b")
        expect(rows.to_h { |r| [ r["component_ref"], r["plane"] ] })
          .to eq("in-a" => "in", "planeless" => "none")
        expect(response.body).not_to include("in-b")
      end

      it "environment=none → the plane-less rows alone" do
        get "/api/v1/platform/component_statuses?environment=none", headers: headers, as: :json

        expect(json_response_data["component_statuses"].map { |r| r["component_ref"] }).to eq([ "planeless" ])
      end

      it "an unknown plane returns nothing and SAYS the plane was unknown" do
        get "/api/v1/platform/component_statuses?environment=moon", headers: headers, as: :json

        expect_success_response
        expect(json_response_data["component_statuses"]).to be_empty
        expect(json_response_data["unknown_environment"]).to be true
      end
    end

    it "paginates like its siblings" do
      3.times { |i| component(component_ref: "c#{i}") }

      get "/api/v1/platform/component_statuses?per_page=2&page=1", headers: headers, as: :json
      expect(json_response_data["component_statuses"].size).to eq(2)
      meta = json_response["meta"]["pagination"]
      expect(meta).to include("total_count" => 3, "total_pages" => 2, "current_page" => 1, "next_page" => 2)

      get "/api/v1/platform/component_statuses?per_page=2&page=2", headers: headers, as: :json
      expect(json_response_data["component_statuses"].size).to eq(1)
      expect(json_response["meta"]["pagination"]["next_page"]).to be_nil
    end
  end

  describe "the wire name for an absent measurement" do
    it "renders `not_measured` literally and never `unknown`" do
      component(component_ref: "blind", verdict: "not_measured",
                conditions: [ { "type" => "Reachable", "status" => "unknown", "reason" => "NoSnapshot",
                                "message" => "no snapshot for this account" } ])

      get "/api/v1/platform/component_statuses", headers: headers, as: :json

      row = json_response_data["component_statuses"].first
      expect(row["verdict"]).to eq("not_measured")
      # The literal, in the RENDERED body — a verdict renamed anywhere between
      # the column and the wire fails here.
      expect(response.body).to include("not_measured")
      expect(verdict_words(response.body)).not_to include("unknown")
    end

    it "keeps the ladder's other five names on the wire unchanged" do
      %w[ok held progressing degraded down].each_with_index do |verdict, i|
        component(component_ref: "v#{i}", verdict: verdict)
      end

      get "/api/v1/platform/component_statuses", headers: headers, as: :json

      expect(json_response_data["component_statuses"].map { |r| r["verdict"] })
        .to match_array(%w[ok held progressing degraded down])
    end
  end

  describe "GET show" do
    it "returns conditions, dependencies, remediation, links, actions, presentation and impact" do
      upstream = component(component_kind: "node", component_ref: "node-1", verdict: "down")
      row = component(
        component_kind: "node_instance", component_ref: "vm-1", verdict: "down",
        display_name: "vm-1",
        conditions: [ { "type" => "Reachable", "status" => false, "reason" => "HeartbeatStale",
                        "message" => "no heartbeat for 7m 12s", "severity" => "down" } ],
        dependencies: [ { "kind" => "node", "ref" => "node-1", "relation" => "hosts" } ],
        remediation: { "state" => "awaiting_operator", "signal_kind" => "fleet.instance_silent" },
        links: [ { "label" => "Open instance", "href" => "/app/compute/vm-1" } ],
        actions: [ { "key" => "cordon", "label" => "Cordon", "method" => "POST",
                     "path" => "/api/v1/system/instances/vm-1/cordon",
                     "permission" => "system.instances.manage", "destructive" => false } ],
        presentation: { "icon" => "Server", "label" => "Instances", "group_order" => 20 }
      )
      dependent = component(component_kind: "service", component_ref: "svc-1", verdict: "degraded",
                            dependencies: [ { "kind" => "node_instance", "ref" => "vm-1", "relation" => "requires" } ])

      get "/api/v1/platform/component_statuses/#{row.id}", headers: headers, as: :json

      expect_success_response
      body = json_response_data["component_status"]
      expect(body).to include("component_kind" => "node_instance", "verdict" => "down",
                              "remediation_state" => "awaiting_operator", "reason" => "HeartbeatStale")
      expect(body["conditions"].first["reason"]).to eq("HeartbeatStale")
      expect(body["dependencies"].first).to include("kind" => "node", "ref" => "node-1")
      expect(body["links"].first["label"]).to eq("Open instance")
      # The action carries its OWN permission; this door grants none of them.
      expect(body["actions"].first["permission"]).to eq("system.instances.manage")
      expect(body["presentation"]).to include("icon" => "Server", "group_order" => 20)

      impact = json_response_data["impact"]
      expect(impact["count"]).to eq(1)
      expect(impact["components"].map { |c| c["component_ref"] }).to eq([ dependent.component_ref ])
      expect(impact["worst_verdict"]).to eq("degraded")
      expect(upstream).to be_persisted
    end

    it "404s another tenant's component rather than confirming it exists" do
      foreign = create(:platform_component_status, account: create(:account))

      get "/api/v1/platform/component_statuses/#{foreign.id}", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET rollup" do
    it "returns the dual rollup, per-kind rollups and the held count" do
      component(component_kind: "node_instance", component_ref: "a", verdict: "down")
      component(:held, component_kind: "node_instance", component_ref: "b")
      component(component_kind: "ai_provider", component_ref: "c", verdict: "ok")

      get "/api/v1/platform/component_statuses/rollup", headers: headers, as: :json

      expect_success_response
      rollup = json_response_data["rollup"]
      expect(rollup["verdict"]).to eq("down")
      expect(rollup["held_count"]).to eq(1)
      expect(rollup["total"]).to eq(3)

      by_kind = json_response_data["by_kind"]
      expect(by_kind["node_instance"]["verdict"]).to eq("down")
      expect(by_kind["node_instance"]["held_count"]).to eq(1)
      expect(by_kind["ai_provider"]["verdict"]).to eq("ok")
    end

    it "a fully drained scope reads ok with the held count beside it, not amber" do
      2.times { |i| component(:held, component_ref: "held-#{i}") }

      get "/api/v1/platform/component_statuses/rollup", headers: headers, as: :json

      expect(json_response_data["rollup"]).to include("verdict" => "ok", "held_count" => 2)
    end

    it "counts a cordoned-AND-down component as held while its own verdict still says down" do
      component(:down, :held_by_intent, component_ref: "drained-and-broken")

      get "/api/v1/platform/component_statuses/rollup", headers: headers, as: :json
      expect(json_response_data["rollup"]).to include("verdict" => "ok", "held_count" => 1)

      get "/api/v1/platform/component_statuses", headers: headers, as: :json
      row = json_response_data["component_statuses"].first
      expect(row).to include("verdict" => "down", "held" => false, "held_by_intent" => true)
    end

    it "honours the environment filter, both plane arms" do
      component(component_ref: "in-a", environment: plane_a, verdict: "down")
      component(component_ref: "in-b", environment: plane_b, verdict: "ok")

      get "/api/v1/platform/component_statuses/rollup?environment=#{plane_b.slug}", headers: headers, as: :json
      expect(json_response_data["rollup"]).to include("verdict" => "ok", "total" => 1)

      get "/api/v1/platform/component_statuses/rollup?environment=#{plane_a.slug}", headers: headers, as: :json
      expect(json_response_data["rollup"]).to include("verdict" => "down", "total" => 1)
    end
  end

  describe "GET impact" do
    it "returns dependents, ranked root causes, and labels the ranking a heuristic" do
      root = component(component_kind: "node", component_ref: "node-1", verdict: "down",
                       conditions: [ { "type" => "Reachable", "status" => false, "reason" => "Unreachable",
                                       "severity" => "down", "last_transition_at" => 2.hours.ago.iso8601 } ])
      middle = component(component_kind: "node_instance", component_ref: "vm-1", verdict: "down",
                         dependencies: [ { "kind" => "node", "ref" => "node-1", "relation" => "hosts" } ],
                         conditions: [ { "type" => "Reachable", "status" => false, "reason" => "HeartbeatStale",
                                         "severity" => "down", "last_transition_at" => 10.minutes.ago.iso8601 } ])
      component(component_kind: "service", component_ref: "svc-1", verdict: "degraded",
                dependencies: [ { "kind" => "node_instance", "ref" => "vm-1", "relation" => "requires" } ])

      get "/api/v1/platform/component_statuses/#{middle.id}/impact", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data["heuristic"]).to be true
      expect(data["heuristic_basis"]).to include("upstream-most")
      expect(data["impact"]["components"].map { |c| c["component_ref"] }).to eq([ "svc-1" ])
      expect(data["root_cause_candidates"].map { |c| c["component_ref"] }).to eq([ root.component_ref ])
    end

    it "404s an id this account cannot see" do
      foreign = create(:platform_component_status, account: create(:account))

      get "/api/v1/platform/component_statuses/#{foreign.id}/impact", headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  # `unknown` is a legal CONDITION status (design §4.2), so a blanket
  # `body.exclude?("unknown")` would be a check that can fail for the wrong
  # reason. Look only at the values in verdict-shaped positions.
  def verdict_words(body)
    body.scan(/"(?:verdict|worst_verdict)"\s*:\s*"([^"]*)"/).flatten
  end
end
