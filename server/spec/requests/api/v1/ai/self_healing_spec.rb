# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::SelfHealing', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.monitoring.read']) }
  let(:headers) { auth_headers_for(user) }
  let(:unauthorized_user) { create(:user, account: account, permissions: []) }

  describe 'GET /api/v1/ai/self_healing/remediation_logs' do
    let!(:log1) { create(:ai_remediation_log, :provider_failover, account: account, executed_at: 1.minute.ago) }
    let!(:log2) { create(:ai_remediation_log, :workflow_retry, account: account, executed_at: 2.minutes.ago) }
    let!(:log3) { create(:ai_remediation_log, :alert_escalation, account: account, executed_at: 3.minutes.ago) }

    it 'returns remediation logs with health summary' do
      get '/api/v1/ai/self_healing/remediation_logs', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['remediation_logs']).to be_an(Array)
      expect(data['remediation_logs'].length).to eq(3)
      expect(data['health_summary']).to be_present
    end

    it 'returns logs ordered by most recent' do
      get '/api/v1/ai/self_healing/remediation_logs', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      logs = data['remediation_logs']
      expect(logs.first['id']).to eq(log1.id)
    end

    it 'filters by action_type' do
      get '/api/v1/ai/self_healing/remediation_logs?action_type=provider_failover',
          headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['remediation_logs'].length).to eq(1)
      expect(data['remediation_logs'].first['action_type']).to eq('provider_failover')
    end

    it 'respects limit parameter' do
      get '/api/v1/ai/self_healing/remediation_logs?limit=2', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['remediation_logs'].length).to eq(2)
    end

    it 'includes health_summary in response' do
      get '/api/v1/ai/self_healing/remediation_logs', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      summary = data['health_summary']
      expect(summary).to include('overall_status', 'remediation_count_1h', 'success_rate')
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/self_healing/remediation_logs',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get '/api/v1/ai/self_healing/remediation_logs', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/self_healing/health_summary' do
    it 'returns health summary' do
      get '/api/v1/ai/self_healing/health_summary', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include('overall_status', 'remediation_count_1h', 'success_rate', 'active_circuit_breakers')
    end

    it 'returns healthy status when no recent remediations' do
      get '/api/v1/ai/self_healing/health_summary', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['overall_status']).to eq('healthy')
      expect(data['success_rate']).to eq(100.0)
    end

    it 'calculates correct success rate' do
      create_list(:ai_remediation_log, 8, :successful, account: account, executed_at: 10.minutes.ago)
      create_list(:ai_remediation_log, 2, :failed, account: account, executed_at: 10.minutes.ago)

      get '/api/v1/ai/self_healing/health_summary', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['remediation_count_1h']).to eq(10)
      expect(data['success_rate']).to eq(80.0)
      expect(data['overall_status']).to eq('healthy')
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/self_healing/health_summary',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end

  describe 'GET /api/v1/ai/self_healing/correlations' do
    it 'returns correlations and devops health' do
      allow_any_instance_of(Ai::SelfHealing::CrossSystemCorrelator).to receive(:correlate_failures)
        .and_return([{ type: 'provider_cascade', count: 2 }])
      allow_any_instance_of(Ai::SelfHealing::CrossSystemCorrelator).to receive(:devops_health)
        .and_return({ pipelines: 'healthy', runners: 'healthy' })

      get '/api/v1/ai/self_healing/correlations', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['correlations']).to be_an(Array)
      expect(data['devops_health']).to be_present
      expect(data['timestamp']).to be_present
    end

    it 'accepts time_range parameter' do
      allow_any_instance_of(Ai::SelfHealing::CrossSystemCorrelator).to receive(:correlate_failures)
        .and_return([])
      allow_any_instance_of(Ai::SelfHealing::CrossSystemCorrelator).to receive(:devops_health)
        .and_return({})

      get '/api/v1/ai/self_healing/correlations?time_range=7200', headers: headers, as: :json

      expect_success_response
    end

    context 'without permission' do
      it 'returns forbidden' do
        get '/api/v1/ai/self_healing/correlations',
            headers: auth_headers_for(unauthorized_user), as: :json

        expect_error_response("Permission denied", 403)
      end
    end
  end
end
