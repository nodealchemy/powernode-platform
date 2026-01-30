# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Customers', type: :request do
  let(:account) { create(:account) }
  let(:plan) { create(:plan) }

  let(:user) do
    create(:user, account: account, permissions: ['customers.read', 'customers.manage'])
  end

  let(:reader_user) do
    create(:user, account: account, permissions: ['customers.read'])
  end

  let(:regular_user) do
    create(:user, account: account, permissions: [])
  end

  let!(:customers) do
    3.times.map do
      customer_account = create(:account, status: 'active')
      create(:subscription, account: customer_account, plan: plan, status: 'active')
      customer_account
    end
  end

  describe 'GET /api/v1/customers' do
    context 'with authentication' do
      it 'returns customers list' do
        get '/api/v1/customers', headers: auth_headers_for(user), as: :json

        expect_success_response
        expect(json_response['data']['customers']).to be_an(Array)
      end

      it 'includes pagination metadata' do
        get '/api/v1/customers', headers: auth_headers_for(user), as: :json

        expect_success_response
        pagination = json_response['data']['pagination']

        expect(pagination).to include(
          'current_page',
          'per_page',
          'total_count',
          'total_pages'
        )
      end

      it 'includes customer stats' do
        get '/api/v1/customers', headers: auth_headers_for(user), as: :json

        expect_success_response
        stats = json_response['data']['stats']

        expect(stats).to include(
          'total_customers',
          'active_customers',
          'active_subscriptions',
          'new_this_month',
          'total_mrr',
          'churn_rate'
        )
      end

      it 'returns customer data with correct structure' do
        get '/api/v1/customers', headers: auth_headers_for(user), as: :json

        expect_success_response
        customer = json_response['data']['customers'].first

        expect(customer).to include(
          'id',
          'name',
          'status',
          'created_at',
          'updated_at'
        )
      end
    end

    context 'with search filter' do
      let!(:searchable_account) do
        customer_account = create(:account, name: 'Acme Corp', status: 'active')
        create(:user, account: customer_account, email: 'contact@acme.com')
        customer_account
      end

      it 'filters by account name' do
        get '/api/v1/customers?search=Acme', headers: auth_headers_for(user), as: :json

        expect_success_response
        customers_data = json_response['data']['customers']

        expect(customers_data.any? { |c| c['name'] == 'Acme Corp' }).to be true
      end

      it 'filters by user email' do
        get '/api/v1/customers?search=acme.com', headers: auth_headers_for(user), as: :json

        expect_success_response
      end
    end

    context 'with status filter' do
      before do
        create(:account, status: 'cancelled')
      end

      it 'filters by active status' do
        get '/api/v1/customers?status=active', headers: auth_headers_for(user), as: :json

        expect_success_response
        customers_data = json_response['data']['customers']

        expect(customers_data.all? { |c| c['status'] == 'active' }).to be true
      end

      it 'filters by cancelled status' do
        get '/api/v1/customers?status=cancelled', headers: auth_headers_for(user), as: :json

        expect_success_response
      end
    end

    context 'with plan filter' do
      it 'filters by plan' do
        get "/api/v1/customers?plan=#{plan.id}", headers: auth_headers_for(user), as: :json

        expect_success_response
      end
    end

    context 'pagination' do
      before do
        25.times do
          customer_account = create(:account)
          create(:subscription, account: customer_account, plan: plan)
        end
      end

      it 'respects per_page parameter' do
        get '/api/v1/customers?per_page=10', headers: auth_headers_for(user), as: :json

        expect_success_response
        expect(json_response['data']['customers'].length).to eq(10)
        expect(json_response['data']['pagination']['per_page']).to eq(10)
      end

      it 'respects page parameter' do
        get '/api/v1/customers?page=2&per_page=10', headers: auth_headers_for(user), as: :json

        expect_success_response
        expect(json_response['data']['pagination']['current_page']).to eq(2)
      end

      it 'caps per_page at 100' do
        get '/api/v1/customers?per_page=200', headers: auth_headers_for(user), as: :json

        expect_success_response
        expect(json_response['data']['pagination']['per_page']).to eq(100)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        get '/api/v1/customers', as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/customers/:id' do
    let(:customer) { customers.first }

    context 'with authentication' do
      it 'returns customer details' do
        get "/api/v1/customers/#{customer.id}", headers: auth_headers_for(user), as: :json

        expect_success_response
        customer_data = json_response['data']['customer']

        expect(customer_data['id']).to eq(customer.id)
      end

      it 'includes detailed information' do
        get "/api/v1/customers/#{customer.id}", headers: auth_headers_for(user), as: :json

        expect_success_response
        customer_data = json_response['data']['customer']

        expect(customer_data).to include(
          'payment_methods',
          'total_invoices',
          'total_payments',
          'lifetime_value',
          'recent_activity'
        )
      end
    end

    context 'with non-existent customer' do
      it 'returns not found error' do
        get '/api/v1/customers/non-existent-id', headers: auth_headers_for(user), as: :json

        expect_error_response(nil, 404)
      end
    end
  end

  describe 'POST /api/v1/customers' do
    let(:valid_params) do
      {
        customer: {
          name: 'New Customer',
          subdomain: 'newcustomer',
          email: 'admin@newcustomer.com',
          plan_id: plan.id
        }
      }
    end

    context 'with authentication' do
      it 'creates a new customer' do
        # Ensure user is created before count check
        headers = auth_headers_for(user)

        expect {
          post '/api/v1/customers',
               params: valid_params,
               headers: headers,
               as: :json
        }.to change(Account, :count).by(1)

        expect_success_response
        expect(json_response['data']['customer']).to be_present
      end

      it 'creates subscription when plan provided' do
        headers = auth_headers_for(user)

        expect {
          post '/api/v1/customers',
               params: valid_params,
               headers: headers,
               as: :json
        }.to change(Subscription, :count).by(1)

        expect_success_response
      end

      it 'creates primary user' do
        # Ensure user is created before count check
        headers = auth_headers_for(user)

        expect {
          post '/api/v1/customers',
               params: valid_params,
               headers: headers,
               as: :json
        }.to change(User, :count).by(1)

        expect_success_response
      end

      it 'returns created status' do
        post '/api/v1/customers',
             params: valid_params,
             headers: auth_headers_for(user),
             as: :json

        expect(response).to have_http_status(:created)
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        invalid_params = { customer: { name: '' } }

        post '/api/v1/customers',
             params: invalid_params,
             headers: auth_headers_for(user),
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/customers/:id' do
    let(:customer) { customers.first }
    let(:update_params) do
      {
        customer: {
          name: 'Updated Name'
        }
      }
    end

    context 'with authentication' do
      it 'updates customer' do
        patch "/api/v1/customers/#{customer.id}",
              params: update_params,
              headers: auth_headers_for(user),
              as: :json

        expect_success_response
        expect(json_response['data']['customer']['name']).to eq('Updated Name')
      end

      it 'updates subscription attributes' do
        subscription_params = {
          customer: {
            subscription_attributes: {
              status: 'canceled'
            }
          }
        }

        patch "/api/v1/customers/#{customer.id}",
              params: subscription_params,
              headers: auth_headers_for(user),
              as: :json

        expect_success_response
      end
    end

    context 'with invalid params' do
      it 'returns validation error' do
        invalid_params = { customer: { name: '' } }

        patch "/api/v1/customers/#{customer.id}",
              params: invalid_params,
              headers: auth_headers_for(user),
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'with non-existent customer' do
      it 'returns not found error' do
        patch '/api/v1/customers/non-existent-id',
              params: update_params,
              headers: auth_headers_for(user),
              as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'DELETE /api/v1/customers/:id' do
    let(:customer) { customers.first }

    context 'with authentication' do
      it 'deactivates customer' do
        delete "/api/v1/customers/#{customer.id}", headers: auth_headers_for(user), as: :json

        expect_success_response
        expect(customer.reload.status).to eq('cancelled')
      end

      it 'does not permanently delete' do
        # Ensure user (and its account) are created before count check
        headers = auth_headers_for(user)
        customer_id = customer.id

        expect {
          delete "/api/v1/customers/#{customer_id}", headers: headers, as: :json
        }.not_to change(Account, :count)
      end
    end

    context 'with non-existent customer' do
      it 'returns not found error' do
        delete '/api/v1/customers/non-existent-id', headers: auth_headers_for(user), as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'GET /api/v1/customers/:id/stats' do
    let(:customer) { customers.first }

    context 'with authentication' do
      it 'returns customer statistics' do
        get "/api/v1/customers/#{customer.id}/stats", headers: auth_headers_for(user), as: :json

        expect_success_response
        stats = json_response['data']

        expect(stats).to include(
          'total_customers',
          'active_customers',
          'active_subscriptions',
          'new_this_month',
          'total_mrr',
          'churn_rate'
        )
      end
    end
  end
end
