# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::AppPlans', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['apps.manage']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:app) { create(:app, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/apps/:app_id/plans' do
    let!(:plans) do
      [
        create(:app_plan, app: app, name: 'Basic', is_active: true, price_cents: 1000),
        create(:app_plan, app: app, name: 'Pro', is_active: true, price_cents: 5000),
        create(:app_plan, app: app, name: 'Enterprise', is_active: false, price_cents: 10000)
      ]
    end

    context 'with authorized access' do
      it 'returns all plans for the app' do
        get "/api/v1/apps/#{app.id}/plans", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(3)
      end

      it 'filters by active status' do
        get "/api/v1/apps/#{app.id}/plans?active=true", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(2)
        expect(data.all? { |p| p['is_active'] }).to be true
      end

      it 'searches by name' do
        get "/api/v1/apps/#{app.id}/plans?search=Basic", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data.length).to eq(1)
        expect(data.first['name']).to eq('Basic')
      end

      it 'sorts by price' do
        get "/api/v1/apps/#{app.id}/plans?sort=price", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        prices = data.map { |p| p['price_cents'] }
        expect(prices).to eq(prices.sort)
      end
    end

    context 'without authorized access' do
      it 'returns forbidden error' do
        get "/api/v1/apps/#{app.id}/plans", headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Unauthorized to access this app', 403)
      end
    end

    context 'with non-existent app' do
      it 'returns not found error' do
        get "/api/v1/apps/non-existent-id/plans", headers: headers, as: :json

        expect_error_response('App not found', 404)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/plans/:id' do
    let(:plan) { create(:app_plan, app: app) }

    context 'with authorized access' do
      it 'returns the plan with detailed information' do
        get "/api/v1/apps/#{app.id}/plans/#{plan.id}", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['id']).to eq(plan.id)
        expect(data).to include(
          'name',
          'slug',
          'description',
          'price_cents',
          'billing_interval',
          'features',
          'permissions',
          'limits'
        )
      end
    end

    context 'with non-existent plan' do
      it 'returns not found error' do
        get "/api/v1/apps/#{app.id}/plans/non-existent-id", headers: headers, as: :json

        expect_error_response('App plan not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/plans' do
    let(:valid_params) do
      {
        app_plan: {
          name: 'Starter',
          slug: 'starter',
          description: 'Starter plan',
          price_cents: 2000,
          billing_interval: 'monthly',
          is_active: true
        }
      }
    end

    context 'with authorized access' do
      it 'creates a new plan' do
        expect do
          post "/api/v1/apps/#{app.id}/plans", params: valid_params, headers: headers, as: :json
        end.to change(app.app_plans, :count).by(1)

        expect(response).to have_http_status(:created)
        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Starter')
        expect(json_response['message']).to eq('App plan created successfully')
      end

      it 'sets sort_order automatically' do
        post "/api/v1/apps/#{app.id}/plans", params: valid_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['sort_order']).to be_present
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_plan: { name: '' } }
        post "/api/v1/apps/#{app.id}/plans", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'without authorized access' do
      it 'returns forbidden error' do
        post "/api/v1/apps/#{app.id}/plans", params: valid_params, headers: auth_headers_for(regular_user), as: :json

        expect_error_response('Unauthorized to access this app', 403)
      end
    end
  end

  describe 'PUT /api/v1/apps/:app_id/plans/:id' do
    let(:plan) { create(:app_plan, app: app, name: 'Old Name', price_cents: 1000) }
    let(:update_params) do
      {
        app_plan: {
          name: 'Updated Name',
          price_cents: 2000
        }
      }
    end

    context 'with authorized access' do
      it 'updates the plan' do
        put "/api/v1/apps/#{app.id}/plans/#{plan.id}", params: update_params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['name']).to eq('Updated Name')
        expect(data['price_cents']).to eq(2000)
        expect(json_response['message']).to eq('App plan updated successfully')
      end

      it 'returns validation errors for invalid params' do
        invalid_params = { app_plan: { name: '' } }
        put "/api/v1/apps/#{app.id}/plans/#{plan.id}", params: invalid_params, headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/apps/:app_id/plans/:id' do
    let!(:plan) { create(:app_plan, app: app) }

    context 'with authorized access' do
      it 'deletes the plan' do
        expect do
          delete "/api/v1/apps/#{app.id}/plans/#{plan.id}", headers: headers, as: :json
        end.to change(app.app_plans, :count).by(-1)

        expect_success_response
        expect(json_response['message']).to eq('App plan deleted successfully')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/plans/:id/activate' do
    let(:plan) { create(:app_plan, app: app, is_active: false) }

    context 'with authorized access' do
      it 'activates the plan' do
        post "/api/v1/apps/#{app.id}/plans/#{plan.id}/activate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be true
        expect(json_response['message']).to eq('App plan activated successfully')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/plans/:id/deactivate' do
    let(:plan) { create(:app_plan, app: app, is_active: true) }

    context 'with authorized access' do
      it 'deactivates the plan' do
        post "/api/v1/apps/#{app.id}/plans/#{plan.id}/deactivate", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['is_active']).to be false
        expect(json_response['message']).to eq('App plan deactivated successfully')
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/plans/reorder' do
    let!(:plan1) { create(:app_plan, app: app, sort_order: 1) }
    let!(:plan2) { create(:app_plan, app: app, sort_order: 2) }
    let!(:plan3) { create(:app_plan, app: app, sort_order: 3) }

    context 'with authorized access' do
      it 'reorders the plans' do
        params = { plan_ids: [plan3.id, plan1.id, plan2.id] }
        post "/api/v1/apps/#{app.id}/plans/reorder", params: params, headers: headers, as: :json

        expect_success_response
        expect(json_response['message']).to eq('App plans reordered successfully')

        plan1.reload
        plan2.reload
        plan3.reload
        expect(plan3.sort_order).to eq(1)
        expect(plan1.sort_order).to eq(2)
        expect(plan2.sort_order).to eq(3)
      end

      it 'returns error when plan_ids is missing' do
        post "/api/v1/apps/#{app.id}/plans/reorder", headers: headers, as: :json

        expect_error_response('Plan IDs required', 400)
      end

      it 'returns error when plan is not found' do
        params = { plan_ids: ['non-existent-id'] }
        post "/api/v1/apps/#{app.id}/plans/reorder", params: params, headers: headers, as: :json

        expect_error_response('One or more plans not found', 404)
      end
    end
  end

  describe 'POST /api/v1/apps/:app_id/plans/compare' do
    let!(:plan1) { create(:app_plan, app: app, name: 'Basic') }
    let!(:plan2) { create(:app_plan, app: app, name: 'Pro') }

    context 'with authorized access' do
      it 'returns comparison data for multiple plans' do
        params = { plan_ids: [plan1.id, plan2.id] }
        post "/api/v1/apps/#{app.id}/plans/compare", params: params, headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data['plans']).to be_an(Array)
        expect(data['plans'].length).to eq(2)
        expect(data['plans'].first).to include(
          'id',
          'name',
          'price_cents',
          'billing_interval',
          'features',
          'permissions',
          'limits'
        )
      end

      it 'returns error when plan_ids is missing' do
        post "/api/v1/apps/#{app.id}/plans/compare", headers: headers, as: :json

        expect_error_response('Plan IDs required for comparison', 400)
      end

      it 'returns error when no plans found' do
        params = { plan_ids: ['non-existent-id'] }
        post "/api/v1/apps/#{app.id}/plans/compare", params: params, headers: headers, as: :json

        expect_error_response('Plans not found', 404)
      end
    end
  end

  describe 'GET /api/v1/apps/:app_id/plans/analytics' do
    let!(:plan) { create(:app_plan, app: app) }

    context 'with authorized access' do
      it 'returns analytics data for all plans' do
        get "/api/v1/apps/#{app.id}/plans/analytics", headers: headers, as: :json

        expect_success_response
        data = json_response['data']
        expect(data).to include(
          'total_plans',
          'active_plans',
          'inactive_plans'
        )
      end
    end
  end
end
