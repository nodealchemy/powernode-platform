# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UsageSummary, type: :model do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:usage_meter) }
    it { is_expected.to belong_to(:subscription).optional }
    it { is_expected.to belong_to(:invoice).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:period_start) }
    it { is_expected.to validate_presence_of(:period_end) }
    it { is_expected.to validate_numericality_of(:total_quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:billable_quantity).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:event_count).is_greater_than_or_equal_to(0) }
    it { is_expected.to validate_numericality_of(:calculated_amount).is_greater_than_or_equal_to(0) }

    describe 'custom validations' do
      it 'validates period_end is after period_start' do
        summary = build(:usage_summary,
          period_start: Time.current,
          period_end: 1.day.ago
        )
        expect(summary).not_to be_valid
        expect(summary.errors[:period_end]).to include('must be after period start')
      end

      it 'is valid when period_end is after period_start' do
        summary = build(:usage_summary,
          period_start: 1.day.ago,
          period_end: Time.current
        )
        expect(summary).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:usage_meter) { create(:usage_meter) }

    describe '.unbilled' do
      it 'returns only unbilled summaries' do
        unbilled = create(:usage_summary,
          account: account,
          usage_meter: usage_meter,
          is_billed: false,
          period_start: Time.current.beginning_of_month,
          period_end: Time.current.end_of_month
        )
        billed = create(:usage_summary, :billed,
          account: account,
          usage_meter: usage_meter,
          period_start: 1.month.ago.beginning_of_month,
          period_end: 1.month.ago.end_of_month
        )

        expect(UsageSummary.unbilled).to include(unbilled)
        expect(UsageSummary.unbilled).not_to include(billed)
      end
    end

    describe '.billed' do
      it 'returns only billed summaries' do
        unbilled = create(:usage_summary,
          account: account,
          usage_meter: usage_meter,
          is_billed: false,
          period_start: Time.current.beginning_of_month,
          period_end: Time.current.end_of_month
        )
        billed = create(:usage_summary, :billed,
          account: account,
          usage_meter: usage_meter,
          period_start: 1.month.ago.beginning_of_month,
          period_end: 1.month.ago.end_of_month
        )

        expect(UsageSummary.billed).to include(billed)
        expect(UsageSummary.billed).not_to include(unbilled)
      end
    end

    describe '.for_period' do
      it 'returns summaries with period_start in the specified range' do
        in_range = create(:usage_summary,
          account: account,
          usage_meter: usage_meter,
          period_start: 5.days.ago,
          period_end: 3.days.ago
        )
        outside_range = create(:usage_summary,
          account: account,
          usage_meter: create(:usage_meter),
          period_start: 30.days.ago,
          period_end: 25.days.ago
        )

        results = UsageSummary.for_period(7.days.ago, 1.day.ago)

        expect(results).to include(in_range)
        expect(results).not_to include(outside_range)
      end
    end

    describe '.quota_exceeded' do
      it 'returns summaries where quota was exceeded' do
        exceeded = create(:usage_summary,
          account: account,
          usage_meter: usage_meter,
          quota_exceeded: true
        )
        not_exceeded = create(:usage_summary,
          account: account,
          usage_meter: create(:usage_meter),
          quota_exceeded: false
        )

        expect(UsageSummary.quota_exceeded).to include(exceeded)
        expect(UsageSummary.quota_exceeded).not_to include(not_exceeded)
      end
    end

    describe '.recent' do
      it 'returns summaries ordered by period_start descending' do
        old = create(:usage_summary,
          account: account,
          usage_meter: usage_meter,
          period_start: 30.days.ago,
          period_end: 25.days.ago
        )
        recent = create(:usage_summary,
          account: account,
          usage_meter: create(:usage_meter),
          period_start: 7.days.ago,
          period_end: 3.days.ago
        )
        newest = create(:usage_summary,
          account: account,
          usage_meter: create(:usage_meter),
          period_start: 2.days.ago,
          period_end: 1.day.ago
        )

        results = UsageSummary.recent

        expect(results.first).to eq(newest)
        expect(results.last).to eq(old)
      end
    end
  end

  describe 'instance methods' do
    let(:usage_summary) { create(:usage_summary) }

    describe '#billed?' do
      it 'returns true when is_billed is true' do
        usage_summary.update!(is_billed: true)
        expect(usage_summary.billed?).to be true
      end

      it 'returns false when is_billed is false' do
        usage_summary.update!(is_billed: false)
        expect(usage_summary.billed?).to be false
      end
    end

    describe '#mark_billed!' do
      let(:invoice) { create(:invoice, account: usage_summary.account) }

      it 'sets is_billed to true and associates with invoice' do
        usage_summary.mark_billed!(invoice)

        expect(usage_summary.is_billed).to be true
        expect(usage_summary.invoice).to eq(invoice)
      end

      it 'persists the changes to the database' do
        usage_summary.mark_billed!(invoice)
        usage_summary.reload

        expect(usage_summary.is_billed).to be true
        expect(usage_summary.invoice_id).to eq(invoice.id)
      end
    end

    describe '#overage_quantity' do
      it 'calculates overage when quota_used exceeds quota_limit' do
        summary = create(:usage_summary,
          quota_limit: 1000,
          quota_used: 1500
        )

        expect(summary.overage_quantity).to eq(500)
      end

      it 'returns 0 when quota_used is below quota_limit' do
        summary = create(:usage_summary,
          quota_limit: 1000,
          quota_used: 800
        )

        expect(summary.overage_quantity).to eq(0)
      end

      it 'returns 0 when quota_limit is nil' do
        summary = create(:usage_summary,
          quota_limit: nil,
          quota_used: 500
        )

        expect(summary.overage_quantity).to eq(0)
      end
    end

    describe '#quota_usage_percent' do
      it 'calculates percentage of quota used' do
        summary = create(:usage_summary,
          quota_limit: 1000,
          quota_used: 750
        )

        expect(summary.quota_usage_percent).to eq(75.0)
      end

      it 'caps at 100%' do
        summary = create(:usage_summary,
          quota_limit: 1000,
          quota_used: 1500
        )

        expect(summary.quota_usage_percent).to eq(100)
      end

      it 'returns 0 when quota_limit is nil' do
        summary = create(:usage_summary,
          quota_limit: nil,
          quota_used: 500
        )

        expect(summary.quota_usage_percent).to eq(0)
      end

      it 'returns 0 when quota_limit is zero' do
        summary = create(:usage_summary,
          quota_limit: 0,
          quota_used: 500
        )

        expect(summary.quota_usage_percent).to eq(0)
      end
    end

    describe '#included_quantity' do
      it 'returns total_quantity when quota_limit is nil' do
        summary = create(:usage_summary,
          total_quantity: 500,
          quota_limit: nil
        )

        expect(summary.included_quantity).to eq(500)
      end

      it 'returns total_quantity when it is less than quota_limit' do
        summary = create(:usage_summary,
          total_quantity: 500,
          quota_limit: 1000
        )

        expect(summary.included_quantity).to eq(500)
      end

      it 'returns quota_limit when total_quantity exceeds it' do
        summary = create(:usage_summary,
          total_quantity: 1500,
          quota_limit: 1000
        )

        expect(summary.included_quantity).to eq(1000)
      end
    end

    describe '#summary' do
      it 'returns a hash with summary information' do
        result = usage_summary.summary

        expect(result).to be_a(Hash)
        expect(result[:id]).to eq(usage_summary.id)
        expect(result[:period_start]).to eq(usage_summary.period_start)
        expect(result[:period_end]).to eq(usage_summary.period_end)
        expect(result[:total_quantity]).to eq(usage_summary.total_quantity)
        expect(result[:billable_quantity]).to eq(usage_summary.billable_quantity)
        expect(result[:event_count]).to eq(usage_summary.event_count)
        expect(result[:calculated_amount]).to eq(usage_summary.calculated_amount)
        expect(result[:is_billed]).to eq(usage_summary.is_billed)
        expect(result[:quota_limit]).to eq(usage_summary.quota_limit)
        expect(result[:quota_used]).to eq(usage_summary.quota_used)
        expect(result[:quota_exceeded]).to eq(usage_summary.quota_exceeded)
      end
    end
  end
end
