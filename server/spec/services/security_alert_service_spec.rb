# frozen_string_literal: true

require "rails_helper"

RSpec.describe SecurityAlertService do
  before { allow(WorkerJobService).to receive(:enqueue_alert_email).and_return("success" => true) }

  describe ".send_alert (system-wide, no account)" do
    it "emails platform system.admins and creates pending EmailDelivery rows" do
      acct = create(:account)
      create(:user, account: acct, permissions: [ "system.admin" ], email: "sysadmin@example.com")
      create(:user, account: acct, permissions: [ "users.manage" ], email: "acctadmin@example.com")

      result = described_class.send_alert(title: "Spike", message: "10 suspicious events")

      expect(result[:sent]).to eq(1)
      delivery = EmailDelivery.find(result[:email_delivery_ids].first)
      expect(delivery.recipient_email).to eq("sysadmin@example.com")
      expect(delivery.status).to eq("pending")
      expect(delivery.metadata["category"]).to eq("security_alert")
      expect(WorkerJobService).to have_received(:enqueue_alert_email).once
    end

    it "returns no_recipients when no system.admin exists" do
      create(:user, account: create(:account), permissions: [ "users.manage" ])
      expect(described_class.send_alert(title: "x", message: "y")).to include(sent: 0, reason: "no_recipients")
    end
  end

  describe ".send_alert (account-scoped)" do
    it "emails only the given account's admins" do
      acct = create(:account)
      other = create(:account)
      create(:user, account: acct, permissions: [ "users.manage" ], email: "a@example.com")
      create(:user, account: other, permissions: [ "users.manage" ], email: "b@example.com")

      result = described_class.send_alert(title: "t", message: "m", account: acct)

      expect(result[:sent]).to eq(1)
      expect(EmailDelivery.find(result[:email_delivery_ids].first).recipient_email).to eq("a@example.com")
    end
  end

  describe "enqueue failure" do
    it "records the delivery as failed (no fabricated success)" do
      acct = create(:account)
      create(:user, account: acct, permissions: [ "system.admin" ], email: "s@example.com")
      allow(WorkerJobService).to receive(:enqueue_alert_email)
        .and_raise(WorkerJobService::WorkerServiceError.new("worker down"))

      result = described_class.send_alert(title: "t", message: "m")
      expect(EmailDelivery.find(result[:email_delivery_ids].first).status).to eq("failed")
    end
  end
end
