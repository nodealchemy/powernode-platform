# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Swarm::Clusters', type: :request do
  let(:account) { create(:account) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['devops.swarm.read', 'devops.swarm.manage']) }

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
        { "ApiVersion" => "1.45", "Swarm" => { "Nodes" => 3, "Managers" => 1 } }
      )
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:swarm_inspect).and_return(
        { "ID" => "swarm-abc123" }
      )
    end

    it 'packs raw tls params into the encrypted_tls_credentials blob on create' do
      post '/api/v1/devops/swarm/clusters',
           params: { cluster: { name: 'TLS Cluster', api_endpoint: 'https://swarm.example.com:2377',
                                environment: 'production', tls_ca: 'placeholder-ca',
                                tls_cert: 'placeholder-client-cert', tls_key: 'placeholder-client-key' } },
           headers: headers, as: :json

      expect_success_response
      cluster = Devops::SwarmCluster.find(json_response['data']['cluster']['id'])
      expect(JSON.parse(cluster.encrypted_tls_credentials)).to eq(
        'ca_cert' => 'placeholder-ca',
        'client_cert' => 'placeholder-client-cert',
        'client_key' => 'placeholder-client-key'
      )
    end

    it 'leaves encrypted_tls_credentials unset when no tls params are given' do
      post '/api/v1/devops/swarm/clusters',
           params: { cluster: { name: 'No TLS Cluster', api_endpoint: 'https://swarm.example.com:2377',
                                environment: 'production' } },
           headers: headers, as: :json

      expect_success_response
      cluster = Devops::SwarmCluster.find(json_response['data']['cluster']['id'])
      expect(cluster.encrypted_tls_credentials).to be_nil
    end

    it 'repacks encrypted_tls_credentials on update' do
      cluster = create(:devops_swarm_cluster, account: account)

      patch "/api/v1/devops/swarm/clusters/#{cluster.id}",
            params: { cluster: { tls_ca: 'updated-ca', tls_cert: 'updated-cert', tls_key: 'updated-key' } },
            headers: headers, as: :json

      expect_success_response
      expect(JSON.parse(cluster.reload.encrypted_tls_credentials)).to eq(
        'ca_cert' => 'updated-ca',
        'client_cert' => 'updated-cert',
        'client_key' => 'updated-key'
      )
    end
  end
end
