# frozen_string_literal: true

require 'rails_helper'

# IMP-80e613fb9c43 review round 2: Api::V1::Internal::Ai::DiscoveryController
# #mcp_servers looked the account up by the caller-SUPPLIED `account_id`
# param (`Account.find(params[:account_id])`), with no WorkerTenancy
# scoping — any worker-mTLS caller could read another account's MCP
# servers, including raw `capabilities` (config secrets, last_error,
# allow_network, ...) by simply passing that account's id. Fixed to scope
# through Api::V1::Internal::WorkerTenancy (same anchor the internal
# mcp_servers controller uses) and to return only `capabilities['tools']`
# — the only key AiDiscoveryScanJob (worker/app/jobs/ai_discovery_scan_job.rb)
# actually reads from this response.
RSpec.describe 'Api::V1::Internal::Ai::Discovery', type: :request do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  let(:worker) { create(:worker, account: account) }
  let(:worker_headers) do
    { 'X-Forwarded-Tls-Client-Cert-Info' => CGI.escape(%(Subject="CN=#{worker.node_instance_id}")) }
  end

  describe 'GET /api/v1/internal/ai/discovery/mcp_servers' do
    it "returns only the calling worker's own account's servers, sliced to capabilities['tools']" do
      server = create(:mcp_server, :connected, account: account)

      get '/api/v1/internal/ai/discovery/mcp_servers', params: { account_id: account.id }, headers: worker_headers

      expect_success_response
      data = json_response_data
      returned = data.find { |s| s['id'] == server.id }
      expect(returned).to be_present
      expect(returned['capabilities'].keys).to eq([ 'tools' ])
      expect(returned['capabilities']).not_to have_key('config')
      expect(returned['capabilities']).not_to have_key('last_error')
      expect(returned['capabilities']).not_to have_key('allow_network')
    end

    it "404s rather than disclosing another account's servers when a different account_id is supplied" do
      create(:mcp_server, :connected, account: other_account)

      get '/api/v1/internal/ai/discovery/mcp_servers', params: { account_id: other_account.id }, headers: worker_headers

      expect_error_response(nil, 404)
    end
  end

  # IMP-80e613fb9c43 review round 2 (fold-in): docker_hosts/swarm_clusters
  # had the identical `Account.find(params[:account_id])` tenancy gap. Their
  # serialized fields were checked for secrets (Devops::DockerHost/
  # SwarmCluster hold TLS material only in `encrypted_tls_credentials`,
  # never touched by either action's hand-picked id/name/status(+children)
  # shape) — nothing to slice there, only tenancy to fix.
  describe 'GET /api/v1/internal/ai/discovery/docker_hosts' do
    it "returns only the calling worker's own account's docker hosts, with no TLS material" do
      host = create(:devops_docker_host, :connected, account: account)

      get '/api/v1/internal/ai/discovery/docker_hosts', params: { account_id: account.id }, headers: worker_headers

      expect_success_response
      returned = json_response_data.find { |h| h['id'] == host.id }
      expect(returned).to include('id' => host.id, 'name' => host.name, 'status' => 'connected')
      expect(returned.keys).to match_array(%w[id name status containers])
    end

    # IMP-80e613fb9c43 review round 3: Devops::DockerContainer has no
    # `status` column (only `state`, an enumerated STATES value, and
    # `status_text`, a free-text Docker CLI-style display string) — the
    # pre-existing `c.status` call raised NoMethodError (uncaught: only
    # RecordNotFound was rescued) for any host with actual containers, so
    # this endpoint — and therefore Docker discovery entirely — never
    # worked once a host had children. Mapped to `state`: it's the
    # validated, enumerated, query/scope-backed field every model
    # predicate (running?/exited?/paused?/stopped?) and scope (running/
    # stopped/by_state) already treats as the container's canonical
    # status; `status_text` is an untyped mirror of Docker's human-readable
    # "Up 2 hours"-style string, not a status value. AiDiscoveryScanJob
    # only ever passes `container['status']` through into its own
    # discovered-agent payload for display (no branching on its value),
    # so `state` (e.g. "running", "exited") is exactly what a caller of
    # this endpoint needs.
    it "returns real container name/status for a host with containers, instead of 500ing" do
      host = create(:devops_docker_host, :connected, account: account)
      create(:devops_docker_container, docker_host: host, name: 'agent-runner', state: 'running')

      get '/api/v1/internal/ai/discovery/docker_hosts', params: { account_id: account.id }, headers: worker_headers

      expect_success_response
      returned = json_response_data.find { |h| h['id'] == host.id }
      expect(returned['containers']).to eq([ { 'name' => 'agent-runner', 'status' => 'running' } ])
    end

    it "404s rather than disclosing another account's docker hosts" do
      create(:devops_docker_host, :connected, account: other_account)

      get '/api/v1/internal/ai/discovery/docker_hosts', params: { account_id: other_account.id }, headers: worker_headers

      expect_error_response(nil, 404)
    end
  end

  describe 'GET /api/v1/internal/ai/discovery/swarm_clusters' do
    it "returns only the calling worker's own account's swarm clusters, with no join-token material" do
      cluster = create(:devops_swarm_cluster, account: account)

      get '/api/v1/internal/ai/discovery/swarm_clusters', params: { account_id: account.id }, headers: worker_headers

      expect_success_response
      returned = json_response_data.find { |c| c['id'] == cluster.id }
      expect(returned).to include('id' => cluster.id, 'name' => cluster.name, 'status' => cluster.status)
      expect(returned.keys).to match_array(%w[id name status services])
    end

    # IMP-80e613fb9c43 review round 3: Devops::SwarmService has no `name`
    # or `status` method/column at all (only `service_name`, and
    # replica-based health via #healthy?/#health_percentage) — the
    # pre-existing `s.name`/`s.status` calls raised NoMethodError
    # (uncaught) for any cluster with actual services, so Swarm discovery
    # never worked once a cluster had children either. `name` maps to
    # `service_name` (the model's own name field). `status` has no direct
    # column equivalent — a swarm service's health is expressed by
    # replica counts, not a single-word state like a container's — so it
    # is derived from the model's own pre-existing `#healthy?` predicate
    # ("healthy"/"unhealthy"), the same two-value shape as every other
    # status field in this codebase, rather than inventing a new concept.
    # AiDiscoveryScanJob only passes `service['status']` through for
    # display (no branching), so this is a safe, meaningful choice.
    it "returns real service name/status for a cluster with services, instead of 500ing" do
      cluster = create(:devops_swarm_cluster, account: account)
      Devops::SwarmService.create!(
        cluster: cluster, docker_service_id: SecureRandom.hex(8), service_name: 'agent-service',
        image: 'nginx:latest', desired_replicas: 2, running_replicas: 2
      )

      get '/api/v1/internal/ai/discovery/swarm_clusters', params: { account_id: account.id }, headers: worker_headers

      expect_success_response
      returned = json_response_data.find { |c| c['id'] == cluster.id }
      expect(returned['services']).to eq([ { 'name' => 'agent-service', 'status' => 'healthy' } ])
    end

    it "404s rather than disclosing another account's swarm clusters" do
      create(:devops_swarm_cluster, account: other_account)

      get '/api/v1/internal/ai/discovery/swarm_clusters', params: { account_id: other_account.id }, headers: worker_headers

      expect_error_response(nil, 404)
    end
  end

  describe 'POST /api/v1/internal/ai/discovery/:scan_id/complete' do
    it "completes the calling worker's own account's scan" do
      result = create(:ai_discovery_result, account: account, scan_type: 'full_scan', status: 'scanning')

      post "/api/v1/internal/ai/discovery/#{result.scan_id}/complete",
           params: { agents: [], connections: [], tools: [], recommendations: [] },
           headers: worker_headers, as: :json

      expect_success_response
      expect(result.reload.status).to eq('completed')
    end

    it "404s rather than completing (or disclosing) another account's scan" do
      result = create(:ai_discovery_result, account: other_account, scan_type: 'full_scan', status: 'scanning')

      post "/api/v1/internal/ai/discovery/#{result.scan_id}/complete",
           params: { agents: [] },
           headers: worker_headers, as: :json

      expect_error_response(nil, 404)
      expect(result.reload.status).not_to eq('completed')
    end
  end

  # IMP-80e613fb9c43 review round 3: `failed` had the identical unscoped
  # `Ai::DiscoveryResult.find_by!(scan_id: ...)` as `complete` (same file,
  # same shape) — folded in with the same fix.
  describe 'POST /api/v1/internal/ai/discovery/:scan_id/failed' do
    it "fails the calling worker's own account's scan" do
      result = create(:ai_discovery_result, account: account, scan_type: 'full_scan', status: 'scanning')

      post "/api/v1/internal/ai/discovery/#{result.scan_id}/failed",
           params: { error_message: 'boom' },
           headers: worker_headers, as: :json

      expect_success_response
      expect(result.reload.status).to eq('failed')
    end

    it "404s rather than failing (or disclosing) another account's scan" do
      result = create(:ai_discovery_result, account: other_account, scan_type: 'full_scan', status: 'scanning')

      post "/api/v1/internal/ai/discovery/#{result.scan_id}/failed",
           params: { error_message: 'boom' },
           headers: worker_headers, as: :json

      expect_error_response(nil, 404)
      expect(result.reload.status).not_to eq('failed')
    end
  end
end
