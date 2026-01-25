# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Internal::TemplateInstallations', type: :request do
  let(:internal_headers) do
    token = JWT.encode(
      { service: 'worker', type: 'service', exp: 1.hour.from_now.to_i },
      Rails.application.config.jwt_secret_key,
      'HS256'
    )
    { 'Authorization' => "Bearer #{token}" }
  end

  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:template) { create(:ai_workflow_template) }
  let!(:installation) do
    create(:ai_workflow_template_installation,
           account: account,
           installed_by_user: user,
           template: template)
  end

  describe 'POST /api/v1/internal/template_installations/:id/update' do
    context 'with valid service token' do
      before do
        allow_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .and_return(true)
      end

      it 'updates template installation to latest version' do
        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: internal_headers,
             as: :json

        expect_success_response
        data = json_response['data']

        expect(data['installation_id']).to eq(installation.installation_id)
        expect(data['template_name']).to eq(installation.template_name)
        expect(data['version']).to eq(installation.template_version)
        expect(data['updated_at']).to be_present
      end

      it 'preserves customizations by default' do
        expect_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .with(user, preserve_customizations: true)
          .and_return(true)

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             params: { user_id: user.id },
             headers: internal_headers,
             as: :json

        expect_success_response
      end

      it 'respects preserve_customizations parameter when true' do
        expect_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .with(user, preserve_customizations: true)
          .and_return(true)

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             params: { user_id: user.id, preserve_customizations: true },
             headers: internal_headers,
             as: :json

        expect_success_response
      end

      it 'respects preserve_customizations parameter when false' do
        expect_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .with(user, preserve_customizations: false)
          .and_return(true)

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             params: { user_id: user.id, preserve_customizations: false },
             headers: internal_headers,
             as: :json

        expect_success_response
      end

      it 'uses installation user when user_id not provided' do
        expect_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .with(user, preserve_customizations: true)
          .and_return(true)

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: internal_headers,
             as: :json

        expect_success_response
      end

      it 'uses provided user_id when specified' do
        other_user = create(:user, account: account)

        expect_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .with(other_user, preserve_customizations: true)
          .and_return(true)

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             params: { user_id: other_user.id },
             headers: internal_headers,
             as: :json

        expect_success_response
      end
    end

    context 'when update fails' do
      before do
        allow_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .and_return(false)
      end

      it 'returns error response' do
        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: internal_headers,
             as: :json

        expect_error_response('Template update failed', 422)
      end
    end

    context 'with non-existent installation' do
      it 'returns not found error' do
        post '/api/v1/internal/template_installations/non-existent-id/update',
             headers: internal_headers,
             as: :json

        expect_error_response('Installation not found', 404)
      end
    end

    context 'when standard error occurs' do
      before do
        allow_any_instance_of(Ai::WorkflowTemplateInstallation)
          .to receive(:update_to_latest_version!)
          .and_raise(StandardError.new('Unexpected error'))
      end

      it 'returns internal error response' do
        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: internal_headers,
             as: :json

        expect(response).to have_http_status(:internal_server_error)
        expect(json_response['success']).to be false
      end
    end

    context 'without service token' do
      it 'returns unauthorized error' do
        post "/api/v1/internal/template_installations/#{installation.id}/update",
             as: :json

        expect_error_response('Service token required', 401)
      end
    end

    context 'with invalid service token' do
      it 'returns unauthorized error for wrong service name' do
        invalid_token = JWT.encode(
          { service: 'invalid', type: 'service', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )
        headers = { 'Authorization' => "Bearer #{invalid_token}" }

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: headers,
             as: :json

        expect_error_response('Invalid service token', 401)
      end

      it 'returns unauthorized error for wrong type' do
        invalid_token = JWT.encode(
          { service: 'worker', type: 'invalid', exp: 1.hour.from_now.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )
        headers = { 'Authorization' => "Bearer #{invalid_token}" }

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: headers,
             as: :json

        expect_error_response('Invalid service token', 401)
      end

      it 'returns unauthorized error for expired token' do
        expired_token = JWT.encode(
          { service: 'worker', type: 'service', exp: 1.hour.ago.to_i },
          Rails.application.config.jwt_secret_key,
          'HS256'
        )
        headers = { 'Authorization' => "Bearer #{expired_token}" }

        post "/api/v1/internal/template_installations/#{installation.id}/update",
             headers: headers,
             as: :json

        expect_error_response('Invalid service token', 401)
      end
    end
  end
end
