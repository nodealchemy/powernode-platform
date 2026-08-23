# frozen_string_literal: true

require 'rails_helper'
require 'erb'
require 'yaml'
require 'fugit'

# The sidekiq-scheduler schedule in config/sidekiq.yml is the only thing that
# makes a "documented daily cron" job actually fire — the job class alone never
# runs. Regression spec for IMP-20c49fe3941f: DailySummaryJob was documented as
# a daily 6 AM cron (docs/operations/daily-summaries.md) but was never added to
# the schedule, so the feature silently never ran.
RSpec.describe 'sidekiq.yml scheduler config' do
  let(:config) do
    raw = File.read(File.expand_path('../../config/sidekiq.yml', __dir__))
    YAML.safe_load(ERB.new(raw).result, permitted_classes: [Symbol], aliases: true)
  end

  # Top-level sidekiq.yml keys are written as symbols (`:scheduler:`); Psych
  # parses them as Symbol when permitted. Schedule entry names are plain strings.
  let(:schedule) { config[:scheduler][:schedule] }

  describe 'daily_summary_generation' do
    subject(:entry) { schedule['daily_summary_generation'] }

    it 'is scheduled' do
      expect(entry).not_to be_nil
    end

    it 'runs DailySummaryJob on the maintenance queue, matching the job class' do
      expect(entry['class']).to eq('DailySummaryJob')
      expect(entry['queue']).to eq('maintenance')
      expect(DailySummaryJob.sidekiq_options['queue']).to eq('maintenance')
    end

    it 'fires daily at 6:00 AM UTC per docs/operations/daily-summaries.md' do
      cron = Fugit.parse_cron(entry['cron'])
      expect(cron).not_to be_nil
      expect(entry['cron']).to eq('0 6 * * *')
    end
  end

  # Reports::ScheduledReportSweepJob is enqueued with args: [] — a periodic
  # sweep with no per-call payload. Without a schedule entry nothing ever
  # triggers it and ScheduledReport rows are never dispatched, which is the
  # same silent-inertness class as the DailySummaryJob regression above.
  describe 'scheduled_report_sweep' do
    subject(:entry) { schedule['scheduled_report_sweep'] }

    it 'is scheduled' do
      expect(entry).not_to be_nil
    end

    # A declared entry naming a class that does not resolve, or that
    # sidekiq-scheduler cannot enqueue, is not a working schedule.
    it 'names a class that actually resolves to an enqueueable job' do
      klass = Object.const_get(entry['class'])
      expect(klass).to be < BaseJob
      expect(klass).to respond_to(:perform_async)
    end

    it 'agrees with the job class about the queue' do
      expect(entry['queue']).to eq('reports')
      expect(Reports::ScheduledReportSweepJob.sidekiq_options['queue']).to eq('reports')
    end

    it 'has a parseable cron expression' do
      expect(Fugit.parse_cron(entry['cron'])).not_to be_nil
    end

    it 'fires often enough to keep dispatch latency under an hour' do
      cron = Fugit.parse_cron(entry['cron'])
      from = Time.utc(2026, 1, 1, 0, 0, 0)
      expect(cron.next_time(from).to_t - from).to be <= 3600
    end
  end

  # The cleanup job destroys report rows and their stored artifacts against a
  # backlog of unknown size. It must stay off the cron until an operator
  # decides otherwise — a schedule entry here would be the unbounded first run.
  describe 'reports cleanup' do
    it 'does NOT register Reports::CleanupOldReportsJob on a cron' do
      scheduled_classes = schedule.values.map { |e| e['class'] }
      expect(scheduled_classes).not_to include('Reports::CleanupOldReportsJob')
    end
  end
end
