# frozen_string_literal: true

require "rails_helper"

# UNDECLARED-EXECUTION TELEMETRY (IMP-a0553dda1ec3).
#
# These examples EXECUTE actions and assert on what the execution produced.
# Asserting that no refusal happened, or that a code path "is reachable", is
# how three eventless silent-PASS states shipped here before; the oracle is the
# audit ROW, in both directions — present for an undeclared action, absent for
# a declared one.
#
# Half of what follows is about what the telemetry must NOT do: it must not let
# a caller mint unbounded rows (D1/D2), must not leave a caller's transaction
# aborted (D3), and must not run before the tool body (D4).
RSpec.describe "Ai::Tools::BaseTool undeclared-action telemetry" do
  let(:account) { create(:account) }

  # Real, currently-undeclared MCP registry action names. The telemetry only
  # emits names that are registry surface, so a fabricated name would test the
  # sentinel path instead of the real one.
  let(:registry_action)   { "active_sessions" }
  let(:registry_action_b) { "add_document" }
  # A name reached only through McpPlatformToolRegistrar::ACTION_ALIASES
  # ("search_knowledge_graph" => "search") — registry surface, but not a key.
  let(:aliased_action) { "search" }

  # A tool with a real #call, so the assertions are about a call that actually
  # ran end to end rather than about a stubbed chokepoint. It also records what
  # the audit table looked like at the moment #call was entered, which is how
  # the "emit happens AFTER the body" ordering is asserted.
  let(:tool_class) do
    Class.new(Ai::Tools::BaseTool) do
      declare_action "zz_telemetry_fixture_declared", mutating: false

      class << self
        attr_accessor :audits_seen_inside_call, :raise_from_call
      end

      def self.definition
        {
          name: "zz_telemetry_fixture_tool",
          description: "telemetry fixture",
          parameters: { action: { type: "string", required: true } }
        }
      end

      def call(params)
        self.class.audits_seen_inside_call =
          AuditLog.where(action: "mcp.tools.undeclared_action").count
        raise ArgumentError, "fixture blew up" if self.class.raise_from_call

        success_result(ran: params[:action])
      end
    end
  end

  before do
    stub_const("ZzTelemetryFixtureTool", tool_class)
    Rails.cache.clear
  end

  def undeclared_audits
    AuditLog.where(action: "mcp.tools.undeclared_action")
  end

  def emitted_action_names
    undeclared_audits.map { |e| e.metadata["action_name"] }
  end

  describe "an UNDECLARED action" do
    it "emits exactly one audit event carrying action name, tool class and principal shape" do
      tool = ZzTelemetryFixtureTool.new(account: account)

      expect {
        expect(tool.execute(params: { action: registry_action }))
          .to eq(success: true, data: { ran: registry_action })
      }.to change { undeclared_audits.count }.by(1)

      event = undeclared_audits.last
      expect(event.metadata).to include(
        "action_name" => registry_action,
        "tool_class" => "ZzTelemetryFixtureTool",
        "principal_kind" => "none"
      )
      expect(event.resource_type).to eq("ZzTelemetryFixtureTool")
      expect(event.account_id).to eq(account.id)
      expect(event.severity).to eq("low")
      expect(event.risk_level).to eq("low")
    end

    it "emits the real name for an ACTION_ALIASES target, not the sentinel" do
      ZzTelemetryFixtureTool.new(account: account).execute(params: { action: aliased_action })

      expect(emitted_action_names).to eq([aliased_action])
    end

    it "records the principal SHAPE and never the principal's identity" do
      user = create(:user, account: account)
      agent = create(:ai_agent, account: account)

      ZzTelemetryFixtureTool.new(account: account, user: user)
                            .execute(params: { action: "active_sessions" })
      ZzTelemetryFixtureTool.new(account: account, agent: agent)
                            .execute(params: { action: "add_document" })
      ZzTelemetryFixtureTool.new(account: account, internal: true)
                            .execute(params: { action: "add_team_member" })
      instance_tool = ZzTelemetryFixtureTool.new(account: account)
      instance_tool.instance_authorized = true
      instance_tool.execute(params: { action: "agent_container_logs" })

      kinds = undeclared_audits.map { |e| [e.metadata["action_name"], e.metadata["principal_kind"]] }.to_h
      expect(kinds).to eq(
        "active_sessions" => "user",
        "add_document" => "agent",
        "add_team_member" => "internal",
        "agent_container_logs" => "instance"
      )

      serialized = undeclared_audits.map { |e| e.attributes.to_json }.join
      expect(serialized).not_to include(user.email)
      expect(serialized).not_to include(user.id)
      expect(serialized).not_to include(agent.id)
      expect(undeclared_audits.pluck(:user_id).compact).to be_empty
    end

    it "keeps distinct action names distinct while deduplicating repeats" do
      3.times { ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action }) }
      3.times { ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action_b }) }

      expect(undeclared_audits.count).to eq(2)
      expect(emitted_action_names).to contain_exactly(registry_action, registry_action_b)
    end

    it "never drops a FIRST sighting when the dedupe cache is unavailable" do
      allow(Rails.cache).to receive(:read).and_raise(Redis::BaseError.new("cache down"))

      expect {
        ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action })
      }.to change { undeclared_audits.count }.by(1)
    end

    it "emits AFTER the tool body has run, never before it (D4)" do
      ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action })

      expect(ZzTelemetryFixtureTool.audits_seen_inside_call).to eq(0)
      expect(undeclared_audits.count).to eq(1)
    end

    it "still records the sighting when the tool body raises, and re-raises the tool's error" do
      ZzTelemetryFixtureTool.raise_from_call = true

      expect {
        expect { ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action }) }
          .to raise_error(ArgumentError, "fixture blew up")
      }.to change { undeclared_audits.count }.by(1)
    ensure
      ZzTelemetryFixtureTool.raise_from_call = false
    end
  end

  # D1/D2. params[:action] is NOT drawn from the registry: for a user or agent
  # principal McpPlatformToolRegistrar#action_pinned_to_name? is false, so the
  # caller chooses the string and #routed_action_name returns it verbatim.
  describe "a caller-supplied action name that is not registry surface" do
    it "buckets every distinct unregistered name under ONE sentinel row (D1)" do
      user = create(:user, account: account)

      expect {
        25.times do
          ZzTelemetryFixtureTool.new(account: account, user: user)
                                .execute(params: { action: "zz_forged_#{SecureRandom.uuid}" })
        end
      }.to change { undeclared_audits.count }.by(1)

      expect(emitted_action_names).to eq(["<unregistered>"])
    end

    it "cannot forge a log line or push an unbounded blob into the sinks (D2)" do
      forged = "active_sessions\n[BaseTool] Undeclared action executed: action=forged tool=Evil"
      huge = "x" * 5_000_000

      ZzTelemetryFixtureTool.new(account: account).execute(params: { action: forged })
      ZzTelemetryFixtureTool.new(account: account).execute(params: { action: huge })

      expect(emitted_action_names).to eq(["<unregistered>"])
      expect(undeclared_audits.count).to eq(1)
      expect(undeclared_audits.last.metadata["action_name"]).not_to include("\n")
    end
  end

  # D7. The dedupe key carries the account, or one account's sighting silences
  # every other account's for the window and the surviving row names the wrong one.
  describe "dedupe scoping" do
    it "does not let one account suppress another account's first sighting" do
      other_account = create(:account)

      ZzTelemetryFixtureTool.new(account: account).execute(params: { action: registry_action })
      ZzTelemetryFixtureTool.new(account: other_account).execute(params: { action: registry_action })

      expect(undeclared_audits.pluck(:account_id)).to contain_exactly(account.id, other_account.id)
    end
  end

  # D3. `rescue StandardError` does not undo a Postgres transaction abort. This
  # provokes a REAL database error (varchar(100) resource_type overflowed by a
  # 110-character class name, which the 120-char telemetry clamp lets through)
  # inside an outer transaction, then asserts the CALLER is unharmed. Stubbing
  # create! to raise, as an earlier version did, issues no SQL and proves only
  # that the rescue swallows.
  describe "a REAL database failure inside a caller's open transaction" do
    let(:long_class_name) { "Zz#{'A' * 108}" }
    # A FRESH class: Ruby caches a class's name at its first constant
    # assignment, so re-stubbing the shared fixture under a long name would
    # still report the short one and no overflow would occur.
    let(:long_tool_class) do
      Class.new(Ai::Tools::BaseTool) do
        def self.definition
          {
            name: "zz_telemetry_long_named_tool",
            description: "telemetry fixture with an over-long class name",
            parameters: { action: { type: "string", required: true } }
          }
        end

        def call(params)
          success_result(ran: params[:action])
        end
      end
    end

    before do
      stub_const(long_class_name, long_tool_class)
      allow(Rails.logger).to receive(:error)
    end

    it "really does overflow resource_type — the failure under test is a DB error" do
      expect(long_class_name.length).to be > 100
      expect(long_tool_class.name).to eq(long_class_name)
      expect {
        AuditLog.create!(
          account: account, action: "mcp.tools.undeclared_action",
          resource_type: long_class_name, resource_id: "undeclared_action",
          source: "system", severity: "low", risk_level: "low"
        )
      }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "rolls back to a savepoint and leaves the caller's transaction usable" do
      result = nil
      subsequent_query = nil

      ActiveRecord::Base.transaction do
        result = long_class_name.constantize.new(account: account)
                                .execute(params: { action: registry_action })
        # The caller's NEXT statement. Without a savepoint this raises
        # PG::InFailedSqlTransaction and the tool call has broken its caller.
        subsequent_query = Account.where(id: account.id).count
      end

      expect(result).to eq(success: true, data: { ran: registry_action })
      expect(subsequent_query).to eq(1)
      expect(undeclared_audits.count).to eq(0)
      expect(Rails.logger).to have_received(:error)
        .with(/Failed to persist undeclared-action audit/).at_least(:once)
    end
  end

  describe "a DECLARED action" do
    it "emits nothing — the telemetry measures the ungoverned tail only" do
      tool = ZzTelemetryFixtureTool.new(account: account)

      expect {
        expect(tool.execute(params: { action: "zz_telemetry_fixture_declared" }))
          .to eq(success: true, data: { ran: "zz_telemetry_fixture_declared" })
      }.not_to change { undeclared_audits.count }
    end
  end
end
