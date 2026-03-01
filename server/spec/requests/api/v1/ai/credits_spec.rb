# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Credits', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.credits.read', 'ai.credits.manage' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }

  let(:credit_service) { instance_double('Ai::CreditManagementService') }

  before do
    allow(Ai::CreditManagementService).to receive(:new).and_return(credit_service)
    allow(credit_service).to receive(:errors).and_return([])
  end

  describe 'GET /api/v1/ai/credits/balance' do
    let(:balance_data) do
      {
        balance: 1000.0,
        reserved: 100.0,
        available: 900.0
      }
    end

    before do
      allow(credit_service).to receive(:get_balance).and_return(balance_data)
    end

    context 'with authentication' do
      it 'returns credit balance' do
        get '/api/v1/ai/credits/balance',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('balance')
        expect(data).to have_key('available')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/ai/credits/balance',
            as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/ai/credits/transactions' do
    let(:transactions_data) do
      {
        transactions: [
          { id: SecureRandom.uuid, type: 'purchase', amount: 100.0 }
        ],
        total: 1
      }
    end

    before do
      allow(credit_service).to receive(:get_transaction_history).and_return(transactions_data)
    end

    context 'with authentication' do
      it 'returns transaction history' do
        get '/api/v1/ai/credits/transactions',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('transactions')
      end

      it 'accepts pagination parameters' do
        get '/api/v1/ai/credits/transactions?limit=25&offset=0',
            headers: headers

        expect(credit_service).to have_received(:get_transaction_history).with(
          hash_including(limit: 25, offset: 0)
        )
      end

      it 'accepts transaction type filter' do
        get '/api/v1/ai/credits/transactions?transaction_type=purchase',
            headers: headers

        expect(credit_service).to have_received(:get_transaction_history).with(
          hash_including(transaction_type: 'purchase')
        )
      end
    end
  end

  describe 'GET /api/v1/ai/credits/packs' do
    let(:packs_data) do
      [
        { id: 'pack_1', credits: 100, price_usd: 10.0 },
        { id: 'pack_2', credits: 500, price_usd: 45.0 }
      ]
    end

    before do
      allow(credit_service).to receive(:get_available_packs).and_return(packs_data)
    end

    context 'with authentication' do
      it 'returns available credit packs' do
        get '/api/v1/ai/credits/packs',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('packs')
        expect(data['packs']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/credits/purchases' do
    let(:purchase_data) do
      {
        id: SecureRandom.uuid,
        status: 'pending',
        credits: 100,
        amount_usd: 10.0
      }
    end

    before do
      allow(credit_service).to receive(:initiate_purchase).and_return(purchase_data)
    end

    context 'with valid parameters' do
      it 'initiates a credit purchase' do
        post '/api/v1/ai/credits/purchases',
             params: {
               pack_id: 'pack_1',
               quantity: 1,
               payment_method: 'stripe'
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end

    context 'when purchase fails' do
      before do
        allow(credit_service).to receive(:initiate_purchase).and_return(nil)
        allow(credit_service).to receive(:errors).and_return([ 'Insufficient funds' ])
      end

      it 'returns error response' do
        post '/api/v1/ai/credits/purchases',
             params: { pack_id: 'pack_1' },
             headers: headers,
             as: :json

        expect_error_response('Insufficient funds', 422)
      end
    end
  end

  describe 'POST /api/v1/ai/credits/purchases/:id/complete' do
    let(:completed_purchase) do
      {
        id: SecureRandom.uuid,
        status: 'completed',
        credits: 100
      }
    end

    before do
      allow(credit_service).to receive(:complete_purchase).and_return(completed_purchase)
    end

    context 'with valid purchase' do
      it 'completes the purchase' do
        post "/api/v1/ai/credits/purchases/#{SecureRandom.uuid}/complete",
             params: { payment_reference: 'pi_123456' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/transfers' do
    let(:transfer_data) do
      {
        id: SecureRandom.uuid,
        status: 'pending',
        amount: 50.0
      }
    end

    let(:to_account) { create(:account) }

    before do
      allow(Account).to receive(:find_by).and_return(to_account)
      allow(credit_service).to receive(:initiate_transfer).and_return(transfer_data)
    end

    context 'with valid parameters' do
      it 'initiates a credit transfer' do
        post '/api/v1/ai/credits/transfers',
             params: {
               to_account_id: to_account.id,
               amount: 50.0,
               description: 'Test transfer'
             },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end

    context 'when destination account not found' do
      before do
        allow(Account).to receive(:find_by).and_return(nil)
      end

      it 'returns not found error' do
        post '/api/v1/ai/credits/transfers',
             params: { to_account_id: SecureRandom.uuid, amount: 50.0 },
             headers: headers,
             as: :json

        expect_error_response('Destination account not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/credits/transfers/:id/approve' do
    let(:approved_transfer) do
      {
        id: SecureRandom.uuid,
        status: 'approved'
      }
    end

    before do
      allow(credit_service).to receive(:approve_transfer).and_return(approved_transfer)
    end

    context 'with valid transfer' do
      it 'approves the transfer' do
        post "/api/v1/ai/credits/transfers/#{SecureRandom.uuid}/approve",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/transfers/:id/complete' do
    let(:completed_transfer) do
      {
        id: SecureRandom.uuid,
        status: 'completed'
      }
    end

    before do
      allow(credit_service).to receive(:complete_transfer).and_return(completed_transfer)
    end

    context 'with valid transfer' do
      it 'completes the transfer' do
        post "/api/v1/ai/credits/transfers/#{SecureRandom.uuid}/complete",
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/transfers/:id/cancel' do
    let(:cancelled_transfer) do
      {
        id: SecureRandom.uuid,
        status: 'cancelled'
      }
    end

    before do
      allow(credit_service).to receive(:cancel_transfer).and_return(cancelled_transfer)
    end

    context 'with valid transfer' do
      it 'cancels the transfer' do
        post "/api/v1/ai/credits/transfers/#{SecureRandom.uuid}/cancel",
             params: { reason: 'Changed mind' },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/deduct' do
    let(:deduction_result) do
      {
        transaction_id: SecureRandom.uuid,
        new_balance: 950.0
      }
    end

    before do
      allow(credit_service).to receive(:deduct_credits).and_return(deduction_result)
    end

    context 'with valid parameters' do
      it 'deducts credits' do
        post '/api/v1/ai/credits/deduct',
             params: {
               amount: 50.0,
               operation_type: 'ai_execution',
               reference: 'exec_123',
               description: 'AI operation'
             },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/calculate_cost' do
    let(:cost_calculation) do
      {
        estimated_cost: 0.05,
        rate_type: 'token_based',
        breakdown: {}
      }
    end

    before do
      allow(credit_service).to receive(:calculate_operation_cost).and_return(cost_calculation)
    end

    context 'with valid parameters' do
      it 'calculates operation cost' do
        post '/api/v1/ai/credits/calculate_cost',
             params: {
               operation_type: 'completion',
               provider_type: 'openai',
               model_name: 'gpt-4',
               metrics: { input_tokens: 100, output_tokens: 50 }
             },
             headers: headers,
             as: :json

        expect_success_response
      end
    end

    context 'when no rate found' do
      before do
        allow(credit_service).to receive(:calculate_operation_cost).and_return(nil)
      end

      it 'returns not found error' do
        post '/api/v1/ai/credits/calculate_cost',
             params: { operation_type: 'unknown' },
             headers: headers,
             as: :json

        expect_error_response('No rate found for this operation', 404)
      end
    end
  end

  describe 'GET /api/v1/ai/credits/usage_analytics' do
    let(:analytics_data) do
      {
        total_spent: 500.0,
        daily_average: 16.67,
        top_operations: []
      }
    end

    before do
      allow(credit_service).to receive(:get_usage_analytics).and_return(analytics_data)
    end

    context 'with authentication' do
      it 'returns usage analytics' do
        get '/api/v1/ai/credits/usage_analytics',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('total_spent')
      end

      it 'accepts period parameter' do
        get '/api/v1/ai/credits/usage_analytics?period_days=60',
            headers: headers

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/ai/credits/enable_reseller' do
    let(:reseller_result) do
      {
        reseller_enabled: true,
        discount_percentage: 15.0
      }
    end

    before do
      allow(credit_service).to receive(:enable_reseller).and_return(reseller_result)
    end

    context 'with valid parameters' do
      it 'enables reseller mode' do
        post '/api/v1/ai/credits/enable_reseller',
             params: { discount_percentage: 15.0 },
             headers: headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/credits/reseller_stats' do
    let(:reseller_stats) do
      {
        total_sales: 1000.0,
        total_customers: 10,
        commission_earned: 150.0
      }
    end

    before do
      allow(credit_service).to receive(:get_reseller_stats).and_return(reseller_stats)
    end

    context 'when reseller is enabled' do
      it 'returns reseller statistics' do
        get '/api/v1/ai/credits/reseller_stats',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('total_sales')
      end
    end

    context 'when reseller is not enabled' do
      before do
        allow(credit_service).to receive(:get_reseller_stats).and_return(nil)
        allow(credit_service).to receive(:errors).and_return([ 'Reseller not enabled' ])
      end

      it 'returns error response' do
        get '/api/v1/ai/credits/reseller_stats',
            headers: headers,
            as: :json

        expect_error_response('Reseller not enabled', 422)
      end
    end
  end
end
