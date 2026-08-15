# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Hosts', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['devops.docker.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['devops.docker.read', 'devops.docker.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/devops/docker/hosts' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_host, 3, account: account)
    end

    it 'returns list of hosts' do
      get '/api/v1/devops/docker/hosts', headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'filters by status' do
      create(:devops_docker_host, :connected, account: account)

      get "/api/v1/devops/docker/hosts?status=connected",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      statuses = response_data['data']['items'].map { |h| h['status'] }
      expect(statuses.uniq).to eq(['connected'])
    end

    it 'filters by environment' do
      create(:devops_docker_host, account: account, environment: 'production')

      get "/api/v1/devops/docker/hosts?environment=production",
          headers: headers, as: :json

      expect_success_response
      response_data = json_response
      envs = response_data['data']['items'].map { |h| h['environment'] }
      expect(envs.uniq).to eq(['production'])
    end

    context 'account isolation' do
      let(:other_account) { create(:account) }

      before do
        create(:devops_docker_host, account: other_account)
      end

      it 'does not return hosts from other accounts' do
        get '/api/v1/devops/docker/hosts', headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['items'].length).to eq(3)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/devops/docker/hosts', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'returns host details' do
      get "/api/v1/devops/docker/hosts/#{host.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']['id']).to eq(host.id)
      expect(response_data['data']['host']['name']).to eq(host.name)
    end

    context 'when host belongs to another account' do
      let(:other_account) { create(:account) }
      let(:other_host) { create(:devops_docker_host, account: other_account) }

      it 'returns not found' do
        get "/api/v1/devops/docker/hosts/#{other_host.id}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:valid_params) do
      {
        host: {
          name: 'New Docker Host',
          api_endpoint: 'https://docker.example.com:2376',
          environment: 'development'
        }
      }
    end

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(
        {
          "ServerVersion" => "24.0.7",
          "OperatingSystem" => "Ubuntu 22.04",
          "Architecture" => "x86_64",
          "KernelVersion" => "5.15.0",
          "MemTotal" => 8_589_934_592,
          "NCPU" => 4,
          "Containers" => 0,
          "Images" => 0,
          "ApiVersion" => "1.45"
        }
      )
    end

    it 'creates a new host' do
      post '/api/v1/devops/docker/hosts', params: valid_params, headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']['name']).to eq('New Docker Host')
      expect(response_data['data']['host']['status']).to eq('connected')
    end

    it 'returns 422 with invalid params' do
      post '/api/v1/devops/docker/hosts',
           params: { host: { name: '' } },
           headers: headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'PATCH /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'updates host successfully' do
      patch "/api/v1/devops/docker/hosts/#{host.id}",
            params: { host: { name: 'Updated Host Name' } },
            headers: headers, as: :json

      expect_success_response
      host.reload
      expect(host.name).to eq('Updated Host Name')
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    it 'deletes host successfully' do
      host_id = host.id

      delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

      expect_success_response
      expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
    end

    # IMP-20fb59ec849d — this endpoint tore down a MANAGED host with a bare
    # destroy!, so the operator's `system.runtime_docker_decommission` policy
    # was honoured on the MCP path (Ai::Tools::DockerProvisioningTool) and
    # silently skipped here. Managed teardown now routes through
    # Ai::AutonomyGate on the SAME action category, so one policy governs both
    # surfaces.
    context 'when the host is managed (NodeInstance-backed)' do
      let(:node) { sdwan_test_node(account: account) }
      let(:node_instance) { sdwan_test_node_instance(node: node) }
      let(:managed_host) do
        create(:devops_docker_host,
               account: account,
               provisioning_state: 'managed',
               api_endpoint: 'tcp://[fd00::30]:2376',
               node_instance_id: node_instance.id)
      end

      def operator_policy!(verb)
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'system.runtime_docker_decommission',
          scope: 'action_type', ai_agent_id: nil, policy: verb, priority: 5, is_active: true
        )
      end

      it 'parks the teardown for approval instead of destroying the row' do
        operator_policy!('require_approval')
        host_id = managed_host.id

        delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

        expect(response).to have_http_status(:accepted)
        expect(json_response['data']['pending']).to be true
        expect(Devops::DockerHost.find_by(id: host_id)).to be_present
      end

      it 'records the gate under the same action category as the MCP path' do
        operator_policy!('require_approval')
        host_id = managed_host.id

        delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

        operation = Ai::DeferredOperation.find_by(source_type: 'Devops::DockerHost', source_id: host_id)
        expect(operation).to be_present
        expect(operation.action_category).to eq('system.runtime_docker_decommission')
        expect(operation.params['host_id']).to eq(host_id)
      end

      it 'refuses outright when the operator policy blocks the category' do
        operator_policy!('block')
        host_id = managed_host.id

        delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(Devops::DockerHost.find_by(id: host_id)).to be_present
      end

      # The inverse oracle: refusing under require_approval/block proves
      # nothing about whether an operator who ALLOWED the action still gets it.
      it 'tears the host down, credential first, when the policy auto-approves' do
        operator_policy!('auto_approve')
        vault_provider = instance_double(Security::VaultCredentialProvider)
        allow(Security::VaultCredentialProvider).to receive(:new).and_return(vault_provider)
        allow(vault_provider).to receive(:purge_credential!).and_return(true)
        host_id = managed_host.id

        delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

        expect_success_response
        expect(vault_provider).to have_received(:purge_credential!)
          .with(credential_type: :docker_daemon_tls, credential_id: host_id)
        expect(Devops::DockerHost.find_by(id: host_id)).to be_nil

        # Through the gate, not around it: the outcome above is identical
        # whether the teardown was permitted or never gated at all, so the
        # operation row is what separates the two.
        operation = Ai::DeferredOperation.find_by(source_type: 'Devops::DockerHost', source_id: host_id)
        expect(operation).to be_present
        expect(operation.status).to eq('completed')
      end
    end

    # CONTROL: the ordinary registration-removal path must stay ungated — the
    # MCP twin resolves MANAGED hosts only, so `system.runtime_docker_decommission`
    # is a managed-host policy and an external host has no platform-issued TLS
    # material to purge. Gating it would turn every DELETE into a 202.
    context 'when the host is external (operator-registered)' do
      it 'deletes immediately and opens no gate' do
        Ai::InterventionPolicy.create!(
          account: account, action_category: 'system.runtime_docker_decommission',
          scope: 'action_type', ai_agent_id: nil, policy: 'require_approval',
          priority: 5, is_active: true
        )
        host_id = host.id

        delete "/api/v1/devops/docker/hosts/#{host_id}", headers: headers, as: :json

        expect_success_response
        expect(Devops::DockerHost.find_by(id: host_id)).to be_nil
        expect(Ai::DeferredOperation.where(source_type: 'Devops::DockerHost', source_id: host_id)).to be_empty
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:id/test_connection' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, account: account) }

    context 'when connection succeeds' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(
          { "ServerVersion" => "24.0.7", "ApiVersion" => "1.45", "OperatingSystem" => "Ubuntu", "Architecture" => "x86_64",
            "KernelVersion" => "5.15.0", "Containers" => 5, "Images" => 12, "MemTotal" => 8_589_934_592, "NCPU" => 4 }
        )
      end

      it 'returns connection result' do
        post "/api/v1/devops/docker/hosts/#{host.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['connection']['success']).to be true
      end
    end

    context 'when connection fails' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping)
          .and_raise(Devops::Docker::ApiClient::ConnectionError.new("Connection refused"))
      end

      it 'returns failure result' do
        post "/api/v1/devops/docker/hosts/#{host.id}/test_connection", headers: headers, as: :json

        expect_success_response
        response_data = json_response
        expect(response_data['data']['connection']['success']).to be false
      end
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:id/sync' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:host) { create(:devops_docker_host, account: account) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:container_list).and_return([])
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_list).and_return([])
    end

    it 'syncs host and returns details' do
      post "/api/v1/devops/docker/hosts/#{host.id}/sync", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['host']).to be_present
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:id/health' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:host) { create(:devops_docker_host, :connected, account: account) }

    it 'returns health information' do
      create(:devops_docker_container, :running, docker_host: host)
      create(:devops_docker_event, :critical, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/health", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      health = response_data['data']['health']
      expect(health['host_id']).to eq(host.id)
      expect(health['status']).to eq('connected')
      expect(health['container_health']).to be_present
      expect(health['image_stats']).to be_present
      expect(health['recent_events']).to be_present
    end
  end

  # Characterization of build_tls_credentials (shared Devops::TlsCredentialParams
  # concern): raw tls_ca/tls_cert/tls_key params are packed into the single
  # encrypted_tls_credentials JSON blob (keys ca_cert/client_cert/client_key) and
  # the raw keys are dropped. Fixtures are obviously-fake placeholders, not real
  # key material.
  describe 'TLS credential packing' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:ping).and_return("OK")
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:info).and_return(
        { "ServerVersion" => "24.0.7", "ApiVersion" => "1.45", "OperatingSystem" => "Ubuntu",
          "Architecture" => "x86_64", "KernelVersion" => "5.15.0", "Containers" => 0, "Images" => 0,
          "MemTotal" => 8_589_934_592, "NCPU" => 4 }
      )
    end

    it 'packs raw tls params into the encrypted_tls_credentials blob on create' do
      post '/api/v1/devops/docker/hosts',
           params: { host: { name: 'TLS Host', api_endpoint: 'https://docker.example.com:2376',
                             environment: 'development', tls_ca: 'placeholder-ca',
                             tls_cert: 'placeholder-client-cert', tls_key: 'placeholder-client-key' } },
           headers: headers, as: :json

      expect_success_response
      host = Devops::DockerHost.find(json_response['data']['host']['id'])
      expect(JSON.parse(host.encrypted_tls_credentials)).to eq(
        'ca_cert' => 'placeholder-ca',
        'client_cert' => 'placeholder-client-cert',
        'client_key' => 'placeholder-client-key'
      )
    end

    it 'leaves encrypted_tls_credentials unset when no tls params are given' do
      post '/api/v1/devops/docker/hosts',
           params: { host: { name: 'No TLS Host', api_endpoint: 'https://docker.example.com:2376',
                             environment: 'development' } },
           headers: headers, as: :json

      expect_success_response
      host = Devops::DockerHost.find(json_response['data']['host']['id'])
      expect(host.encrypted_tls_credentials).to be_nil
    end

    it 'repacks encrypted_tls_credentials on update' do
      host = create(:devops_docker_host, account: account)

      patch "/api/v1/devops/docker/hosts/#{host.id}",
            params: { host: { tls_ca: 'updated-ca', tls_cert: 'updated-cert', tls_key: 'updated-key' } },
            headers: headers, as: :json

      expect_success_response
      expect(JSON.parse(host.reload.encrypted_tls_credentials)).to eq(
        'ca_cert' => 'updated-ca',
        'client_cert' => 'updated-cert',
        'client_key' => 'updated-key'
      )
    end
  end
end
