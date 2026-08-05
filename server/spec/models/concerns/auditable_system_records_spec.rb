# frozen_string_literal: true

require "rails_helper"

# IMP-4a4a497a8c15 — auditing of SYSTEM-level (accountless) records.
#
# Auditable#write_audit_log cannot write a row for an accountless record
# because audit_logs.account_id is null: false, so it calls
# #record_audit_skipped, which instruments "audit.write_skipped.auditable" and
# returns nil.
#
# The platform-scoped answer already existed for ONE operation:
# Ai::Agent#audit_global_agent_change audited UPDATES to a global agent into
# the same audit_logs table under a sentinel account, tagged
# metadata.global_agent. This change extends it to CREATE and DESTROY, and
# makes the sentinel lookup FAIL CLOSED — it used to fall back to
# `Account.first`, i.e. an arbitrary tenant, who could then read platform
# events through their own audit relation.
RSpec.describe "Auditable — system-level records (IMP-4a4a497a8c15)" do
  # Auditable.logging_enabled defaults to FALSE in test (auditable.rb:37 — every
  # factory would otherwise pay an INSERT). Every example here runs inside
  # with_logging, otherwise "no audit row was written" would be true for a
  # reason that has nothing to do with the behaviour under test.
  around { |example| Auditable.with_logging { example.run } }

  let(:account) { create(:account) }

  # A system agent still needs a creator: Ai::Agent's `belongs_to :creator` is
  # NOT optional, and the factory derives the creator's user from `account` —
  # so `account: nil` alone fails on "Account must exist" for the USER, not the
  # agent. Supplying an operator explicitly is also the realistic shape: a
  # platform admin owns the change, the agent owns no tenant.
  let(:operator) { create(:user, account: create(:account)) }

  def system_agent(**overrides)
    create(:ai_agent, account: nil, creator: operator, **overrides)
  end

  def audit_rows_for(agent)
    AuditLog.where(resource_type: "Ai::Agent", resource_id: agent.id)
  end

  def skipped_events
    events = []
    subscriber = ActiveSupport::Notifications.subscribe(Auditable::SKIPPED_NOTIFICATION) do |*args|
      events << ActiveSupport::Notifications::Event.new(*args).payload
    end
    yield
    events
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # The control. Without this, every "no row" assertion below could pass
  # because auditing is simply inert in test, and the file would prove nothing.
  describe "an ACCOUNT-scoped agent (the working path)" do
    it "writes a durable, queryable AuditLog row" do
      agent = create(:ai_agent, account: account)

      row = audit_rows_for(agent).where(action: "created").last
      expect(row).to be_present
      expect(row.account_id).to eq(account.id)
    end
  end

  describe "a SYSTEM agent (account_id nil)" do
    it "can exist at all — the fixture reaches the state under test" do
      agent = system_agent

      expect(agent.account_id).to be_nil
      expect(agent).to be_persisted
    end

    context "when the platform sentinel account exists" do
      # The decoy is created FIRST and so sorts first (UUIDv7 primary keys are
      # time-ordered, and Account.first orders by PK). Without it, the sentinel
      # would itself BE Account.first and every assertion below would be
      # satisfied by the old `|| Account.first` fallback just as well as by the
      # named lookup — the fixture would be answered by the wrong branch.
      let!(:decoy)    { create(:account) }
      let!(:sentinel) { create(:account, name: "Powernode Admin") }

      before { expect(Account.first.id).to eq(decoy.id) }

      it "records CREATE against the sentinel" do
        agent = system_agent

        row = audit_rows_for(agent).where(action: "ai.agents.create").last
        expect(row).to be_present
        expect(row.account_id).to eq(sentinel.id)
        expect(row.account_id).not_to eq(decoy.id)
        expect(row.metadata["global_agent"]).to be(true)
      end

      it "records UPDATE against the sentinel (pre-existing behaviour, unchanged)" do
        agent = system_agent

        agent.update!(name: "renamed-#{SecureRandom.hex(3)}")

        row = audit_rows_for(agent).where(action: "ai.agents.update").last
        expect(row).to be_present
        expect(row.account_id).to eq(sentinel.id)
        expect(row.metadata["global_agent"]).to be(true)
        expect(row.metadata["changed_fields"]).to include("name")
      end

      it "records DELETE against the sentinel" do
        agent = system_agent
        agent.destroy!

        row = audit_rows_for(agent).where(action: "ai.agents.delete").last
        expect(row).to be_present
        expect(row.account_id).to eq(sentinel.id)
        expect(row.metadata["global_agent"]).to be(true)
      end

      # The platform path is gated `if: :global?`. An ACCOUNT-scoped agent must
      # keep going through the ordinary Auditable path only — otherwise every
      # tenant's agent would also mint a row against the sentinel, which is a
      # cross-tenant write in the opposite direction.
      it "writes NO platform row for an ACCOUNT-scoped agent" do
        agent = create(:ai_agent, account: account)

        expect(audit_rows_for(agent).where("action LIKE ?", "ai.agents.%")).to be_empty
        expect(sentinel.audit_logs.where(resource_id: agent.id)).to be_empty
      end
    end

    # FAIL CLOSED. A row naming the wrong party is worse than a missing row,
    # because the record exists precisely to be trusted — and here the misfiled
    # row was also READABLE by a tenant with no relationship to the event.
    context "when NO sentinel account exists" do
      let!(:tenant_a) { create(:account) }
      let!(:tenant_b) { create(:account) }

      before { expect(Account.where(name: "Powernode Admin")).to be_empty }

      it "writes NO row to ANY account on create" do
        agent = system_agent

        expect(audit_rows_for(agent)).to be_empty
        expect(tenant_a.audit_logs.where(resource_id: agent.id)).to be_empty
        expect(tenant_b.audit_logs.where(resource_id: agent.id)).to be_empty
      end

      it "writes NO row to ANY account on update" do
        agent = system_agent

        agent.update!(name: "renamed-#{SecureRandom.hex(3)}")

        expect(audit_rows_for(agent)).to be_empty
        expect(tenant_a.audit_logs.where(resource_id: agent.id)).to be_empty
        expect(tenant_b.audit_logs.where(resource_id: agent.id)).to be_empty
      end

      it "writes NO row to ANY account on destroy" do
        agent = system_agent
        agent.destroy!

        expect(audit_rows_for(agent)).to be_empty
        expect(tenant_a.audit_logs.where(resource_id: agent.id)).to be_empty
        expect(tenant_b.audit_logs.where(resource_id: agent.id)).to be_empty
      end

      # Failing closed silently would trade a wrong row for an invisible gap.
      # The skip rides the notification Auditable already defines for exactly
      # this — "so the gap is countable in production rather than living only
      # in a log line" (auditable.rb:45).
      it "emits the skip signal, naming the missing sentinel as the reason" do
        agent = nil
        events = skipped_events { agent = system_agent }

        payload = events.find do |e|
          e[:record_id] == agent.id && e[:reason] == Audit::PlatformAccount::MISSING_REASON
        end
        expect(payload).to be_present
        expect(payload[:action]).to eq("ai.agents.create")
      end

      # Failing closed must be a DECISION, not a swallowed exception. Without
      # the `return unless account` guard in the writer, AuditLog.create! is
      # still reached with a nil account, raises RecordInvalid, and the
      # best-effort rescue hides it — same empty table, but arrived at by a
      # failed INSERT per event, and logged as an audit FAILURE rather than a
      # deliberate skip.
      it "refuses without raising or logging an audit failure" do
        failures = []
        allow(Rails.logger).to receive(:warn) { |msg| failures << msg.to_s }

        agent = system_agent
        agent.update!(name: "renamed-#{SecureRandom.hex(3)}")

        expect(audit_rows_for(agent)).to be_empty
        expect(failures.grep(/audit failed/)).to be_empty
      end
    end

    # Auditable's OWN skip still fires for a global agent: the generic path
    # declines (account nil + audit_optional_account!), and the platform path
    # above takes over. Two different reasons, both countable.
    it "still emits Auditable's own skip signal, with the model's declared reason" do
      agent = nil
      events = skipped_events { agent = system_agent }

      payload = events.find do |e|
        e[:model] == "Ai::Agent" && e[:record_id] == agent.id && e[:action] == "created"
      end
      expect(payload).to be_present
      expect(payload[:reason]).to eq("system agents are shared across tenants and own no account")
    end
  end

  # Tenant isolation is the constraint the fix had to preserve. Reads go
  # through `current_user.account.audit_logs` (audit_logs_controller.rb:170),
  # i.e. WHERE account_id = '<uuid>'.
  describe "tenant isolation" do
    it "scopes an account's audit_logs relation by account_id" do
      other = create(:account)
      agent = create(:ai_agent, account: account)

      expect(account.audit_logs.where(resource_id: agent.id)).to be_present
      expect(other.audit_logs.where(resource_id: agent.id)).to be_empty
    end

    it "never surfaces a NULL-account row through an account relation" do
      expect(account.audit_logs.where(account_id: nil)).to be_empty
    end
  end
end
