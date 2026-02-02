# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Plans', type: :request do
  let(:account) { create(:account) }
  let(:admin_user) { create(:user, :admin, account: account) }
  # Create user with explicitly no permissions to test permission denial
  let(:regular_user) { create(:user, account: account, permissions: []) }

  # Create permissions needed for testing
  let!(:plans_manage_permission) do
    Permission.find_or_create_by!(name: 'plans.manage') do |p|
      p.resource = 'plans'
      p.action = 'manage'
      p.category = 'billing'
    end
  end

  let!(:admin_billing_view_permission) do
    Permission.find_or_create_by!(name: 'admin.billing.read') do |p|
      p.resource = 'admin.billing'
      p.action = 'view'
      p.category = 'admin'
    end
  end

  # User with plans.manage permission
  let(:plan_manager_user) do
    user = create(:user, account: account)
    user.permissions = [ plans_manage_permission ]
    user.save!
    user
  end

  # User with admin.billing.read permission
  let(:billing_viewer_user) do
    user = create(:user, account: account)
    user.permissions = [ admin_billing_view_permission ]
    user.save!
    user
  end

  let(:headers) { auth_headers_for(plan_manager_user) }
  let(:regular_headers) { auth_headers_for(regular_user) }

  before(:each) do
    Rails.cache.clear
  end

  describe 'GET /api/v1/public/plans' do
    let!(:active_public_plan) { create(:plan, status: 'active', is_public: true, price_cents: 2999) }
    let!(:active_public_plan_2) { create(:plan, status: 'active', is_public: true, price_cents: 4999) }
    let!(:inactive_plan) { create(:plan, status: 'inactive', is_public: true) }
    let!(:private_plan) { create(:plan, status: 'active', is_public: false) }

    it 'returns only active public plans without authentication' do
      get '/api/v1/public/plans', as: :json

      expect(response).to have_http_status(:success)
      json = json_response
      expect(json['success']).to be true
      expect(json['data']['plans'].length).to eq(2)
      expect(json['data']['total_count']).to eq(2)
    end

    it 'orders plans by price ascending' do
      get '/api/v1/public/plans', as: :json

      json = json_response
      prices = json['data']['plans'].map { |p| p['price_cents'] }
      expect(prices).to eq(prices.sort)
    end

    it 'includes plan details for registration' do
      get '/api/v1/public/plans', as: :json

      json = json_response
      plan_data = json['data']['plans'].first
      expect(plan_data).to include(
        'id', 'name', 'description', 'price_cents', 'currency',
        'billing_cycle', 'trial_days', 'formatted_price', 'monthly_price',
        'features', 'limits'
      )
    end

    it 'includes discount information' do
      active_public_plan.update!(
        has_annual_discount: true,
        annual_discount_percent: 20,
        has_promotional_discount: true,
        promotional_discount_percent: 10
      )

      get '/api/v1/public/plans', as: :json

      json = json_response
      plan_data = json['data']['plans'].find { |p| p['id'] == active_public_plan.id }
      expect(plan_data).to include(
        'has_annual_discount' => true,
        'annual_discount_percent' => '20.0',
        'has_promotional_discount' => true,
        'promotional_discount_percent' => '10.0'
      )
    end

    it 'excludes inactive plans' do
      get '/api/v1/public/plans', as: :json

      json = json_response
      plan_ids = json['data']['plans'].map { |p| p['id'] }
      expect(plan_ids).not_to include(inactive_plan.id)
    end

    it 'excludes private plans' do
      get '/api/v1/public/plans', as: :json

      json = json_response
      plan_ids = json['data']['plans'].map { |p| p['id'] }
      expect(plan_ids).not_to include(private_plan.id)
    end
  end

  describe 'GET /api/v1/plans/status' do
    let!(:active_public_plan) { create(:plan, status: 'active', is_public: true) }
    let!(:active_private_plan) { create(:plan, status: 'active', is_public: false) }
    let!(:inactive_plan) { create(:plan, status: 'inactive', is_public: true) }

    it 'returns plan counts for authenticated user' do
      get '/api/v1/plans/status', headers: auth_headers_for(regular_user), as: :json

      expect(response).to have_http_status(:success)
      json = json_response
      expect(json['success']).to be true
      expect(json['data']).to include(
        'has_plans' => true,
        'total_count' => 3,
        'active_count' => 2,
        'public_count' => 1
      )
    end

    it 'requires authentication' do
      get '/api/v1/plans/status', as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns has_plans false when no plans exist' do
      Plan.destroy_all

      get '/api/v1/plans/status', headers: auth_headers_for(regular_user), as: :json

      json = json_response
      expect(json['data']['has_plans']).to be false
      expect(json['data']['total_count']).to eq(0)
    end
  end

  describe 'GET /api/v1/plans' do
    let!(:active_public_plan) { create(:plan, status: 'active', is_public: true) }
    let!(:active_private_plan) { create(:plan, status: 'active', is_public: false) }
    let!(:inactive_plan) { create(:plan, status: 'inactive', is_public: true) }
    let!(:archived_plan) { create(:plan, status: 'archived', is_public: false) }

    context 'with plans.manage permission' do
      it 'returns all plans' do
        get '/api/v1/plans', headers: headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['plans'].length).to eq(4)
        expect(json['data']['total_count']).to eq(4)
      end

      it 'includes subscription counts' do
        create(:subscription, :active, plan: active_public_plan)
        create(:subscription, :trialing, plan: active_public_plan)
        create(:subscription, :canceled, plan: active_public_plan)

        get '/api/v1/plans', headers: headers, as: :json

        json = json_response
        plan_data = json['data']['plans'].find { |p| p['id'] == active_public_plan.id }
        expect(plan_data['subscription_count']).to eq(3)
        expect(plan_data['active_subscription_count']).to eq(2) # active + trialing
      end
    end

    context 'with admin.billing.read permission' do
      it 'returns all plans' do
        get '/api/v1/plans', headers: auth_headers_for(billing_viewer_user), as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['data']['plans'].length).to eq(4)
      end
    end

    context 'without management permission' do
      it 'returns only active public plans' do
        get '/api/v1/plans', headers: regular_headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['data']['plans'].length).to eq(1)

        plan_data = json['data']['plans'].first
        expect(plan_data['id']).to eq(active_public_plan.id)
      end
    end

    it 'requires authentication' do
      get '/api/v1/plans', as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /api/v1/plans/:id' do
    let(:plan) { create(:plan, :with_limits, status: 'active', is_public: true) }

    it 'returns plan details' do
      get "/api/v1/plans/#{plan.id}", headers: regular_headers, as: :json

      expect(response).to have_http_status(:success)
      json = json_response
      expect(json['success']).to be true
      expect(json['data']['plan']).to include(
        'id' => plan.id,
        'name' => plan.name,
        'description' => plan.description,
        'price_cents' => plan.price_cents,
        'currency' => plan.currency,
        'billing_cycle' => plan.billing_cycle,
        'status' => plan.status
      )
    end

    it 'includes detailed fields' do
      get "/api/v1/plans/#{plan.id}", headers: regular_headers, as: :json

      json = json_response
      expect(json['data']['plan']).to include(
        'features', 'limits', 'default_roles', 'required_roles',
        'metadata', 'can_be_deleted'
      )
    end

    it 'requires authentication' do
      get "/api/v1/plans/#{plan.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 404 for non-existent plan' do
      get '/api/v1/plans/00000000-0000-0000-0000-000000000000', headers: regular_headers, as: :json

      expect(response).to have_http_status(:not_found)
      json = json_response
      expect(json['success']).to be false
      expect(json['error']).to eq('Plan not found')
    end
  end

  describe 'POST /api/v1/plans' do
    let(:valid_params) do
      {
        plan: {
          name: 'Premium Plan',
          description: 'Our premium offering',
          price_cents: 4999,
          currency: 'USD',
          billing_cycle: 'monthly',
          status: 'active',
          trial_days: 14,
          is_public: true,
          features: { 'api_access' => true, 'priority_support' => true },
          limits: { 'max_users' => 25, 'max_api_keys' => 10 }
        }
      }
    end

    context 'with plans.manage permission' do
      it 'creates a new plan' do
        expect {
          post '/api/v1/plans', params: valid_params, headers: headers, as: :json
        }.to change(Plan, :count).by(1)

        expect(response).to have_http_status(:created)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['plan']['name']).to eq('Premium Plan')
        expect(json['data']['message']).to eq('Plan created successfully')
      end

      it 'creates an audit log entry' do
        expect {
          post '/api/v1/plans', params: valid_params, headers: headers, as: :json
        }.to change(AuditLog, :count).by_at_least(1)

        audit_log = AuditLog.find_by(action: 'create_plan')
        expect(audit_log).to be_present
        expect(audit_log.user).to eq(plan_manager_user)
        expect(audit_log.metadata['plan_name']).to eq('Premium Plan')
      end

      it 'creates plan with features and limits' do
        post '/api/v1/plans', params: valid_params, headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['features']).to eq({ 'api_access' => true, 'priority_support' => true })
        expect(json['data']['plan']['limits']['max_users']).to eq(25)
      end

      it 'creates plan with discount settings' do
        params_with_discount = valid_params.deep_merge(
          plan: {
            has_annual_discount: true,
            annual_discount_percent: 20,
            has_volume_discount: true,
            volume_discount_tiers: [
              { 'min_quantity' => 5, 'discount_percent' => 10 },
              { 'min_quantity' => 10, 'discount_percent' => 20 }
            ]
          }
        )

        post '/api/v1/plans', params: params_with_discount, headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['has_annual_discount']).to be true
        expect(json['data']['plan']['annual_discount_percent']).to eq('20.0')
        expect(json['data']['plan']['volume_discount_tiers'].length).to eq(2)
      end
    end

    context 'with admin.billing.read permission' do
      it 'allows plan creation' do
        expect {
          post '/api/v1/plans', params: valid_params, headers: auth_headers_for(billing_viewer_user), as: :json
        }.to change(Plan, :count).by(1)

        expect(response).to have_http_status(:created)
      end
    end

    context 'without management permission' do
      it 'denies access' do
        post '/api/v1/plans', params: valid_params, headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
        json = json_response
        expect(json['success']).to be false
        expect(json['error']).to include('Permission denied')
      end
    end

    context 'with validation errors' do
      it 'returns error for missing name' do
        invalid_params = valid_params.deep_merge(plan: { name: '' })

        post '/api/v1/plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = json_response
        expect(json['success']).to be false
      end

      it 'returns error for duplicate name' do
        create(:plan, name: 'Premium Plan')

        post '/api/v1/plans', params: valid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        json = json_response
        expect(json['success']).to be false
      end

      it 'returns error for invalid currency' do
        invalid_params = valid_params.deep_merge(plan: { currency: 'INVALID' })

        post '/api/v1/plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for invalid billing cycle' do
        invalid_params = valid_params.deep_merge(plan: { billing_cycle: 'weekly' })

        post '/api/v1/plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for negative price' do
        invalid_params = valid_params.deep_merge(plan: { price_cents: -100 })

        post '/api/v1/plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for trial_days exceeding maximum' do
        invalid_params = valid_params.deep_merge(plan: { trial_days: 400 })

        post '/api/v1/plans', params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'requires authentication' do
      post '/api/v1/plans', params: valid_params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT /api/v1/plans/:id' do
    let(:plan) { create(:plan, name: 'Original Plan', price_cents: 2999) }
    let(:update_params) do
      {
        plan: {
          name: 'Updated Plan',
          price_cents: 3999,
          description: 'Updated description'
        }
      }
    end

    context 'with plans.manage permission' do
      it 'updates the plan' do
        put "/api/v1/plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['plan']['name']).to eq('Updated Plan')
        expect(json['data']['plan']['price_cents']).to eq(3999)
        expect(json['data']['message']).to eq('Plan updated successfully')
      end

      it 'creates an audit log entry with old and new values' do
        put "/api/v1/plans/#{plan.id}", params: update_params, headers: headers, as: :json

        audit_log = AuditLog.find_by(action: 'update_plan')
        expect(audit_log).to be_present
        expect(audit_log.old_values['name']).to eq('Original Plan')
        expect(audit_log.new_values['name']).to eq('Updated Plan')
      end

      it 'allows partial updates' do
        put "/api/v1/plans/#{plan.id}",
            params: { plan: { description: 'New description only' } },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:success)
        plan.reload
        expect(plan.description).to eq('New description only')
        expect(plan.name).to eq('Original Plan')
      end

      it 'updates discount settings' do
        put "/api/v1/plans/#{plan.id}",
            params: { plan: { has_annual_discount: true, annual_discount_percent: 15 } },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:success)
        plan.reload
        expect(plan.has_annual_discount).to be true
        expect(plan.annual_discount_percent.to_i).to eq(15)
      end
    end

    context 'without management permission' do
      it 'denies access' do
        put "/api/v1/plans/#{plan.id}", params: update_params, headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'with validation errors' do
      it 'returns error for invalid data' do
        put "/api/v1/plans/#{plan.id}",
            params: { plan: { name: '' } },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns error for duplicate name' do
        create(:plan, name: 'Existing Plan')

        put "/api/v1/plans/#{plan.id}",
            params: { plan: { name: 'Existing Plan' } },
            headers: headers,
            as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    it 'returns 404 for non-existent plan' do
      put '/api/v1/plans/00000000-0000-0000-0000-000000000000',
          params: update_params,
          headers: headers,
          as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      put "/api/v1/plans/#{plan.id}", params: update_params, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/plans/:id' do
    let!(:plan) { create(:plan) }

    context 'with plans.manage permission' do
      context 'when plan has no active subscriptions' do
        it 'deletes the plan' do
          expect {
            delete "/api/v1/plans/#{plan.id}", headers: headers, as: :json
          }.to change(Plan, :count).by(-1)

          expect(response).to have_http_status(:success)
          json = json_response
          expect(json['success']).to be true
          expect(json['data']['message']).to eq('Plan deleted successfully')
        end

        it 'creates an audit log entry' do
          delete "/api/v1/plans/#{plan.id}", headers: headers, as: :json

          audit_log = AuditLog.find_by(action: 'delete_plan')
          expect(audit_log).to be_present
          expect(audit_log.metadata['plan_name']).to eq(plan.name)
        end

        it 'prevents deletion when plan has subscriptions due to foreign key constraint' do
          # Note: Due to database foreign key constraints, plans cannot be deleted
          # when ANY subscriptions exist, regardless of status. This is by design
          # to preserve historical subscription data integrity.
          create(:subscription, :canceled, plan: plan)

          expect {
            delete "/api/v1/plans/#{plan.id}", headers: headers, as: :json
          }.not_to change(Plan, :count)

          # The can_be_deleted? check passes (no ACTIVE subscriptions)
          # but the actual destroy fails due to FK constraint
          expect(response).to have_http_status(:unprocessable_content)
        end
      end

      context 'when plan has active subscriptions' do
        before do
          create(:subscription, :active, plan: plan)
        end

        it 'returns error and does not delete' do
          expect {
            delete "/api/v1/plans/#{plan.id}", headers: headers, as: :json
          }.not_to change(Plan, :count)

          expect(response).to have_http_status(:unprocessable_content)
          json = json_response
          expect(json['success']).to be false
          expect(json['error']).to eq('Cannot delete plan with active subscriptions')
        end
      end

      context 'when plan has trialing subscriptions' do
        before do
          create(:subscription, :trialing, plan: plan)
        end

        it 'returns error and does not delete' do
          expect {
            delete "/api/v1/plans/#{plan.id}", headers: headers, as: :json
          }.not_to change(Plan, :count)

          expect(response).to have_http_status(:unprocessable_content)
          json = json_response
          expect(json['error']).to eq('Cannot delete plan with active subscriptions')
        end
      end
    end

    context 'without management permission' do
      it 'denies access' do
        delete "/api/v1/plans/#{plan.id}", headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'returns 404 for non-existent plan' do
      delete '/api/v1/plans/00000000-0000-0000-0000-000000000000', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      delete "/api/v1/plans/#{plan.id}", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'POST /api/v1/plans/:id/duplicate' do
    let(:original_plan) do
      create(:plan,
             name: 'Original Premium',
             description: 'Premium plan',
             price_cents: 4999,
             status: 'active',
             is_public: true,
             features: { 'api_access' => true },
             limits: { 'max_users' => 50 },
             paypal_plan_id: 'P-123')
    end

    context 'with plans.manage permission' do
      it 'duplicates the plan' do
        # Create original plan before the expect block to ensure accurate count
        plan_to_duplicate = original_plan
        expect {
          post "/api/v1/plans/#{plan_to_duplicate.id}/duplicate", headers: headers, as: :json
        }.to change(Plan, :count).by(1)

        expect(response).to have_http_status(:created)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['message']).to eq('Plan duplicated successfully')
      end

      it 'creates plan with "(Copy)" suffix' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['name']).to eq('Original Premium (Copy)')
      end

      it 'sets duplicated plan as inactive' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['status']).to eq('inactive')
      end

      it 'clears payment provider IDs' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['paypal_plan_id']).to be_nil
      end

      it 'copies features and limits' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['features']).to eq({ 'api_access' => true })
        expect(json['data']['plan']['limits']['max_users']).to eq(50)
      end

      it 'copies price and billing cycle' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: headers, as: :json

        json = json_response
        expect(json['data']['plan']['price_cents']).to eq(4999)
        expect(json['data']['plan']['billing_cycle']).to eq(original_plan.billing_cycle)
      end
    end

    context 'without management permission' do
      it 'denies access' do
        post "/api/v1/plans/#{original_plan.id}/duplicate", headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'returns 404 for non-existent plan' do
      post '/api/v1/plans/00000000-0000-0000-0000-000000000000/duplicate', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      post "/api/v1/plans/#{original_plan.id}/duplicate", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'PUT /api/v1/plans/:id/toggle_status' do
    let(:active_plan) { create(:plan, status: 'active') }
    let(:inactive_plan) { create(:plan, status: 'inactive') }

    context 'with plans.manage permission' do
      it 'toggles active plan to inactive' do
        put "/api/v1/plans/#{active_plan.id}/toggle_status", headers: headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['success']).to be true
        expect(json['data']['plan']['status']).to eq('inactive')
        expect(json['data']['message']).to eq('Plan status updated successfully')
      end

      it 'toggles inactive plan to active' do
        put "/api/v1/plans/#{inactive_plan.id}/toggle_status", headers: headers, as: :json

        expect(response).to have_http_status(:success)
        json = json_response
        expect(json['data']['plan']['status']).to eq('active')
      end

      it 'creates an audit log entry' do
        put "/api/v1/plans/#{active_plan.id}/toggle_status", headers: headers, as: :json

        audit_log = AuditLog.find_by(action: 'toggle_plan_status')
        expect(audit_log).to be_present
        expect(audit_log.metadata['old_status']).to eq('active')
        expect(audit_log.metadata['new_status']).to eq('inactive')
      end
    end

    context 'without management permission' do
      it 'denies access' do
        put "/api/v1/plans/#{active_plan.id}/toggle_status", headers: regular_headers, as: :json

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'returns 404 for non-existent plan' do
      put '/api/v1/plans/00000000-0000-0000-0000-000000000000/toggle_status', headers: headers, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      put "/api/v1/plans/#{active_plan.id}/toggle_status", as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'response format consistency' do
    let(:plan) { create(:plan, status: 'active', is_public: true) }

    it 'returns consistent success response format' do
      get '/api/v1/public/plans', as: :json

      json = json_response
      expect(json).to have_key('success')
      expect(json).to have_key('data')
      expect(json['success']).to be true
    end

    it 'returns consistent error response format for authentication failure' do
      get '/api/v1/plans', as: :json

      json = json_response
      expect(json).to have_key('success')
      expect(json).to have_key('error')
      expect(json['success']).to be false
    end

    it 'returns consistent error response format for permission denied' do
      post '/api/v1/plans', params: { plan: { name: 'Test' } }, headers: regular_headers, as: :json

      json = json_response
      expect(json).to have_key('success')
      expect(json).to have_key('error')
      expect(json['success']).to be false
    end

    it 'returns consistent error response format for validation errors' do
      post '/api/v1/plans', params: { plan: { name: '' } }, headers: headers, as: :json

      json = json_response
      expect(json).to have_key('success')
      expect(json['success']).to be false
    end
  end
end
