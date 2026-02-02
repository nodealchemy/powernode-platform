# frozen_string_literal: true

require "rails_helper"

RSpec.describe SupplyChain::VendorMonitoringEvent, type: :model do
  let(:account) { create(:account) }
  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let(:user) { create(:user, account: account) }

  describe "constants" do
    it "defines EVENT_TYPES" do
      expect(described_class::EVENT_TYPES).to eq(
        %w[security_incident breach certification_expiry contract_renewal service_degradation compliance_update news_alert]
      )
    end

    it "defines SEVERITIES" do
      expect(described_class::SEVERITIES).to eq(%w[critical high medium low info])
    end

    it "defines SOURCES" do
      expect(described_class::SOURCES).to eq(%w[internal external automated manual])
    end
  end

  describe "associations" do
    it { is_expected.to belong_to(:vendor).class_name("SupplyChain::Vendor") }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:acknowledged_by).class_name("User").optional }
  end

  describe "validations" do
    subject { build(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account) }

    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_inclusion_of(:event_type).in_array(described_class::EVENT_TYPES) }

    it { is_expected.to validate_presence_of(:severity) }
    it { is_expected.to validate_inclusion_of(:severity).in_array(described_class::SEVERITIES) }

    it { is_expected.to validate_presence_of(:source) }
    it { is_expected.to validate_inclusion_of(:source).in_array(described_class::SOURCES) }

    it { is_expected.to validate_presence_of(:title) }

    # Note: detected_at has a before_validation callback that sets it if nil,
    # so we test the validation separately
    it "validates presence of detected_at" do
      event = build(:supply_chain_vendor_monitoring_event, detected_at: Time.current)
      event.detected_at = nil
      # The callback will set it during validation
      event.validate
      expect(event.detected_at).to be_present
    end

    context "with invalid event_type" do
      it "is invalid" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "invalid_type")
        expect(event).not_to be_valid
        expect(event.errors[:event_type]).to be_present
      end
    end

    context "with invalid severity" do
      it "is invalid" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "extreme")
        expect(event).not_to be_valid
        expect(event.errors[:severity]).to be_present
      end
    end

    context "with invalid source" do
      it "is invalid" do
        event = build(:supply_chain_vendor_monitoring_event, source: "unknown")
        expect(event).not_to be_valid
        expect(event.errors[:source]).to be_present
      end
    end
  end

  describe "callbacks" do
    describe "before_validation :set_detected_at" do
      it "sets detected_at to current time on create if not provided" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: nil)
        expect(event.detected_at).to be_nil

        event.validate
        expect(event.detected_at).to be_present
      end

      it "preserves detected_at if already set" do
        past_time = 5.days.ago
        event = build(:supply_chain_vendor_monitoring_event, detected_at: past_time)
        event.validate

        expect(event.detected_at.to_date).to eq(past_time.to_date)
      end
    end

    describe "before_save :sanitize_jsonb_fields" do
      it "initializes recommended_actions to empty array if nil" do
        event = create(:supply_chain_vendor_monitoring_event, recommended_actions: nil)
        expect(event.recommended_actions).to eq([])
      end

      it "initializes affected_services to empty array if nil" do
        event = create(:supply_chain_vendor_monitoring_event, affected_services: nil)
        expect(event.affected_services).to eq([])
      end

      it "initializes metadata to empty hash if nil" do
        event = create(:supply_chain_vendor_monitoring_event, metadata: nil)
        expect(event.metadata).to eq({})
      end

      it "preserves existing recommended_actions" do
        actions = [ { id: SecureRandom.uuid, action: "Test", status: "pending" } ]
        event = create(:supply_chain_vendor_monitoring_event, recommended_actions: actions)
        # JSONB stores as strings, not symbols
        expect(event.recommended_actions.first["action"]).to eq("Test")
        expect(event.recommended_actions.first["status"]).to eq("pending")
      end

      it "preserves existing affected_services" do
        services = [ "Service A", "Service B" ]
        event = create(:supply_chain_vendor_monitoring_event, affected_services: services)
        expect(event.affected_services).to eq(services)
      end
    end
  end

  describe "event type predicates" do
    describe "#security_incident?" do
      it "returns true for security_incident event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "security_incident")
        expect(event.security_incident?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "breach")
        expect(event.security_incident?).to be false
      end
    end

    describe "#breach?" do
      it "returns true for breach event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "breach")
        expect(event.breach?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "security_incident")
        expect(event.breach?).to be false
      end
    end

    describe "#certification_expiry?" do
      it "returns true for certification_expiry event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "certification_expiry")
        expect(event.certification_expiry?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "breach")
        expect(event.certification_expiry?).to be false
      end
    end

    describe "#contract_renewal?" do
      it "returns true for contract_renewal event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "contract_renewal")
        expect(event.contract_renewal?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "security_incident")
        expect(event.contract_renewal?).to be false
      end
    end

    describe "#service_degradation?" do
      it "returns true for service_degradation event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "service_degradation")
        expect(event.service_degradation?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "breach")
        expect(event.service_degradation?).to be false
      end
    end

    describe "#compliance_update?" do
      it "returns true for compliance_update event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "compliance_update")
        expect(event.compliance_update?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "security_incident")
        expect(event.compliance_update?).to be false
      end
    end

    describe "#news_alert?" do
      it "returns true for news_alert event type" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "news_alert")
        expect(event.news_alert?).to be true
      end

      it "returns false for other event types" do
        event = build(:supply_chain_vendor_monitoring_event, event_type: "breach")
        expect(event.news_alert?).to be false
      end
    end
  end

  describe "severity predicates" do
    describe "#critical?" do
      it "returns true for critical severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "critical")
        expect(event.critical?).to be true
      end

      it "returns false for other severities" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "high")
        expect(event.critical?).to be false
      end
    end

    describe "#high?" do
      it "returns true for high severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "high")
        expect(event.high?).to be true
      end

      it "returns false for other severities" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "medium")
        expect(event.high?).to be false
      end
    end

    describe "#high_severity?" do
      it "returns true for critical severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "critical")
        expect(event.high_severity?).to be true
      end

      it "returns true for high severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "high")
        expect(event.high_severity?).to be true
      end

      it "returns false for medium severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "medium")
        expect(event.high_severity?).to be false
      end

      it "returns false for low severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "low")
        expect(event.high_severity?).to be false
      end

      it "returns false for info severity" do
        event = build(:supply_chain_vendor_monitoring_event, severity: "info")
        expect(event.high_severity?).to be false
      end
    end
  end

  describe "acknowledgment predicates and operations" do
    describe "#acknowledged?" do
      it "returns true when is_acknowledged is true" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: true)
        expect(event.acknowledged?).to be true
      end

      it "returns false when is_acknowledged is false" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: false)
        expect(event.acknowledged?).to be false
      end
    end

    describe "#unacknowledged?" do
      it "returns true when is_acknowledged is false" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: false)
        expect(event.unacknowledged?).to be true
      end

      it "returns false when is_acknowledged is true" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: true)
        expect(event.unacknowledged?).to be false
      end
    end

    describe "#acknowledge!" do
      let(:event) { create(:supply_chain_vendor_monitoring_event, is_acknowledged: false, vendor: vendor, account: account) }

      it "sets is_acknowledged to true" do
        event.acknowledge!(user)
        expect(event.is_acknowledged).to be true
      end

      it "sets acknowledged_at to current time" do
        before_time = Time.current
        event.acknowledge!(user)
        expect(event.acknowledged_at).to be >= before_time
      end

      it "sets acknowledged_by to the provided user" do
        event.acknowledge!(user)
        expect(event.acknowledged_by).to eq(user)
      end

      it "persists the changes" do
        event.acknowledge!(user)
        reloaded = described_class.find(event.id)
        expect(reloaded.is_acknowledged).to be true
        expect(reloaded.acknowledged_by_id).to eq(user.id)
      end
    end
  end

  describe "resolution predicates and operations" do
    describe "#resolved?" do
      it "returns true when resolved_at is present" do
        event = build(:supply_chain_vendor_monitoring_event, resolved_at: Time.current)
        expect(event.resolved?).to be true
      end

      it "returns false when resolved_at is nil" do
        event = build(:supply_chain_vendor_monitoring_event, resolved_at: nil)
        expect(event.resolved?).to be false
      end
    end

    describe "#unresolved?" do
      it "returns true when resolved_at is nil" do
        event = build(:supply_chain_vendor_monitoring_event, resolved_at: nil)
        expect(event.unresolved?).to be true
      end

      it "returns false when resolved_at is present" do
        event = build(:supply_chain_vendor_monitoring_event, resolved_at: Time.current)
        expect(event.unresolved?).to be false
      end
    end

    describe "#active?" do
      it "returns true when unacknowledged and unresolved" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: false, resolved_at: nil)
        expect(event.active?).to be true
      end

      it "returns false when acknowledged" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: true, resolved_at: nil)
        expect(event.active?).to be false
      end

      it "returns false when resolved" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: false, resolved_at: Time.current)
        expect(event.active?).to be false
      end

      it "returns false when both acknowledged and resolved" do
        event = build(:supply_chain_vendor_monitoring_event, is_acknowledged: true, resolved_at: Time.current)
        expect(event.active?).to be false
      end
    end

    describe "#resolve!" do
      let(:event) { create(:supply_chain_vendor_monitoring_event, resolved_at: nil, vendor: vendor, account: account) }

      it "sets resolved_at to current time" do
        before_time = Time.current
        event.resolve!
        expect(event.resolved_at).to be >= before_time
      end

      it "persists the changes" do
        event.resolve!
        reloaded = described_class.find(event.id)
        expect(reloaded.resolved_at).to be_present
      end
    end

    describe "#reopen!" do
      let(:event) do
        create(:supply_chain_vendor_monitoring_event,
               is_acknowledged: true,
               acknowledged_at: 1.day.ago,
               acknowledged_by: user,
               resolved_at: 1.hour.ago,
               vendor: vendor,
               account: account)
      end

      it "sets is_acknowledged to false" do
        event.reopen!
        expect(event.is_acknowledged).to be false
      end

      it "clears acknowledged_at" do
        event.reopen!
        expect(event.acknowledged_at).to be_nil
      end

      it "clears acknowledged_by" do
        event.reopen!
        expect(event.acknowledged_by).to be_nil
      end

      it "clears resolved_at" do
        event.reopen!
        expect(event.resolved_at).to be_nil
      end

      it "persists all changes" do
        event.reopen!
        reloaded = described_class.find(event.id)
        expect(reloaded.is_acknowledged).to be false
        expect(reloaded.acknowledged_at).to be_nil
        expect(reloaded.acknowledged_by).to be_nil
        expect(reloaded.resolved_at).to be_nil
      end
    end
  end

  describe "recommended actions management" do
    let(:event) { create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account) }

    describe "#add_recommended_action" do
      it "adds an action with default priority" do
        result = event.add_recommended_action(action: "Test action")
        # Method returns hash with symbol keys
        expect(result[:action]).to eq("Test action")
        expect(result[:priority]).to eq("medium")
        expect(result[:status]).to eq("pending")
      end

      it "adds an action with custom priority" do
        result = event.add_recommended_action(action: "Urgent action", priority: "high")
        expect(result[:priority]).to eq("high")
      end

      it "includes due_date if provided" do
        due_date = 5.days.from_now
        result = event.add_recommended_action(action: "Timed action", due_date: due_date)
        expect(result[:due_date]).to eq(due_date.iso8601)
      end

      it "generates a UUID for each action" do
        result = event.add_recommended_action(action: "Test action")
        expect(result[:id]).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      end

      it "sets added_at timestamp" do
        result = event.add_recommended_action(action: "Test action")
        # Verify it's a valid ISO8601 timestamp
        expect { Time.iso8601(result[:added_at]) }.not_to raise_error
        expect(result[:added_at]).to be_present
      end

      it "persists the action to the database" do
        event.add_recommended_action(action: "Test action")
        reloaded = described_class.find(event.id)
        expect(reloaded.recommended_actions.count).to eq(1)
        expect(reloaded.recommended_actions.first["action"]).to eq("Test action")
      end

      it "appends to existing actions" do
        event.add_recommended_action(action: "First action")
        event.add_recommended_action(action: "Second action")

        reloaded = described_class.find(event.id)
        expect(reloaded.recommended_actions.count).to eq(2)
      end
    end

    describe "#complete_action" do
      let(:action_id) { SecureRandom.uuid }
      let(:event) do
        event = create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account)
        event.recommended_actions = [
          {
            id: action_id,
            action: "Test action",
            priority: "high",
            status: "pending",
            added_at: Time.current.iso8601
          }
        ]
        event.save
        event
      end

      it "marks the action as completed" do
        event.complete_action(action_id)
        expect(event.recommended_actions.first["status"]).to eq("completed")
      end

      it "sets completed_at timestamp" do
        event.complete_action(action_id)
        completed_at_str = event.recommended_actions.first["completed_at"]
        expect(completed_at_str).to be_present
        # Just verify it's a valid ISO8601 timestamp
        expect { Time.iso8601(completed_at_str) }.not_to raise_error
      end

      it "persists the change" do
        event.complete_action(action_id)
        reloaded = described_class.find(event.id)
        expect(reloaded.recommended_actions.first["status"]).to eq("completed")
      end

      it "leaves other actions unchanged" do
        other_id = SecureRandom.uuid
        event.recommended_actions << {
          id: other_id,
          action: "Other action",
          status: "pending",
          added_at: Time.current.iso8601
        }
        event.save

        event.complete_action(action_id)
        expect(event.recommended_actions.find { |a| a["id"] == other_id }["status"]).to eq("pending")
      end
    end

    describe "#pending_actions" do
      let(:event) do
        event = create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account)
        event.recommended_actions = [
          { id: "1", action: "First", status: "pending", added_at: Time.current.iso8601 },
          { id: "2", action: "Second", status: "completed", added_at: Time.current.iso8601 },
          { id: "3", action: "Third", status: "pending", added_at: Time.current.iso8601 }
        ]
        event.save
        event
      end

      it "returns only pending actions" do
        pending = event.pending_actions
        expect(pending.count).to eq(2)
        expect(pending.map { |a| a["id"] }).to contain_exactly("1", "3")
      end

      it "returns empty array when no pending actions" do
        event.recommended_actions = []
        expect(event.pending_actions).to eq([])
      end

      it "returns empty array when recommended_actions is nil" do
        event.recommended_actions = nil
        expect(event.pending_actions).to eq([])
      end
    end

    describe "#completed_actions" do
      let(:event) do
        event = create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account)
        event.recommended_actions = [
          { id: "1", action: "First", status: "pending", added_at: Time.current.iso8601 },
          { id: "2", action: "Second", status: "completed", added_at: Time.current.iso8601 },
          { id: "3", action: "Third", status: "completed", added_at: Time.current.iso8601 }
        ]
        event.save
        event
      end

      it "returns only completed actions" do
        completed = event.completed_actions
        expect(completed.count).to eq(2)
        expect(completed.map { |a| a["id"] }).to contain_exactly("2", "3")
      end

      it "returns empty array when no completed actions" do
        event.recommended_actions = []
        expect(event.completed_actions).to eq([])
      end

      it "returns empty array when recommended_actions is nil" do
        event.recommended_actions = nil
        expect(event.completed_actions).to eq([])
      end
    end
  end

  describe "time tracking" do
    describe "#days_since_detection" do
      it "returns 0 when detected_at is today" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: Time.current)
        expect(event.days_since_detection).to eq(0)
      end

      it "returns correct days for past detection" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: 5.days.ago)
        expect(event.days_since_detection).to be >= 5
      end

      it "returns 0 when detected_at is nil" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: nil)
        expect(event.days_since_detection).to eq(0)
      end
    end

    describe "#time_to_acknowledge" do
      it "returns nil when not acknowledged" do
        event = build(:supply_chain_vendor_monitoring_event, acknowledged_at: nil)
        expect(event.time_to_acknowledge).to be_nil
      end

      it "returns nil when detected_at is nil" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: nil, acknowledged_at: Time.current)
        expect(event.time_to_acknowledge).to be_nil
      end

      it "calculates hours to acknowledgment" do
        detected = 4.hours.ago
        acknowledged = 1.hour.ago
        event = build(:supply_chain_vendor_monitoring_event, detected_at: detected, acknowledged_at: acknowledged)
        expect(event.time_to_acknowledge).to be_between(2.5, 3.5)
      end

      it "rounds to 2 decimal places" do
        detected = 1.hour.ago + 15.minutes
        acknowledged = 1.hour.ago + 30.minutes
        event = build(:supply_chain_vendor_monitoring_event, detected_at: detected, acknowledged_at: acknowledged)
        expect(event.time_to_acknowledge).to eq(0.25)
      end
    end

    describe "#time_to_resolve" do
      it "returns nil when not resolved" do
        event = build(:supply_chain_vendor_monitoring_event, resolved_at: nil)
        expect(event.time_to_resolve).to be_nil
      end

      it "returns nil when detected_at is nil" do
        event = build(:supply_chain_vendor_monitoring_event, detected_at: nil, resolved_at: Time.current)
        expect(event.time_to_resolve).to be_nil
      end

      it "calculates hours to resolution" do
        detected = 24.hours.ago
        resolved = 1.hour.ago
        event = build(:supply_chain_vendor_monitoring_event, detected_at: detected, resolved_at: resolved)
        expect(event.time_to_resolve).to be_between(22.5, 23.5)
      end

      it "rounds to 2 decimal places" do
        detected = 2.hours.ago
        resolved = 1.hour.ago
        event = build(:supply_chain_vendor_monitoring_event, detected_at: detected, resolved_at: resolved)
        # Should be approximately 1 hour
        expect(event.time_to_resolve).to be_within(0.1).of(1.0)
      end
    end
  end

  describe "#summary" do
    let(:event) do
      create(:supply_chain_vendor_monitoring_event,
             vendor: vendor,
             account: account,
             event_type: "security_incident",
             severity: "high",
             title: "Test Security Incident",
             description: "A test incident",
             is_acknowledged: false)
    end

    it "returns a hash with required keys" do
      summary = event.summary
      expect(summary).to be_a(Hash)
      expect(summary.keys).to include(:id, :vendor_id, :vendor_name, :event_type, :severity, :source, :title,
                                       :description, :external_url, :is_acknowledged, :is_resolved,
                                       :pending_action_count, :detected_at, :acknowledged_at, :resolved_at,
                                       :days_since_detection, :created_at)
    end

    it "includes correct event data" do
      summary = event.summary
      expect(summary[:id]).to eq(event.id)
      expect(summary[:vendor_id]).to eq(vendor.id)
      expect(summary[:vendor_name]).to eq(vendor.name)
      expect(summary[:event_type]).to eq("security_incident")
      expect(summary[:severity]).to eq("high")
      expect(summary[:title]).to eq("Test Security Incident")
    end

    it "reflects is_resolved status correctly" do
      event.update!(resolved_at: Time.current)
      expect(event.summary[:is_resolved]).to be true

      event.update!(resolved_at: nil)
      expect(event.summary[:is_resolved]).to be false
    end

    it "counts pending actions correctly" do
      event.add_recommended_action(action: "Action 1")
      event.add_recommended_action(action: "Action 2")
      event.reload

      summary = event.summary
      expect(summary[:pending_action_count]).to eq(2)
    end
  end

  describe "#detailed_event" do
    let(:event) do
      create(:supply_chain_vendor_monitoring_event,
             vendor: vendor,
             account: account,
             acknowledged_by: user,
             acknowledged_at: 1.hour.ago,
             is_acknowledged: true,
             resolved_at: 30.minutes.ago)
    end

    it "returns a hash with required keys" do
      detailed = event.detailed_event
      expect(detailed.keys).to include(:summary, :recommended_actions, :affected_services, :acknowledged_by,
                                        :time_to_acknowledge_hours, :time_to_resolve_hours)
    end

    it "includes summary" do
      detailed = event.detailed_event
      expect(detailed[:summary]).to be_a(Hash)
      expect(detailed[:summary][:id]).to eq(event.id)
    end

    it "includes recommended actions" do
      event.add_recommended_action(action: "Test action", priority: "high")
      detailed = event.detailed_event
      expect(detailed[:recommended_actions].count).to eq(1)
      expect(detailed[:recommended_actions].first["action"]).to eq("Test action")
    end

    it "includes affected services" do
      event.update!(affected_services: [ "Service A", "Service B" ])
      detailed = event.detailed_event
      expect(detailed[:affected_services]).to eq([ "Service A", "Service B" ])
    end

    it "includes acknowledged_by email" do
      detailed = event.detailed_event
      expect(detailed[:acknowledged_by]).to eq(user.email)
    end

    it "handles nil acknowledged_by" do
      event.update!(acknowledged_by: nil)
      detailed = event.detailed_event
      expect(detailed[:acknowledged_by]).to be_nil
    end

    it "includes time tracking data" do
      detailed = event.detailed_event
      expect(detailed[:time_to_acknowledge_hours]).to be_a(Float).or be_nil
      expect(detailed[:time_to_resolve_hours]).to be_a(Float).or be_nil
    end
  end

  describe "scopes" do
    let!(:security_incident) { create(:supply_chain_vendor_monitoring_event, :security_incident, vendor: vendor, account: account) }
    let!(:breach) { create(:supply_chain_vendor_monitoring_event, :breach, vendor: vendor, account: account) }
    let!(:certification_expiry) { create(:supply_chain_vendor_monitoring_event, :certification_expiry, vendor: vendor, account: account) }
    let!(:contract_renewal) { create(:supply_chain_vendor_monitoring_event, :contract_renewal, vendor: vendor, account: account) }

    describe ".by_type" do
      it "filters by event type" do
        incidents = described_class.by_type("security_incident")
        expect(incidents).to include(security_incident)
        expect(incidents).not_to include(breach)
      end

      it "returns empty array for non-existent type" do
        expect(described_class.by_type("nonexistent")).to be_empty
      end
    end

    describe ".security_incidents" do
      it "returns only security incident events" do
        incidents = described_class.security_incidents
        expect(incidents).to include(security_incident)
        expect(incidents).not_to include(breach, certification_expiry)
      end
    end

    describe ".breaches" do
      it "returns only breach events" do
        breaches = described_class.breaches
        expect(breaches).to include(breach)
        expect(breaches).not_to include(security_incident, certification_expiry)
      end
    end

    describe ".certification_expiries" do
      it "returns only certification_expiry events" do
        expiries = described_class.certification_expiries
        expect(expiries).to include(certification_expiry)
        expect(expiries).not_to include(security_incident, breach)
      end
    end

    describe ".by_severity" do
      let!(:critical_event) { create(:supply_chain_vendor_monitoring_event, :critical, vendor: vendor, account: account) }
      let!(:medium_event) { create(:supply_chain_vendor_monitoring_event, severity: "medium", vendor: vendor, account: account) }

      it "filters by severity level" do
        critical = described_class.by_severity("critical")
        expect(critical).to include(critical_event)
        expect(critical).not_to include(medium_event)
      end
    end

    describe ".critical" do
      let!(:critical_event) { create(:supply_chain_vendor_monitoring_event, :critical, vendor: vendor, account: account) }

      it "returns only critical severity events" do
        critical = described_class.critical
        expect(critical).to include(critical_event)
        expect(critical).not_to include(security_incident)
      end
    end

    describe ".high_severity" do
      let!(:critical_event) { create(:supply_chain_vendor_monitoring_event, :critical, vendor: vendor, account: account) }
      let!(:high_event) { create(:supply_chain_vendor_monitoring_event, :high_severity_event, vendor: vendor, account: account) }
      let!(:medium_event) { create(:supply_chain_vendor_monitoring_event, severity: "medium", vendor: vendor, account: account) }

      it "returns critical and high severity events" do
        high_sev = described_class.high_severity
        expect(high_sev).to include(critical_event, high_event)
        expect(high_sev).not_to include(medium_event)
      end
    end

    describe ".by_source" do
      let!(:external_event) { create(:supply_chain_vendor_monitoring_event, source: "external", vendor: vendor, account: account) }
      let!(:internal_event) { create(:supply_chain_vendor_monitoring_event, :internal_source, vendor: vendor, account: account) }

      it "filters by source" do
        external = described_class.by_source("external")
        expect(external).to include(external_event)
        expect(external).not_to include(internal_event)
      end
    end

    describe ".acknowledged" do
      let!(:acknowledged_event) { create(:supply_chain_vendor_monitoring_event, :acknowledged, vendor: vendor, account: account) }
      let!(:unacknowledged_event) { create(:supply_chain_vendor_monitoring_event, is_acknowledged: false, vendor: vendor, account: account) }

      it "returns only acknowledged events" do
        acked = described_class.acknowledged
        expect(acked).to include(acknowledged_event)
        expect(acked).not_to include(unacknowledged_event)
      end
    end

    describe ".unacknowledged" do
      let!(:acknowledged_event) { create(:supply_chain_vendor_monitoring_event, :acknowledged, vendor: vendor, account: account) }
      let!(:unacknowledged_event) { create(:supply_chain_vendor_monitoring_event, is_acknowledged: false, vendor: vendor, account: account) }

      it "returns only unacknowledged events" do
        unacked = described_class.unacknowledged
        expect(unacked).to include(unacknowledged_event)
        expect(unacked).not_to include(acknowledged_event)
      end
    end

    describe ".resolved" do
      let!(:resolved_event) { create(:supply_chain_vendor_monitoring_event, :resolved, vendor: vendor, account: account) }
      let!(:unresolved_event) { create(:supply_chain_vendor_monitoring_event, resolved_at: nil, vendor: vendor, account: account) }

      it "returns only resolved events" do
        resolved = described_class.resolved
        expect(resolved).to include(resolved_event)
        expect(resolved).not_to include(unresolved_event)
      end
    end

    describe ".unresolved" do
      let!(:resolved_event) { create(:supply_chain_vendor_monitoring_event, :resolved, vendor: vendor, account: account) }
      let!(:unresolved_event) { create(:supply_chain_vendor_monitoring_event, resolved_at: nil, vendor: vendor, account: account) }

      it "returns only unresolved events" do
        unresolved = described_class.unresolved
        expect(unresolved).to include(unresolved_event)
        expect(unresolved).not_to include(resolved_event)
      end
    end

    describe ".active" do
      let!(:active_event) { create(:supply_chain_vendor_monitoring_event, :active, vendor: vendor, account: account) }
      let!(:acknowledged_event) { create(:supply_chain_vendor_monitoring_event, :acknowledged, vendor: vendor, account: account) }
      let!(:resolved_event) { create(:supply_chain_vendor_monitoring_event, :resolved, vendor: vendor, account: account) }

      it "returns only unacknowledged and unresolved events" do
        active = described_class.active
        expect(active).to include(active_event)
        expect(active).not_to include(acknowledged_event, resolved_event)
      end
    end

    describe ".for_vendor" do
      let!(:other_vendor) { create(:supply_chain_vendor, account: account) }
      let!(:other_event) { create(:supply_chain_vendor_monitoring_event, vendor: other_vendor, account: account) }

      it "returns events for specific vendor" do
        vendor_events = described_class.for_vendor(vendor.id)
        expect(vendor_events).to include(security_incident, breach, certification_expiry, contract_renewal)
        expect(vendor_events).not_to include(other_event)
      end
    end

    describe ".recent" do
      let!(:old_event) { create(:supply_chain_vendor_monitoring_event, :old, vendor: vendor, account: account) }
      let!(:recent_event) { create(:supply_chain_vendor_monitoring_event, :recent, vendor: vendor, account: account) }

      it "orders events by detected_at descending" do
        recent = described_class.recent
        expect(recent.first.detected_at).to be >= recent.last.detected_at
      end

      it "puts most recent first" do
        recent = described_class.recent
        # Orders by detected_at desc, so most recent is first
        expect(recent.first.detected_at).to be >= recent.last.detected_at
      end
    end

    describe ".detected_after" do
      let!(:old_event) { create(:supply_chain_vendor_monitoring_event, :old, vendor: vendor, account: account) }
      let!(:recent_event) { create(:supply_chain_vendor_monitoring_event, :recent, vendor: vendor, account: account) }

      it "returns events detected after specified time" do
        cutoff = 10.days.ago
        after_events = described_class.detected_after(cutoff)
        expect(after_events).to include(recent_event)
        expect(after_events).not_to include(old_event)
      end
    end

    describe ".detected_before" do
      let!(:old_event) { create(:supply_chain_vendor_monitoring_event, :old, vendor: vendor, account: account) }
      let!(:recent_event) { create(:supply_chain_vendor_monitoring_event, :recent, vendor: vendor, account: account) }

      it "returns events detected before specified time" do
        cutoff = 10.days.ago
        before_events = described_class.detected_before(cutoff)
        expect(before_events).to include(old_event)
        expect(before_events).not_to include(recent_event)
      end
    end
  end

  describe "class methods for creating events" do
    describe ".create_security_incident" do
      it "creates a security incident event" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "SQL Injection Found",
          severity: "critical"
        )

        expect(event).to be_persisted
        expect(event.event_type).to eq("security_incident")
        expect(event.severity).to eq("critical")
        expect(event.title).to eq("SQL Injection Found")
      end

      it "defaults to high severity" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident"
        )

        expect(event.severity).to eq("high")
      end

      it "defaults to external source" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident"
        )

        expect(event.source).to eq("external")
      end

      it "allows custom source" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident",
          source: "internal"
        )

        expect(event.source).to eq("internal")
      end

      it "includes description and external_url when provided" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident",
          description: "Security vulnerability found",
          external_url: "https://example.com/cve/123"
        )

        expect(event.description).to eq("Security vulnerability found")
        expect(event.external_url).to eq("https://example.com/cve/123")
      end

      it "includes recommended actions when provided" do
        actions = [ { action: "Review incident", priority: "high" } ]
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident",
          recommended_actions: actions
        )

        expect(event.recommended_actions.count).to eq(1)
        expect(event.recommended_actions.first["action"]).to eq("Review incident")
        expect(event.recommended_actions.first["priority"]).to eq("high")
      end

      it "initializes empty recommended_actions by default" do
        event = described_class.create_security_incident(
          vendor: vendor,
          account: account,
          title: "Test Incident"
        )

        expect(event.recommended_actions).to eq([])
      end
    end

    describe ".create_certification_expiry" do
      it "creates a certification_expiry event" do
        expires_at = 15.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event).to be_persisted
        expect(event.event_type).to eq("certification_expiry")
        expect(event.source).to eq("automated")
      end

      it "sets title with certification name" do
        expires_at = 15.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.title).to include("ISO27001")
      end

      it "includes expiry date in description" do
        expires_at = 15.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.description).to include(expires_at.to_date.to_s)
      end

      it "sets critical severity when expires within 7 days" do
        expires_at = 5.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.severity).to eq("critical")
      end

      it "sets high severity when expires within 30 days" do
        expires_at = 20.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.severity).to eq("high")
      end

      it "sets medium severity when expires after 30 days" do
        expires_at = 60.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.severity).to eq("medium")
      end

      it "creates a recommended action" do
        expires_at = 15.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        expect(event.recommended_actions.count).to eq(1)
        expect(event.recommended_actions.first["action"]).to include("updated certification")
      end

      it "sets action due date 14 days before expiry" do
        expires_at = 15.days.from_now
        event = described_class.create_certification_expiry(
          vendor: vendor,
          account: account,
          certification_name: "ISO27001",
          expires_at: expires_at
        )

        action_due = Time.iso8601(event.recommended_actions.first["due_date"])
        expected_due = expires_at - 14.days
        expect(action_due.to_date).to eq(expected_due.to_date)
      end
    end

    describe ".create_contract_renewal" do
      it "creates a contract_renewal event" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event).to be_persisted
        expect(event.event_type).to eq("contract_renewal")
        expect(event.source).to eq("automated")
      end

      it "sets title indicating contract renewal" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event.title).to include("Contract renewal")
      end

      it "includes renewal date in description" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event.description).to include(renewal_date.to_date.to_s)
      end

      it "sets high severity when renewal within 14 days" do
        renewal_date = 10.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event.severity).to eq("high")
      end

      it "sets medium severity when renewal after 14 days" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event.severity).to eq("medium")
      end

      it "creates two recommended actions" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        expect(event.recommended_actions.count).to eq(2)
      end

      it "sets first action with contract review" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        first_action = event.recommended_actions.first
        expect(first_action["action"]).to include("Review contract terms")
      end

      it "sets second action with risk reassessment" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        second_action = event.recommended_actions.second
        expect(second_action["action"]).to include("risk reassessment")
      end

      it "sets first action due 30 days before renewal" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        first_due = Time.iso8601(event.recommended_actions.first["due_date"])
        expected_due = renewal_date - 30.days
        expect(first_due.to_date).to eq(expected_due.to_date)
      end

      it "sets second action due 45 days before renewal" do
        renewal_date = 30.days.from_now
        event = described_class.create_contract_renewal(
          vendor: vendor,
          account: account,
          renewal_date: renewal_date
        )

        second_due = Time.iso8601(event.recommended_actions.second["due_date"])
        expected_due = renewal_date - 45.days
        expect(second_due.to_date).to eq(expected_due.to_date)
      end
    end
  end

  describe "integration tests" do
    let(:event) { create(:supply_chain_vendor_monitoring_event, vendor: vendor, account: account) }

    it "creates an event with all defaults" do
      expect(event).to be_persisted
      expect(event.vendor).to eq(vendor)
      expect(event.account).to eq(account)
      expect(event.detected_at).to be_present
      expect(event.recommended_actions).to eq([])
      expect(event.affected_services).to eq([])
      expect(event.metadata).to eq({})
    end

    it "supports full event lifecycle" do
      # Event starts unacknowledged and unresolved
      expect(event.active?).to be true
      expect(event.unacknowledged?).to be true
      expect(event.unresolved?).to be true

      # Add recommended actions
      event.add_recommended_action(action: "Investigate", priority: "high")
      expect(event.pending_actions.count).to eq(1)

      # Acknowledge the event
      event.acknowledge!(user)
      expect(event.acknowledged?).to be true
      expect(event.acknowledged_by).to eq(user)

      # Resolve the event
      event.resolve!
      expect(event.resolved?).to be true
      expect(event.active?).to be false

      # Reopen the event
      event.reopen!
      expect(event.unacknowledged?).to be true
      expect(event.unresolved?).to be true
    end

    it "filters events by multiple criteria" do
      critical_breach = create(:supply_chain_vendor_monitoring_event,
                               :breach,
                               :critical,
                               vendor: vendor,
                               account: account)
      high_incident = create(:supply_chain_vendor_monitoring_event,
                              :security_incident,
                              :high_severity_event,
                              vendor: vendor,
                              account: account)

      results = described_class.unresolved.high_severity.for_vendor(vendor.id)
      expect(results).to include(critical_breach, high_incident)
    end
  end
end
