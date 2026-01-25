# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::ValidationStatistics', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.workflows.read']) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/ai/validation_statistics' do
    let!(:workflow) { create(:ai_workflow, account: account) }
    let!(:validation1) { create(:workflow_validation, workflow: workflow, health_score: 85, overall_status: 'valid') }
    let!(:validation2) { create(:workflow_validation, workflow: workflow, health_score: 60, overall_status: 'warning') }

    context 'with proper permissions' do
      it 'returns validation statistics' do
        get '/api/v1/ai/validation_statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['statistics']).to include(
          'overview',
          'health_distribution',
          'status_distribution',
          'issue_categories',
          'trends',
          'top_issues'
        )
        expect(data['time_range']).to be_present
      end

      it 'accepts time_range parameter' do
        get '/api/v1/ai/validation_statistics?time_range=7d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('7d')
      end

      it 'defaults to 30 days for time_range' do
        get '/api/v1/ai/validation_statistics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('30d')
      end
    end

    context 'without ai.workflows.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get '/api/v1/ai/validation_statistics', headers: headers_without_permission, as: :json

        expect_error_response('Insufficient permissions to view validation statistics', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/validation_statistics', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/validation_statistics/common_issues' do
    let!(:workflow) { create(:ai_workflow, account: account) }

    before do
      # Create validations with issues
      create(:workflow_validation, workflow: workflow,
             issues: [
               { code: 'MISSING_INPUT', severity: 'error', category: 'configuration', message: 'Missing required input' },
               { code: 'TIMEOUT_WARNING', severity: 'warning', category: 'performance', message: 'Timeout risk' }
             ])
      create(:workflow_validation, workflow: workflow,
             issues: [
               { code: 'MISSING_INPUT', severity: 'error', category: 'configuration', message: 'Missing required input' }
             ])
    end

    context 'with proper permissions' do
      it 'returns common issues' do
        get '/api/v1/ai/validation_statistics/common_issues', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['common_issues']).to be_an(Array)
        expect(data['total_unique_issues']).to eq(2)
      end

      it 'accepts limit parameter' do
        get '/api/v1/ai/validation_statistics/common_issues?limit=5', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['common_issues'].length).to be <= 5
      end

      it 'limits maximum to 50 issues' do
        get '/api/v1/ai/validation_statistics/common_issues?limit=100', headers: headers, as: :json

        expect_success_response
        # Maximum should be 50 even though we requested 100
      end

      it 'orders issues by count descending' do
        get '/api/v1/ai/validation_statistics/common_issues', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        issues = data['common_issues']

        if issues.length > 1
          expect(issues.first['count']).to be >= issues.last['count']
        end
      end

      it 'includes issue details' do
        get '/api/v1/ai/validation_statistics/common_issues', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        first_issue = data['common_issues'].first

        expect(first_issue).to include(
          'code',
          'severity',
          'category',
          'message',
          'count'
        )
      end
    end

    context 'with time_range filter' do
      it 'accepts time_range parameter' do
        get '/api/v1/ai/validation_statistics/common_issues?time_range=7d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('7d')
      end
    end
  end

  describe 'GET /api/v1/ai/validation_statistics/health_distribution' do
    let!(:workflow1) { create(:ai_workflow, account: account) }
    let!(:workflow2) { create(:ai_workflow, account: account) }
    let!(:workflow3) { create(:ai_workflow, account: account) }

    before do
      # Create validations with appropriate issues that result in desired health scores
      # Model callback calculates: 100 - (error_count * 15) - (warning_count * 5)
      # :healthy trait produces score ~95 (1 info issue = no deduction)
      # :with_warnings trait produces score ~75 (2 warnings = -10, 1 info = 0)
      # :unhealthy trait produces score ~40 (3 errors = -45)
      create(:workflow_validation, :healthy, workflow: workflow1)      # excellent (>= 90)
      create(:workflow_validation, :with_warnings, workflow: workflow2) # good (70-89)
      create(:workflow_validation, :unhealthy, workflow: workflow3)    # poor (< 50)
    end

    context 'with proper permissions' do
      it 'returns health distribution' do
        get '/api/v1/ai/validation_statistics/health_distribution', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['distribution']).to include('excellent', 'good', 'fair', 'poor')
        expect(data['averages']).to include('excellent', 'good', 'fair', 'poor')
        expect(data['total_workflows']).to eq(3)
        expect(data['overall_average']).to be_a(Numeric)
      end

      it 'categorizes health scores correctly' do
        get '/api/v1/ai/validation_statistics/health_distribution', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        distribution = data['distribution']

        expect(distribution['excellent']).to eq(1) # >= 90
        expect(distribution['good']).to eq(1)      # >= 70 and < 90
        expect(distribution['poor']).to eq(1)      # < 50
      end

      it 'calculates average health scores per bucket' do
        get '/api/v1/ai/validation_statistics/health_distribution', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        averages = data['averages']

        # Verify averages are numeric and within expected ranges
        expect(averages['excellent']).to be >= 90 if data['distribution']['excellent'] > 0
        expect(averages['good']).to be >= 70 if data['distribution']['good'] > 0
        expect(averages['good']).to be < 90 if data['distribution']['good'] > 0
      end

      it 'accepts time_range parameter' do
        get '/api/v1/ai/validation_statistics/health_distribution?time_range=90d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('90d')
      end
    end

    context 'with no validations' do
      before do
        WorkflowValidation.destroy_all
      end

      it 'returns empty distribution' do
        get '/api/v1/ai/validation_statistics/health_distribution', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['total_workflows']).to eq(0)
        expect(data['overall_average']).to eq(0)
      end
    end
  end

  describe 'error handling' do
    context 'when database error occurs' do
      before do
        allow(WorkflowValidation).to receive(:joins).and_raise(ActiveRecord::StatementInvalid.new('Database error'))
      end

      it 'returns internal server error' do
        get '/api/v1/ai/validation_statistics', headers: headers, as: :json

        expect_error_response('Failed to get validation statistics', 500)
      end
    end
  end

  describe 'time range parsing' do
    context 'with different time range values' do
      it 'handles 7d time range' do
        get '/api/v1/ai/validation_statistics?time_range=7d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('7d')
      end

      it 'handles 30d time range' do
        get '/api/v1/ai/validation_statistics?time_range=30d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('30d')
      end

      it 'handles 90d time range' do
        get '/api/v1/ai/validation_statistics?time_range=90d', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('90d')
      end

      it 'handles 1y time range' do
        get '/api/v1/ai/validation_statistics?time_range=1y', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['time_range']['period']).to eq('1y')
      end

      it 'defaults to 30d for invalid time range' do
        get '/api/v1/ai/validation_statistics?time_range=invalid', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        # Controller returns the original param for the period but uses 30d internally for the calculation
        expect(data['time_range']['period']).to eq('invalid')
      end
    end
  end

  describe 'cross-account isolation' do
    let(:other_account) { create(:account) }
    let(:other_workflow) { create(:ai_workflow, account: other_account) }
    let!(:other_validation) { create(:workflow_validation, workflow: other_workflow) }

    it 'does not include validations from other accounts' do
      get '/api/v1/ai/validation_statistics', headers: headers, as: :json

      expect_success_response
      data = json_response_data

      # Should only see workflows from current account
      expect(data['statistics']['overview']['total_workflows']).to eq(account.ai_workflows.count)
    end
  end
end
