# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::BuildProvenance', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['supply_chain.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/supply_chain/build_provenance' do
    let!(:repository) { create(:devops_repository, account: account) }
    let!(:attestation) { create(:supply_chain_attestation, account: account) }
    let!(:provenance1) do
      create(:supply_chain_build_provenance,
             account: account,
             repository: repository,
             attestation: attestation,
             build_type: 'github-actions',
             verified: true,
             reproducible: true)
    end
    let!(:provenance2) do
      create(:supply_chain_build_provenance,
             account: account,
             build_type: 'gitlab-ci',
             verified: false)
    end
    let!(:other_provenance) { create(:supply_chain_build_provenance, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of build provenances for current account' do
        get '/api/v1/supply_chain/build_provenance', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['build_provenances']).to be_an(Array)
        expect(data['build_provenances'].length).to eq(2)
        expect(data['build_provenances'].none? { |p| p['id'] == other_provenance.id }).to be true
        expect(data['meta']).to have_key('total')
      end

      it 'filters by build_type' do
        get '/api/v1/supply_chain/build_provenance',
            params: { build_type: 'github-actions' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['build_provenances'].length).to eq(1)
        expect(data['build_provenances'].first['build_type']).to eq('github-actions')
      end

      it 'filters by verified status' do
        get '/api/v1/supply_chain/build_provenance',
            params: { verified: 'true' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['build_provenances'].all? { |p| p['verified'] == true }).to be true
      end

      it 'filters by reproducible status' do
        get '/api/v1/supply_chain/build_provenance',
            params: { reproducible: 'true' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['build_provenances'].all? { |p| p['reproducible'] == true }).to be true
      end

      it 'filters by repository_id' do
        get '/api/v1/supply_chain/build_provenance',
            params: { repository_id: repository.id },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['build_provenances'].all? { |p| p['repository']['id'] == repository.id }).to be true
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/build_provenance', headers: unauthorized_headers, as: :json

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/build_provenance', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/build_provenance/:id' do
    let(:repository) { create(:devops_repository, account: account) }
    let(:attestation) { create(:supply_chain_attestation, account: account) }
    let(:provenance) do
      create(:supply_chain_build_provenance,
             account: account,
             repository: repository,
             attestation: attestation,
             build_config: { 'steps' => ['build', 'test'] },
             materials: [{ 'uri' => 'git+https://github.com/test/repo' }],
             environment: { 'os' => 'linux' })
    end
    let(:other_provenance) { create(:supply_chain_build_provenance, account: other_account) }

    context 'with proper permissions' do
      it 'returns build provenance details' do
        get "/api/v1/supply_chain/build_provenance/#{provenance.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['build_provenance']).to include(
          'id' => provenance.id,
          'provenance_id' => provenance.provenance_id,
          'build_type' => provenance.build_type,
          'verified' => provenance.verified,
          'reproducible' => provenance.reproducible
        )
        expect(data['build_provenance']['repository']).to be_present
        expect(data['build_provenance']['build_config']).to be_present
        expect(data['build_provenance']['materials']).to be_present
        expect(data['build_provenance']['environment']).to be_present
      end

      it 'returns not found for non-existent provenance' do
        get "/api/v1/supply_chain/build_provenance/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Build provenance not found', 404)
      end
    end

    context 'accessing provenance from different account' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/build_provenance/#{other_provenance.id}", headers: headers, as: :json

        expect_error_response('Build provenance not found', 404)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/build_provenance/:id/verify_reproducibility' do
    let(:provenance) do
      create(:supply_chain_build_provenance,
             account: account,
             reproducibility_status: 'not_verified')
    end

    context 'with proper permissions' do
      it 'starts reproducibility verification' do
        allow(::SupplyChain::ReproducibilityVerificationJob).to receive(:perform_later)

        post "/api/v1/supply_chain/build_provenance/#{provenance.id}/verify_reproducibility",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['build_provenance']['reproducibility_status']).to eq('verifying')
        expect(data['message']).to eq('Reproducibility verification started')

        expect(::SupplyChain::ReproducibilityVerificationJob)
          .to have_received(:perform_later).with(provenance.id, user.id)
      end

      it 'returns error when verification already in progress' do
        provenance.update!(reproducibility_status: 'verifying')

        post "/api/v1/supply_chain/build_provenance/#{provenance.id}/verify_reproducibility",
             headers: headers,
             as: :json

        expect_error_response('Verification already in progress', 422)
      end

      it 'returns error when update fails' do
        allow_any_instance_of(SupplyChain::BuildProvenance)
          .to receive(:update!)
          .and_raise(StandardError.new('Update failed'))

        post "/api/v1/supply_chain/build_provenance/#{provenance.id}/verify_reproducibility",
             headers: headers,
             as: :json

        expect_error_response('Failed to start verification: Update failed', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/build_provenance/#{provenance.id}/verify_reproducibility",
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end
end
