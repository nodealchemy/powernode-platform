# frozen_string_literal: true

require "rails_helper"

# Campaign 01a08c9b, increment A4 — the agent's view of the status plane.
#
# Three reads, and the oracles that matter are the ones a wrong answer would
# pass: every action refused WITHOUT the permission and allowed WITH it, every
# public action DECLARED (an undeclared action is invisible to the annotation
# export in E2), and the three-valued environment filter answering the same way
# the REST door does.
RSpec.describe Ai::Tools::PlatformStatusTool do
  let(:account) { create(:account) }
  let(:reader)  { create(:user, account: account, permissions: [ "platform.status.read" ]) }
  let(:tool)    { described_class.new(account: account, user: reader) }

  let(:plane_a) { account.environments.find_by!(slug: "dev") }
  let(:plane_b) { account.environments.find_by!(slug: "prod") }

  def component(*traits, **attrs)
    create(:platform_component_status, *traits, **{ account: account }.merge(attrs))
  end

  def call(action, **rest) = tool.execute(params: { action: action }.merge(rest))

  def refs(result) = result.dig(:data, :component_statuses).map { |r| r[:component_ref] }

  # A METHOD, not a constant: a constant assigned inside an RSpec block lands
  # on Object and can be clobbered by a same-named constant in another spec
  # file — an order-dependent flake waiting to happen.
  def advertised_actions = %w[list_component_status get_component_status get_component_impact]

  describe "declarations and annotations" do
    it "declares every action it advertises, all read-only" do
      advertised = ::Ai::Tools::PlatformApiToolRegistry.all_tools
                                                       .select { |_, klass| klass == described_class.name }
                                                       .keys.map(&:to_s)
      expect(advertised).to match_array(advertised_actions)

      advertised.each do |action|
        declaration = described_class.declared_action(action)
        expect(declaration).not_to be_nil, "#{action} is advertised but not declared"
        expect(declaration[:mutating]).to be(false), "#{action} is declared mutating"
      end
    end

    # The other arm: `mutating: false` is a real value here, not something
    # every declaration happens to carry. A mutating verb elsewhere reads true.
    it "is not asserting a property every declared action has" do
      expect(::Ai::Tools::EnvironmentTool.declared_action("environment_update")[:mutating]).to be(true)
    end

    it "advertises the tools/list read-only annotation for the list and get verbs" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      # `include`, not `eq`. Increment E2 rewrote this export mid-campaign and
      # its shape moved TWICE inside one session: first gaining an
      # `annotationSource` key valued "declared", then "inferred". Pinning the
      # whole hash with `eq` made this spec a tripwire for every future
      # addition to a wire object another lane owns. The substance A4 pins is
      # the HINT — a later key is not a regression; a missing readOnlyHint is.
      expect(entries["platform.list_component_status"]["annotations"]).to include("readOnlyHint" => true)
      expect(entries["platform.get_component_status"]["annotations"]).to include("readOnlyHint" => true)
    end

    # The verb is named `get_component_impact`, not `component_impact`, so it
    # carries the hint too. Mcp::ToolCatalog derives readOnlyHint from the
    # action name's FIRST underscore segment (READ_ONLY_ACTION_PREFIXES); a
    # name outside that vocabulary ships a read verb with no hint however it
    # is declared. Asserted here so a rename out of the prefix set fails loudly
    # rather than silently dropping the annotation.
    it "carries the read-only annotation on the impact verb too, because of its name" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entry = catalog.list_entries.find { |t| t["name"] == "platform.get_component_impact" }

      expect(entry).not_to be_nil
      expect(entry["annotations"]).to include("readOnlyHint" => true)
      expect(described_class.declared_action("get_component_impact")[:mutating]).to be(false)
    end

    # The other arm: the hint is NOT handed out to everything, so "it has the
    # hint" above is a real observation and not a property of the catalog.
    #
    # Written as a COMPARISON inside one example rather than as an assertion
    # about the mutating verb alone. E2 is still in flight and has already
    # emitted three different shapes for a mutating verb (`nil`, then
    # `{readOnlyHint: false, destructiveHint: false, annotationSource:
    # "declared"}`, then `{annotationSource: "inferred"}`). Pinning any one of
    # them asserts a moment rather than a rule. What must hold in every shape
    # is that a read verb's hint is true and a mutating verb's is not — and
    # comparing the two in one example means the day annotations vanish
    # entirely, this fails instead of passing quietly.
    it "does not hand the read-only hint to a mutating verb" do
      catalog = ::Mcp::ToolCatalog.new(protocol_version: ::Mcp::ProtocolService::ALL_SUPPORTED_VERSIONS.max)
      entries = catalog.list_entries.index_by { |t| t["name"] }

      mutating = entries["platform.environment_update"]
      reading  = entries["platform.list_component_status"]
      expect(mutating).not_to be_nil
      expect(reading).not_to be_nil

      expect(reading["annotations"].to_h["readOnlyHint"]).to be(true)
      expect(mutating["annotations"].to_h["readOnlyHint"]).not_to be(true)
    end

    it "names a permission the catalog recognizes on every action" do
      expect(::Permissions.permission_exists?(described_class::REQUIRED_PERMISSION)).to be true
      described_class::ACTION_PERMISSIONS.each_value do |permission|
        expect(::Permissions.permission_exists?(permission)).to be true
      end
      expect(described_class::ACTION_PERMISSIONS.keys).to match_array(advertised_actions)
    end
  end

  describe "permission enforcement" do
    let(:row) { component }

    it "refuses every action without platform.status.read" do
      stranger = described_class.new(account: account, user: create(:user, account: account, permissions: []))

      [
        { action: "list_component_status" },
        { action: "get_component_status", id: row.id },
        { action: "get_component_impact", id: row.id }
      ].each do |params|
        result = stranger.execute(params: params)
        expect(result[:success]).to be(false), "#{params[:action]} was allowed without the permission"
        expect(result[:error]).to include("platform.status.read")
        expect(result[:data]).to be_nil
      end
    end

    it "allows every action with it" do
      [
        { action: "list_component_status" },
        { action: "get_component_status", id: row.id },
        { action: "get_component_impact", id: row.id }
      ].each do |params|
        expect(tool.execute(params: params)[:success]).to be(true), "#{params[:action]} was refused for a holder"
      end
    end
  end

  describe "list_component_status" do
    it "returns this account's rows plus the shared ones, never another tenant's" do
      component(component_ref: "mine")
      create(:platform_component_status, :shared, component_ref: "shared-thing")
      create(:platform_component_status, account: create(:account), component_ref: "theirs")

      expect(refs(call("list_component_status"))).to contain_exactly("mine", "shared-thing")
    end

    # The shared-row ruling (2026-09-10), both arms, from a SECOND account:
    # a NULL-account row reaches every holder of platform.status.read labelled
    # `scope: "shared"`, and account A's own rows never reach B.
    it "labels shared rows scope=shared for another account, and hides that account's own rows" do
      create(:platform_component_status, :shared, component_ref: "shared-breaker")
      component(component_ref: "account-a-only")

      account_b = create(:account)
      tool_b = described_class.new(
        account: account_b,
        user: create(:user, account: account_b, permissions: [ "platform.status.read" ])
      )
      rows = tool_b.execute(params: { action: "list_component_status" }).dig(:data, :component_statuses)

      expect(rows.map { |r| r[:component_ref] }).to eq([ "shared-breaker" ])
      expect(rows.first[:scope]).to eq("shared")
      expect(rows.map { |r| r[:component_ref] }).not_to include("account-a-only")
    end

    it "labels an account row scope=account" do
      component(component_ref: "mine")

      expect(call("list_component_status").dig(:data, :component_statuses).first[:scope]).to eq("account")
    end

    it "filters by kind, both arms" do
      component(component_kind: "ai_provider", component_ref: "openai")
      component(component_kind: "docker_host", component_ref: "host-1")

      result = refs(call("list_component_status", kind: "ai_provider"))
      expect(result).to include("openai")
      expect(result).not_to include("host-1")
    end

    it "filters by verdict, both arms, and refuses one outside the ladder" do
      component(component_ref: "broken", verdict: "down")
      component(component_ref: "fine", verdict: "ok")

      result = refs(call("list_component_status", verdict: "down"))
      expect(result).to eq([ "broken" ])
      expect(result).not_to include("fine")

      refused = call("list_component_status", verdict: "on_fire")
      expect(refused[:success]).to be false
      expect(refused[:error]).to include("on_fire")
    end

    it "unhealthy_only keeps not_measured, degraded and down and drops ok and held" do
      component(component_ref: "blind", verdict: "not_measured")
      component(component_ref: "sick", verdict: "degraded")
      component(component_ref: "dead", verdict: "down")
      component(component_ref: "fine", verdict: "ok")
      component(:held, component_ref: "drained")

      expect(refs(call("list_component_status", unhealthy_only: true)))
        .to contain_exactly("blind", "sick", "dead")
      expect(refs(call("list_component_status")))
        .to contain_exactly("blind", "sick", "dead", "fine", "drained")
    end

    describe "the three-valued environment filter" do
      before do
        component(component_ref: "in-a", environment: plane_a)
        component(component_ref: "in-b", environment: plane_b)
        component(component_ref: "planeless", environment: nil)
      end

      it "absent → every row" do
        expect(refs(call("list_component_status"))).to contain_exactly("in-a", "in-b", "planeless")
      end

      it "a plane → that plane PLUS the plane-less rows, labelled, and never another plane's" do
        result = call("list_component_status", environment: plane_a.slug)
        rows = result.dig(:data, :component_statuses)

        expect(rows.map { |r| r[:component_ref] }).to contain_exactly("in-a", "planeless")
        expect(rows.map { |r| r[:component_ref] }).not_to include("in-b")
        expect(rows.to_h { |r| [ r[:component_ref], r[:plane] ] }).to eq("in-a" => "in", "planeless" => "none")
      end

      it "environment=none → the plane-less rows alone" do
        expect(refs(call("list_component_status", environment: "none"))).to eq([ "planeless" ])
      end

      it "REFUSES a plane this account does not have rather than answering from every plane" do
        result = call("list_component_status", environment: "moon")
        expect(result[:success]).to be false
        expect(result[:error]).to include("moon")
      end
    end

    it "pages with the shared keyset envelope" do
      3.times { |i| component(component_ref: "c#{i}") }

      first = call("list_component_status", limit: 2)
      expect(first.dig(:data, :component_statuses).size).to eq(2)
      expect(first.dig(:data, :count)).to eq(3)
      expect(first.dig(:data, :has_more)).to be true

      second = call("list_component_status", limit: 2, cursor: first.dig(:data, :next_cursor))
      expect(second.dig(:data, :component_statuses).size).to eq(1)
      expect(second.dig(:data, :has_more)).to be false
    end

    it "uses `not_measured` on the wire and never `unknown`" do
      component(component_ref: "blind", verdict: "not_measured")

      row = call("list_component_status").dig(:data, :component_statuses).first
      expect(row[:verdict]).to eq("not_measured")
      expect(::Platform::ComponentStatus::VERDICTS).not_to include("unknown")
    end
  end

  # A4b review F3: the MCP surface asserted none of the three A4b keys, and its
  # eager-load had no guard. F1 and F2 are asserted here too, since the tool is
  # the surface an agent reads.
  describe "the A4b fields on the MCP surface" do
    def rows_by_ref(result) = result.dig(:data, :component_statuses).index_by { |r| r[:component_ref] }

    it "carries reason_message and the plane's slug and name" do
      component(component_ref: "vm-1", verdict: "down", environment: plane_a,
                conditions: [ { "type" => "Reachable", "status" => false, "reason" => "HeartbeatStale",
                                "message" => "no heartbeat for 7m 12s", "severity" => "down" } ])

      row = rows_by_ref(call("list_component_status"))["vm-1"]

      expect(row).to include(reason: "HeartbeatStale", reason_message: "no heartbeat for 7m 12s",
                             environment_slug: plane_a.slug, environment_name: plane_a.name)
    end

    # Rows on THREE DIFFERENT planes, so a per-row load is three distinct
    # statements the query cache cannot absorb.
    it "loads the planes once per page, not once per row" do
      %w[dev ci staging].each_with_index do |slug, i|
        component(component_ref: "c#{i}", environment: account.environments.find_by!(slug: slug))
      end

      queries = 0
      counter = ->(_n, _s, _f, _i, payload) { queries += 1 if payload[:sql]&.include?("ai_environments") }
      result = nil
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { result = call("list_component_status") }

      expect(result.dig(:data, :component_statuses).size).to eq(3)
      expect(queries).to be <= 1
    end

    it "names no reason on a healthy row whose only false condition is an intent" do
      component(component_ref: "provider", verdict: "ok",
                conditions: [ { "type" => "Held", "status" => false, "reason" => "Active",
                                "message" => "provider is enabled" } ])
      component(component_ref: "node", verdict: "ok",
                conditions: [ { "type" => "Held", "status" => false, "reason" => "NotHeld" } ])

      rows = rows_by_ref(call("list_component_status"))

      %w[provider node].each { |ref| expect(rows[ref]).to include(reason: nil, reason_message: nil) }
    end

    it "never prints another tenant's plane name, on a shared row or a mis-pointed account row" do
      foreign_plane = create(:account).environments.find_by!(slug: "dev")
      foreign_plane.update!(name: "Acme EU Secret Plane")
      create(:platform_component_status, :shared, component_ref: "leaky-shared", environment: foreign_plane)
      component(component_ref: "leaky-own", environment: foreign_plane)

      result = call("list_component_status")

      expect(result.to_json).not_to include("Acme EU Secret Plane")
      rows = rows_by_ref(result)
      %w[leaky-shared leaky-own].each do |ref|
        expect(rows[ref]).to include(environment_slug: nil, environment_name: nil)
      end
    end
  end

  describe "get_component_status" do
    it "returns the full row and an impact summary, found by id or by kind+ref" do
      row = component(
        component_kind: "node_instance", component_ref: "vm-1", verdict: "down",
        conditions: [ { "type" => "Reachable", "status" => false, "reason" => "HeartbeatStale", "severity" => "down" } ],
        actions: [ { "key" => "cordon", "permission" => "system.instances.manage" } ]
      )
      component(component_kind: "service", component_ref: "svc-1", verdict: "degraded",
                dependencies: [ { "kind" => "node_instance", "ref" => "vm-1" } ])

      by_id = call("get_component_status", id: row.id)
      expect(by_id.dig(:data, :component_status, :reason)).to eq("HeartbeatStale")
      expect(by_id.dig(:data, :component_status, :actions).first["permission"]).to eq("system.instances.manage")
      expect(by_id.dig(:data, :impact, :count)).to eq(1)
      expect(by_id.dig(:data, :impact, :worst_verdict)).to eq("degraded")

      by_key = call("get_component_status", component_kind: "node_instance", component_ref: "vm-1")
      expect(by_key.dig(:data, :component_status, :id)).to eq(row.id)
    end

    it "reports another tenant's component as absent, and says what it needs when given nothing" do
      foreign = create(:platform_component_status, account: create(:account))

      absent = call("get_component_status", id: foreign.id)
      expect(absent[:success]).to be false
      expect(absent[:error]).to include("not found")

      expect(call("get_component_status")[:error]).to include("component_kind")
    end
  end

  describe "get_component_impact" do
    let!(:root) do
      component(component_kind: "node", component_ref: "node-1", verdict: "down",
                conditions: [ { "type" => "Reachable", "status" => false, "reason" => "Unreachable",
                                "severity" => "down", "last_transition_at" => 2.hours.ago.iso8601 } ])
    end
    let!(:middle) do
      component(component_kind: "node_instance", component_ref: "vm-1", verdict: "down",
                dependencies: [ { "kind" => "node", "ref" => "node-1" } ],
                conditions: [ { "type" => "Reachable", "status" => false, "reason" => "HeartbeatStale",
                                "severity" => "down", "last_transition_at" => 10.minutes.ago.iso8601 } ])
    end
    let!(:leaf) do
      component(component_kind: "service", component_ref: "svc-1", verdict: "degraded",
                dependencies: [ { "kind" => "node_instance", "ref" => "vm-1" } ])
    end

    it "returns dependents and ranked candidates, LABELLED a heuristic" do
      result = call("get_component_impact", id: middle.id)

      expect(result.dig(:data, :heuristic)).to be true
      expect(result.dig(:data, :heuristic_basis)).to include("upstream-most")
      expect(result.dig(:data, :impact, :components).map { |c| c[:component_ref] }).to eq([ "svc-1" ])
      expect(result.dig(:data, :root_cause_candidates).map { |c| c[:component_ref] }).to eq([ root.component_ref ])
    end

    # F4 (A4 review), the MCP half of the same defect.
    it "reports a SHARED component's dependents that live in this account, and not another account's" do
      shared = create(:platform_component_status, :shared, component_kind: "agent_circuit_breaker",
                                                           component_ref: "breaker", verdict: "down")
      mine = component(component_kind: "ai_provider", component_ref: "openai", verdict: "degraded",
                       dependencies: [ { "kind" => "agent_circuit_breaker", "ref" => "breaker" } ])
      other = create(:account)
      create(:platform_component_status, account: other, component_kind: "ai_provider",
                                         component_ref: "their-openai", verdict: "down",
                                         dependencies: [ { "kind" => "agent_circuit_breaker", "ref" => "breaker" } ])

      result = call("get_component_impact", id: shared.id)

      expect(result.dig(:data, :impact, :count)).to eq(1)
      expect(result.dig(:data, :impact, :components).map { |c| c[:component_ref] }).to eq([ mine.component_ref ])
      expect(result.to_json).not_to include("their-openai")
    end

    it "clamps depth to the cycle-safe ceiling and defaults when unusable" do
      expect(call("get_component_impact", id: leaf.id, depth: 99).dig(:data, :depth))
        .to eq(::Platform::Status::Rollup::DEFAULT_DEPTH)
      expect(call("get_component_impact", id: leaf.id, depth: 0).dig(:data, :depth))
        .to eq(::Platform::Status::Rollup::DEFAULT_DEPTH)
      expect(call("get_component_impact", id: leaf.id, depth: 1).dig(:data, :depth)).to eq(1)
    end

    it "a depth of 1 sees only the first hop upstream" do
      shallow = call("get_component_impact", id: leaf.id, depth: 1)
      deep    = call("get_component_impact", id: leaf.id, depth: 4)

      expect(shallow.dig(:data, :root_cause_candidates).map { |c| c[:component_ref] }).to eq([ "vm-1" ])
      expect(deep.dig(:data, :root_cause_candidates).map { |c| c[:component_ref] }).to eq([ "node-1" ])
    end
  end

  it "refuses an action it does not advertise" do
    expect(call("delete_everything")[:success]).to be false
  end
end
