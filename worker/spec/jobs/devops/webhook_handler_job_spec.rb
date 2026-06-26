# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Devops::WebhookHandlerJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:webhook_event_id) { 'devops-event-123-uuid' }
  let(:api_client_double) { instance_double(BackendApiClient) }

  let(:sample_event) do
    {
      'event_type' => 'push',
      'provider_id' => 'provider-123',
      'payload' => {
        'ref' => 'refs/heads/main',
        'commits' => [{ 'id' => 'abc123', 'message' => 'Test commit' }],
        'repository' => { 'full_name' => 'owner/repo' }
      }
    }
  end

  let(:matching_pipeline) do
    {
      'id' => 'pipeline-1',
      'triggers' => { 'push' => { 'branches' => ['main'] } }
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)

    # String-keyed API doubles: route GETs by path
    allow(api_client_double).to receive(:get) do |path, *_args|
      if path.include?('/webhook_events/')
        { 'data' => { 'webhook_event' => sample_event } }
      else
        { 'data' => { 'pipelines' => [matching_pipeline] } }
      end
    end
    allow(api_client_double).to receive(:patch).and_return({ 'success' => true })
    allow(api_client_double).to receive(:post)
      .and_return({ 'data' => { 'pipeline_run' => { 'id' => 'run-1' } } })

    # Idempotency helpers (provided by BaseJob)
    allow(job_instance).to receive(:already_processed?).and_return(false)
    allow(job_instance).to receive(:mark_processed)
  end

  describe 'class configuration' do
    it 'uses devops_webhooks queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('devops_webhooks')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    context 'when the event has already been processed (idempotency)' do
      before do
        allow(job_instance).to receive(:already_processed?).and_return(true)
      end

      it 'returns a skipped result' do
        result = job_instance.execute(webhook_event_id)

        expect(result).to eq({ skipped: true, reason: 'already_processed' })
      end

      it 'does not fetch the webhook event again' do
        job_instance.execute(webhook_event_id)

        expect(api_client_double).not_to have_received(:get)
      end

      it 'does not create or execute pipeline runs a second time' do
        job_instance.execute(webhook_event_id)

        expect(api_client_double).not_to have_received(:post)
      end
    end

    context 'when processing a matching webhook event' do
      it 'creates a pipeline run for the matching pipeline' do
        job_instance.execute(webhook_event_id)

        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/devops/pipeline_runs',
          hash_including(:pipeline_run)
        )
      end

      it 'delegates pipeline execution to the server' do
        job_instance.execute(webhook_event_id)

        expect(api_client_double).to have_received(:post).with(
          '/api/v1/internal/devops/pipeline_runs/run-1/execute'
        )
      end

      it 'marks the event as processed in the idempotency store after success' do
        job_instance.execute(webhook_event_id)

        expect(job_instance).to have_received(:mark_processed)
          .with("devops_webhook:#{webhook_event_id}")
      end
    end

    context 'when the same event is processed twice (Sidekiq retry)' do
      it 'does not create duplicate pipeline runs on the second run' do
        processed = false
        allow(job_instance).to receive(:already_processed?) { processed }
        allow(job_instance).to receive(:mark_processed) { processed = true }

        job_instance.execute(webhook_event_id)
        job_instance.execute(webhook_event_id)

        # First run: 1 create POST + 1 execute POST = 2 calls. Second run short-circuits.
        expect(api_client_double).to have_received(:post).exactly(2).times
      end
    end
  end
end
