require 'rails_helper'

RSpec.describe AuditLog, type: :model do
  let(:audit_log) { build(:audit_log) }

  describe "associations" do
    it { should belong_to(:user).optional }
    it { should belong_to(:account) }
  end

  describe "validations" do
    it { should validate_presence_of(:action) }
    it { should validate_inclusion_of(:action).in_array(%w[create update delete login logout payment subscription_change role_change]) }
    it { should validate_presence_of(:resource_type) }
    it { should validate_presence_of(:resource_id) }
    it { should validate_presence_of(:source) }
    it { should validate_inclusion_of(:source).in_array(%w[web api system webhook]) }
  end

  describe "scopes" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let!(:user_audit) { create(:audit_log, user: user, account: account, action: "login") }
    let!(:system_audit) { create(:audit_log, user: nil, account: account, action: "create") }
    let!(:other_account_audit) { create(:audit_log, account: create(:account), action: "update") }

    describe ".for_resource" do
      it "filters by resource type and id" do
        resource = create(:user)
        audit = create(:audit_log, resource_type: "User", resource_id: resource.id)

        expect(AuditLog.for_resource("User", resource.id)).to include(audit)
        expect(AuditLog.for_resource("Account", resource.id)).not_to include(audit)
      end
    end

    describe ".by_user" do
      it "filters by user" do
        expect(AuditLog.by_user(user)).to include(user_audit)
        expect(AuditLog.by_user(user)).not_to include(system_audit, other_account_audit)
      end
    end

    describe ".by_account" do
      it "filters by account" do
        expect(AuditLog.by_account(account)).to include(user_audit, system_audit)
        expect(AuditLog.by_account(account)).not_to include(other_account_audit)
      end
    end

    describe ".by_action" do
      it "filters by action type" do
        expect(AuditLog.by_action("login")).to include(user_audit)
        expect(AuditLog.by_action("login")).not_to include(system_audit, other_account_audit)
      end
    end

    describe ".recent" do
      it "orders by created_at descending" do
        older_audit = create(:audit_log)
        # Ensure newer audit has a later timestamp
        sleep(0.01) # Small delay to ensure different timestamps
        newer_audit = create(:audit_log)

        recent_audits = AuditLog.recent.limit(2)
        expect(recent_audits.first.created_at).to be > recent_audits.last.created_at
      end
    end

    describe ".in_date_range" do
      it "filters by date range" do
        old_audit = create(:audit_log, created_at: 2.days.ago)
        recent_audit = create(:audit_log, created_at: 1.hour.ago)

        results = AuditLog.in_date_range(1.day.ago, Time.current)
        expect(results).to include(recent_audit)
        expect(results).not_to include(old_audit)
      end
    end
  end

  describe "callbacks" do
    describe "#set_defaults" do
      it "initializes default values" do
        audit = AuditLog.new
        expect(audit.old_values).to eq({})
        expect(audit.new_values).to eq({})
        expect(audit.metadata).to eq({})
      end
    end
  end

  describe "class methods" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:resource) { create(:subscription, account: account) }

    describe ".log_action" do
      it "creates an audit log with all required fields" do
        audit = AuditLog.log_action(
          action: "create",
          resource: resource,
          user: user,
          account: account,
          old_values: { status: "pending" },
          new_values: { status: "active" },
          ip_address: "192.168.1.1",
          user_agent: "Test Browser",
          source: "web",
          metadata: { test: "data" }
        )

        expect(audit).to be_persisted
        expect(audit.action).to eq("create")
        expect(audit.resource_type).to eq("Subscription")
        expect(audit.resource_id).to eq(resource.id)
        expect(audit.user).to eq(user)
        expect(audit.account).to eq(account)
        expect(audit.old_values).to eq({ "status" => "pending" })
        expect(audit.new_values).to eq({ "status" => "active" })
        expect(audit.ip_address).to eq("192.168.1.1")
        expect(audit.user_agent).to eq("Test Browser")
        expect(audit.source).to eq("web")
        expect(audit.metadata).to eq({ "test" => "data" })
      end

      it "defaults source to web when not provided" do
        audit = AuditLog.log_action(
          action: "update",
          resource: resource,
          account: account
        )

        expect(audit.source).to eq("web")
      end

      it "defaults metadata to empty hash when not provided" do
        audit = AuditLog.log_action(
          action: "update",
          resource: resource,
          account: account
        )

        expect(audit.metadata).to eq({})
      end
    end

    describe ".log_login" do
      it "creates login audit log" do
        audit = AuditLog.log_login(
          user,
          ip_address: "192.168.1.1",
          source: "web"
        )

        expect(audit.action).to eq("login")
        expect(audit.resource_type).to eq("User")
        expect(audit.resource_id).to eq(user.id)
        expect(audit.user).to eq(user)
        expect(audit.account).to eq(account)
        expect(audit.ip_address).to eq("192.168.1.1")
        expect(audit.source).to eq("web")
      end
    end

    describe ".log_logout" do
      it "creates logout audit log" do
        audit = AuditLog.log_logout(
          user,
          ip_address: "192.168.1.1",
          source: "web"
        )

        expect(audit.action).to eq("logout")
        expect(audit.resource_type).to eq("User")
        expect(audit.resource_id).to eq(user.id)
        expect(audit.user).to eq(user)
        expect(audit.account).to eq(account)
        expect(audit.ip_address).to eq("192.168.1.1")
        expect(audit.source).to eq("web")
      end
    end

    describe ".log_payment" do
      it "creates payment audit log" do
        invoice = create(:invoice, account: account)
        payment = create(:payment, invoice: invoice, amount_cents: 2999, status: "succeeded")

        audit = AuditLog.log_payment(
          payment,
          source: "api"
        )

        expect(audit.action).to eq("payment")
        expect(audit.resource_type).to eq("Payment")
        expect(audit.resource_id).to eq(payment.id)
        expect(audit.account).to eq(account)
        expect(audit.new_values).to include(
          "amount_cents" => 2999,
          "status" => "succeeded"
        )
        expect(audit.source).to eq("api")
      end
    end

    describe ".log_subscription_change" do
      it "creates subscription change audit log" do
        subscription = create(:subscription, account: account)

        audit = AuditLog.log_subscription_change(
          subscription,
          "active",
          "cancelled",
          user: user,
          source: "web"
        )

        expect(audit.action).to eq("subscription_change")
        expect(audit.resource_type).to eq("Subscription")
        expect(audit.resource_id).to eq(subscription.id)
        expect(audit.user).to eq(user)
        expect(audit.account).to eq(account)
        expect(audit.old_values).to eq({ "status" => "active" })
        expect(audit.new_values).to eq({ "status" => "cancelled" })
        expect(audit.source).to eq("web")
      end
    end
  end

  describe "instance methods" do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    describe "#resource" do
      it "returns the associated resource" do
        audit = create(:audit_log, resource_type: "User", resource_id: user.id)

        expect(audit.resource).to eq(user)
      end

      it "returns nil for non-existent resource" do
        audit = create(:audit_log, resource_type: "User", resource_id: "non-existent-id")

        expect(audit.resource).to be_nil
      end

      it "returns nil for invalid resource type" do
        audit = create(:audit_log, resource_type: "InvalidModel", resource_id: user.id)

        expect(audit.resource).to be_nil
      end
    end

    describe "#actor" do
      it "returns user when user is present" do
        audit = create(:audit_log, user: user)

        expect(audit.actor).to eq(user)
      end

      it "returns 'System' when user is nil" do
        audit = create(:audit_log, user: nil)

        expect(audit.actor).to eq("System")
      end
    end

    describe "#summary" do
      let(:audit) { build(:audit_log, user: user, resource_type: "Account") }

      it "generates summary for login action" do
        audit.action = "login"
        expect(audit.summary).to eq("#{user} logged in")
      end

      it "generates summary for logout action" do
        audit.action = "logout"
        expect(audit.summary).to eq("#{user} logged out")
      end

      it "generates summary for create action" do
        audit.action = "create"
        expect(audit.summary).to eq("#{user} created Account")
      end

      it "generates summary for update action" do
        audit.action = "update"
        expect(audit.summary).to eq("#{user} updated Account")
      end

      it "generates summary for delete action" do
        audit.action = "delete"
        expect(audit.summary).to eq("#{user} deleted Account")
      end

      it "generates summary for payment action" do
        audit.action = "payment"
        audit.new_values = { "amount_cents" => 2999, "status" => "completed" }
        expect(audit.summary).to eq("Payment of $29.99 completed")
      end

      it "generates summary for subscription change action" do
        audit.action = "subscription_change"
        audit.old_values = { "status" => "active" }
        audit.new_values = { "status" => "cancelled" }
        expect(audit.summary).to eq("Subscription changed from active to cancelled")
      end

      it "generates summary for role change action" do
        audit.action = "role_change"
        expect(audit.summary).to eq("#{user} changed roles for Account")
      end

      it "generates generic summary for unknown action" do
        audit.action = "unknown_action"
        expect(audit.summary).to eq("#{user} performed unknown_action on Account")
      end

      it "handles system actor" do
        audit.user = nil
        audit.action = "create"
        expect(audit.summary).to eq("System created Account")
      end
    end

    describe "#changes_summary" do
      it "returns nil when no old or new values" do
        audit = build(:audit_log)
        expect(audit.changes_summary).to be_nil
      end

      it "returns nil when old_values is empty" do
        audit = build(:audit_log, new_values: { "status" => "active" })
        expect(audit.changes_summary).to be_nil
      end

      it "returns nil when new_values is empty" do
        audit = build(:audit_log, old_values: { "status" => "pending" })
        expect(audit.changes_summary).to be_nil
      end

      it "generates changes summary for modified values" do
        audit = build(:audit_log,
          old_values: { "status" => "pending", "name" => "Old Name", "unchanged" => "same" },
          new_values: { "status" => "active", "name" => "New Name", "unchanged" => "same" }
        )

        changes = audit.changes_summary
        expect(changes).to include("status: pending → active")
        expect(changes).to include("name: Old Name → New Name")
        expect(changes).not_to include("unchanged")
      end

      it "handles values that don't exist in old_values" do
        audit = build(:audit_log,
          old_values: { "status" => "pending" },
          new_values: { "status" => "active", "new_field" => "new_value" }
        )

        changes = audit.changes_summary
        expect(changes).to include("status: pending → active")
        expect(changes).to include("new_field:  → new_value")
      end
    end
  end
end
