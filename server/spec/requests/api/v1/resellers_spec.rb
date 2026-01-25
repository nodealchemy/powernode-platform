# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Resellers', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  let(:headers) { auth_headers_for(user) }
  let(:admin_headers) { auth_headers_for(admin_user) }

  before do
    admin_user.grant_permission('resellers.read')
    admin_user.grant_permission('resellers.manage')
  end

  describe 'GET /api/v1/resellers' do
    before do
      create_list(:reseller, 3, status: 'active')
    end

    context 'with resellers.read permission' do
      it 'returns list of resellers' do
        get '/api/v1/resellers', headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.first).to include('id', 'company_name', 'referral_code', 'tier', 'status')
      end

      it 'supports filtering by status' do
        get '/api/v1/resellers', params: { status: 'active' }, headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data.all? { |r| r['status'] == 'active' }).to be true
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        get '/api/v1/resellers', headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect_error_response
      end
    end
  end

  describe 'GET /api/v1/resellers/:id' do
    let(:reseller) { create(:reseller, account: account) }

    it 'returns reseller details' do
      get "/api/v1/resellers/#{reseller.id}", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include(
        'id' => reseller.id,
        'company_name' => reseller.company_name,
        'referral_code' => reseller.referral_code
      )
    end

    context 'with non-existent reseller' do
      it 'returns not found error' do
        get "/api/v1/resellers/#{SecureRandom.uuid}", headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect_error_response('Reseller not found')
      end
    end
  end

  describe 'POST /api/v1/resellers' do
    let(:valid_params) do
      {
        company_name: 'Test Reseller Inc',
        contact_email: 'contact@testreseller.com',
        contact_phone: '+1234567890',
        website_url: 'https://testreseller.com',
        tax_id: 'TAX-12345',
        payout_method: 'bank_transfer'
      }
    end

    context 'with valid params' do
      before do
        allow_any_instance_of(ResellerService).to receive(:apply).and_return(
          {
            success: true,
            reseller: create(:reseller, account: account)
          }
        )
      end

      it 'creates a reseller application' do
        post '/api/v1/resellers', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response_data
        expect(data).to have_key('id')
      end
    end

    context 'with invalid params' do
      before do
        allow_any_instance_of(ResellerService).to receive(:apply).and_return(
          {
            success: false,
            error: 'Invalid application'
          }
        )
      end

      it 'returns error' do
        post '/api/v1/resellers', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response
      end
    end
  end

  describe 'PATCH /api/v1/resellers/:id' do
    let(:reseller) { create(:reseller, account: account) }
    let(:update_params) do
      {
        contact_email: 'newemail@example.com',
        contact_phone: '+9876543210'
      }
    end

    it 'updates the reseller' do
      patch "/api/v1/resellers/#{reseller.id}", params: update_params, headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data['contact_email']).to eq('newemail@example.com')
    end
  end

  describe 'GET /api/v1/resellers/:id/dashboard' do
    let(:reseller) { create(:reseller, account: account) }

    before do
      allow_any_instance_of(ResellerService).to receive(:dashboard_stats).and_return(
        {
          success: true,
          stats: {
            total_referrals: 10,
            active_referrals: 8,
            total_revenue: 5000,
            pending_payout: 500
          }
        }
      )
    end

    it 'returns dashboard statistics' do
      get "/api/v1/resellers/#{reseller.id}/dashboard", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to include(
        'total_referrals' => 10,
        'active_referrals' => 8,
        'total_revenue' => 5000,
        'pending_payout' => 500
      )
    end
  end

  describe 'POST /api/v1/resellers/:id/request_payout' do
    let(:reseller) { create(:reseller, account: account) }
    let(:payout_params) { { amount: 100.0 } }

    context 'with valid amount' do
      before do
        allow_any_instance_of(ResellerService).to receive(:request_payout).and_return(
          {
            success: true,
            payout: double(summary: { id: SecureRandom.uuid, amount: 100.0, status: 'pending' })
          }
        )
      end

      it 'creates a payout request' do
        post "/api/v1/resellers/#{reseller.id}/request_payout",
             params: payout_params,
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('amount' => 100.0, 'status' => 'pending')
      end
    end

    context 'with invalid amount' do
      let(:payout_params) { { amount: 0 } }

      it 'returns error' do
        post "/api/v1/resellers/#{reseller.id}/request_payout",
             params: payout_params,
             headers: headers,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect_error_response('Invalid payout amount')
      end
    end
  end

  describe 'GET /api/v1/resellers/:id/commissions' do
    let(:reseller) { create(:reseller, account: account) }

    before do
      create_list(:reseller_commission, 5, reseller: reseller)
    end

    it 'returns reseller commissions' do
      get "/api/v1/resellers/#{reseller.id}/commissions", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.first).to include('id', 'commission_type', 'commission_amount', 'status')
    end

    it 'filters by status' do
      get "/api/v1/resellers/#{reseller.id}/commissions",
          params: { status: 'pending' },
          headers: headers,
          as: :json

      expect_success_response
    end
  end

  describe 'GET /api/v1/resellers/:id/referrals' do
    let(:reseller) { create(:reseller, account: account) }

    before do
      create_list(:reseller_referral, 3, reseller: reseller)
    end

    it 'returns reseller referrals' do
      get "/api/v1/resellers/#{reseller.id}/referrals", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(3)
    end
  end

  describe 'GET /api/v1/resellers/:id/payouts' do
    let(:reseller) { create(:reseller, account: account) }

    before do
      create_list(:reseller_payout, 2, reseller: reseller)
    end

    it 'returns reseller payouts' do
      get "/api/v1/resellers/#{reseller.id}/payouts", headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.length).to eq(2)
    end
  end

  describe 'POST /api/v1/resellers/:id/approve' do
    let(:reseller) { create(:reseller, status: 'pending') }

    context 'with resellers.manage permission' do
      before do
        allow_any_instance_of(ResellerService).to receive(:approve_application).and_return(
          {
            success: true,
            reseller: reseller
          }
        )
      end

      it 'approves the reseller' do
        post "/api/v1/resellers/#{reseller.id}/approve", headers: admin_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('id')
      end
    end

    context 'without permission' do
      it 'returns forbidden error' do
        post "/api/v1/resellers/#{reseller.id}/approve", headers: headers, as: :json

        expect(response).to have_http_status(:forbidden)
        expect_error_response
      end
    end
  end

  describe 'POST /api/v1/resellers/:id/activate' do
    let(:reseller) { create(:reseller, status: 'approved') }

    context 'with resellers.manage permission' do
      before do
        allow_any_instance_of(ResellerService).to receive(:activate_reseller).and_return(
          {
            success: true,
            reseller: reseller
          }
        )
      end

      it 'activates the reseller' do
        post "/api/v1/resellers/#{reseller.id}/activate", headers: admin_headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/resellers/:id/suspend' do
    let(:reseller) { create(:reseller, status: 'active') }

    context 'with resellers.manage permission' do
      it 'suspends the reseller' do
        post "/api/v1/resellers/#{reseller.id}/suspend",
             params: { reason: 'Policy violation' },
             headers: admin_headers,
             as: :json

        expect_success_response
      end
    end
  end

  describe 'POST /api/v1/resellers/payouts/:payout_id/process' do
    let(:payout) { create(:reseller_payout, status: 'pending') }

    context 'with resellers.manage permission' do
      before do
        allow_any_instance_of(ResellerService).to receive(:process_payout).and_return(
          {
            success: true,
            payout: payout
          }
        )
        allow(payout).to receive(:summary).and_return({ id: payout.id, status: 'processed' })
      end

      it 'processes the payout' do
        post "/api/v1/resellers/payouts/#{payout.id}/process", headers: admin_headers, as: :json

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/resellers/me' do
    context 'with reseller profile' do
      let(:reseller) { create(:reseller, account: account) }

      it 'returns current user reseller profile' do
        get '/api/v1/resellers/me', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include('id' => reseller.id)
      end
    end

    context 'without reseller profile' do
      it 'returns not found error' do
        get '/api/v1/resellers/me', headers: headers, as: :json

        expect(response).to have_http_status(:not_found)
        expect_error_response('No reseller profile found')
      end
    end
  end

  describe 'POST /api/v1/resellers/track_referral' do
    let(:referred_account) { create(:account) }
    let(:referral_params) do
      {
        referral_code: 'TEST-CODE',
        referred_account_id: referred_account.id
      }
    end

    context 'with valid referral code' do
      before do
        allow_any_instance_of(ResellerService).to receive(:track_referral).and_return(
          { success: true }
        )
      end

      it 'tracks the referral' do
        post '/api/v1/resellers/track_referral', params: referral_params, headers: headers, as: :json

        expect_success_response
      end
    end

    context 'without referral code' do
      it 'returns bad request error' do
        post '/api/v1/resellers/track_referral',
             params: { referred_account_id: referred_account.id },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:bad_request)
        expect_error_response('Referral code is required')
      end
    end
  end

  describe 'GET /api/v1/resellers/tiers' do
    it 'returns reseller tiers information' do
      get '/api/v1/resellers/tiers', headers: headers, as: :json

      expect_success_response
      data = json_response_data
      expect(data).to be_an(Array)
      expect(data.first).to include('tier', 'commission_percentage', 'min_referrals')
    end
  end
end
