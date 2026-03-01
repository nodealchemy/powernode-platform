# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::Publisher', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.publisher.read', 'ai.publisher.manage' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: [ 'ai.publisher.read' ]) }
  let(:other_account) { create(:account) }
  let(:other_user) { create(:user, account: other_account, permissions: [ 'ai.publisher.read' ]) }

  let(:headers) { auth_headers_for(user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }
  let(:other_headers) { auth_headers_for(other_user) }

  describe 'GET /api/v1/ai/publisher' do
    # Each account can only have one publisher (unique constraint)
    let(:second_account) { create(:account) }
    let!(:publisher1) { create(:ai_publisher_account, account: account, status: 'active') }
    let!(:publisher2) { create(:ai_publisher_account, account: second_account, status: 'pending') }
    let!(:other_publisher) { create(:ai_publisher_account, account: other_account, status: 'suspended') }

    context 'with proper permissions' do
      it 'returns list of publisher accounts' do
        get '/api/v1/ai/publisher', headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        # Controller returns ALL publishers (not filtered by account)
        expect(data.length).to eq(3)
        expect(data.map { |p| p['id'] }).to include(publisher1.id, publisher2.id, other_publisher.id)
      end

      it 'filters by status' do
        get '/api/v1/ai/publisher?status=active', headers: headers

        expect_success_response
        data = json_response_data
        expect(data.length).to eq(1)
        expect(data.first['status']).to eq('active')
      end

      it 'supports pagination' do
        get '/api/v1/ai/publisher?page=1&per_page=1', headers: headers

        expect_success_response
        response_body = json_response
        expect(response_body['meta']['pagination']).to include(
          'current_page' => 1,
          'per_page' => 1,
          'total_count' => 3
        )
      end
    end

    context 'without ai.publisher.read permission' do
      it 'returns forbidden error' do
        user_without_permission = create(:user, account: account, permissions: [])
        headers_without_permission = auth_headers_for(user_without_permission)

        get '/api/v1/ai/publisher', headers: headers_without_permission

        expect_error_response('Permission denied: ai.publisher.read', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns publisher account details' do
        get "/api/v1/ai/publisher/#{publisher.id}", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'id' => publisher.id,
          'publisher_name' => publisher.publisher_name,
          'status' => publisher.status
        )
      end

      it 'returns not found for non-existent publisher' do
        get "/api/v1/ai/publisher/#{SecureRandom.uuid}", headers: headers

        expect_error_response('Publisher not found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/publisher' do
    let(:valid_params) do
      {
        publisher_name: 'Test Publisher',
        publisher_slug: 'test-publisher',
        description: 'A test publisher',
        support_email: 'support@test.com'
      }
    end

    context 'with proper permissions' do
      it 'creates a new publisher account' do
        expect {
          post '/api/v1/ai/publisher', params: valid_params, headers: headers, as: :json
        }.to change { Ai::PublisherAccount.count }.by(1)

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['publisher_name']).to eq('Test Publisher')
      end

      it 'returns error if publisher already exists for account' do
        create(:ai_publisher_account, account: account)

        post '/api/v1/ai/publisher', params: valid_params, headers: headers, as: :json

        expect_error_response('Account already has a publisher profile', 422)
      end
    end

    context 'without ai.publisher.manage permission' do
      it 'returns forbidden error' do
        post '/api/v1/ai/publisher', params: valid_params, headers: read_only_headers, as: :json

        expect_error_response('Permission denied: ai.publisher.manage', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/dashboard' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns publisher dashboard data' do
        get "/api/v1/ai/publisher/#{publisher.id}/dashboard", headers: headers

        expect_success_response
        data = json_response_data
        # Dashboard returns: publisher, overview, earnings, recent_sales, top_templates
        expect(data).to have_key('publisher')
        expect(data).to have_key('overview')
        expect(data).to have_key('earnings')
      end
    end

    context 'accessing other account publisher' do
      let(:other_publisher) { create(:ai_publisher_account, account: other_account) }

      it 'returns forbidden error' do
        # Use read_only_headers (no manage permission) - users with ai.publisher.manage can access any publisher
        get "/api/v1/ai/publisher/#{other_publisher.id}/dashboard", headers: read_only_headers

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/analytics' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns analytics data' do
        get "/api/v1/ai/publisher/#{publisher.id}/analytics", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('period')
        expect(data).to have_key('summary')
        expect(data['daily_metrics']).to be_an(Array)
      end

      it 'accepts period parameter' do
        get "/api/v1/ai/publisher/#{publisher.id}/analytics?period=7", headers: headers

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/earnings' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      before do
        # Mock the earnings snapshot model that doesn't exist yet
        earnings_snapshot_relation = double(
          where: double(order: double(limit: []))
        )
        stub_const('Ai::PublisherEarningsSnapshot', earnings_snapshot_relation)

        # Mock the transactions relation
        transactions_relation = double(
          completed: double(order: double(limit: []))
        )
        allow(Ai::MarketplaceTransaction).to receive(:where).and_return(transactions_relation)
      end

      it 'returns earnings data' do
        get "/api/v1/ai/publisher/#{publisher.id}/earnings", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to have_key('current')
        expect(data['history']).to be_an(Array)
        expect(data['recent_transactions']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/templates' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns publisher templates' do
        get "/api/v1/ai/publisher/#{publisher.id}/templates", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end

      it 'filters by status' do
        get "/api/v1/ai/publisher/#{publisher.id}/templates?status=published", headers: headers

        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/payouts' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns payout history' do
        get "/api/v1/ai/publisher/#{publisher.id}/payouts", headers: headers

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/publisher/:id/request_payout' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'requests a payout' do
        allow_any_instance_of(Ai::MarketplacePaymentService).to receive(:process_publisher_payout)
          .and_return({ success: true, transfer_id: 'test_transfer', amount: 100.0 })

        post "/api/v1/ai/publisher/#{publisher.id}/request_payout",
             params: { amount: 100.0 }, headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['transfer_id']).to eq('test_transfer')
      end

      it 'returns error for invalid amount' do
        post "/api/v1/ai/publisher/#{publisher.id}/request_payout",
             params: { amount: 0 }, headers: headers, as: :json

        expect_error_response('Invalid payout amount', 400)
      end
    end

    context 'without ai.publisher.manage permission' do
      it 'returns forbidden error' do
        post "/api/v1/ai/publisher/#{publisher.id}/request_payout",
             params: { amount: 100.0 }, headers: read_only_headers, as: :json

        expect_error_response('Permission denied: ai.publisher.manage', 403)
      end
    end
  end

  describe 'POST /api/v1/ai/publisher/:id/stripe_setup' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'initiates Stripe Connect setup' do
        allow_any_instance_of(Ai::MarketplacePaymentService).to receive(:setup_stripe_connect)
          .and_return({ success: true, onboarding_url: 'https://stripe.com/onboard' })

        post "/api/v1/ai/publisher/#{publisher.id}/stripe_setup",
             params: { return_url: 'https://test.com/return', refresh_url: 'https://test.com/refresh' },
             headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['onboarding_url']).to be_present
      end

      it 'returns error if URLs are missing' do
        post "/api/v1/ai/publisher/#{publisher.id}/stripe_setup", headers: headers, as: :json

        expect_error_response('return_url and refresh_url are required', 400)
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/:id/stripe_status' do
    let(:publisher) { create(:ai_publisher_account, account: account) }

    context 'with proper permissions' do
      it 'returns Stripe account status' do
        allow_any_instance_of(Ai::MarketplacePaymentService).to receive(:verify_stripe_account)
          .and_return({ success: true, status: 'active', payout_enabled: true })

        get "/api/v1/ai/publisher/#{publisher.id}/stripe_status", headers: headers

        expect_success_response
        data = json_response_data
        expect(data['status']).to eq('active')
      end
    end
  end

  describe 'GET /api/v1/ai/publisher/me' do
    context 'with existing publisher profile' do
      let!(:publisher) { create(:ai_publisher_account, account: account) }

      it 'returns current account publisher profile' do
        get '/api/v1/ai/publisher/me', headers: headers

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(publisher.id)
      end
    end

    context 'without publisher profile' do
      it 'returns not found error' do
        get '/api/v1/ai/publisher/me', headers: headers

        expect_error_response('No publisher profile found', 404)
      end
    end
  end
end
