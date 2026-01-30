# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::Attributions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write']) }
  let(:admin_user) { create(:user, account: account, permissions: ['supply_chain.read', 'supply_chain.write', 'supply_chain.admin']) }
  let(:read_only_user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: ['supply_chain.read']) }

  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/supply_chain/attributions' do
    let!(:sbom_component) { create(:supply_chain_sbom_component, account: account) }
    let!(:license) { create(:supply_chain_license) }
    let!(:attribution1) { create(:supply_chain_attribution, account: account, sbom_component: sbom_component, license: license) }
    let!(:attribution2) { create(:supply_chain_attribution, account: account) }
    let!(:other_attribution) { create(:supply_chain_attribution, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of attributions for current account' do
        get '/api/v1/supply_chain/attributions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['attributions']).to be_an(Array)
        expect(data['attributions'].length).to eq(2)
        expect(data['attributions'].none? { |a| a['id'] == other_attribution.id }).to be true
        expect(json_response['meta']).to have_key('total_count')
      end

      it 'filters by requires_attribution type' do
        attribution1.update!(requires_attribution: true)
        attribution2.update!(requires_attribution: false)

        get '/api/v1/supply_chain/attributions', params: { type: 'requires_attribution' }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['attributions'].all? { |a| a['requires_attribution'] == true }).to be true
      end

      it 'filters by license_id' do
        get '/api/v1/supply_chain/attributions', params: { license_id: license.id }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['attributions'].all? { |a| a['license']['id'] == license.id }).to be true
      end

      it 'filters by sbom_component_id' do
        get '/api/v1/supply_chain/attributions', params: { sbom_component_id: sbom_component.id }, headers: headers

        expect_success_response
        data = json_response_data
        expect(data['attributions'].length).to eq(1)
        expect(data['attributions'].first['sbom_component']['id']).to eq(sbom_component.id)
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/attributions', headers: unauthorized_headers, as: :json

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/attributions', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/attributions/:id' do
    let(:sbom_component) { create(:supply_chain_sbom_component, account: account) }
    let(:license) { create(:supply_chain_license) }
    let(:attribution) { create(:supply_chain_attribution, account: account, sbom_component: sbom_component, license: license) }
    let(:other_attribution) { create(:supply_chain_attribution, account: other_account) }

    context 'with proper permissions' do
      it 'returns attribution details' do
        get "/api/v1/supply_chain/attributions/#{attribution.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['attribution']['id']).to eq(attribution.id)
        expect(data['attribution']['package_name']).to eq(attribution.package_name)
        expect(data['attribution']['sbom_component']).to be_present
        expect(data['attribution']['license']).to be_present
        # Details included in show
        expect(data['attribution']['license_text']).to be_present.or be_nil
        expect(data['attribution']['notice_text']).to be_present.or be_nil
        expect(data['attribution']['attribution_url']).to be_present.or be_nil
      end

      it 'returns not found for non-existent attribution' do
        get "/api/v1/supply_chain/attributions/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Attribution not found', 404)
      end
    end

    context 'accessing attribution from different account' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/attributions/#{other_attribution.id}", headers: headers, as: :json

        expect_error_response('Attribution not found', 404)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/attributions' do
    let(:sbom_component) { create(:supply_chain_sbom_component, account: account) }
    let(:license) { create(:supply_chain_license) }
    let(:valid_params) do
      {
        attribution: {
          sbom_component_id: sbom_component.id,
          license_id: license.id,
          package_name: 'test-package',
          package_version: '1.0.0',
          copyright_holder: 'Test Company',
          copyright_year: 2024,
          requires_attribution: true
        }
      }
    end

    context 'with proper permissions' do
      it 'creates a new attribution' do
        expect {
          post '/api/v1/supply_chain/attributions', params: valid_params, headers: headers, as: :json
        }.to change { account.supply_chain_attributions.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['attribution']['package_name']).to eq('test-package')
        expect(data['attribution']['copyright_holder']).to eq('Test Company')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { attribution: { package_name: nil } }

        post '/api/v1/supply_chain/attributions', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post '/api/v1/supply_chain/attributions', params: valid_params, headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'PATCH /api/v1/supply_chain/attributions/:id' do
    let(:attribution) { create(:supply_chain_attribution, account: account) }
    let(:update_params) do
      {
        attribution: {
          copyright_holder: 'Updated Company',
          copyright_year: 2025
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the attribution' do
        patch "/api/v1/supply_chain/attributions/#{attribution.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['attribution']['copyright_holder']).to eq('Updated Company')
        expect(data['attribution']['copyright_year']).to eq(2025)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        patch "/api/v1/supply_chain/attributions/#{attribution.id}", params: update_params, headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'DELETE /api/v1/supply_chain/attributions/:id' do
    let!(:attribution) { create(:supply_chain_attribution, account: account) }

    context 'with proper permissions' do
      it 'deletes the attribution' do
        expect {
          delete "/api/v1/supply_chain/attributions/#{attribution.id}", headers: headers, as: :json
        }.to change { account.supply_chain_attributions.count }.by(-1)

        expect_success_response
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        delete "/api/v1/supply_chain/attributions/#{attribution.id}", headers: read_only_headers, as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/attributions/generate_notice_file' do
    let(:sbom) { create(:supply_chain_sbom, account: account) }
    let!(:sbom_component) { create(:supply_chain_sbom_component, account: account) }
    let!(:license) { create(:supply_chain_license) }
    let!(:attribution) { create(:supply_chain_attribution, account: account, sbom_component: sbom_component, license: license) }

    context 'with proper permissions' do
      it 'generates a notice file' do
        allow(::SupplyChain::AttributionService).to receive(:generate_notice_file).and_return({
          success: true,
          content: 'Generated notice file content',
          format: 'text',
          component_count: 1,
          license_count: 1
        })

        post '/api/v1/supply_chain/attributions/generate_notice_file',
             params: { sbom_id: sbom.id, format: 'text' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['notice_file']).to include(
          'content' => 'Generated notice file content',
          'format' => 'text',
          'component_count' => 1,
          'license_count' => 1
        )
      end

      it 'returns error when sbom_id is missing' do
        post '/api/v1/supply_chain/attributions/generate_notice_file',
             headers: headers,
             as: :json

        expect_error_response('sbom_id is required', 422)
      end

      it 'returns error when SBOM not found' do
        post '/api/v1/supply_chain/attributions/generate_notice_file',
             params: { sbom_id: SecureRandom.uuid },
             headers: headers,
             as: :json

        expect_error_response('SBOM not found', 404)
      end

      it 'returns error when generation fails' do
        allow(::SupplyChain::AttributionService).to receive(:generate_notice_file).and_return({
          success: false,
          error: 'Generation failed'
        })

        post '/api/v1/supply_chain/attributions/generate_notice_file',
             params: { sbom_id: sbom.id },
             headers: headers,
             as: :json

        expect_error_response('Generation failed', 422)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post '/api/v1/supply_chain/attributions/generate_notice_file',
             params: { sbom_id: sbom.id },
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/attributions/export' do
    let!(:attribution) { create(:supply_chain_attribution, account: account) }

    context 'with proper permissions' do
      it 'exports attributions as JSON' do
        get '/api/v1/supply_chain/attributions/export',
            params: { export_format: 'json' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['attributions']).to be_an(Array)
        expect(data['exported_at']).to be_present
        expect(data['total_count']).to eq(1)
      end

      it 'exports attributions as CSV' do
        get '/api/v1/supply_chain/attributions/export',
            params: { export_format: 'csv' },
            headers: headers

        expect(response).to have_http_status(:success)
        expect(response.content_type).to include('text/csv')
        expect(response.headers['Content-Disposition']).to include('attributions')
      end

      it 'exports attributions as SPDX' do
        get '/api/v1/supply_chain/attributions/export',
            params: { export_format: 'spdx' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['spdxVersion']).to eq('SPDX-2.3')
        expect(data['packages']).to be_an(Array)
      end

      it 'returns error for unsupported format' do
        get '/api/v1/supply_chain/attributions/export',
            params: { export_format: 'xml' },
            headers: headers

        expect_error_response('Unsupported format: xml', 422)
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/attributions/export',
            headers: unauthorized_headers

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end
  end
end
