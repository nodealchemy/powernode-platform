# frozen_string_literal: true

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

    it 'accepts the canonical report types' do
      PdfReportService::REPORT_TYPES.each do |type|
        report = build(:scheduled_report, report_type: type, account: account, user: user)
        expect(report).to be_valid, "expected #{type} to be valid"
      end
    end

    it 'rejects unknown report types' do
      report = build(:scheduled_report, report_type: 'mystery', account: account, user: user)
      expect(report).not_to be_valid
      expect(report.errors[:report_type]).to be_present
    end
  end

  describe 'scopes' do
    let!(:active_report) { create(:scheduled_report, account: account, user: user, is_active: true) }
    let!(:inactive_report) { create(:scheduled_report, :inactive, account: account, user: user) }
    let!(:due_report) do
      report = create(:scheduled_report, account: account, user: user, is_active: true)
      report.update_column(:next_run_at, 1.hour.ago)
      report
    end

    it '.active returns only active reports' do
      expect(ScheduledReport.active).to include(active_report)
      expect(ScheduledReport.active).not_to include(inactive_report)
    end

    it '.due_for_execution returns active reports with past next_run_at' do
      expect(ScheduledReport.due_for_execution).to include(due_report)
      expect(ScheduledReport.due_for_execution).not_to include(active_report, inactive_report)
    end
  end

  describe 'next_run_at calculation' do
    it 'sets next_run_at on create' do
      report = create(:scheduled_report, :daily, account: account, user: user)
      expect(report.next_run_at).to be_present
      expect(report.next_run_at.hour).to eq(8)
    end

    it 'recalculates when frequency changes' do
      scheduled_report.update!(frequency: 'daily')
      expect(scheduled_report.next_run_at.hour).to eq(8)
    end
  end

  describe '#recipients_list' do
    it 'returns array recipients verbatim' do
      report = create(:scheduled_report, account: account, user: user, recipients: %w[a@x b@x])
      expect(report.recipients_list).to eq(%w[a@x b@x])
    end

    it 'parses JSON string recipients' do
      report = create(:scheduled_report, account: account, user: user)
      report.update_column(:recipients, '["a@x", "b@x"]')
      expect(report.recipients_list).to eq(%w[a@x b@x])
    end

    it 'returns [] for invalid JSON' do
      report = create(:scheduled_report, account: account, user: user)
      report.update_column(:recipients, 'not-json')
      expect(report.recipients_list).to eq([])
    end
  end

  describe '#execute_report!' do
    let(:report_request) { instance_double(ReportRequest, id: SecureRandom.uuid) }

    before do
      allow(PdfReportService).to receive(:enqueue!).and_return(report_request)
    end

    it 'dispatches the worker job via PdfReportService.enqueue!' do
      result = scheduled_report.execute_report!

      expect(PdfReportService).to have_received(:enqueue!).with(
        hash_including(
          report_type: scheduled_report.report_type,
          account: scheduled_report.account,
          user: scheduled_report.user,
          format: scheduled_report.format
        )
      )
      expect(result).to eq(report_request)
    end

    it 'passes email delivery metadata when recipients are configured' do
      scheduled_report.update!(recipients: %w[ops@example.com])
      scheduled_report.execute_report!

      expect(PdfReportService).to have_received(:enqueue!).with(
        hash_including(
          parameters: hash_including(
            'delivery_method' => 'email',
            'recipients' => %w[ops@example.com]
          )
        )
      )
    end

    it 'updates last_run_at and pushes next_run_at into the future after dispatch' do
      scheduled_report.update_column(:next_run_at, 1.hour.ago)

      scheduled_report.execute_report!
      scheduled_report.reload

      expect(scheduled_report.last_run_at).to be_within(2.seconds).of(Time.current)
      expect(scheduled_report.next_run_at).to be > Time.current
    end

    it 'returns nil when inactive' do
      scheduled_report.update!(is_active: false)
      expect(scheduled_report.execute_report!).to be_nil
      expect(PdfReportService).not_to have_received(:enqueue!)
    end
  end
end
