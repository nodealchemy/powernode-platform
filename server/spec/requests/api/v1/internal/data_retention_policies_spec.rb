# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::DataRetentionPolicies', type: :request do
  # Service token authentication
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  describe 'GET /api/v1/internal/data_retention_policies' do
    let!(:active_policy1) do
      DataManagement::RetentionPolicy.create!(
        data_type: 'audit_logs',
        retention_days: 90,
        action: 'archive',
        active: true
      )
    end

    let!(:active_policy2) do
      DataManagement::RetentionPolicy.create!(
        data_type: 'user_sessions',
        retention_days: 30,
        action: 'delete',
        active: true
      )
    end

    let!(:inactive_policy) do
      DataManagement::RetentionPolicy.create!(
        data_type: 'temporary_files',
        retention_days: 7,
        action: 'delete',
        active: false
      )
    end

    context 'with service token authentication' do
      it 'returns active retention policies' do
        get '/api/v1/internal/data_retention_policies',
            headers: internal_headers,
            as: :json

        expect_success_response
        data = json_response_data

        expect(data.size).to eq(2)
        policy_ids = data.map { |p| p['id'] }
        expect(policy_ids).to include(active_policy1.id, active_policy2.id)
        expect(policy_ids).not_to include(inactive_policy.id)
      end

      it 'returns policies ordered by data_type' do
        get '/api/v1/internal/data_retention_policies',
            headers: internal_headers,
            as: :json

        data = json_response_data
        data_types = data.map { |p| p['data_type'] }

        expect(data_types).to eq(['audit_logs', 'user_sessions'])
      end

      it 'includes all policy fields' do
        get '/api/v1/internal/data_retention_policies',
            headers: internal_headers,
            as: :json

        data = json_response_data
        policy = data.first

        expect(policy).to include(
          'id',
          'data_type',
          'retention_days',
          'action',
          'active',
          'created_at',
          'updated_at'
        )
      end

      it 'returns correct policy data' do
        get '/api/v1/internal/data_retention_policies',
            headers: internal_headers,
            as: :json

        data = json_response_data
        audit_policy = data.find { |p| p['data_type'] == 'audit_logs' }

        expect(audit_policy).to include(
          'id' => active_policy1.id,
          'data_type' => 'audit_logs',
          'retention_days' => 90,
          'action' => 'archive',
          'active' => true
        )
      end

      it 'returns empty array when no active policies exist' do
        DataManagement::RetentionPolicy.update_all(active: false)

        get '/api/v1/internal/data_retention_policies',
            headers: internal_headers,
            as: :json

        expect_success_response
        # When data is an empty array, render_success may omit the data key
        data = json_response['data']
        expect(data).to be_nil.or eq([])
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/internal/data_retention_policies', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error' do
        invalid_token = JWT.encode(
          { service: 'other', type: 'user', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )

        get '/api/v1/internal/data_retention_policies',
            headers: { 'Authorization' => "Bearer #{invalid_token}" },
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
