# frozen_string_literal: true

require "rails_helper"

# Regression guard for IMP-f2cfaed728c4. The email channel used to enqueue
# "SendNotificationEmailJob", a class no worker app defines, so the worker
# answered 422 and the alert email silently never sent.
#
# The oracle is deliberately NOT "the enqueue call succeeded" — that succeeded
# against the bug too (pushing an HTTP payload is what worked). It asserts the
# two things that make an alert actually deliverable: a pending EmailDelivery
# ledger row, and dispatch onto the alert-email job whose worker-side terminal
# function exists.
RSpec.describe Monitoring::AlertingService, "email channel" do
  subject(:service) { described_class.new }

  let(:alert_email) { "ops@example.com" }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("ALERT_EMAIL").and_return(alert_email)
    allow(WorkerJobService).to receive(:enqueue_alert_email).and_return({ "status" => "queued" })
  end

  def send_email_alert
    service.send(:send_email_alert, "Disk almost full", "node-3 at 94%", :critical,
      { "node" => "node-3", "usage" => "94%" })
  end

  it "creates a pending EmailDelivery ledger row for the alert" do
    expect { send_email_alert }.to change(EmailDelivery, :count).by(1)

    delivery = EmailDelivery.order(:created_at).last
    expect(delivery.recipient_email).to eq(alert_email)
    expect(delivery.status).to eq("pending")
    expect(delivery.subject).to eq("[CRITICAL] Disk almost full")
  end

  it "dispatches the ledger row to the alert-email job" do
    result = send_email_alert

    expect(result[:success]).to be true
    expect(WorkerJobService).to have_received(:enqueue_alert_email) do |payload|
      expect(payload[:email_delivery_id]).to eq(EmailDelivery.order(:created_at).last.id)
      expect(payload[:recipient]).to eq(alert_email)
      expect(payload[:subject]).to eq("[CRITICAL] Disk almost full")
      expect(payload[:body]).to include("node-3 at 94%")
    end
  end

  # The name must be one the worker can constantize; Notifications::AlertEmailJob
  # is the only alert path whose worker-side chain terminates in a route that
  # exists (POST /api/v1/internal/emails/:id/delivered).
  it "routes through enqueue_alert_email, not the generic enqueue_job lane" do
    allow(WorkerJobService).to receive(:enqueue_job)

    send_email_alert

    expect(WorkerJobService).not_to have_received(:enqueue_job)
  end

  it "marks the ledger row failed when dispatch raises" do
    allow(WorkerJobService).to receive(:enqueue_alert_email)
      .and_raise(WorkerJobService::WorkerServiceError, "worker down")

    result = send_email_alert

    expect(result[:success]).to be false
    expect(EmailDelivery.order(:created_at).last.status).to eq("failed")
  end

  it "reports unconfigured rather than creating a row when no alert email is set" do
    allow(ENV).to receive(:[]).with("ALERT_EMAIL").and_return(nil)

    expect { expect(described_class.new.send(:send_email_alert, "t", "m", :critical, {})[:success]).to be false }
      .not_to change(EmailDelivery, :count)
  end
end
