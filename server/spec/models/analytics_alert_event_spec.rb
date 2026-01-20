# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsAlertEvent, type: :model do
  let(:account) { create(:account) }
  let(:alert) { create(:analytics_alert, account: account) }

  describe "associations" do
    it { is_expected.to belong_to(:analytics_alert) }
    it { is_expected.to belong_to(:account).optional }
  end

  describe "validations" do
    subject { build(:analytics_alert_event, analytics_alert: alert) }

    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_inclusion_of(:event_type).in_array(%w[triggered resolved acknowledged escalated]) }
    it { is_expected.to validate_inclusion_of(:severity).in_array(%w[critical high medium low info]) }
  end

  describe "#triggered?" do
    it "returns true when event_type is triggered" do
      event = build(:analytics_alert_event, event_type: "triggered")
      expect(event.triggered?).to be true
    end

    it "returns false for other event types" do
      event = build(:analytics_alert_event, event_type: "resolved")
      expect(event.triggered?).to be false
    end
  end

  describe "#resolved?" do
    it "returns true when resolved is true" do
      event = build(:analytics_alert_event, resolved: true)
      expect(event.resolved?).to be true
    end
  end

  describe "#acknowledged?" do
    it "returns true when acknowledged is true" do
      event = build(:analytics_alert_event, acknowledged: true)
      expect(event.acknowledged?).to be true
    end
  end

  describe "#critical?" do
    it "returns true when severity is critical" do
      event = build(:analytics_alert_event, severity: "critical")
      expect(event.critical?).to be true
    end
  end

  describe "#acknowledge!" do
    let(:event) { create(:analytics_alert_event, analytics_alert: alert, event_type: "triggered") }

    it "sets acknowledged to true" do
      event.acknowledge!(by: "admin@example.com")
      expect(event.acknowledged).to be true
    end

    it "sets acknowledged_at" do
      event.acknowledge!(by: "admin@example.com")
      expect(event.acknowledged_at).to be_present
    end

    it "sets acknowledged_by" do
      event.acknowledge!(by: "admin@example.com")
      expect(event.acknowledged_by).to eq("admin@example.com")
    end
  end

  describe "#resolve!" do
    let(:event) { create(:analytics_alert_event, analytics_alert: alert, event_type: "triggered") }

    it "sets resolved to true" do
      event.resolve!(notes: "Issue fixed")
      expect(event.resolved).to be true
    end

    it "sets resolved_at" do
      event.resolve!(notes: "Issue fixed")
      expect(event.resolved_at).to be_present
    end

    it "sets resolution_notes" do
      event.resolve!(notes: "Issue fixed")
      expect(event.resolution_notes).to eq("Issue fixed")
    end
  end

  describe "#summary" do
    let(:event) { create(:analytics_alert_event, analytics_alert: alert) }

    it "returns summary hash" do
      summary = event.summary

      expect(summary).to include(:id, :alert_id, :event_type, :triggered_value)
      expect(summary).to include(:threshold_value, :message, :severity)
      expect(summary).to include(:acknowledged, :resolved, :created_at)
    end
  end

  describe "scopes" do
    let!(:triggered) { create(:analytics_alert_event, analytics_alert: alert, event_type: "triggered") }
    let!(:resolved_event) { create(:analytics_alert_event, analytics_alert: alert, event_type: "resolved", resolved: true) }
    let!(:acknowledged_event) { create(:analytics_alert_event, analytics_alert: alert, event_type: "triggered", acknowledged: true) }

    it "filters triggered events" do
      expect(described_class.triggered).to include(triggered, acknowledged_event)
      expect(described_class.triggered).not_to include(resolved_event)
    end

    it "filters unacknowledged triggered events" do
      unacked = described_class.unacknowledged
      expect(unacked).to include(triggered)
      expect(unacked).not_to include(acknowledged_event)
    end

    it "filters unresolved events" do
      unresolved = described_class.unresolved
      expect(unresolved).to include(triggered, acknowledged_event)
      expect(unresolved).not_to include(resolved_event)
    end

    it "filters by severity" do
      critical = create(:analytics_alert_event, analytics_alert: alert, severity: "critical")
      expect(described_class.by_severity("critical")).to include(critical)
    end

    it "filters by period" do
      old_event = create(:analytics_alert_event, analytics_alert: alert, created_at: 5.days.ago)
      recent_event = create(:analytics_alert_event, analytics_alert: alert, created_at: 1.day.ago)

      period_events = described_class.for_period(3.days.ago, Time.current)
      expect(period_events).to include(recent_event)
      expect(period_events).not_to include(old_event)
    end

    it "orders by recent" do
      events = described_class.recent
      expect(events.first.created_at).to be >= events.last.created_at
    end
  end
end
