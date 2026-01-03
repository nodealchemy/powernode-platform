# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Git::ScheduledPipelineJob, type: :job do
  subject { described_class }

  let(:job_instance) { described_class.new }
  let(:api_client_double) { instance_double(BackendApiClient) }
  let(:schedule_id) { 'schedule-123-uuid' }
  let(:account_id) { 'account-456-uuid' }
  let(:credential_id) { 'cred-789-uuid' }
  let(:repository_id) { 'repo-abc-uuid' }

  let(:sample_credential) do
    {
      'id' => credential_id,
      'provider_type' => 'github',
      'api_base_url' => nil,
      'access_token' => 'ghp_test_token',
      'status' => 'active'
    }
  end

  let(:sample_schedule) do
    {
      'id' => schedule_id,
      'name' => 'Nightly Build',
      'cron_expression' => '0 2 * * *',
      'workflow_file' => '.github/workflows/build.yml',
      'ref' => 'main',
      'inputs' => { 'debug' => 'false' },
      'credential_id' => credential_id,
      'repository' => {
        'id' => repository_id,
        'owner' => 'test-owner',
        'name' => 'test-repo',
        'full_name' => 'test-owner/test-repo',
        'credential_id' => credential_id
      }
    }
  end

  before do
    mock_powernode_worker_config
    allow(BackendApiClient).to receive(:new).and_return(api_client_double)
    allow(api_client_double).to receive(:get).and_return({ 'data' => {} })
    allow(api_client_double).to receive(:post).and_return({ 'success' => true })
    # Mock idempotency methods
    allow(job_instance).to receive(:already_processed?).and_return(false)
    allow(job_instance).to receive(:mark_processed)
  end

  describe 'class configuration' do
    it_behaves_like 'a base job', described_class

    it 'uses schedules queue' do
      expect(described_class.sidekiq_options['queue']).to eq('schedules')
    end

    it 'has 3 retries configured' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end

  describe '#execute' do
    context 'with no parameters (all due schedules)' do
      let(:due_schedules) { [sample_schedule] }

      before do
        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/schedules/due')
          .and_return({ 'data' => due_schedules })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        stub_request(:post, %r{api\.github\.com/repos/.+/actions/workflows/.+/dispatches})
          .to_return(status: 204, body: '')

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runs})
          .to_return(status: 200, body: { workflow_runs: [{ id: 12345 }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'fetches all due schedules' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:get)
          .with('/api/v1/internal/git/schedules/due')
      end

      it 'returns results summary' do
        result = job_instance.execute({})

        expect(result).to include(:total, :triggered, :failed, :skipped)
      end

      it 'triggers pipeline for each due schedule' do
        result = job_instance.execute({})

        expect(result[:triggered]).to eq(1)
      end

      it 'records successful run' do
        job_instance.execute({})

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/internal/git/schedules/#{schedule_id}/record_run", hash_including(status: 'success'))
      end
    end

    context 'with schedule_id (single schedule)' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        stub_request(:post, %r{api\.github\.com/repos/.+/actions/workflows/.+/dispatches})
          .to_return(status: 204, body: '')

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runs})
          .to_return(status: 200, body: { workflow_runs: [{ id: 67890 }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'executes specific schedule' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result).to include(status: :triggered, run_id: '67890')
      end

      it 'fetches schedule details' do
        job_instance.execute(schedule_id: schedule_id)

        expect(api_client_double).to have_received(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
      end
    end

    context 'with account_id' do
      let(:due_schedules) { [sample_schedule] }

      before do
        allow(api_client_double).to receive(:get)
          .with('/api/v1/internal/git/schedules/due', { account_id: account_id })
          .and_return({ 'data' => due_schedules })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        stub_request(:post, %r{api\.github\.com/repos/.+/actions/workflows/.+/dispatches})
          .to_return(status: 204, body: '')

        stub_request(:get, %r{api\.github\.com/repos/.+/actions/runs})
          .to_return(status: 200, body: { workflow_runs: [{ id: 11111 }] }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'fetches due schedules for account' do
        job_instance.execute(account_id: account_id)

        expect(api_client_double).to have_received(:get)
          .with('/api/v1/internal/git/schedules/due', { account_id: account_id })
      end
    end

    context 'when schedule not found' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => nil })
      end

      it 'returns error' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result).to eq({ error: 'Schedule not found' })
      end
    end

    context 'when schedule already executed (idempotency)' do
      before do
        allow(job_instance).to receive(:already_processed?).and_return(true)

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })
      end

      it 'skips execution' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result).to eq({ status: :skipped, reason: 'already_executed' })
      end
    end

    context 'when credential not found' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => nil })
      end

      it 'records failure' do
        job_instance.execute(schedule_id: schedule_id)

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/internal/git/schedules/#{schedule_id}/record_run", hash_including(status: 'failure'))
      end
    end

    context 'when GitHub workflow trigger fails' do
      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => sample_credential })

        stub_request(:post, %r{api\.github\.com/repos/.+/actions/workflows/.+/dispatches})
          .to_return(status: 404, body: { message: 'Workflow not found' }.to_json)
      end

      it 'records failure' do
        job_instance.execute(schedule_id: schedule_id)

        expect(api_client_double).to have_received(:post)
          .with("/api/v1/internal/git/schedules/#{schedule_id}/record_run", hash_including(status: 'failure'))
      end

      it 'returns failed status' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result[:status]).to eq(:failed)
      end
    end

    context 'with GitLab provider' do
      let(:gitlab_credential) do
        sample_credential.merge('provider_type' => 'gitlab', 'api_base_url' => 'https://gitlab.com/api/v4')
      end

      before do
        # Disable real HTTP connections for this context
        WebMock.disable_net_connect!

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => gitlab_credential })

        # Stub ANY request to gitlab.com
        stub_request(:any, %r{gitlab\.com})
          .to_return(status: 201, body: { id: 99999 }.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      it 'triggers GitLab pipeline' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result).to include(status: :triggered, run_id: '99999')
      end
    end

    context 'with Gitea provider' do
      let(:gitea_credential) do
        sample_credential.merge('provider_type' => 'gitea', 'api_base_url' => 'https://gitea.example.com/api/v1')
      end

      before do
        # Disable real HTTP connections for this context
        WebMock.disable_net_connect!

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => gitea_credential })

        # Stub ANY request to gitea.example.com
        stub_request(:any, %r{gitea\.example\.com})
          .to_return(status: 204, body: '')
      end

      it 'triggers Gitea workflow' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result).to include(status: :triggered)
      end
    end

    context 'with unsupported provider' do
      let(:unsupported_credential) do
        sample_credential.merge('provider_type' => 'bitbucket')
      end

      before do
        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/schedules/#{schedule_id}")
          .and_return({ 'data' => sample_schedule })

        allow(api_client_double).to receive(:get)
          .with("/api/v1/internal/git/credentials/#{credential_id}/decrypted")
          .and_return({ 'data' => unsupported_credential })
      end

      it 'returns error' do
        result = job_instance.execute(schedule_id: schedule_id)

        expect(result[:status]).to eq(:failed)
        expect(result[:error]).to include('Unsupported provider')
      end
    end
  end

  describe 'API error handling' do
    before do
      allow(api_client_double).to receive(:get)
        .and_raise(BackendApiClient::ApiError.new('API Error', 500))
    end

    it 'raises the error for retry' do
      expect { job_instance.execute({}) }
        .to raise_error(BackendApiClient::ApiError)
    end
  end

  describe 'logging' do
    let(:job_args) { {} }

    before do
      allow(api_client_double).to receive(:get)
        .with('/api/v1/internal/git/schedules/due')
        .and_return({ 'data' => [] })
    end

    it_behaves_like 'a job with logging'
  end
end
