# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::QuarantineRecord, type: :model do
  let(:account) { create(:account) }

  describe "associations" do
    it { should belong_to(:account) }
  end

  describe "validations" do
    subject { build(:ai_quarantine_record, account: account) }

    it { should validate_presence_of(:agent_id) }
    it { should validate_presence_of(:severity) }
    it { should validate_presence_of(:status) }
    it { should validate_presence_of(:trigger_reason) }
    it { should validate_inclusion_of(:severity).in_array(%w[low medium high critical]) }
    it { should validate_inclusion_of(:status).in_array(%w[active escalated restored expired]) }
    it { should validate_numericality_of(:cooldown_minutes).only_integer.is_greater_than_or_equal_to(0) }

    it "is invalid with an unknown severity" do
      record = build(:ai_quarantine_record, account: account, severity: "unknown")
      expect(record).not_to be_valid
    end

    it "is invalid with an unknown status" do
      record = build(:ai_quarantine_record, account: account, status: "invalid")
      expect(record).not_to be_valid
    end
  end

  describe "scopes" do
    let!(:active_record) { create(:ai_quarantine_record, account: account, status: "active") }
    let!(:restored_record) { create(:ai_quarantine_record, :restored, account: account) }
    let!(:critical_record) { create(:ai_quarantine_record, :critical, account: account) }

    it ".active returns only active records" do
      expect(described_class.active).to include(active_record, critical_record)
      expect(described_class.active).not_to include(restored_record)
    end

    it ".restored returns only restored records" do
      expect(described_class.restored).to include(restored_record)
      expect(described_class.restored).not_to include(active_record)
    end

    it ".by_severity filters by severity" do
      expect(described_class.by_severity("critical")).to include(critical_record)
      expect(described_class.by_severity("critical")).not_to include(active_record)
    end

    it ".critical returns critical records" do
      expect(described_class.critical).to include(critical_record)
      expect(described_class.critical).not_to include(active_record)
    end

    it ".for_agent scopes by agent_id" do
      results = described_class.for_agent(active_record.agent_id)
      expect(results).to include(active_record)
    end

    it ".restorable returns records past scheduled_restore_at" do
      restorable = create(:ai_quarantine_record, :restorable, account: account)
      expect(described_class.restorable).to include(restorable)
      expect(described_class.restorable).not_to include(active_record) # active_record has future restore time
    end
  end

  describe "instance methods" do
    describe "#past_cooldown?" do
      it "returns true when cooldown has passed" do
        record = build(:ai_quarantine_record, cooldown_minutes: 0)
        expect(record.past_cooldown?).to be true
      end

      it "returns false when cooldown has not passed" do
        record = create(:ai_quarantine_record, account: account, cooldown_minutes: 9999)
        expect(record.past_cooldown?).to be false
      end
    end

    describe "#auto_restorable?" do
      it "returns true when active and past scheduled_restore_at" do
        record = build(:ai_quarantine_record, status: "active", scheduled_restore_at: 1.minute.ago)
        expect(record.auto_restorable?).to be true
      end

      it "returns false when not active" do
        record = build(:ai_quarantine_record, :restored, scheduled_restore_at: 1.minute.ago)
        expect(record.auto_restorable?).to be false
      end
    end

    describe "#severity_level" do
      it "returns numeric severity level" do
        expect(build(:ai_quarantine_record, severity: "low").severity_level).to eq(0)
        expect(build(:ai_quarantine_record, severity: "critical").severity_level).to eq(3)
      end
    end
  end
end
