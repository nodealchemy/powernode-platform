# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsAlert, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { is_expected.to belong_to(:account).optional }
    it { is_expected.to have_many(:alert_events).class_name("AnalyticsAlertEvent").dependent(:destroy) }
  end

  describe "validations" do
    subject { build(:analytics_alert) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:alert_type) }
    it { is_expected.to validate_presence_of(:metric_name) }
    it { is_expected.to validate_presence_of(:condition) }
    it { is_expected.to validate_presence_of(:threshold_value) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:alert_type).in_array(%w[threshold anomaly trend comparison]) }
    it { is_expected.to validate_inclusion_of(:condition).in_array(%w[greater_than less_than equals change_percent anomaly_detected]) }
    it { is_expected.to validate_inclusion_of(:status).in_array(%w[enabled disabled triggered resolved]) }
  end

  describe "#enabled?" do
    it "returns true when status is enabled" do
      alert = build(:analytics_alert, status: "enabled")
      expect(alert.enabled?).to be true
    end

    it "returns false when status is not enabled" do
      alert = build(:analytics_alert, status: "disabled")
      expect(alert.enabled?).to be false
    end
  end

  describe "#triggered?" do
    it "returns true when status is triggered" do
      alert = build(:analytics_alert, status: "triggered")
      expect(alert.triggered?).to be true
    end
  end

  describe "#in_cooldown?" do
    it "returns true when cooldown_until is in the future" do
      alert = build(:analytics_alert, cooldown_until: 30.minutes.from_now)
      expect(alert.in_cooldown?).to be true
    end

    it "returns false when cooldown_until is in the past" do
      alert = build(:analytics_alert, cooldown_until: 30.minutes.ago)
      expect(alert.in_cooldown?).to be false
    end

    it "returns false when cooldown_until is nil" do
      alert = build(:analytics_alert, cooldown_until: nil)
      expect(alert.in_cooldown?).to be false
    end
  end

  describe "#can_trigger?" do
    it "returns true when enabled and not in cooldown" do
      alert = build(:analytics_alert, status: "enabled", cooldown_until: nil)
      expect(alert.can_trigger?).to be true
    end

    it "returns false when disabled" do
      alert = build(:analytics_alert, status: "disabled")
      expect(alert.can_trigger?).to be false
    end

    it "returns false when in cooldown" do
      alert = build(:analytics_alert, status: "enabled", cooldown_until: 30.minutes.from_now)
      expect(alert.can_trigger?).to be false
    end
  end

  describe "#evaluate!" do
    context "greater_than condition" do
      let(:alert) { create(:analytics_alert, condition: "greater_than", threshold_value: 50000, status: "enabled") }

      it "triggers when value exceeds threshold" do
        expect(alert.evaluate!(60000)).to be true
        expect(alert.status).to eq("triggered")
      end

      it "does not trigger when value is below threshold" do
        expect(alert.evaluate!(40000)).to be false
        expect(alert.status).to eq("enabled")
      end
    end

    context "less_than condition" do
      let(:alert) { create(:analytics_alert, condition: "less_than", threshold_value: 100, status: "enabled") }

      it "triggers when value is below threshold" do
        expect(alert.evaluate!(50)).to be true
        expect(alert.status).to eq("triggered")
      end

      it "does not trigger when value is above threshold" do
        expect(alert.evaluate!(150)).to be false
      end
    end

    context "equals condition" do
      let(:alert) { create(:analytics_alert, condition: "equals", threshold_value: 100, status: "enabled") }

      it "triggers when value equals threshold" do
        expect(alert.evaluate!(100)).to be true
      end

      it "does not trigger when value does not equal threshold" do
        expect(alert.evaluate!(99)).to be false
      end
    end
  end

  describe "#trigger!" do
    let(:alert) { create(:analytics_alert, account: account, status: "enabled") }

    it "creates an alert event" do
      expect { alert.trigger!(60000) }.to change { alert.alert_events.count }.by(1)
    end

    it "updates status to triggered" do
      alert.trigger!(60000)
      expect(alert.status).to eq("triggered")
    end

    it "updates last_triggered_at" do
      expect { alert.trigger!(60000) }.to change { alert.last_triggered_at }
    end

    it "increments trigger_count" do
      expect { alert.trigger!(60000) }.to change { alert.trigger_count }.by(1)
    end

    it "sets cooldown_until" do
      alert.trigger!(60000)
      expect(alert.cooldown_until).to be_within(1.minute).of(alert.cooldown_minutes.minutes.from_now)
    end
  end

  describe "#resolve!" do
    let(:alert) { create(:analytics_alert, :triggered, account: account) }

    it "updates status to resolved" do
      alert.resolve!
      expect(alert.status).to eq("resolved")
    end

    it "creates a resolved event" do
      expect { alert.resolve!(notes: "Issue fixed") }.to change { alert.alert_events.count }.by(1)
      expect(alert.alert_events.last.event_type).to eq("resolved")
    end

    it "does not resolve if not triggered" do
      alert.update!(status: "enabled")
      alert.resolve!
      expect(alert.status).to eq("enabled")
    end
  end

  describe "#acknowledge!" do
    let(:alert) { create(:analytics_alert, :triggered, account: account) }

    before do
      alert.trigger!(60000)
    end

    it "marks the last triggered event as acknowledged" do
      alert.acknowledge!(by: "admin@example.com")
      last_event = alert.alert_events.where(event_type: "triggered").order(created_at: :desc).first
      expect(last_event.acknowledged).to be true
      expect(last_event.acknowledged_by).to eq("admin@example.com")
    end
  end

  describe "#summary" do
    let(:alert) { create(:analytics_alert) }

    it "returns summary hash" do
      summary = alert.summary

      expect(summary).to include(:id, :name, :alert_type, :metric_name)
      expect(summary).to include(:condition, :threshold_value, :current_value, :status)
    end
  end

  describe "notification channels" do
    let(:alert) do
      create(:analytics_alert,
        notification_channels: [ "email:admin@example.com", "slack:#alerts", "webhook:https://example.com/webhook" ]
      )
    end

    it "stores multiple notification channels" do
      expect(alert.notification_channels).to include("email:admin@example.com")
      expect(alert.notification_channels).to include("slack:#alerts")
    end
  end

  describe "scopes" do
    let!(:enabled) { create(:analytics_alert, status: "enabled") }
    let!(:disabled) { create(:analytics_alert, status: "disabled") }
    let!(:triggered) { create(:analytics_alert, status: "triggered") }

    it "filters enabled alerts" do
      expect(described_class.enabled).to include(enabled)
      expect(described_class.enabled).not_to include(disabled, triggered)
    end

    it "filters triggered alerts" do
      expect(described_class.triggered).to include(triggered)
      expect(described_class.triggered).not_to include(enabled, disabled)
    end

    it "filters platform_wide alerts" do
      platform = create(:analytics_alert, account: nil)
      account_alert = create(:analytics_alert, account: account)

      expect(described_class.platform_wide).to include(platform)
      expect(described_class.platform_wide).not_to include(account_alert)
    end

    it "filters due_for_check alerts" do
      never_checked = create(:analytics_alert, status: "enabled", last_checked_at: nil)
      recently_checked = create(:analytics_alert, status: "enabled", last_checked_at: 1.minute.ago)
      old_check = create(:analytics_alert, status: "enabled", last_checked_at: 10.minutes.ago)

      due = described_class.due_for_check
      expect(due).to include(never_checked, old_check)
      expect(due).not_to include(recently_checked)
    end
  end
end
