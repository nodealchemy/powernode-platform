# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::VendorMonitoringEvents', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:write_user) { create(:user, account: account, permissions: ['supply_chain.write']) }
  let(:headers) { auth_headers_for(user) }
  let(:write_headers) { auth_headers_for(write_user) }

  let(:vendor) { create(:supply_chain_vendor, account: account) }
  let!(:monitoring_event) do
    create(:supply_chain_vendor_monitoring_event,
           account: account,
           vendor: vendor,
           event_type: 'security_incident',
           severity: 'high',
           is_acknowledged: false)
  end

  describe 'GET /api/v1/supply_chain/vendor_monitoring_events' do
    context 'with valid authentication and permissions' do
      it 'returns list of vendor monitoring events' do
        get '/api/v1/supply_chain/vendor_monitoring_events', headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['vendor_monitoring_events']).to be_an(Array)
        expect(data['vendor_monitoring_events'].first['id']).to eq(monitoring_event.id)
        expect(data['vendor_monitoring_events'].first['event_type']).to eq('security_incident')
      end

      it 'includes vendor details' do
        get '/api/v1/supply_chain/vendor_monitoring_events', headers: headers

        data = json_response_data
        event = data['vendor_monitoring_events'].first
        expect(event['vendor']).to be_present
        expect(event['vendor']['id']).to eq(vendor.id)
        expect(event['vendor']['name']).to eq(vendor.name)
      end

      it 'filters by event_type' do
        create(:supply_chain_vendor_monitoring_event,
               account: account,
               vendor: vendor,
               event_type: 'compliance_update')

        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { event_type: 'security_incident' },
            headers: headers

        data = json_response_data
        expect(data['vendor_monitoring_events'].all? { |e| e['event_type'] == 'security_incident' }).to be true
      end

      it 'filters by severity' do
        create(:supply_chain_vendor_monitoring_event,
               account: account,
               vendor: vendor,
               severity: 'low')

        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { severity: 'high' },
            headers: headers

        data = json_response_data
        expect(data['vendor_monitoring_events'].all? { |e| e['severity'] == 'high' }).to be true
      end

      it 'filters by vendor_id' do
        other_vendor = create(:supply_chain_vendor, account: account)
        create(:supply_chain_vendor_monitoring_event, account: account, vendor: other_vendor)

        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { vendor_id: vendor.id },
            headers: headers

        data = json_response_data
        expect(data['vendor_monitoring_events'].all? { |e| e['vendor']['id'] == vendor.id }).to be true
      end

      it 'filters unacknowledged events' do
        create(:supply_chain_vendor_monitoring_event, :acknowledged,
               account: account,
               vendor: vendor)

        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { unacknowledged: 'true' },
            headers: headers

        data = json_response_data
        expect(data['vendor_monitoring_events'].all? { |e| e['is_acknowledged'] == false }).to be true
      end

      it 'filters active (unresolved) events' do
        create(:supply_chain_vendor_monitoring_event, :resolved,
               account: account,
               vendor: vendor)

        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { active: 'true' },
            headers: headers

        data = json_response_data
        expect(data['vendor_monitoring_events'].all? { |e| e['resolved_at'].nil? }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/supply_chain/vendor_monitoring_events',
            params: { page: 1, per_page: 10 },
            headers: headers

        expect(response).to have_http_status(:ok)
        expect(json_response['meta']).to be_present
      end
    end

    context 'without proper permissions' do
      let(:no_permission_user) { create(:user, account: account, permissions: []) }
      let(:no_permission_headers) { auth_headers_for(no_permission_user) }

      it 'returns forbidden error' do
        get '/api/v1/supply_chain/vendor_monitoring_events', headers: no_permission_headers

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('Insufficient permissions')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/vendor_monitoring_events'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/vendor_monitoring_events/:id' do
    context 'with valid authentication and permissions' do
      it 'returns vendor monitoring event details' do
        get "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}", headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['vendor_monitoring_event']['id']).to eq(monitoring_event.id)
        expect(data['vendor_monitoring_event']['event_type']).to eq('security_incident')
        expect(data['vendor_monitoring_event']['severity']).to eq('high')
      end

      it 'includes detailed information' do
        monitoring_event.update!(
          description: 'Detailed description',
          recommended_actions: [{ 'action' => 'action1' }, { 'action' => 'action2' }],
          metadata: { source: 'test' }
        )

        get "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}", headers: headers

        data = json_response_data
        event = data['vendor_monitoring_event']
        expect(event['description']).to eq('Detailed description')
        expect(event['recommended_actions']).to be_an(Array)
        expect(event['metadata']).to be_present
      end
    end

    context 'with non-existent event' do
      it 'returns not found error' do
        get '/api/v1/supply_chain/vendor_monitoring_events/non-existent-id', headers: headers

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to include('not found')
      end
    end

    context 'without proper permissions' do
      let(:no_permission_user) { create(:user, account: account, permissions: []) }
      let(:no_permission_headers) { auth_headers_for(no_permission_user) }

      it 'returns forbidden error' do
        get "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}", headers: no_permission_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendor_monitoring_events/:id/acknowledge' do
    context 'with valid authentication and write permissions' do
      it 'acknowledges the event' do
        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/acknowledge",
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['vendor_monitoring_event']['is_acknowledged']).to be true
        expect(json_response['message']).to include('acknowledged')
      end

      it 'returns error when already acknowledged' do
        monitoring_event.update!(is_acknowledged: true, acknowledged_at: Time.current)

        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/acknowledge",
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('already acknowledged')
      end
    end

    context 'without write permissions' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/acknowledge",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('Insufficient permissions')
      end
    end
  end

  describe 'POST /api/v1/supply_chain/vendor_monitoring_events/:id/resolve' do
    context 'with valid authentication and write permissions' do
      it 'resolves the event' do
        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/resolve",
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['vendor_monitoring_event']['resolved_at']).to be_present
        expect(json_response['message']).to include('resolved')
      end

      it 'returns error when already resolved' do
        monitoring_event.update!(resolved_at: Time.current)

        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/resolve",
             headers: write_headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['error']).to include('already resolved')
      end
    end

    context 'without write permissions' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/vendor_monitoring_events/#{monitoring_event.id}/resolve",
             headers: headers,
             as: :json

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('Insufficient permissions')
      end
    end
  end
end
