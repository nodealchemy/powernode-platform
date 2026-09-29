# frozen_string_literal: true

require 'spec_helper'

# The job resolves each remote over the internal API, runs
# Devops::IncrementMergeService, and reports the outcome to the server. The
# backend API and the service are doubles here; the git work itself is covered
# against real local repositories in increment_merge_service_spec.
RSpec.describe Git::DevMergeIncrementJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:payload) do
    { 'deferred_operation_id' => 'op-1', 'account_id' => 'acct-1', 'source_ref' => 'feature/x',
      'target_branch' => 'develop', 'expected_source_sha' => 'c' * 40,
      'remotes' => [ { 'repository_id' => 'repo-1' } ], 'forbidden_names' => %w[zzhidden] }
  end

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:bail_if_ai_suspended!).and_return(false)
    allow(api_client).to receive(:post)
  end

  it 'never retries a merge blind' do
    expect(described_class.get_sidekiq_options['retry']).to eq(0)
  end

  it 'reports the service outcome to the server' do
    service = instance_double(Devops::IncrementMergeService,
                              call: { 'status' => 'succeeded', 'remotes' => [ { 'status' => 'pushed' } ] })
    allow(Devops::IncrementMergeService).to receive(:new).and_return(service)

    job.execute(payload)

    expect(api_client).to have_received(:post)
      .with('/api/v1/internal/ai/dev_merges/op-1/report', hash_including('status' => 'succeeded'))
  end

  it 'merges nothing while the account is suspended, and reports that' do
    allow(job).to receive(:bail_if_ai_suspended!).with('acct-1').and_return(true)
    allow(Devops::IncrementMergeService).to receive(:new)

    job.execute(payload)

    expect(Devops::IncrementMergeService).not_to have_received(:new)
    expect(api_client).to have_received(:post)
      .with('/api/v1/internal/ai/dev_merges/op-1/report', hash_including('status' => 'failed', 'stage' => 'kill_switch'))
  end

  it 'keeps the private-extension names out of its log line' do
    redacted = described_class.redact_args([ payload ])

    expect(redacted.inspect).not_to include('zzhidden')
    expect(redacted.first['forbidden_names']).to eq('[1 names]')
  end

  describe 'remote resolution' do
    before do
      allow(api_client).to receive(:get).with('/api/v1/internal/git/repositories/repo-1').and_return(
        'data' => { 'id' => 'repo-1', 'full_name' => 'o/r', 'clone_url' => 'https://git.example.invalid/o/r.git',
                    'credential' => { 'id' => 'cred-1', 'provider_type' => 'gitea',
                                      'provider' => { 'api_base_url' => 'https://git.example.invalid/api/v1' } } }
      )
      allow(api_client).to receive(:get).with('/api/v1/internal/git/credentials/cred-1/decrypted').and_return(
        'data' => { 'credentials' => { 'access_token' => 'tok-secret' }, 'provider' => { 'provider_type' => 'gitea' } }
      )
    end

    it 'carries the token in an Authorization header, never in the URL, and marks it for scrubbing' do
      remote = job.send(:resolve_remote, 'repo-1')

      expect(remote[:url]).to eq('https://git.example.invalid/o/r.git')
      expect(remote[:auth_header]).to eq("Authorization: Basic #{Base64.strict_encode64('git:tok-secret')}")
      expect(remote[:secrets]).to include('tok-secret')
    end

    it 'hands the Gitea provider the host base, since it appends /api/v1 itself' do
      expect(job.send(:resolve_remote, 'repo-1')[:api_config])
        .to include('provider_type' => 'gitea', 'api_url' => 'https://git.example.invalid')
    end
  end
end
