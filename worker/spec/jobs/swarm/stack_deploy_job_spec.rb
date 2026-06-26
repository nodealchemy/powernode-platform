# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the Docker Swarm stack deployer.
#
# This job mutates live infrastructure: it creates or updates Swarm services via
# the Docker Engine API. These specs never open a real Engine/HTTP connection —
# the Faraday Docker client (built by DockerClientConcern), the backend
# api_client, and the convergence poll loop are all stubbed. The focus is the
# load-bearing decision: create-a-new-service vs update-an-existing-service, and
# the in_progress -> completed/partially_converged/failed status contract.
RSpec.describe Swarm::StackDeployJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:docker) { instance_double(Faraday::Connection) }
  let(:deployment_id) { 'deploy-123' }
  let(:deployment_path) { "/api/v1/internal/devops/swarm/deployments/#{deployment_id}" }
  let(:connection_path) { '/api/v1/internal/devops/swarm/clusters/cluster-1/connection' }

  let(:deployment) do
    {
      'id' => deployment_id,
      'cluster_id' => 'cluster-1',
      'stack_name' => 'mystack',
      'compose_yaml' => "services:\n  web:\n    image: nginx:latest\n"
    }
  end
  let(:connection) do
    { 'host' => '10.0.0.1', 'port' => '2376', 'tls_enabled' => false }
  end

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)

    # Never build a real Faraday/TLS client or poll a real Engine for convergence.
    allow(job).to receive(:build_docker_client).and_return(docker)
    allow(job).to receive(:wait_for_convergence).and_return(true)

    allow(api_client).to receive(:get)
      .with(deployment_path)
      .and_return({ 'data' => { 'deployment' => deployment } })
    allow(api_client).to receive(:get)
      .with(connection_path)
      .and_return({ 'data' => { 'connection' => connection } })
    allow(api_client).to receive(:patch).and_return({})
  end

  describe 'job configuration' do
    it 'runs on the devops_high queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('devops_high')
    end

    it 'retries at most once (deploys are not freely re-runnable)' do
      expect(described_class.sidekiq_options['retry']).to eq(1)
    end

    it 'inherits the shared BaseJob behavior' do
      expect(job).to be_a(BaseJob)
    end
  end

  describe '#execute service create-vs-update branch' do
    context 'when the service does not yet exist' do
      before { allow(job).to receive(:find_existing_service).and_return(nil) }

      it 'issues an Engine API create and never an update' do
        create_resp = instance_double(Faraday::Response, success?: true, body: '{"ID":"svc-new"}')

        expect(docker).to receive(:post).with('/services/create').and_return(create_resp)
        expect(docker).not_to receive(:post).with(a_string_matching(%r{/update}))

        job.execute(deployment_id)
      end
    end

    context 'when the service already exists' do
      let(:existing) { { 'ID' => 'svc-123', 'Version' => { 'Index' => 7 } } }

      before { allow(job).to receive(:find_existing_service).and_return(existing) }

      it 'issues an Engine API update pinned to the current version index, never a create' do
        update_resp = instance_double(Faraday::Response, success?: true, body: '')

        expect(docker).to receive(:post).with('/services/svc-123/update?version=7').and_return(update_resp)
        expect(docker).not_to receive(:post).with('/services/create')

        job.execute(deployment_id)
      end
    end
  end

  describe '#execute status reporting' do
    before do
      allow(job).to receive(:find_existing_service).and_return(nil)
      allow(docker).to receive(:post)
        .with('/services/create')
        .and_return(instance_double(Faraday::Response, success?: true, body: '{"ID":"svc-new"}'))
    end

    it 'reports in_progress first, then completed when convergence succeeds' do
      allow(job).to receive(:wait_for_convergence).and_return(true)

      expect(api_client).to receive(:patch)
        .with(deployment_path, hash_including(status: 'in_progress')).ordered.and_return({})
      expect(api_client).to receive(:patch)
        .with(deployment_path, hash_including(status: 'completed')).ordered.and_return({})

      job.execute(deployment_id)
    end

    it 'reports partially_converged when convergence times out' do
      allow(job).to receive(:wait_for_convergence).and_return(false)

      expect(api_client).to receive(:patch)
        .with(deployment_path, hash_including(status: 'partially_converged')).and_return({})

      job.execute(deployment_id)
    end
  end

  describe '#execute failure path' do
    before do
      allow(job).to receive(:find_existing_service).and_return(nil)
      allow(docker).to receive(:post)
        .with('/services/create')
        .and_return(instance_double(Faraday::Response, success?: false, status: 500, body: 'boom'))
    end

    it 'marks the deployment failed and re-raises when the Engine rejects the create' do
      expect(api_client).to receive(:patch)
        .with(deployment_path, hash_including(status: 'failed')).and_return({})

      expect { job.execute(deployment_id) }.to raise_error(/Failed to create service/)
    end
  end

  describe '#parse_compose' do
    it 'rejects compose documents missing a services key' do
      expect { job.send(:parse_compose, "version: '3'\n") }
        .to raise_error(/missing 'services' key/)
    end
  end
end
