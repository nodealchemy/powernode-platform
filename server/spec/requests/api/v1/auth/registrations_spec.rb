# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Auth::Registrations', type: :request do
  before do
    allow(WorkerJobService).to receive(:enqueue_job).and_return({ 'status' => 'queued' })
    allow(WorkerJobService).to receive(:enqueue_notification_email).and_return({ 'status' => 'queued' })
  end

  describe 'POST /api/v1/auth/register' do
    let(:valid_params) do
      {
        account_name: 'Test Company',
        name: 'John Doe',
        email: 'john@example.com',
        password: TestUsers::PASSWORD
      }
    end

    context 'with valid registration data' do
      it 'creates new account and user successfully' do
        expect {
          post '/api/v1/auth/register',
               params: valid_params,
               as: :json
        }.to change(Account, :count).by(1)
         .and change(User, :count).by(1)

        expect_success_response
        expect(response).to have_http_status(:created)

        response_data = json_response
        expect(response_data['data']['user']).to be_present
        expect(response_data['data']['account']).to be_present
        expect(response_data['data']['access_token']).to be_present
        expect(response_data['data']['expires_at']).to be_present
        # Refresh token is now in HttpOnly cookie, not in response body
        expect(response.cookies['refresh_token']).to be_present
      end

      it 'auto-generates subdomain from account name' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        account = Account.last
        expect(account.subdomain).to eq('test-company')
      end

      it 'assigns owner role to first user' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        user = User.last
        expect(user.role_names).to include('owner')
      end

      it 'sends verification email when required' do
        # Force email verification to be required (overrides test env auto-verify)
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))

        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response
        expect(WorkerJobService).to have_received(:enqueue_notification_email)
      end

      it 'includes verification warning in response' do
        # Force email verification to be required (overrides test env auto-verify)
        allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))

        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['warning']).to include('verify your account')
      end
    end

    context 'with plan selection' do
      let(:plan) { create(:plan, status: 'active', is_public: true, trial_days: 14) }
      let(:params_with_plan) { valid_params.merge(plan_id: plan.id) }

      before do
        allow(Shared::FeatureGateService).to receive(:billing_enabled?).and_return(true)
      end

      it 'creates subscription with trial period' do
        expect {
          post '/api/v1/auth/register',
               params: params_with_plan,
               as: :json
        }.to change(Billing::Subscription, :count).by(1)

        expect_success_response

        response_data = json_response
        expect(response_data['data']['subscription']).to be_present
        expect(response_data['data']['subscription']['status']).to eq('trialing')
        expect(response_data['data']['subscription']['plan']['id']).to eq(plan.id)
      end

      it 'does not create subscription for inactive plan' do
        inactive_plan = create(:plan, status: 'inactive', is_public: true)

        expect {
          post '/api/v1/auth/register',
               params: valid_params.merge(plan_id: inactive_plan.id),
               as: :json
        }.not_to change(Billing::Subscription, :count)

        expect_success_response

        response_data = json_response
        expect(response_data['data']['subscription']).to be_nil
      end

      it 'does not create subscription for non-public plan' do
        private_plan = create(:plan, status: 'active', is_public: false)

        expect {
          post '/api/v1/auth/register',
               params: valid_params.merge(plan_id: private_plan.id),
               as: :json
        }.not_to change(Billing::Subscription, :count)

        expect_success_response

        response_data = json_response
        expect(response_data['data']['subscription']).to be_nil
      end
    end

    context 'with firstName and lastName parameters' do
      it 'combines firstName and lastName' do
        post '/api/v1/auth/register',
             params: {
               account_name: 'Test Company',
               firstName: 'Jane',
               lastName: 'Smith',
               email: 'jane@example.com',
               password: TestUsers::PASSWORD
             },
             as: :json

        expect_success_response

        user = User.last
        expect(user.name).to eq('Jane Smith')
      end

      it 'handles snake_case variants' do
        post '/api/v1/auth/register',
             params: {
               account_name: 'Test Company',
               first_name: 'Bob',
               last_name: 'Jones',
               email: 'bob@example.com',
               password: TestUsers::PASSWORD
             },
             as: :json

        expect_success_response

        user = User.last
        expect(user.name).to eq('Bob Jones')
      end
    end

    context 'with camelCase parameter variants' do
      it 'accepts accountName instead of account_name' do
        post '/api/v1/auth/register',
             params: {
               accountName: 'CamelCase Company',
               name: 'Test User',
               email: 'camel@example.com',
               password: TestUsers::PASSWORD
             },
             as: :json

        expect_success_response

        account = Account.last
        expect(account.name).to eq('CamelCase Company')
      end
    end

    context 'with duplicate subdomain' do
      before do
        create(:account, name: 'Test Company', subdomain: 'test-company')
      end

      it 'generates unique subdomain by appending counter' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        account = Account.last
        expect(account.subdomain).to eq('test-company1')
      end
    end

    context 'with duplicate email' do
      before do
        create(:user, email: 'john@example.com')
      end

      it 'returns validation error' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unprocessable_content)

        response_data = json_response
        expect(response_data['success']).to be false
        expect(response_data['error']).to be_present
      end
    end

    context 'with missing required fields' do
      it 'returns validation error for missing email' do
        post '/api/v1/auth/register',
             params: valid_params.except(:email),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns validation error for missing password' do
        post '/api/v1/auth/register',
             params: valid_params.except(:password),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns validation error for missing name' do
        post '/api/v1/auth/register',
             params: valid_params.except(:name),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with invalid email format' do
      it 'returns validation error' do
        post '/api/v1/auth/register',
             params: valid_params.merge(email: 'invalid-email'),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'with weak password' do
      it 'returns validation error' do
        post '/api/v1/auth/register',
             params: valid_params.merge(password: 'weak'),
             as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'when email verification not required' do
      it 'auto-verifies user email' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        user = User.last
        expect(user.email_verified?).to be true
      end

      it 'does not include warning in response' do
        post '/api/v1/auth/register',
             params: valid_params,
             as: :json

        expect_success_response

        response_data = json_response
        expect(response_data['data']['warning']).to be_nil
      end
    end

    context 'when email sending fails' do
      before do
        allow(WorkerJobService).to receive(:enqueue_notification_email).and_raise(StandardError.new('Email service down'))
      end

      it 'still completes registration successfully' do
        expect {
          post '/api/v1/auth/register',
               params: valid_params,
               as: :json
        }.to change(User, :count).by(1)

        expect_success_response
      end
    end
  end
end
