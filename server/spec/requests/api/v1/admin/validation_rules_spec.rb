# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Admin::ValidationRules', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :owner, account: account) }
  let(:regular_user) { create(:user, :member, account: account) }
  let(:admin_headers) { auth_headers_for(admin_user) }
  let(:regular_headers) { auth_headers_for(regular_user) }

  describe 'GET /api/v1/admin/validation_rules' do
    let!(:rule1) { create(:validation_rule, :structure_error, enabled: true) }
    let!(:rule2) { create(:validation_rule, :connectivity_warning, enabled: false) }

    context 'with admin permissions' do
      it 'returns list of validation rules' do
        get '/api/v1/admin/validation_rules', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation_rules']).to be_an(Array)
        expect(data['validation_rules'].length).to eq(2)
        expect(data['meta']).to include(
          'total',
          'enabled_count',
          'disabled_count',
          'categories',
          'severities'
        )
      end

      it 'filters by category' do
        get '/api/v1/admin/validation_rules',
            params: { category: 'structure' },
            headers: admin_headers

        expect_success_response
        data = json_response_data
        expect(data['validation_rules'].length).to eq(1)
        expect(data['validation_rules'].first['category']).to eq('structure')
      end

      it 'filters by severity' do
        get '/api/v1/admin/validation_rules',
            params: { severity: 'warning' },
            headers: admin_headers

        expect_success_response
        data = json_response_data
        expect(data['validation_rules'].length).to eq(1)
        expect(data['validation_rules'].first['severity']).to eq('warning')
      end

      it 'filters by enabled status' do
        get '/api/v1/admin/validation_rules',
            params: { enabled: 'true' },
            headers: admin_headers

        expect_success_response
        data = json_response_data
        expect(data['validation_rules'].all? { |r| r['enabled'] }).to be true
      end

      it 'filters by auto_fixable' do
        create(:validation_rule, :auto_fixable)

        get '/api/v1/admin/validation_rules',
            params: { auto_fixable: 'true' },
            headers: admin_headers

        expect_success_response
        data = json_response_data
        expect(data['validation_rules'].all? { |r| r['auto_fixable'] }).to be true
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get '/api/v1/admin/validation_rules', headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view validation rules', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/admin/validation_rules', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/admin/validation_rules/:id' do
    let(:rule) { create(:validation_rule, :structure_error) }

    context 'with admin permissions' do
      it 'returns validation rule details' do
        get "/api/v1/admin/validation_rules/#{rule.id}", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation_rule']).to include(
          'id' => rule.id,
          'name' => rule.name,
          'category' => rule.category,
          'severity' => rule.severity
        )
        expect(data['validation_rule']).to have_key('configuration')
      end

      it 'returns not found for non-existent rule' do
        get "/api/v1/admin/validation_rules/#{SecureRandom.uuid}", headers: admin_headers, as: :json

        expect_error_response('Validation rule not found', 404)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        get "/api/v1/admin/validation_rules/#{rule.id}", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to view validation rules', 403)
      end
    end
  end

  describe 'POST /api/v1/admin/validation_rules' do
    let(:valid_params) do
      {
        validation_rule: {
          name: 'Test Rule',
          description: 'A test validation rule',
          category: 'structure',
          severity: 'warning',
          enabled: true,
          auto_fixable: false,
          configuration: { check_type: 'node_count', priority: 'low' }
        }
      }
    end

    context 'with admin permissions' do
      it 'creates a new validation rule' do
        expect {
          post '/api/v1/admin/validation_rules', params: valid_params, headers: admin_headers, as: :json
        }.to change(ValidationRule, :count).by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['validation_rule']).to include(
          'name' => 'Test Rule',
          'category' => 'structure',
          'severity' => 'warning'
        )
        expect(data['message']).to eq('Validation rule created successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = valid_params.deep_merge(validation_rule: { name: nil })

        post '/api/v1/admin/validation_rules', params: invalid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end

      it 'returns error for duplicate name' do
        create(:validation_rule, name: 'Test Rule')

        post '/api/v1/admin/validation_rules', params: valid_params, headers: admin_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        post '/api/v1/admin/validation_rules', params: valid_params, headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage validation rules', 403)
      end
    end
  end

  describe 'PATCH /api/v1/admin/validation_rules/:id' do
    let(:rule) { create(:validation_rule, :structure_error) }
    let(:update_params) do
      {
        validation_rule: {
          severity: 'info',
          enabled: false
        }
      }
    end

    context 'with admin permissions' do
      it 'updates the validation rule' do
        patch "/api/v1/admin/validation_rules/#{rule.id}",
              params: update_params,
              headers: admin_headers,
              as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation_rule']['severity']).to eq('info')
        expect(data['validation_rule']['enabled']).to be false
        expect(data['message']).to eq('Validation rule updated successfully')
      end

      it 'returns validation errors for invalid update' do
        invalid_params = { validation_rule: { severity: 'invalid' } }

        patch "/api/v1/admin/validation_rules/#{rule.id}",
              params: invalid_params,
              headers: admin_headers,
              as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/admin/validation_rules/#{rule.id}",
              params: update_params,
              headers: regular_headers,
              as: :json

        expect_error_response('Insufficient permissions to manage validation rules', 403)
      end
    end
  end

  describe 'DELETE /api/v1/admin/validation_rules/:id' do
    let!(:rule) { create(:validation_rule, :structure_error) }

    context 'with admin permissions' do
      it 'deletes the validation rule' do
        expect {
          delete "/api/v1/admin/validation_rules/#{rule.id}", headers: admin_headers, as: :json
        }.to change(ValidationRule, :count).by(-1)

        expect_success_response
        expect(json_response_data['message']).to eq('Validation rule deleted successfully')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        delete "/api/v1/admin/validation_rules/#{rule.id}", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage validation rules', 403)
      end
    end
  end

  describe 'PATCH /api/v1/admin/validation_rules/:id/enable' do
    let(:rule) { create(:validation_rule, :structure_error, enabled: false) }

    context 'with admin permissions' do
      it 'enables the validation rule' do
        patch "/api/v1/admin/validation_rules/#{rule.id}/enable", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation_rule']['enabled']).to be true
        expect(data['message']).to eq('Validation rule enabled successfully')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/admin/validation_rules/#{rule.id}/enable", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage validation rules', 403)
      end
    end
  end

  describe 'PATCH /api/v1/admin/validation_rules/:id/disable' do
    let(:rule) { create(:validation_rule, :structure_error, enabled: true) }

    context 'with admin permissions' do
      it 'disables the validation rule' do
        patch "/api/v1/admin/validation_rules/#{rule.id}/disable", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['validation_rule']['enabled']).to be false
        expect(data['message']).to eq('Validation rule disabled successfully')
      end
    end

    context 'without admin permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/admin/validation_rules/#{rule.id}/disable", headers: regular_headers, as: :json

        expect_error_response('Insufficient permissions to manage validation rules', 403)
      end
    end
  end
end
