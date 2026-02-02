# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::LicenseDetections', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'supply_chain.read' ]) }
  let(:write_user) { create(:user, account: account, permissions: [ 'supply_chain.write' ]) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }
  let(:write_headers) { auth_headers_for(write_user) }
  let(:unauthorized_headers) { auth_headers_for(unauthorized_user) }

  let(:sbom_component) { create(:supply_chain_sbom_component, account: account) }
  let(:license) { create(:supply_chain_license) }

  let!(:detection) do
    create(:supply_chain_license_detection,
           account: account,
           sbom_component: sbom_component,
           license: license,
           detected_license_id: 'MIT',
           detected_license_name: 'MIT License',
           detection_source: 'manifest',
           confidence_score: 0.95,
           is_primary: true,
           requires_review: false)
  end

  describe 'GET /api/v1/supply_chain/license_detections' do
    context 'with valid authentication and permissions' do
      it 'returns list of license detections' do
        get '/api/v1/supply_chain/license_detections', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detections']).to be_an(Array)
        expect(data['license_detections'].first['id']).to eq(detection.id)
        expect(data['license_detections'].first['detected_license_id']).to eq('MIT')
        expect(data['license_detections'].first['detected_license_name']).to eq('MIT License')
      end

      it 'includes detection metadata' do
        get '/api/v1/supply_chain/license_detections', headers: headers

        data = json_response_data
        det = data['license_detections'].first
        expect(det['detection_source']).to eq('manifest')
        expect(det['confidence_score'].to_f).to eq(0.95)
        expect(det['is_primary']).to be true
        expect(det['requires_review']).to be false
      end

      it 'includes sbom_component details' do
        get '/api/v1/supply_chain/license_detections', headers: headers

        data = json_response_data
        det = data['license_detections'].first
        expect(det['sbom_component']).to be_present
        expect(det['sbom_component']['id']).to eq(sbom_component.id)
        expect(det['sbom_component']['version']).to eq(sbom_component.version)
      end

      it 'includes license details' do
        get '/api/v1/supply_chain/license_detections', headers: headers

        data = json_response_data
        det = data['license_detections'].first
        expect(det['license']).to be_present
        expect(det['license']['id']).to eq(license.id)
        expect(det['license']['spdx_id']).to eq(license.spdx_id)
        expect(det['license']['name']).to eq(license.name)
      end

      it 'includes effective license information' do
        get '/api/v1/supply_chain/license_detections', headers: headers

        data = json_response_data
        det = data['license_detections'].first
        expect(det['effective_license_id']).to be_present
        expect(det['effective_license_name']).to be_present
      end

      it 'filters by source (detection_source)' do
        create(:supply_chain_license_detection,
               account: account,
               detection_source: 'file')

        get '/api/v1/supply_chain/license_detections',
            params: { source: 'manifest' },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['detection_source'] == 'manifest' }).to be true
      end

      it 'filters by requires_review true' do
        create(:supply_chain_license_detection,
               account: account,
               requires_review: true)

        get '/api/v1/supply_chain/license_detections',
            params: { requires_review: 'true' },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['requires_review'] == true }).to be true
      end

      it 'filters by requires_review false' do
        create(:supply_chain_license_detection,
               account: account,
               requires_review: true)

        get '/api/v1/supply_chain/license_detections',
            params: { requires_review: 'false' },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['requires_review'] == false }).to be true
      end

      it 'filters by primary' do
        create(:supply_chain_license_detection,
               account: account,
               is_primary: false)

        get '/api/v1/supply_chain/license_detections',
            params: { primary: 'true' },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['is_primary'] == true }).to be true
      end

      it 'filters by license_id' do
        other_license = create(:supply_chain_license)
        create(:supply_chain_license_detection,
               account: account,
               license: other_license)

        get '/api/v1/supply_chain/license_detections',
            params: { license_id: license.id },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['license']['id'] == license.id }).to be true
      end

      it 'filters by sbom_component_id' do
        other_component = create(:supply_chain_sbom_component, account: account)
        create(:supply_chain_license_detection,
               account: account,
               sbom_component: other_component)

        get '/api/v1/supply_chain/license_detections',
            params: { sbom_component_id: sbom_component.id },
            headers: headers

        data = json_response_data
        expect(data['license_detections'].all? { |d| d['sbom_component']['id'] == sbom_component.id }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/supply_chain/license_detections',
            params: { page: 1, per_page: 10 },
            headers: headers

        expect_success_response
        expect(json_response['meta']).to be_present
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        get '/api/v1/supply_chain/license_detections', headers: unauthorized_headers

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/license_detections'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/license_detections/:id' do
    context 'with valid authentication and permissions' do
      it 'returns license detection details' do
        get "/api/v1/supply_chain/license_detections/#{detection.id}", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['license_detection']['id']).to eq(detection.id)
        expect(data['license_detection']['detected_license_id']).to eq('MIT')
        expect(data['license_detection']['detected_license_name']).to eq('MIT License')
        expect(data['license_detection']['detection_source']).to eq('manifest')
      end

      it 'includes detailed information' do
        detection.update!(
          file_path: 'package.json',
          ai_interpretation: { model: 'gpt-4', reasoning: 'test' },
          metadata: { detection_time_ms: 100 }
        )

        get "/api/v1/supply_chain/license_detections/#{detection.id}", headers: headers

        data = json_response_data
        det = data['license_detection']
        expect(det['file_path']).to eq('package.json')
        expect(det['ai_interpretation']).to be_present
        expect(det['metadata']).to be_present
      end

      it 'includes sbom_component and license details' do
        get "/api/v1/supply_chain/license_detections/#{detection.id}", headers: headers

        data = json_response_data
        det = data['license_detection']
        expect(det['sbom_component']).to be_present
        expect(det['sbom_component']['id']).to eq(sbom_component.id)
        expect(det['license']).to be_present
        expect(det['license']['id']).to eq(license.id)
      end
    end

    context 'with non-existent detection' do
      it 'returns not found error' do
        get "/api/v1/supply_chain/license_detections/#{SecureRandom.uuid}", headers: headers

        expect_error_response('License detection not found', 404)
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        get "/api/v1/supply_chain/license_detections/#{detection.id}", headers: unauthorized_headers

        expect_error_response('Insufficient permissions to view supply chain data', 403)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/license_detections/:id/mark_review' do
    context 'with valid authentication and write permissions' do
      it 'marks the detection for review' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/mark_review",
             params: { reason: 'Needs manual verification' },
             headers: write_headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['license_detection']['requires_review']).to be true
        expect(json_response['message']).to include('marked for review')

        detection.reload
        expect(detection.requires_review).to be true
        expect(detection.metadata['review_reason']).to eq('Needs manual verification')
      end

      it 'marks for review without reason' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/mark_review",
             headers: write_headers,
             as: :json

        expect_success_response
        detection.reload
        expect(detection.requires_review).to be true
      end
    end

    context 'without write permissions' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/license_detections/#{detection.id}/mark_review",
             params: { reason: 'Test' },
             headers: headers,
             as: :json

        expect_error_response('Insufficient permissions to manage supply chain data', 403)
      end
    end
  end
end
