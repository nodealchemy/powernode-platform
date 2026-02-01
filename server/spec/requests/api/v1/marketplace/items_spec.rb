# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Marketplace::Items', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:headers) { auth_headers_for(user) }

  describe 'GET /api/v1/marketplace' do
    context 'without authentication (public access)' do
      it 'returns marketplace items' do
        get '/api/v1/marketplace', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data).to be_an(Array)
        expect(json_response['meta']).to include(
          'current_page',
          'per_page',
          'total_count',
          'total_pages'
        )
      end

      it 'filters by types parameter' do
        get '/api/v1/marketplace?types=workflow_template,pipeline_template', as: :json

        expect_success_response
        expect(json_response['meta']['filters']['types']).to eq(['workflow_template', 'pipeline_template'])
      end

      it 'filters by search parameter' do
        get '/api/v1/marketplace?search=test', as: :json

        expect_success_response
        expect(json_response['meta']['filters']['search']).to eq('test')
      end

      it 'filters by category parameter' do
        get '/api/v1/marketplace?category=productivity', as: :json

        expect_success_response
        expect(json_response['meta']['filters']['category']).to eq('productivity')
      end

      it 'paginates results' do
        get '/api/v1/marketplace?page=2&per_page=5', as: :json

        expect_success_response
        meta = json_response['meta']
        expect(meta['current_page']).to eq(2)
        expect(meta['per_page']).to eq(5)
      end
    end

    context 'with authentication' do
      it 'returns marketplace items with auth context' do
        get '/api/v1/marketplace', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/marketplace/featured' do
    context 'without authentication' do
      it 'returns featured items' do
        get '/api/v1/marketplace/featured', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to be <= 12
      end
    end
  end

  describe 'GET /api/v1/marketplace/categories' do
    context 'without authentication' do
      it 'returns available categories' do
        get '/api/v1/marketplace/categories', as: :json

        expect_success_response
        data = json_response_data
        expect(data).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/marketplace/:type/:id' do
    let(:workflow_template) { create(:ai_workflow_template, :published, is_marketplace_published: true, marketplace_status: 'approved') }

    context 'without authentication' do
      it 'returns item details for valid type' do
        get "/api/v1/marketplace/workflow_template/#{workflow_template.id}", as: :json

        expect_success_response
        data = json_response_data
        expect(data['id']).to eq(workflow_template.id)
        expect(data['type']).to eq('workflow_template')
      end

      it 'returns error for invalid type' do
        get '/api/v1/marketplace/invalid_type/123', as: :json

        expect_error_response('Invalid item type: invalid_type', 400)
      end

      it 'returns error for non-existent item' do
        get "/api/v1/marketplace/workflow_template/#{SecureRandom.uuid}", as: :json

        expect_error_response('Workflow Template not found', 404)
      end
    end

    context 'with authentication' do
      it 'includes subscription info when authenticated' do
        get "/api/v1/marketplace/workflow_template/#{workflow_template.id}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('subscription')
      end
    end
  end

  describe 'POST /api/v1/marketplace/:type/:id/subscribe' do
    let(:workflow_template) { create(:ai_workflow_template, :published) }

    context 'with authentication' do
      it 'creates a subscription to the item' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscribe)
          .and_return({
            success: true,
            data: double(
              id: SecureRandom.uuid,
              subscribable_id: workflow_template.id,
              subscription_type: 'workflow_template',
              item_name: workflow_template.name,
              status: 'active',
              tier: 'standard',
              subscribed_at: Time.current
            )
          })

        post "/api/v1/marketplace/workflow_template/#{workflow_template.id}/subscribe",
             params: { tier: 'standard' },
             headers: headers,
             as: :json

        expect(response).to have_http_status(:created)
        data = json_response_data
        expect(data['item_id']).to eq(workflow_template.id)
        expect(data['item_type']).to eq('workflow_template')
        expect(data['status']).to eq('active')
      end

      it 'returns error when subscription fails' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscribe)
          .and_return({
            success: false,
            errors: ['Subscription failed']
          })

        post "/api/v1/marketplace/workflow_template/#{workflow_template.id}/subscribe",
             headers: headers,
             as: :json

        expect(response).to have_http_status(422)
        expect(json_response['success']).to be false
        expect(json_response['error']).to include('Subscription failed')
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/marketplace/workflow_template/#{workflow_template.id}/subscribe", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/marketplace/:type/:id/unsubscribe' do
    let(:workflow_template) { create(:ai_workflow_template, :published) }

    context 'with authentication' do
      it 'cancels the subscription' do
        subscription = double(id: SecureRandom.uuid)
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscription_for)
          .and_return(subscription)
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:unsubscribe)
          .and_return({ success: true })

        delete "/api/v1/marketplace/workflow_template/#{workflow_template.id}/unsubscribe",
               params: { reason: 'No longer needed' },
               headers: headers,
               as: :json

        expect_success_response
        expect(json_response_data['message']).to eq('Subscription cancelled successfully')
      end

      it 'returns error when no subscription found' do
        allow_any_instance_of(Marketplace::SubscriptionOrchestrator)
          .to receive(:subscription_for)
          .and_return(nil)

        delete "/api/v1/marketplace/workflow_template/#{workflow_template.id}/unsubscribe",
               headers: headers,
               as: :json

        expect_error_response('No active subscription found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        delete "/api/v1/marketplace/workflow_template/#{workflow_template.id}/unsubscribe", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
