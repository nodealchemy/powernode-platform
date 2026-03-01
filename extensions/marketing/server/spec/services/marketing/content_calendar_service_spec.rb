# frozen_string_literal: true

require "rails_helper"

RSpec.describe Marketing::ContentCalendarService do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  describe "#list" do
    let!(:entry1) { create(:marketing_content_calendar, account: account, scheduled_date: Date.current) }
    let!(:entry2) { create(:marketing_content_calendar, account: account, scheduled_date: 1.week.from_now.to_date) }
    let!(:other_account_entry) { create(:marketing_content_calendar) }

    it "returns entries for the account" do
      result = service.list
      expect(result).to include(entry1, entry2)
      expect(result).not_to include(other_account_entry)
    end

    it "filters by date range" do
      result = service.list(start_date: Date.current.to_s, end_date: (Date.current + 2.days).to_s)
      expect(result).to include(entry1)
      expect(result).not_to include(entry2)
    end

    it "filters by entry type" do
      email_entry = create(:marketing_content_calendar, :email, account: account)
      result = service.list(entry_type: "email")
      expect(result).to include(email_entry)
    end

    it "filters by status" do
      published = create(:marketing_content_calendar, :published, account: account)
      result = service.list(status: "published")
      expect(result).to include(published)
    end
  end

  describe "#create" do
    let(:params) do
      {
        title: "New Post",
        entry_type: "post",
        scheduled_date: 1.week.from_now.to_date,
        status: "planned"
      }
    end

    it "creates a calendar entry" do
      entry = service.create(params)
      expect(entry).to be_persisted
      expect(entry.title).to eq("New Post")
      expect(entry.account).to eq(account)
    end

    it "defaults status to planned" do
      entry = service.create(params.except(:status))
      expect(entry.status).to eq("planned")
    end

    it "raises on invalid params" do
      expect {
        service.create({ title: "" })
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "#update" do
    let(:entry) { create(:marketing_content_calendar, account: account) }

    it "updates the entry" do
      service.update(entry, { title: "Updated Title" })
      expect(entry.reload.title).to eq("Updated Title")
    end
  end

  describe "#destroy" do
    let!(:entry) { create(:marketing_content_calendar, account: account) }

    it "destroys the entry" do
      expect { service.destroy(entry) }.to change(Marketing::ContentCalendar, :count).by(-1)
    end
  end

  describe "#detect_conflicts" do
    let(:date) { 1.week.from_now.to_date }

    before do
      create(:marketing_content_calendar, account: account, scheduled_date: date, scheduled_time: "09:00", entry_type: "post")
    end

    it "detects conflicting entries on the same date" do
      result = service.detect_conflicts(date: date)
      expect(result[:has_conflicts]).to be true
      expect(result[:count]).to eq(1)
    end

    it "narrows by time" do
      result = service.detect_conflicts(date: date, time: "10:00")
      expect(result[:has_conflicts]).to be false
    end

    it "excludes specified entry" do
      existing = account.marketing_content_calendars.first
      result = service.detect_conflicts(date: date, exclude_id: existing.id)
      expect(result[:has_conflicts]).to be false
    end
  end

  describe "#entries_for_range" do
    it "groups entries by date" do
      create(:marketing_content_calendar, account: account, scheduled_date: Date.current)
      create(:marketing_content_calendar, account: account, scheduled_date: Date.current)
      create(:marketing_content_calendar, account: account, scheduled_date: Date.tomorrow)

      result = service.entries_for_range(Date.current, Date.tomorrow)
      expect(result[Date.current].length).to eq(2)
      expect(result[Date.tomorrow].length).to eq(1)
    end
  end
end
