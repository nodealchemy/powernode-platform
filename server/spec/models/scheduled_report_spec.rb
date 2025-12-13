require 'rails_helper'

RSpec.describe ScheduledReport, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:scheduled_report) { create(:scheduled_report, account: account, user: user) }

  describe 'associations' do
    it { should belong_to(:user) }
    it { should belong_to(:account).optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:report_type) }
    it { should validate_presence_of(:frequency) }
    it { should validate_presence_of(:format) }

    it { should validate_inclusion_of(:frequency).in_array(%w[daily weekly monthly]) }
    it { should validate_inclusion_of(:format).in_array(%w[pdf csv]) }

    context 'report_type validation' do
      it 'validates report_type is in allowed types' do
        report = build(:scheduled_report, report_type: 'invalid_type', account: account, user: user)
        expect(report).not_to be_valid
        expect(report.errors[:report_type]).to include('is not included in the list')
      end

      it 'allows valid report types' do
        report = build(:scheduled_report, report_type: 'revenue_report', account: account, user: user)
        expect(report).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_report) { create(:scheduled_report, account: account, user: user, is_active: true) }
    let!(:inactive_report) { create(:scheduled_report, :inactive, account: account, user: user) }
    let!(:due_report) {
      report = create(:scheduled_report, account: account, user: user, is_active: true)
      report.update_column(:next_run_at, 1.hour.ago) # Bypass callbacks to set past time
      report
    }

    describe '.active' do
      it 'returns only active reports' do
        expect(ScheduledReport.active).to include(active_report)
        expect(ScheduledReport.active).not_to include(inactive_report)
      end
    end

    describe '.for_account' do
      let(:other_account) { create(:account) }
      let!(:other_report) { create(:scheduled_report, account: other_account, user: create(:user, account: other_account)) }

      it 'returns reports for specific account' do
        expect(ScheduledReport.for_account(account)).to include(active_report, inactive_report, due_report)
        expect(ScheduledReport.for_account(account)).not_to include(other_report)
      end
    end

    describe '.due_for_execution' do
      it 'returns active reports that are due' do
        expect(ScheduledReport.due_for_execution).to include(due_report)
        expect(ScheduledReport.due_for_execution).not_to include(inactive_report)
        expect(ScheduledReport.due_for_execution).not_to include(active_report) # Not due yet
      end
    end
  end

  describe 'callbacks' do
    describe 'calculate_next_run_time' do
      context 'on create' do
        it 'sets next_run_at based on frequency' do
          report = create(:scheduled_report, :daily, account: account, user: user)
          expect(report.next_run_at).to be_present
        end
      end

      context 'when frequency changes' do
        it 'recalculates next_run_at' do
          scheduled_report.update!(frequency: 'daily')
          expect(scheduled_report.next_run_at.hour).to eq(8) # Should be at 8 AM
          expect(scheduled_report.next_run_at.to_date).to eq(1.day.from_now.to_date)
        end
      end
    end
  end

  describe '#recipients_list' do
    context 'when recipients is an array' do
      it 'returns the array' do
        report = create(:scheduled_report, account: account, user: user, recipients: [ 'test1@example.com', 'test2@example.com' ])
        expect(report.recipients_list).to eq([ 'test1@example.com', 'test2@example.com' ])
      end
    end

    context 'when recipients is JSON string' do
      it 'parses the JSON' do
        report = create(:scheduled_report, account: account, user: user)
        report.update_column(:recipients, '["test1@example.com", "test2@example.com"]')
        expect(report.recipients_list).to eq([ 'test1@example.com', 'test2@example.com' ])
      end
    end

    context 'when recipients is invalid JSON' do
      it 'returns empty array' do
        report = create(:scheduled_report, account: account, user: user)
        report.update_column(:recipients, 'invalid json')
        expect(report.recipients_list).to eq([])
      end
    end

    context 'when recipients is blank' do
      it 'returns empty array' do
        report = create(:scheduled_report, account: account, user: user, recipients: nil)
        expect(report.recipients_list).to eq([])
      end
    end
  end

  describe '#recipients_list=' do
    it 'stores array as JSON' do
      emails = [ 'test1@example.com', 'test2@example.com' ]
      scheduled_report.recipients_list = emails
      expect(scheduled_report.recipients).to eq(emails.to_json)
    end

    it 'stores string as-is' do
      json_string = '["test1@example.com"]'
      scheduled_report.recipients_list = json_string
      expect(scheduled_report.recipients).to eq(json_string)
    end
  end

  describe '#execute_report!' do
    let(:pdf_data) { 'fake pdf content' }
    let(:pdf_service) { instance_double(PdfReportService) }

    before do
      allow(PdfReportService).to receive(:new).and_return(pdf_service)
      allow(pdf_service).to receive(:generate_pdf).and_return(pdf_data)
      allow(scheduled_report).to receive(:send_report_email)
      allow(Rails.logger).to receive(:info)
    end

    context 'when report is active' do
      it 'generates report and updates timestamps' do
        expect(pdf_service).to receive(:generate_pdf)
        expect(scheduled_report).to receive(:send_report_email).with(pdf_data)

        result = scheduled_report.execute_report!

        expect(result).to eq(pdf_data)
        expect(scheduled_report.reload.last_run_at).to be_present
      end

      it 'logs execution' do
        scheduled_report.execute_report!
        expect(Rails.logger).to have_received(:info).with(/Scheduled report .* executed and emailed/)
      end
    end

    context 'when report is inactive' do
      it 'does not execute' do
        scheduled_report.update!(is_active: false)
        expect(pdf_service).not_to receive(:generate_pdf)
        expect(scheduled_report.execute_report!).to be_nil
      end
    end
  end

  describe '#generate_report_subject' do
    context 'with different frequencies' do
      {
        'daily' => /Daily .* Report/,
        'weekly' => /Weekly .* Report/,
        'monthly' => /Monthly .* Report/
      }.each do |frequency, expected_pattern|
        it "generates correct subject for #{frequency} reports" do
          trait = frequency == 'monthly' ? nil : frequency.to_sym
          report = trait ? create(:scheduled_report, trait, account: account, user: user) :
                          create(:scheduled_report, account: account, user: user, frequency: frequency)
          expect(report.generate_report_subject).to match(expected_pattern)
        end
      end
    end
  end

  describe '#format_report_period' do
    let(:report) { create(:scheduled_report, :with_history, account: account, user: user) }

    context 'with different frequencies' do
      {
        'daily' => /\w+ \d+, \d{4}/,
        'weekly' => /Week of \w+ \d+ - \w+ \d+, \d{4}/,
        'monthly' => /\w+ \d{4}/
      }.each do |frequency, expected_pattern|
        it "formats #{frequency} period correctly" do
          report.update!(frequency: frequency)
          expect(report.format_report_period).to match(expected_pattern)
        end
      end
    end
  end

  describe 'private methods' do
    describe '#calculate_next_run_time' do
      it 'calculates daily next run time' do
        report = build(:scheduled_report, :daily, account: account, user: user)
        report.save!
        expect(report.next_run_at.hour).to eq(8)
      end

      it 'calculates weekly next run time' do
        report = build(:scheduled_report, :weekly, account: account, user: user)
        report.save!
        expect(report.next_run_at.hour).to eq(8) # Should be at 8 AM
        expect(report.next_run_at).to be_within(2.days).of(1.week.from_now.beginning_of_week + 8.hours)
      end

      it 'calculates monthly next run time' do
        report = build(:scheduled_report, account: account, user: user, frequency: 'monthly')
        report.save!
        expect(report.next_run_at.hour).to eq(8) # Should be at 8 AM
        expect(report.next_run_at.day).to eq(1) # Should be first of month
        expect(report.next_run_at).to be_within(5.days).of(1.month.from_now.beginning_of_month + 8.hours)
      end
    end
  end
end
