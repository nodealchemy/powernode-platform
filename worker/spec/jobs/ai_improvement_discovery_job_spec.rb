# frozen_string_literal: true

require 'rails_helper'

# D1 — the clock half, after the review's H2. The worker walks the server's
# discovery units one POST at a time through the NON-retrying client, never
# through the retrying `post` and never under a job-level retry: each call runs
# a sweep that files offers, so a re-send is a second sweep.
RSpec.describe AiImprovementDiscoveryJob, type: :job do
  let(:job_instance) { described_class.new }
  let(:api_client_double) { double('BackendApiClient') }
  let(:path) { '/api/v1/internal/ai/improvement_discovery/run' }

  # The cursor lives in Sidekiq's Redis. A two-method stand-in keeps the spec
  # off a real Redis while the job's own get/set calls run unchanged.
  let(:cursor_store) { {} }
  let(:redis_conn) do
    store = cursor_store
    Object.new.tap do |conn|
      conn.define_singleton_method(:get) { |key| store[key] }
      conn.define_singleton_method(:set) { |key, value| store[key] = value.to_s }
    end
  end

  before do
    mock_powernode_worker_config
    Sidekiq::Testing.fake!
    allow(job_instance).to receive(:api_client).and_return(api_client_double)
    allow_any_instance_of(BaseJob).to receive(:check_runaway_loop).and_return(nil)
    allow(Sidekiq).to receive(:redis).and_yield(redis_conn)
  end

  after { Sidekiq::Worker.clear_all }

  def unit(position, done:, status: 'completed', offers_created: 0, degraded: 0)
    { 'success' => true,
      'data' => { 'ran_unit' => true, 'status' => status, 'findings' => 1,
                  'offers_created' => offers_created, 'offers_deduped' => 0, 'offers_parked' => 0,
                  'analyzers_degraded' => degraded, 'position' => position,
                  'next_position' => position + 1, 'done' => done } }
  end

  it 'walks every unit by position, one non-retrying POST each, and totals them' do
    expect(api_client_double).to receive(:post_no_retry)
      .with(path, { 'position' => 0 }, timeout: described_class::UNIT_TIMEOUT).ordered
      .and_return(unit(0, done: false, offers_created: 2))
    expect(api_client_double).to receive(:post_no_retry)
      .with(path, { 'position' => 1 }, timeout: described_class::UNIT_TIMEOUT).ordered
      .and_return(unit(1, done: true, offers_created: 1))
    expect(api_client_double).not_to receive(:post)

    totals = job_instance.execute

    expect(totals).to include('units' => 2, 'offers_created' => 3, 'units_completed' => 2)
  end

  it 'stops at once when the server has no unit to run' do
    expect(api_client_double).to receive(:post_no_retry).once
      .and_return({ 'success' => true, 'data' => { 'ran_unit' => false, 'done' => true, 'next_position' => 1 } })

    expect(job_instance.execute).to eq({})
  end

  it 'ends the tick on a unit timeout, without re-sending it or moving on, and records it' do
    expect(api_client_double).to receive(:post_no_retry)
      .with(path, { 'position' => 0 }, timeout: described_class::UNIT_TIMEOUT).once
      .and_raise(BackendApiClient::ApiError.new('Request timeout: execution expired', 408))
    expect(api_client_double).to receive(:post_no_retry)
      .with(described_class::TIMED_OUT_PATH, { 'position' => 0 }, timeout: described_class::TIMED_OUT_TIMEOUT).once
      .and_return({ 'success' => true, 'data' => { 'recorded' => true } })

    expect { job_instance.execute }.not_to raise_error
  end

  it 'raises on any other API error so Sidekiq records the failure' do
    allow(api_client_double).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new('boom', 500))

    expect(job_instance).to receive(:log_error).with('Improvement discovery failed', kind_of(BackendApiClient::ApiError))
    expect { job_instance.execute }.to raise_error(BackendApiClient::ApiError)
  end

  it 'has Sidekiq retry switched off, since a retried tick re-runs every sweep' do
    expect(described_class.get_sidekiq_options['retry']).to eq(0)
  end

  it 'warns rather than staying silent when a unit ran with degraded analyzers' do
    allow(api_client_double).to receive(:post_no_retry).and_return(unit(0, done: true, degraded: 2))

    expect(job_instance).to receive(:log_warn).with('Improvement discovery ran with degraded analyzers', degraded: 2)

    job_instance.execute
  end

  it 'does NOT warn when every analyzer completed' do
    allow(api_client_double).to receive(:post_no_retry).and_return(unit(0, done: true))

    expect(job_instance).not_to receive(:log_warn)

    job_instance.execute
  end

  # D1 re-verify: a timed-out unit ended the tick and the next tick restarted at
  # unit one, so one slow unit starved every unit after it, every week.
  describe 'the cursor past a slow unit' do
    let(:timeout_error) { BackendApiClient::ApiError.new('Request timeout: execution expired', 408) }

    # Three units: 0 fast, 1 slow (it times out every time), 2 fast.
    def serve(posted, recorded, slow: 1)
      allow(api_client_double).to receive(:post_no_retry) do |called_path, body, **|
        if called_path == described_class::TIMED_OUT_PATH
          recorded << body['position']
          next({ 'success' => true, 'data' => { 'recorded' => true } })
        end

        posted << body['position']
        raise timeout_error if body['position'] == slow

        unit(body['position'], done: body['position'] == 2)
      end
    end

    it 'reaches the unit after the slow one on the next tick, and records the slow one' do
      first_tick = []
      second_tick = []
      recorded = []

      serve(first_tick, recorded)
      job_instance.execute
      serve(second_tick, recorded)
      job_instance.execute

      expect(first_tick).to eq([ 0, 1 ])
      expect(second_tick.first).to eq(2)
      expect(second_tick).to eq([ 2, 0, 1 ])
      expect(recorded).to eq([ 1, 1 ])
    end

    it 'goes back to the top after a whole lap with no timeout' do
      cursor_store[described_class::CURSOR_KEY] = '2'
      posted = []
      serve(posted, [], slow: nil)

      job_instance.execute

      expect(posted).to eq([ 2, 0, 1 ])
      expect(cursor_store[described_class::CURSOR_KEY]).to eq('0')
    end

    it 'keeps the cursor when the platform, not the unit, fails' do
      cursor_store[described_class::CURSOR_KEY] = '2'
      allow(api_client_double).to receive(:post_no_retry).and_raise(BackendApiClient::ApiError.new('boom', 500))

      expect { job_instance.execute }.to raise_error(BackendApiClient::ApiError)
      expect(cursor_store[described_class::CURSOR_KEY]).to eq('2')
    end
  end
end
