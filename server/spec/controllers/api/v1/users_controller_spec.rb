# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::UsersController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:subscription) { create(:subscription, account: account) }
  let(:plan) { create(:plan, :with_limits) }
  
  before do
    subscription.update!(plan: plan)
    sign_in_as_user(user)
  end

  describe 'POST #create' do
    let(:user_params) do
      {
        email: 'newuser@example.com',
        first_name: 'New',
        last_name: 'User',
        password: 'VerySecurePassword2024!@#',
        password_confirmation: 'VerySecurePassword2024!@#'
      }
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
        expect(JSON.parse(response.body)['message']).to eq('User created successfully')
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
        expect(JSON.parse(response.body)['success']).to be false
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
        expect(JSON.parse(response.body)['success']).to be true
      end
    end

    context 'when account has no subscription' do
      let(:account_without_subscription) { create(:account) }
      let(:user_without_subscription) { create(:user, account: account_without_subscription) }

      before do
        sign_in_as_user(user_without_subscription)
      end

      it 'returns error message' do
        post :create, params: { user: user_params }

        expect(response).to have_http_status(:forbidden)
        expect(JSON.parse(response.body)['error']).to eq('User limit reached for your current plan')
      end
    end
  end
end