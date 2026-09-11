# frozen_string_literal: true

require 'rails_helper'

# Regression coverage for the Swarm health-check reconciler, focused on the
# report_health_results seam (see review-lane9-render-success item 3c): each
# call has a server-side side effect (increments/resets the cluster's
# consecutive_failures streak, and creates a SwarmEvent per alert), so a
# response lost after the server already applied it must NOT be retried by
# this client — a retry would double-count the streak and duplicate events.
# post_no_retry (BackendApiClient) disables the default connection's 5x
# timeout/5xx retry middleware; this file pins that report_health_results
# goes through it and never through the retrying #post.
RSpec.describe Swarm::HealthCheckJob, type: :job do
  let(:job) { described_class.new }
  let(:api_client) { instance_double(BackendApiClient) }
  let(:docker) { instance_double(Faraday::Connection) }
  let(:cluster) { { 'id' => 'cluster-1', 'name' => 'prod-swarm' } }
  let(:connection) { { 'host' => '10.0.0.1', 'port' => '2376', 'tls_enabled' => false } }

  before do
    allow(job).to receive(:api_client).and_return(api_client)
    allow(job).to receive(:log_info)
    allow(job).to receive(:log_error)
    allow(job).to receive(:log_warn)

    allow(job).to receive(:build_docker_client).and_return(docker)

    allow(api_client).to receive(:get)
      .with('/api/v1/internal/devops/swarm/clusters', status: 'connected')
      .and_return({ 'data' => { 'clusters' => [cluster] } })
    allow(api_client).to receive(:get)
      .with('/api/v1/internal/devops/swarm/clusters/cluster-1/connection')
      .and_return({ 'data' => { 'connection' => connection } })

    ping_resp = instance_double(Faraday::Response, success?: true)
    nodes_resp = instance_double(Faraday::Response, success?: true, body: '[]')
    services_resp = instance_double(Faraday::Response, success?: true, body: '[]')
    allow(docker).to receive(:get).with('_ping').and_return(ping_resp)
    allow(docker).to receive(:get).with('nodes').and_return(nodes_resp)
    allow(docker).to receive(:get).with('services').and_return(services_resp)

    allow(api_client).to receive(:post_no_retry).and_return({})
  end

  it 'reports health results through post_no_retry, never the retrying post' do
    expect(api_client).to receive(:post_no_retry)
      .with('/api/v1/internal/devops/swarm/clusters/cluster-1/health_results', hash_including(status: 'healthy'))
    expect(api_client).not_to receive(:post)

    job.execute
  end

  it 'still reports (via post_no_retry) when the cluster health check itself raises' do
    allow(job).to receive(:check_cluster_health).and_raise(StandardError, 'boom')

    expect(api_client).to receive(:post_no_retry)
      .with('/api/v1/internal/devops/swarm/clusters/cluster-1/health_results', hash_including(status: 'unreachable'))
    expect(api_client).not_to receive(:post)

    job.execute
  end

  describe 'job configuration' do
    it 'runs on the devops_default queue' do
      expect(described_class.sidekiq_options['queue'].to_s).to eq('devops_default')
    end

    it 'inherits the shared BaseJob behavior' do
      expect(job).to be_a(BaseJob)
    end
  end
end
