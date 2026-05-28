# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::UsersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before do
    sign_in_as_user(user)
  end

  describe 'POST #create' do
    let(:user_params) do
      {
        email: 'newuser@example.com',
        name: 'New User',
        password: 'VerySecurePassword2024!@#',
        password_confirmation: 'VerySecurePassword2024!@#'
      }
    end

    context 'in core mode (no billing — unlimited)' do
      it 'creates user successfully regardless of existing count' do
        create_list(:user, 5, account: account)
        post :create, params: { user: user_params }

        expect(response).to have_http_status(:created)
        expect(JSON.parse(response.body)['success']).to be true
        expect(JSON.parse(response.body)['data']).to be_present
      end
    end

    # Plan-based user-limit enforcement is business-mode behavior (Billing::Plan).
    context 'with plan-based limits (business mode)' do
      let(:subscription) { create(:subscription, account: account) }
      let(:plan) { create(:plan, :with_limits) }

      before do
        skip 'requires business billing models' unless defined?(Billing::Subscription)
        subscription.update!(plan: plan)
      end

      context 'when under user limit' do
        before do
          plan.update!(limits: { 'max_users' => 5 })
          create_list(:user, 2, account: account)
        end

        it 'creates user successfully' do
          post :create, params: { user: user_params }

          expect(response).to have_http_status(:created)
          expect(JSON.parse(response.body)['success']).to be true
        end
      end

      context 'when user limit is reached' do
        before do
          plan.update!(limits: { 'max_users' => 3 })
          create_list(:user, 2, account: account) # 3 total with existing user
        end

        it 'returns error message' do
          post :create, params: { user: user_params }

          expect(response).to have_http_status(:forbidden)
          expect(JSON.parse(response.body)['error']).to eq('User limit reached for your current plan')
        end

        it 'does not create the user' do
          expect {
            post :create, params: { user: user_params }
          }.not_to change(User, :count)
        end
      end

      context 'when plan has unlimited users' do
        before do
          plan.update!(limits: { 'max_users' => 9999 })
          create_list(:user, 50, account: account)
        end

        it 'creates user successfully even with many existing users' do
          post :create, params: { user: user_params }

          expect(response).to have_http_status(:created)
        end
      end
    end
  end
end
