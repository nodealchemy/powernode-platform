# frozen_string_literal: true

require "rails_helper"

# Component status plane — how long an outage is worth remembering.
RSpec.describe Platform::Status::EventRetention do
  let(:account) { create(:account) }

  def event(occurred_at:)
    create(:platform_status_event, account: account, occurred_at: occurred_at)
  end

  describe ".retention_days" do
    it "defaults to 30 with no setting, and reads the setting when there is one" do
      expect(described_class.retention_days).to eq(described_class::DEFAULT_RETENTION_DAYS)
      expect(described_class.retention_days).to eq(30)

      SiteSetting.create!(key: described_class::RETENTION_SETTING, value: "90", setting_type: "integer")

      expect(described_class.retention_days).to eq(90)
    end

    it "falls back to the default on a blank or non-positive setting" do
      setting = SiteSetting.create!(key: described_class::RETENTION_SETTING, value: "0",
                                    setting_type: "integer")
      # Zero read literally would delete every event the moment it was written;
      # a typo in a settings form must not be able to do that.
      expect(described_class.retention_days).to eq(30)

      setting.update!(value: "-5")
      expect(described_class.retention_days).to eq(30)
    end
  end

  describe ".prune!" do
    it "deletes a 31-day-old event and keeps a 29-day-old one — both arms" do
      old = event(occurred_at: 31.days.ago)
      recent = event(occurred_at: 29.days.ago)

      expect(described_class.prune!).to eq(1)

      expect(Platform::StatusEvent.exists?(old.id)).to be(false)
      expect(Platform::StatusEvent.exists?(recent.id)).to be(true)
    end

    it "moves the boundary with the setting, in both directions" do
      event(occurred_at: 40.days.ago)
      setting = SiteSetting.create!(key: described_class::RETENTION_SETTING, value: "90",
                                    setting_type: "integer")

      # A 90-day window keeps a 40-day-old event...
      expect(described_class.prune!).to eq(0)
      expect(Platform::StatusEvent.count).to eq(1)

      # ...and a 7-day window does not.
      setting.update!(value: "7")
      expect(described_class.prune!).to eq(1)
      expect(Platform::StatusEvent.count).to eq(0)
    end

    it "is a no-op on an empty table and on a table with nothing old enough" do
      expect(described_class.prune!).to eq(0)

      event(occurred_at: 1.hour.ago)
      expect(described_class.prune!).to eq(0)
      expect(Platform::StatusEvent.count).to eq(1)
    end

    it "prunes a shared (NULL-account) event too — retention is global" do
      shared = create(:platform_status_event, :shared, occurred_at: 60.days.ago)

      described_class.prune!

      expect(Platform::StatusEvent.exists?(shared.id)).to be(false)
    end

    it "is BOUNDED per pass, leaving the rest for the next tick" do
      stub_const("#{described_class}::MAX_ROWS_PER_RUN", 2)
      3.times { event(occurred_at: 60.days.ago) }

      expect(described_class.prune!).to eq(2)
      expect(Platform::StatusEvent.count).to eq(1)

      # The leftovers are not stranded; there is simply no deadline.
      expect(described_class.prune!).to eq(1)
      expect(Platform::StatusEvent.count).to eq(0)
    end

    it "honours an explicit now, so the boundary is testable rather than clock-dependent" do
      event(occurred_at: 10.days.ago)

      expect(described_class.prune!(now: Time.current)).to eq(0)
      expect(described_class.prune!(now: 40.days.from_now)).to eq(1)
    end
  end
end
