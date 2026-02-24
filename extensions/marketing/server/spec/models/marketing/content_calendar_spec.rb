# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::ContentCalendar, type: :model do
  subject { build(:marketing_content_calendar) }

  describe "associations" do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:campaign).class_name("Marketing::Campaign").optional }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
    it { is_expected.to validate_presence_of(:entry_type) }
    it { is_expected.to validate_inclusion_of(:entry_type).in_array(Marketing::ContentCalendar::ENTRY_TYPES) }
    it { is_expected.to validate_presence_of(:scheduled_date) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Marketing::ContentCalendar::STATUSES) }
  end

  describe "scopes" do
    let(:account) { create(:account) }

    it "filters by date range" do
      entry1 = create(:marketing_content_calendar, account: account, scheduled_date: Date.current)
      entry2 = create(:marketing_content_calendar, account: account, scheduled_date: 1.month.from_now.to_date)

      results = described_class.by_date_range(Date.current, 1.week.from_now.to_date)
      expect(results).to include(entry1)
      expect(results).not_to include(entry2)
    end

    it "returns upcoming entries" do
      past = create(:marketing_content_calendar, :past, account: account)
      future = create(:marketing_content_calendar, account: account, scheduled_date: 1.week.from_now.to_date)

      expect(described_class.upcoming).to include(future)
      expect(described_class.upcoming).not_to include(past)
    end

    it "filters by type" do
      email = create(:marketing_content_calendar, :email, account: account)
      social = create(:marketing_content_calendar, :social, account: account)

      expect(described_class.by_type("email")).to include(email)
      expect(described_class.by_type("email")).not_to include(social)
    end
  end

  describe "#calendar_summary" do
    let(:entry) { create(:marketing_content_calendar) }

    it "returns summary hash with expected keys" do
      summary = entry.calendar_summary
      expect(summary).to include(:id, :title, :entry_type, :scheduled_date, :status)
    end
  end
end
