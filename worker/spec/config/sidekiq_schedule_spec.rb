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
end
