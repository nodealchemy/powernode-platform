# frozen_string_literal: true

require "rails_helper"

# Component status plane, increment A9 — the drawer's investigation surface
# (design §5.3 and §6).
RSpec.describe "Api::V1::Platform component status investigations", type: :request do
  let(:account) { create(:account) }
  let(:reader) { create(:user, account: account, permissions: [ "platform.status.read" ]) }
  let(:operator) do
    create(:user, account: account, permissions: [ "platform.status.read", "ai.autonomy.manage" ])
  end
  let(:stranger) { create(:user, account: account, permissions: []) }

  let(:component) do
    create(:platform_component_status, account: account, component_kind: "docker_host",
                                       component_ref: "host-1", display_name: "web-1",
                                       verdict: ::Platform::ComponentStatus::DOWN,
                                       conditions: [ { "type" => "Connected", "status" => false,
                                                       "reason" => "ConnectionError",
                                                       "severity" => "down" } ])
  end

  def path(id = component.id) = "/api/v1/platform/component_statuses/#{id}/investigations"
  def body = JSON.parse(response.body)

  def list(user: reader, id: component.id)
    get path(id), headers: auth_headers_for(user)
  end

  def open_one(user: operator, id: component.id)
    post path(id), headers: auth_headers_for(user), as: :json
  end

  describe "GET :id/investigations" do
    it "401s without authentication" do
      get path

      expect(response).to have_http_status(:unauthorized)
    end

    it "403s a user without platform.status.read" do
      list(user: stranger)

      expect(response).to have_http_status(:forbidden)
    end

    # THE READ FLOOR IS THE READ FLOOR. A reader who can see the component on
    # the page can see what has been investigated about it, without holding the
    # permission that lets them start one.
    it "200s a reader holding only the floor — the other arm" do
      list

      expect(response).to have_http_status(:ok)
    end

    it "404s a component belonging to another account" do
      theirs = create(:platform_component_status, account: create(:account),
                                                  component_kind: "docker_host", component_ref: "theirs")

      list(id: theirs.id)

      expect(response).to have_http_status(:not_found)
    end

    it "separates the open investigation from the concluded ones" do
      open_row = ::Platform::InvestigationService.new(account: account)
                                                 .open!(component, trigger: "operator")[:investigation]
      done = ::Platform::Investigation.create!(
        account_id: account.id, component_kind: "docker_host", component_ref: "host-1",
        trigger: "down", status: ::Platform::Investigation::STATUS_COMPLETED,
        conclusion: "Most likely: disk full (confidence 0.35).",
        hypotheses: [ { "cause" => "disk full", "confidence" => 0.35, "confidence_state" => "measured" } ]
      )

      list

      expect(body["data"]["open"].map { |r| r["id"] }).to eq([ open_row.id ])
      expect(body["data"]["recent"].map { |r| r["id"] }).to eq([ done.id ])
      expect(body["data"]["daily_cap"]).to eq(::Platform::InvestigationService.daily_cap)
    end

    # The open row carries its evidence, because that is what the drawer shows
    # while it waits; a concluded one does not, because the list would then
    # carry ten evidence blobs to render ten one-line summaries.
    it "carries evidence on the open row and not on the concluded list" do
      ::Platform::InvestigationService.new(account: account).open!(component, trigger: "operator")
      ::Platform::Investigation.create!(
        account_id: account.id, component_kind: "docker_host", component_ref: "host-2",
        trigger: "down", status: ::Platform::Investigation::STATUS_COMPLETED
      )

      list

      expect(body["data"]["open"].first).to have_key("evidence")
    end

    it "carries the hypotheses with the confidence STATE, not a bare number" do
      ::Platform::Investigation.create!(
        account_id: account.id, component_kind: "docker_host", component_ref: "host-1",
        trigger: "operator", status: ::Platform::Investigation::STATUS_COMPLETED,
        hypotheses: [ { "cause" => "upstream lost", "confidence" => nil,
                        "confidence_state" => ::Platform::Investigation::Confidence::NOT_MEASURED } ]
      )

      list

      hypothesis = body["data"]["recent"].first["hypotheses"].first
      expect(hypothesis["confidence"]).to be_nil
      expect(hypothesis["confidence_state"]).to eq("not_measured")
    end

    it "does not list another component's investigations — the other arm" do
      other = create(:platform_component_status, account: account, component_kind: "docker_host",
                                                 component_ref: "host-9")
      ::Platform::InvestigationService.new(account: account).open!(other, trigger: "operator")

      list

      expect(body["data"]["open"]).to eq([])
    end

    it "reads a shared component's investigations" do
      shared = create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                           component_ref: "breaker-1")
      ::Platform::InvestigationService.new(account: nil).open!(shared, trigger: "operator")

      list(id: shared.id)

      expect(response).to have_http_status(:ok)
      expect(body["data"]["open"].size).to eq(1)
    end
  end

  describe "POST :id/investigations" do
    it "401s without authentication" do
      post path

      expect(response).to have_http_status(:unauthorized)
    end

    # STARTING one spends money and creates a row somebody must dispose of, so
    # the read floor alone does not buy it. Identical to the MCP verb's split.
    it "403s a reader who holds only platform.status.read" do
      open_one(user: reader)

      expect(response).to have_http_status(:forbidden)
      expect(::Platform::Investigation.count).to eq(0)
    end

    it "201s an operator who holds ai.autonomy.manage — the other arm" do
      open_one

      expect(response).to have_http_status(:created)
      investigation = body["data"]["investigation"]
      expect(investigation["trigger"]).to eq("operator")
      expect(investigation["status"]).to eq("open")
      expect(investigation["open"]).to be(true)
      expect(investigation["evidence"]["conditions"]).to be_present
      expect(::Platform::Investigation.count).to eq(1)
    end

    # Ranking is the worker's. An open investigation with evidence and no
    # hypotheses is the correct result of pressing the button.
    it "returns before ranking, with no hypotheses" do
      open_one

      expect(body["data"]["investigation"]["hypotheses"]).to eq([])
    end

    it "404s a component belonging to another account, before opening anything" do
      theirs = create(:platform_component_status, account: create(:account),
                                                  component_kind: "docker_host", component_ref: "theirs")

      open_one(id: theirs.id)

      expect(response).to have_http_status(:not_found)
      expect(::Platform::Investigation.count).to eq(0)
    end

    describe "the bounds, which are the service's" do
      it "409s the second open investigation of one component" do
        open_one
        open_one

        expect(response).to have_http_status(:conflict)
        expect(body["details"]["refused"])
          .to eq(::Platform::InvestigationService::REFUSED_ALREADY_OPEN)
        expect(::Platform::Investigation.count).to eq(1)
      end

      # The other arm, and the reason the index is partial.
      it "allows another once the first has concluded" do
        open_one
        ::Platform::Investigation.first.update!(status: ::Platform::Investigation::STATUS_COMPLETED)

        open_one

        expect(response).to have_http_status(:created)
        expect(::Platform::Investigation.count).to eq(2)
      end

      it "409s past the daily cap and says what the cap is" do
        allow(::Platform::InvestigationService).to receive(:daily_cap).and_return(0)

        open_one

        expect(response).to have_http_status(:conflict)
        expect(body["details"]["refused"])
          .to eq(::Platform::InvestigationService::REFUSED_DAILY_CAP)
        expect(body["details"]["daily_cap"]).to eq(0)
      end
    end

    # THE TWO DOORS AGREE — asserted BEHAVIOURALLY, from the tool's own
    # constant, against the REST door (A9 review S2).
    #
    # The previous example compared the MCP constant to a string literal and
    # never touched the controller, so it stayed green while the REST door was
    # patched to a permission that does not exist. This builds a user holding
    # EXACTLY the floor plus whatever the MCP verb requires, and POSTs to the
    # REST door. If the REST door moves to any other permission, the 201 arm
    # goes red; the 403 arm proves the door does refuse without it, so the pair
    # cannot pass by the door accepting everybody.
    describe "the REST door accepts exactly what the MCP verb requires" do
      let(:mcp_permission) { Ai::Tools::PlatformInvestigationTool::ACTION_PERMISSIONS.fetch("platform_investigate") }

      it "admits a user holding the floor plus the MCP verb's permission" do
        exact = create(:user, account: account, permissions: [ "platform.status.read", mcp_permission ])

        open_one(user: exact)

        expect(response).to have_http_status(:created)
      end

      it "refuses a user holding the floor plus some OTHER write permission" do
        other = create(:user, account: account, permissions: [ "platform.status.read", "ai.goals.manage" ])

        open_one(user: other)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # A6 re-verification G1 — the person who pressed Investigate is recorded,
  # and is the only person ranking may spend as.
  describe "who opened it, and why no agent ranked it" do
    it "records the operator as the opener" do
      open_one

      expect(response).to have_http_status(:created)
      expect(body["data"]["investigation"]["opened_by_user_id"]).to eq(operator.id)
      expect(::Platform::Investigation.find(body["data"]["investigation"]["id"]).opened_by_user_id)
        .to eq(operator.id)
    end

    # Concluded rows carry no evidence on this list, so the ranking record has
    # its own field: this is where the drawer reads "ranking was not run".
    it "says why no agent ranked a concluded investigation, on the list the drawer reads" do
      automatic = ::Platform::InvestigationService.new(account: account)
                                                  .open!(component, trigger: "down")[:investigation]
      ::Platform::Investigation::Ranking.record_outcome!(
        automatic, { ranked: nil, agent: nil,
                     ranking: { "state" => "not_run", "reason" => "AutomaticSpendNeedsGrant",
                                "message" => "Ranking was not run because automatic spend needs an " \
                                             "agent-scoped grant.",
                                "retryable" => false } }
      )
      ::Platform::InvestigationService.new(account: account).conclude!(automatic)

      list

      row = body["data"]["recent"].first
      expect(row["opened_by_user_id"]).to be_nil
      expect(row["ranking"]).to include("state" => "not_run", "reason" => "AutomaticSpendNeedsGrant")
      expect(row["conclusion"]).to include("agent-scoped grant")
    end
  end

  # A9 review S1 — a SHARED component's investigation belongs to whoever opened
  # it. It used to be filed under the component's nil account: one bucket every
  # tenant shared, jointly capped, visible to all, and able to refuse them all.
  describe "investigating a SHARED component" do
    let(:account_b) { create(:account) }
    let(:operator_b) do
      create(:user, account: account_b, permissions: [ "platform.status.read", "ai.autonomy.manage" ])
    end
    let(:shared) do
      create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                   component_ref: "breaker-1",
                                                   verdict: ::Platform::ComponentStatus::DEGRADED,
                                                   conditions: [ { "type" => "Closed", "status" => false,
                                                                   "reason" => "BreakerOpen",
                                                                   "severity" => "degraded" } ])
    end

    it "files the investigation under the caller's account, not nil" do
      open_one(id: shared.id)

      expect(response).to have_http_status(:created)
      expect(::Platform::Investigation.find(body["data"]["investigation"]["id"]).account_id).to eq(account.id)
    end

    it "does not show one tenant's investigation to another" do
      open_one(id: shared.id)

      list(user: operator_b, id: shared.id)

      expect(body["data"]["open"]).to eq([])
    end

    # The sharpest edge: one tenant's open row used to refuse every other
    # tenant with AlreadyOpen, indefinitely.
    it "lets another tenant open its own investigation of the same component" do
      open_one(id: shared.id)

      open_one(user: operator_b, id: shared.id)

      expect(response).to have_http_status(:created)
      expect(::Platform::Investigation.where(component_ref: "breaker-1").pluck(:account_id))
        .to contain_exactly(account.id, account_b.id)
    end

    # The spend cap is counted against the CALLER's own account. It used to be
    # charged to the shared nil bucket, which bypassed the caller's cap
    # entirely.
    it "charges the caller's own daily cap" do
      allow(::Platform::InvestigationService).to receive(:daily_cap).and_return(1)
      open_one(id: shared.id)

      open_one(id: component.id)

      expect(response).to have_http_status(:conflict)
      expect(body["details"]["refused"]).to eq(::Platform::InvestigationService::REFUSED_DAILY_CAP)
    end

    it "does not charge another tenant's cap — the other arm" do
      allow(::Platform::InvestigationService).to receive(:daily_cap).and_return(1)
      open_one(id: shared.id)

      open_one(user: operator_b, id: shared.id)

      expect(response).to have_http_status(:created)
    end
  end

  # A9 review S4 — the component's scope, taken from the plane's one serializer.
  describe "the scope label" do
    it "labels a shared component as shared" do
      shared = create(:platform_component_status, :shared, component_kind: "provider_circuit_breaker",
                                                           component_ref: "breaker-2")

      list(id: shared.id)

      expect(body["data"]["scope"]).to eq(::Platform::ComponentStatusSerializer::SCOPE_SHARED)
    end

    it "labels an account component as account — the other arm" do
      list

      expect(body["data"]["scope"]).to eq(::Platform::ComponentStatusSerializer::SCOPE_ACCOUNT)
    end

    it "carries the label on the 201 too" do
      open_one

      expect(body["data"]["scope"]).to eq(::Platform::ComponentStatusSerializer::SCOPE_ACCOUNT)
    end
  end
end
