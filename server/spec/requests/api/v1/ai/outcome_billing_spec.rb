# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::OutcomeBilling', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['ai.billing.read', 'ai.billing.manage']) }
  let(:limited_user) { create(:user, account: account, permissions: ['ai.billing.read']) }
  let(:headers) { auth_headers_for(user) }
  let(:limited_headers) { auth_headers_for(limited_user) }

  describe 'GET /api/v1/ai/outcome_billing/definitions' do
    context 'with proper permissions' do
      it 'returns list of outcome definitions' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:list_definitions)
          .and_return({ definitions: [], total: 0 })

        get '/api/v1/ai/outcome_billing/definitions', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by outcome type' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:list_definitions)
          .and_return({ definitions: [], total: 0 })

        get '/api/v1/ai/outcome_billing/definitions?outcome_type=completion', headers: headers

        expect_success_response
      end

      it 'supports pagination' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:list_definitions)
          .and_return({ definitions: [], total: 0 })

        get '/api/v1/ai/outcome_billing/definitions?limit=20&offset=0', headers: headers

        expect_success_response
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/outcome_billing/definitions', as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/definitions/:id' do
    context 'with proper permissions' do
      it 'returns definition details' do
        definition = { id: SecureRandom.uuid, name: 'Test Definition' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_definition)
          .and_return(definition)

        get "/api/v1/ai/outcome_billing/definitions/#{definition[:id]}", headers: headers, as: :json

        expect_success_response
      end

      it 'returns error for non-existent definition' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_definition)
          .and_return(nil)
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:errors)
          .and_return(['Not found'])

        get "/api/v1/ai/outcome_billing/definitions/#{SecureRandom.uuid}", headers: headers, as: :json

        expect_error_response('Not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/definitions' do
    let(:definition_params) do
      {
        name: 'New Definition',
        outcome_type: 'completion',
        base_price_usd: 0.01,
        success_criteria: {}
      }
    end

    context 'with proper permissions' do
      it 'creates a new outcome definition' do
        definition = { id: SecureRandom.uuid, name: 'New Definition' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:create_definition)
          .and_return(definition)

        post '/api/v1/ai/outcome_billing/definitions',
             params: definition_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
      end

      it 'returns validation errors' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:create_definition)
          .and_return(nil)
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:errors)
          .and_return(['Name is required'])

        post '/api/v1/ai/outcome_billing/definitions',
             params: { name: nil },
             headers: headers,
             as: :json

        expect_error_response('Name is required', 422)
      end
    end
  end

  describe 'PATCH /api/v1/ai/outcome_billing/definitions/:id' do
    let(:definition_id) { SecureRandom.uuid }
    let(:update_params) { { name: 'Updated Name' } }

    context 'with proper permissions' do
      it 'updates the definition' do
        definition = { id: definition_id, name: 'Updated Name' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:update_definition)
          .and_return(definition)

        patch "/api/v1/ai/outcome_billing/definitions/#{definition_id}",
              params: update_params,
              headers: headers,
              as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/contracts' do
    context 'with proper permissions' do
      it 'returns list of contracts' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:list_contracts)
          .and_return({ contracts: [], total: 0 })

        get '/api/v1/ai/outcome_billing/contracts', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by status' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:list_contracts)
          .and_return({ contracts: [], total: 0 })

        get '/api/v1/ai/outcome_billing/contracts?status=active', headers: headers

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/contracts/:id' do
    context 'with proper permissions' do
      it 'returns contract details' do
        contract = { id: SecureRandom.uuid, name: 'Test Contract' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_contract)
          .and_return(contract)

        get "/api/v1/ai/outcome_billing/contracts/#{contract[:id]}", headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/contracts' do
    let(:contract_params) do
      {
        outcome_definition_id: SecureRandom.uuid,
        name: 'Test Contract',
        contract_type: 'sla'
      }
    end

    context 'with proper permissions' do
      it 'creates a new contract' do
        contract = { id: SecureRandom.uuid, name: 'Test Contract' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:create_contract)
          .and_return(contract)

        post '/api/v1/ai/outcome_billing/contracts',
             params: contract_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/contracts/:id/activate' do
    let(:contract_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'activates the contract' do
        contract = { id: contract_id, status: 'active' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:activate_contract)
          .and_return(contract)

        post "/api/v1/ai/outcome_billing/contracts/#{contract_id}/activate",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/contracts/:id/suspend' do
    let(:contract_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'suspends the contract' do
        contract = { id: contract_id, status: 'suspended' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:suspend_contract)
          .and_return(contract)

        post "/api/v1/ai/outcome_billing/contracts/#{contract_id}/suspend",
             params: { reason: 'Violation' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/contracts/:id/cancel' do
    let(:contract_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'cancels the contract' do
        contract = { id: contract_id, status: 'cancelled' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:cancel_contract)
          .and_return(contract)

        post "/api/v1/ai/outcome_billing/contracts/#{contract_id}/cancel",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/records' do
    context 'with proper permissions' do
      it 'returns list of billing records' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_billing_records)
          .and_return({ records: [], total: 0 })

        get '/api/v1/ai/outcome_billing/records', headers: headers, as: :json

        expect_success_response
      end

      it 'filters by status' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_billing_records)
          .and_return({ records: [], total: 0 })

        get '/api/v1/ai/outcome_billing/records?status=completed', headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/records' do
    let(:record_params) do
      {
        outcome_definition_id: SecureRandom.uuid,
        status: 'in_progress',
        started_at: Time.current.to_s
      }
    end

    context 'with proper permissions' do
      it 'creates a billing record' do
        record = { id: SecureRandom.uuid }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:record_outcome)
          .and_return(record)

        post '/api/v1/ai/outcome_billing/records',
             params: record_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'PATCH /api/v1/ai/outcome_billing/records/:id/complete' do
    let(:record_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'completes the billing record' do
        record = { id: record_id, status: 'completed' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:complete_outcome)
          .and_return(record)

        patch "/api/v1/ai/outcome_billing/records/#{record_id}/complete",
              params: { status: 'completed', is_successful: true },
              headers: headers,
              as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/records/mark_billed' do
    let(:record_ids) { [SecureRandom.uuid, SecureRandom.uuid] }

    context 'with proper permissions' do
      it 'marks records as billed' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:mark_as_billed)
          .and_return({ updated_count: 2 })

        post '/api/v1/ai/outcome_billing/records/mark_billed',
             params: { record_ids: record_ids },
             headers: headers,
             as: :json

        expect_success_response
      end

      it 'returns error for invalid params' do
        post '/api/v1/ai/outcome_billing/records/mark_billed',
             params: { record_ids: [] },
             headers: headers,
             as: :json

        expect_error_response('record_ids must be a non-empty array', 400)
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/violations' do
    context 'with proper permissions' do
      it 'returns list of violations' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_violations)
          .and_return({ violations: [], total: 0 })

        get '/api/v1/ai/outcome_billing/violations', headers: headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/violations/:id/approve' do
    let(:violation_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'approves violation credit' do
        violation = { id: violation_id, credit_status: 'approved' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:approve_violation_credit)
          .and_return(violation)

        post "/api/v1/ai/outcome_billing/violations/#{violation_id}/approve",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/violations/:id/apply' do
    let(:violation_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'applies violation credit' do
        violation = { id: violation_id, credit_status: 'applied' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:apply_violation_credit)
          .and_return(violation)

        post "/api/v1/ai/outcome_billing/violations/#{violation_id}/apply",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/outcome_billing/violations/:id/reject' do
    let(:violation_id) { SecureRandom.uuid }

    context 'with proper permissions' do
      it 'rejects violation credit' do
        violation = { id: violation_id, credit_status: 'rejected' }
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:reject_violation_credit)
          .and_return(violation)

        post "/api/v1/ai/outcome_billing/violations/#{violation_id}/reject",
             params: { reason: 'Not valid' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/summary' do
    context 'with proper permissions' do
      it 'returns billing summary' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_billing_summary)
          .and_return({ total_revenue: 1000, total_outcomes: 500 })

        get '/api/v1/ai/outcome_billing/summary', headers: headers, as: :json

        expect_success_response
      end

      it 'accepts period parameter' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_billing_summary)
          .and_return({})

        get '/api/v1/ai/outcome_billing/summary?period_days=60', headers: headers

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/outcome_billing/sla_performance' do
    context 'with proper permissions' do
      it 'returns SLA performance metrics' do
        allow_any_instance_of(Ai::OutcomeBillingService).to receive(:get_sla_performance)
          .and_return({ average_uptime: 99.9, total_violations: 2 })

        get '/api/v1/ai/outcome_billing/sla_performance', headers: headers, as: :json

        expect_success_response
      end
    end
  end
end
