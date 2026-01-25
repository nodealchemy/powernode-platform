# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::SupplyChain::ScanExecutions', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['supply_chain.read']) }
  let(:write_user) { create(:user, account: account, permissions: ['supply_chain.write']) }
  let(:headers) { auth_headers_for(user) }
  let(:write_headers) { auth_headers_for(write_user) }

  let(:scan_instance) { create(:supply_chain_scan_instance, account: account) }
  let!(:scan_execution) do
    create(:supply_chain_scan_execution,
           account: account,
           scan_instance: scan_instance,
           status: 'completed',
           trigger_type: 'manual',
           triggered_by: user)
  end

  describe 'GET /api/v1/supply_chain/scan_executions' do
    context 'with valid authentication and permissions' do
      it 'returns list of scan executions' do
        get '/api/v1/supply_chain/scan_executions', headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['scan_executions']).to be_an(Array)
        expect(data['scan_executions'].first['id']).to eq(scan_execution.id)
        expect(data['scan_executions'].first['status']).to eq('completed')
      end

      it 'includes scan instance details' do
        get '/api/v1/supply_chain/scan_executions', headers: headers

        data = json_response_data
        execution = data['scan_executions'].first
        expect(execution['scan_instance']).to be_present
        expect(execution['scan_instance']['id']).to eq(scan_instance.id)
        expect(execution['scan_instance']['name']).to eq(scan_instance.name)
      end

      it 'filters by status' do
        create(:supply_chain_scan_execution, account: account, status: 'running')

        get '/api/v1/supply_chain/scan_executions', params: { status: 'completed' }, headers: headers

        data = json_response_data
        expect(data['scan_executions'].all? { |e| e['status'] == 'completed' }).to be true
      end

      it 'filters by trigger_type' do
        create(:supply_chain_scan_execution, account: account, trigger_type: 'scheduled')

        get '/api/v1/supply_chain/scan_executions', params: { trigger_type: 'manual' }, headers: headers

        data = json_response_data
        expect(data['scan_executions'].all? { |e| e['trigger_type'] == 'manual' }).to be true
      end

      it 'filters by scan_instance_id' do
        other_instance = create(:supply_chain_scan_instance, account: account)
        create(:supply_chain_scan_execution, account: account, scan_instance: other_instance)

        get '/api/v1/supply_chain/scan_executions',
            params: { scan_instance_id: scan_instance.id },
            headers: headers

        data = json_response_data
        expect(data['scan_executions'].length).to eq(1)
        expect(data['scan_executions'].first['scan_instance']['id']).to eq(scan_instance.id)
      end

      it 'filters by since timestamp' do
        old_execution = create(:supply_chain_scan_execution, account: account, created_at: 2.days.ago)
        since_time = 1.day.ago.iso8601

        get '/api/v1/supply_chain/scan_executions', params: { since: since_time }, headers: headers

        data = json_response_data
        expect(data['scan_executions'].map { |e| e['id'] }).not_to include(old_execution.id)
        expect(data['scan_executions'].map { |e| e['id'] }).to include(scan_execution.id)
      end

      it 'supports pagination' do
        get '/api/v1/supply_chain/scan_executions', params: { page: 1, per_page: 10 }, headers: headers

        expect(response).to have_http_status(:ok)
        expect(json_response['meta']).to be_present
      end
    end

    context 'without proper permissions' do
      let(:no_permission_user) { create(:user, account: account, permissions: []) }
      let(:no_permission_headers) { auth_headers_for(no_permission_user) }

      it 'returns forbidden error' do
        get '/api/v1/supply_chain/scan_executions', headers: no_permission_headers

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('Insufficient permissions')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/supply_chain/scan_executions'

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/supply_chain/scan_executions/:id' do
    context 'with valid authentication and permissions' do
      it 'returns scan execution details' do
        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}", headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['scan_execution']['id']).to eq(scan_execution.id)
        expect(data['scan_execution']['status']).to eq('completed')
      end

      it 'includes detailed information' do
        scan_execution.update!(
          input_data: { target_type: 'repository', target_id: '123' },
          output_data: { findings: 5 },
          metrics: { duration: 1234 }
        )

        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}", headers: headers

        data = json_response_data
        execution = data['scan_execution']
        expect(execution['input_data']).to be_present
        expect(execution['output_data']).to be_present
        expect(execution['metrics']).to be_present
      end
    end

    context 'with non-existent execution' do
      it 'returns not found error' do
        get '/api/v1/supply_chain/scan_executions/non-existent-id', headers: headers

        expect(response).to have_http_status(:not_found)
        expect(json_response['error']).to include('not found')
      end
    end

    context 'without proper permissions' do
      let(:no_permission_user) { create(:user, account: account, permissions: []) }
      let(:no_permission_headers) { auth_headers_for(no_permission_user) }

      it 'returns forbidden error' do
        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}", headers: no_permission_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'POST /api/v1/supply_chain/scan_executions/:id/cancel' do
    let(:running_execution) do
      create(:supply_chain_scan_execution,
             account: account,
             scan_instance: scan_instance,
             status: 'running')
    end

    context 'with valid authentication and write permissions' do
      before do
        allow(SupplyChainChannel).to receive(:broadcast_execution_failed)
      end

      it 'cancels the execution' do
        post "/api/v1/supply_chain/scan_executions/#{running_execution.id}/cancel", headers: write_headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['scan_execution']['status']).to eq('cancelled')
        expect(json_response['message']).to include('cancelled')
      end

      it 'broadcasts cancellation event' do
        expect(SupplyChainChannel).to receive(:broadcast_execution_failed)
          .with(anything, 'Cancelled by user')

        post "/api/v1/supply_chain/scan_executions/#{running_execution.id}/cancel", headers: write_headers
      end

      it 'returns error when execution is not cancellable' do
        completed_execution = create(:supply_chain_scan_execution,
                                      account: account,
                                      status: 'completed')

        post "/api/v1/supply_chain/scan_executions/#{completed_execution.id}/cancel", headers: write_headers

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response['error']).to include('cannot be cancelled')
      end
    end

    context 'without write permissions' do
      it 'returns forbidden error' do
        post "/api/v1/supply_chain/scan_executions/#{running_execution.id}/cancel", headers: headers

        expect(response).to have_http_status(:forbidden)
        expect(json_response['error']).to include('Insufficient permissions')
      end
    end
  end

  describe 'GET /api/v1/supply_chain/scan_executions/:id/logs' do
    let!(:execution_log) do
      create(:supply_chain_execution_log,
             scan_execution: scan_execution,
             level: 'info',
             message: 'Test log message')
    end

    context 'with valid authentication and permissions' do
      it 'returns execution logs' do
        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}/logs", headers: headers

        expect(response).to have_http_status(:ok)
        data = json_response_data
        expect(data['execution_id']).to eq(scan_execution.id)
        expect(data['logs']).to be_an(Array)
        expect(data['logs'].first['message']).to eq('Test log message')
        expect(data['logs'].first['level']).to eq('info')
      end

      it 'filters logs by level' do
        create(:supply_chain_execution_log,
               scan_execution: scan_execution,
               level: 'error',
               message: 'Error message')

        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}/logs",
            params: { level: 'info' },
            headers: headers

        data = json_response_data
        expect(data['logs'].all? { |log| log['level'] == 'info' }).to be true
      end

      it 'filters logs by since timestamp' do
        old_log = create(:supply_chain_execution_log,
                         scan_execution: scan_execution,
                         created_at: 2.days.ago)
        since_time = 1.day.ago.iso8601

        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}/logs",
            params: { since: since_time },
            headers: headers

        data = json_response_data
        expect(data['logs'].map { |log| log['id'] }).not_to include(old_log.id)
      end

      it 'supports pagination' do
        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}/logs",
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
        get "/api/v1/supply_chain/scan_executions/#{scan_execution.id}/logs", headers: no_permission_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
