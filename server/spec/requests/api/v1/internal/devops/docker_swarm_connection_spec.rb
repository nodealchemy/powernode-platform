# frozen_string_literal: true

require 'rails_helper'

# The worker (worker/app/jobs/docker/host_sync_job.rb,
# worker/app/jobs/docker/health_check_job.rb, and every worker/app/jobs/swarm/*
# job via DockerClientConcern) fetches connection details via
# `response.dig("data", "connection")` — identically for both Docker hosts and
# Swarm clusters. Api::V1::Internal::Devops::DockerController#connection
# already nested its payload under a `connection:` key; SwarmController#connection
# did not (render_success(cluster_id:, api_endpoint:, ...) puts those keys
# directly under `data`, with no `connection` wrapper), so `dig("data",
# "connection")` returned nil for every Swarm job and build_docker_client(nil)
# raised before ever reaching the host/port/TLS logic.
RSpec.describe 'Api::V1::Internal::Devops docker/swarm #connection', type: :request do
  let(:account) { create(:account) }
  let(:worker) { create(:worker, account: account) }
  let(:worker_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }
  end

  describe 'GET /api/v1/internal/devops/docker/hosts/:id/connection' do
    let(:host) do
      create(:devops_docker_host, :with_tls, account: account,
        api_endpoint: 'https://docker-host-1.example.com:2376', tls_verify: false)
    end

    it 'nests the connection payload the worker expects under data.connection' do
      get api_v1_internal_devops_docker_host_connection_path(host), headers: worker_headers

      json = JSON.parse(response.body)
      connection = json.dig('data', 'connection')

      expect(connection).to be_present
      expect(connection['api_endpoint']).to eq(host.api_endpoint)
      expect(connection['encrypted_tls_credentials']).to eq(host.encrypted_tls_credentials)
      expect(connection['tls_verify']).to eq(false)
    end
  end

  describe 'GET /api/v1/internal/devops/swarm/clusters/:id/connection' do
    let(:cluster) do
      create(:devops_swarm_cluster, account: account,
        api_endpoint: 'https://swarm-cluster-1.example.com:2377',
        encrypted_tls_credentials: { client_cert: 'CERT', client_key: 'KEY' }.to_json,
        tls_verify: false)
    end

    it 'nests the connection payload the worker expects under data.connection' do
      get api_v1_internal_devops_swarm_cluster_connection_path(cluster), headers: worker_headers

      json = JSON.parse(response.body)
      connection = json.dig('data', 'connection')

      expect(connection).to be_present
      expect(connection['api_endpoint']).to eq(cluster.api_endpoint)
      expect(connection['encrypted_tls_credentials']).to eq(cluster.encrypted_tls_credentials)
      expect(connection['tls_verify']).to eq(false)
    end
  end
end
