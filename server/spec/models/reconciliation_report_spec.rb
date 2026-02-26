# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Billing::ReconciliationReport, type: :model do
  subject { build(:reconciliation_report) }

  describe 'validations' do
    it { should validate_presence_of(:reconciliation_date) }
    it { should validate_presence_of(:reconciliation_type) }
    it { should validate_inclusion_of(:reconciliation_type).in_array(%w[daily weekly monthly custom]) }
    it { should validate_presence_of(:date_range_start) }
    it { should validate_presence_of(:date_range_end) }
    it { should validate_presence_of(:discrepancies_count) }
    it { should validate_numericality_of(:discrepancies_count).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:high_severity_count) }
    it { should validate_numericality_of(:high_severity_count).is_greater_than_or_equal_to(0) }
    it { should validate_presence_of(:medium_severity_count) }
    it { should validate_numericality_of(:medium_severity_count).is_greater_than_or_equal_to(0) }
  end

  describe 'scopes' do
    let!(:old_report) { create(:reconciliation_report, created_at: 1.week.ago) }
    let!(:recent_report) { create(:reconciliation_report, created_at: 1.day.ago) }
    let!(:no_discrepancies) { create(:reconciliation_report, discrepancies_count: 0, created_at: 2.hours.ago) }
    let!(:with_discrepancies) { create(:reconciliation_report, discrepancies_count: 5, created_at: 3.hours.ago) }
    let!(:high_priority) { create(:reconciliation_report, high_severity_count: 2, discrepancies_count: 2, created_at: 4.hours.ago) }
    let!(:low_priority) { create(:reconciliation_report, high_severity_count: 0, created_at: 5.hours.ago) }

    describe '.recent' do
      it 'orders by created_at desc' do
        reports = described_class.recent.to_a
        # Check that reports are ordered by created_at descending
        expect(reports.length).to eq(6)
        created_at_times = reports.map(&:created_at)
        expect(created_at_times).to eq(created_at_times.sort.reverse)
        # Verify the oldest report is last
        expect(reports.last).to eq(old_report)
      end
    end

    describe '.with_discrepancies' do
      it 'returns reports with discrepancies' do
        expect(described_class.with_discrepancies).to contain_exactly(with_discrepancies, high_priority)
      end
    end

    describe '.high_priority' do
      it 'returns reports with high severity discrepancies' do
        expect(described_class.high_priority).to contain_exactly(high_priority)
      end
    end
  end

  describe 'instance methods' do
    let(:report) do
      create(:reconciliation_report,
        discrepancies_count: 5,
        high_severity_count: 2,
        medium_severity_count: 3,
        summary: {
          'local_payments' => 100,
          'total_amount_variance' => 5000
        }
      )
    end

    describe '#has_discrepancies?' do
      it 'returns true when discrepancies exist' do
        expect(report.has_discrepancies?).to be_truthy
      end

      it 'returns false when no discrepancies' do
        report.update!(discrepancies_count: 0)
        expect(report.has_discrepancies?).to be_falsy
      end
    end

    describe '#high_priority?' do
      it 'returns true when high severity discrepancies exist' do
        expect(report.high_priority?).to be_truthy
      end

      it 'returns false when no high severity discrepancies' do
        report.update!(high_severity_count: 0)
        expect(report.high_priority?).to be_falsy
      end
    end

    describe '#date_range' do
      it 'returns a range from start to end date' do
        expected_range = report.date_range_start..report.date_range_end
        expect(report.date_range).to eq(expected_range)
      end
    end

    describe '#total_payments' do
      it 'returns local payments from summary' do
        expect(report.total_payments).to eq(100)
      end

      it 'returns 0 when summary is nil' do
        report.update!(summary: nil)
        expect(report.total_payments).to eq(0)
      end

      it 'returns 0 when local_payments is missing' do
        report.update!(summary: {})
        expect(report.total_payments).to eq(0)
      end
    end

    describe '#amount_variance' do
      it 'returns amount variance from summary' do
        expect(report.amount_variance).to eq(5000)
      end

      it 'returns 0 when summary is nil' do
        report.update!(summary: nil)
        expect(report.amount_variance).to eq(0)
      end
    end
  end

  describe 'factory' do
    it 'creates valid reconciliation report' do
      report = create(:reconciliation_report)
      expect(report).to be_valid
      expect(report.reconciliation_date).to be_present
      expect(report.reconciliation_type).to be_in(%w[daily weekly monthly custom])
      expect(report.date_range_start).to be_present
      expect(report.date_range_end).to be_present
      expect(report.discrepancies_count).to be >= 0
      expect(report.high_severity_count).to be >= 0
      expect(report.medium_severity_count).to be >= 0
    end
  end
end
