# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Devops', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.devops.read', 'ai.devops.manage']) }
  let(:limited_user) { create(:user, account: account, permissions: ['ai.devops.read']) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/ai/devops/templates' do
    let!(:template1) { create(:ai_devops_template, name: 'Template 1', category: 'deployment') }
    let!(:template2) { create(:ai_devops_template, name: 'Template 2', category: 'security') }

    context 'with proper permissions' do
      it 'returns list of templates' do
        get '/api/v1/ai/devops/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
        expect(data).to have_key('pagination')
      end

      it 'filters templates by category' do
        get '/api/v1/ai/devops/templates?category=deployment', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['templates']).to be_an(Array)
      end

      it 'supports pagination' do
        get '/api/v1/ai/devops/templates?page=1&per_page=10', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count')
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        user_without_permissions = create(:user, account: account)
        headers_without_permissions = auth_headers_for(user_without_permissions)

        get '/api/v1/ai/devops/templates', headers: headers_without_permissions, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/devops/templates/:id' do
    let(:template) { create(:ai_devops_template) }

    context 'with proper permissions' do
      it 'returns template details' do
        get "/api/v1/ai/devops/templates/#{template.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['template']).to include('id', 'name', 'workflow_definition')
      end
    end

    context 'with invalid template id' do
      it 'returns not found error' do
        get "/api/v1/ai/devops/templates/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/ai/devops/templates' do
    let(:template_params) do
      {
        name: 'New Template',
        category: 'deployment',
        template_type: 'deployment_validation',
        workflow_definition: { steps: [] },
        description: 'Test template'
      }
    end

    context 'with proper permissions' do
      it 'creates a new template' do
        post '/api/v1/ai/devops/templates', params: template_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['template']).to include('id', 'name')
      end
    end

    context 'without manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/devops/templates', params: template_params, headers: limited_headers, as: :json

        expect_error_response('Insufficient permissions', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/devops/installations' do
    let!(:installation) { create(:ai_devops_template_installation, account: account) }

    context 'with proper permissions' do
      it 'returns list of installations' do
        get '/api/v1/ai/devops/installations', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['installations']).to be_an(Array)
        expect(data).to have_key('pagination')
      end
    end
  end

  describe 'POST /api/v1/ai/devops/templates/:template_id/install' do
    let(:template) { create(:ai_devops_template) }
    let(:install_params) do
      {
        variable_values: { key: 'value' },
        custom_config: {}
      }
    end

    context 'with proper permissions' do
      it 'installs the template' do
        allow_any_instance_of(Ai::DevopsService).to receive(:install_template)
          .and_return({ success: true, installation: create(:ai_devops_template_installation) })

        post "/api/v1/ai/devops/templates/#{template.id}/install",
             params: install_params,
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data['installation']).to be_present
      end

      it 'returns error when installation fails' do
        allow_any_instance_of(Ai::DevopsService).to receive(:install_template)
          .and_return({ success: false, error: 'Installation failed' })

        post "/api/v1/ai/devops/templates/#{template.id}/install",
             params: install_params,
             headers: headers,
             as: :json

        expect_error_response('Installation failed', 422)
      end
    end
  end

  describe 'GET /api/v1/ai/devops/executions' do
    let!(:execution) { create(:ai_pipeline_execution, account: account) }

    context 'with proper permissions' do
      it 'returns list of executions' do
        get '/api/v1/ai/devops/executions', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['executions']).to be_an(Array)
        expect(data).to have_key('pagination')
      end

      it 'filters by status' do
        get '/api/v1/ai/devops/executions?status=running', headers: headers

        expect_success_response
      end

      it 'filters by pipeline type' do
        get '/api/v1/ai/devops/executions?pipeline_type=ci', headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/devops/executions' do
    let(:execution_params) do
      {
        pipeline_type: 'ci',
        input_data: {},
        trigger_source: 'manual'
      }
    end

    context 'with proper permissions' do
      it 'creates a new execution' do
        allow_any_instance_of(Ai::DevopsService).to receive(:execute_pipeline)
          .and_return({ success: true, execution: create(:ai_pipeline_execution) })

        post '/api/v1/ai/devops/executions', params: execution_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['execution']).to be_present
      end

      it 'returns error when execution fails' do
        allow_any_instance_of(Ai::DevopsService).to receive(:execute_pipeline)
          .and_return({ success: false, error: 'Execution failed' })

        post '/api/v1/ai/devops/executions', params: execution_params, headers: headers, as: :json

        expect_error_response('Execution failed', 422)
      end
    end
  end

  describe 'GET /api/v1/ai/devops/executions/:id' do
    let(:execution) { create(:ai_pipeline_execution, account: account) }

    context 'with proper permissions' do
      it 'returns execution details' do
        get "/api/v1/ai/devops/executions/#{execution.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['execution']).to include('id', 'pipeline_type', 'status')
      end
    end
  end

  describe 'GET /api/v1/ai/devops/risks' do
    let!(:risk) { create(:ai_deployment_risk, account: account) }

    context 'with proper permissions' do
      it 'returns list of risks' do
        get '/api/v1/ai/devops/risks', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['risks']).to be_an(Array)
      end

      it 'filters by environment' do
        get '/api/v1/ai/devops/risks?environment=production', headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/devops/risks/assess' do
    let(:assess_params) do
      {
        deployment_type: 'production',
        target_environment: 'production',
        change_data: {}
      }
    end

    context 'with proper permissions' do
      it 'assesses deployment risk' do
        allow_any_instance_of(Ai::DevopsService).to receive(:assess_deployment_risk)
          .and_return({ success: true, assessment: create(:ai_deployment_risk) })

        post '/api/v1/ai/devops/risks/assess', params: assess_params, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['assessment']).to be_present
      end
    end
  end

  describe 'PUT /api/v1/ai/devops/risks/:id/approve' do
    let(:risk) { create(:ai_deployment_risk, account: account, status: 'pending') }

    context 'with proper permissions' do
      it 'approves the risk' do
        allow_any_instance_of(Ai::DeploymentRisk).to receive(:approve!).and_return(true)

        put "/api/v1/ai/devops/risks/#{risk.id}/approve",
            params: { rationale: 'Looks safe' },
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data['assessment']).to be_present
      end
    end
  end

  describe 'PUT /api/v1/ai/devops/risks/:id/reject' do
    let(:risk) { create(:ai_deployment_risk, account: account, status: 'pending') }

    context 'with proper permissions' do
      it 'rejects the risk' do
        allow_any_instance_of(Ai::DeploymentRisk).to receive(:reject!).and_return(true)

        put "/api/v1/ai/devops/risks/#{risk.id}/reject",
            params: { rationale: 'Too risky' },
            headers: headers,
            as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/devops/reviews' do
    let!(:review) { create(:ai_code_review, account: account) }

    context 'with proper permissions' do
      it 'returns list of code reviews' do
        get '/api/v1/ai/devops/reviews', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['reviews']).to be_an(Array)
      end

      it 'filters by status' do
        get '/api/v1/ai/devops/reviews?status=completed', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/devops/reviews' do
    let(:review_params) do
      {
        repository_id: 'repo-123',
        pull_request_number: 42,
        commit_sha: 'abc123'
      }
    end

    context 'with proper permissions' do
      it 'creates a code review' do
        allow_any_instance_of(Ai::DevopsService).to receive(:create_code_review)
          .and_return({ success: true, review: create(:ai_code_review) })

        post '/api/v1/ai/devops/reviews', params: review_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['review']).to be_present
      end
    end
  end

  describe 'GET /api/v1/ai/devops/reviews/:id' do
    let(:review) { create(:ai_code_review, account: account) }

    context 'with proper permissions' do
      it 'returns review details' do
        get "/api/v1/ai/devops/reviews/#{review.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['review']).to include('id', 'status')
      end
    end
  end

  describe 'GET /api/v1/ai/devops/analytics' do
    context 'with proper permissions' do
      it 'returns pipeline analytics' do
        allow_any_instance_of(Ai::DevopsService).to receive(:get_pipeline_analytics)
          .and_return({ total_executions: 10, success_rate: 0.9 })

        get '/api/v1/ai/devops/analytics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['analytics']).to be_present
      end

      it 'accepts date range parameters' do
        allow_any_instance_of(Ai::DevopsService).to receive(:get_pipeline_analytics)
          .and_return({ total_executions: 5, success_rate: 0.8 })

        get "/api/v1/ai/devops/analytics?start_date=#{7.days.ago.iso8601}&end_date=#{Time.current.iso8601}",
            headers: headers

        expect_success_response
      end
    end
  end
end
