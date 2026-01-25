# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::LicenseDetections', type: :request do
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

  describe 'GET /api/v1/supply_chain/license_detections' do
    let!(:component) { create(:supply_chain_component, account: account) }
    let!(:license1) { create(:supply_chain_license, spdx_id: 'MIT') }
    let!(:license2) { create(:supply_chain_license, spdx_id: 'Apache-2.0') }
    let!(:detection1) do
      create(:supply_chain_license_detection,
             account: account,
             component: component,
             license: license1,
             detection_method: 'file_scan',
             confidence_level: 'high',
             overridden: false)
    end
    let!(:detection2) do
      create(:supply_chain_license_detection,
             account: account,
             component: component,
             license: license2,
             detection_method: 'package_metadata',
             confidence_level: 'medium',
             overridden: true,
             overridden_by: user)
    end
    let!(:other_detection) { create(:supply_chain_license_detection, account: other_account) }

    context 'with proper permissions' do
      it 'returns list of license detections for current account' do
        get '/api/v1/supply_chain/license_detections', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['license_detections']).to be_an(Array)
        expect(data['license_detections'].length).to eq(2)
        expect(data['license_detections'].none? { |d| d['id'] == other_detection.id }).to be true
        expect(data['meta']).to have_key('total')
      end

      it 'filters by detection method' do
        get '/api/v1/supply_chain/license_detections',
            params: { method: 'file_scan' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].length).to eq(1)
        expect(data['license_detections'].first['detection_method']).to eq('file_scan')
      end

      it 'filters by confidence level' do
        get '/api/v1/supply_chain/license_detections',
            params: { confidence: 'high' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].all? { |d| d['confidence_level'] == 'high' }).to be true
      end

      it 'filters by overridden status (true)' do
        get '/api/v1/supply_chain/license_detections',
            params: { overridden: 'true' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].all? { |d| d['overridden'] == true }).to be true
      end

      it 'filters by overridden status (false)' do
        get '/api/v1/supply_chain/license_detections',
            params: { overridden: 'false' },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].all? { |d| d['overridden'] == false }).to be true
      end

      it 'filters by license_id' do
        get '/api/v1/supply_chain/license_detections',
            params: { license_id: license1.id },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].all? { |d| d['detected_license']['id'] == license1.id }).to be true
      end

      it 'filters by component_id' do
        get '/api/v1/supply_chain/license_detections',
            params: { component_id: component.id },
            headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections'].all? { |d| d['component']['id'] == component.id }).to be true
      end
    end

    context 'without supply_chain.read permission' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/license_detections', headers: unauthorized_headers, as: :json

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/license_detections', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/license_detections/:id' do
    let(:component) { create(:supply_chain_component, account: account) }
    let(:license) { create(:supply_chain_license) }
    let(:override_license) { create(:supply_chain_license, spdx_id: 'GPL-3.0') }
    let(:detection) do
      create(:supply_chain_license_detection,
             account: account,
             component: component,
             license: license,
             overridden: true,
             override_license: override_license,
             override_reason: 'Manual review',
             overridden_by: user,
             source_file: 'package.json',
             match_text: 'MIT License')
    end
    let(:other_detection) { create(:supply_chain_license_detection, account: other_account) }

    context 'with proper permissions' do
      it 'returns license detection details' do
        get "/api/v1/supply_chain/license_detections/#{detection.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['license_detection']).to include(
          'id' => detection.id,
          'detection_method' => detection.detection_method,
          'confidence_level' => detection.confidence_level,
          'overridden' => true
        )
        expect(data['license_detection']['component']).to be_present
        expect(data['license_detection']['detected_license']).to be_present
        expect(data['license_detection']['effective_license']['id']).to eq(override_license.id)
        expect(data['license_detection']['source_file']).to be_present
        expect(data['license_detection']['match_text']).to be_present
        expect(data['license_detection']['override_reason']).to be_present
        expect(data['license_detection']['overridden_by']).to be_present
      end

      it 'returns not found for non-existent detection' do
        get "/api/v1/supply_chain/license_detections/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('License detection not found', 404)
      end
    end

    context 'accessing detection from different account' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/license_detections/#{other_detection.id}", headers: headers, as: :json

        expect_error_response('License detection not found', 404)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/license_detections/:id/override' do
    let(:component) { create(:supply_chain_component, account: account) }
    let(:original_license) { create(:supply_chain_license, spdx_id: 'MIT') }
    let(:new_license) { create(:supply_chain_license, spdx_id: 'Apache-2.0') }
    let(:detection) do
      create(:supply_chain_license_detection,
             account: account,
             component: component,
             license: original_license,
             overridden: false)
    end

    context 'with proper permissions' do
      it 'overrides the license detection' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/override",
             params: { license_id: new_license.id, reason: 'Manual verification' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['license_detection']['overridden']).to be true
        expect(data['license_detection']['effective_license']['id']).to eq(new_license.id)
        expect(data['message']).to eq('License detection overridden')

        detection.reload
        expect(detection.override_license_id).to eq(new_license.id)
        expect(detection.override_reason).to eq('Manual verification')
        expect(detection.overridden_by).to eq(user)
        expect(detection.overridden_at).to be_present
      end

      it 'returns error when license_id is missing' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/override",
             params: { reason: 'Test' },
             headers: headers,
             as: :json

        expect_error_response('license_id is required for override', 422)
      end

      it 'returns error when license not found' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/override",
             params: { license_id: SecureRandom.uuid, reason: 'Test' },
             headers: headers,
             as: :json

        expect_error_response('License not found', 404)
      end
    end

    context 'without supply_chain.write permission' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/override",
             params: { license_id: new_license.id, reason: 'Test' },
             headers: read_only_headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end
end
