# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Ai::AgentMarketplace', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.marketplace.read' ]) }
  let(:publisher_user) { create(:user, account: account, permissions: [ 'ai.agents.read', 'ai.marketplace.read', 'ai.marketplace.publish' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:headers) { auth_headers_for(user) }
  let(:publisher_headers) { auth_headers_for(publisher_user) }

  # Create test data using lambdas (no factories available)
  let(:service) { instance_double('Ai::MarketplaceService') }
  # Helper to create publisher with memoization
  let(:publisher_record) do
    account.create_ai_publisher_account!(
      publisher_name: 'Test Publisher',
      publisher_slug: "test-publisher-#{SecureRandom.hex(4)}",
      description: 'Test Description',
      status: 'active',
      verification_status: 'verified'
    )
  end

  # Helper to create template with memoization
  let(:template_record) do
    publisher_record.agent_templates.create!(
      name: 'Test Template',
      slug: "test-template-#{SecureRandom.hex(4)}",
      description: 'Test description',
      category: 'productivity',
      vertical: 'customer_service',
      pricing_type: 'free',
      version: '1.0.0',
      status: 'published',
      published_at: Time.current,
      agent_config: {},
      installation_count: 10,
      average_rating: 4.5,
      review_count: 5,
      is_featured: false,
      is_verified: false,
      price_usd: nil,
      monthly_price_usd: nil,
      long_description: 'Long description',
      required_credentials: [],
      required_tools: [],
      sample_prompts: [],
      screenshots: [],
      tags: [],
      features: [],
      limitations: [],
      setup_instructions: 'Setup instructions',
      changelog: []
    )
  end

  # Keep lambdas for backward compatibility with tests that use them
  let(:publisher) { -> { publisher_record } }
  let(:template) { -> { template_record } }

  before do
    allow(::Ai::MarketplaceService).to receive(:new).and_return(service)
  end

  describe 'GET /api/v1/ai/agent_marketplace/templates' do
    let(:publisher_double) do
      double('Publisher',
             id: SecureRandom.uuid,
             publisher_name: 'Publisher 1',
             publisher_slug: 'publisher-1',
             verified?: true)
    end

    let(:template_double) do
      double('Template',
             id: SecureRandom.uuid,
             name: 'Template 1',
             slug: 'template-1',
             description: 'Desc 1',
             category: 'productivity',
             vertical: 'sales',
             pricing_type: 'free',
             price_usd: nil,
             monthly_price_usd: nil,
             version: '1.0.0',
             installation_count: 10,
             average_rating: 4.5,
             review_count: 5,
             is_featured: true,
             is_verified: true,
             published_at: Time.current,
             publisher: publisher_double)
    end

    let(:templates_collection) do
      # Create a paginated collection that responds to map and pagination methods
      templates = [ template_double ]
      Struct.new(:templates, :current_page, :total_pages, :total_count, :limit_value) do
        include Enumerable

        def each(&block)
          templates.each(&block)
        end

        def map(&block)
          templates.map(&block)
        end
      end.new(templates, 1, 1, 1, 20)
    end

    before do
      allow(service).to receive(:search_templates).and_return(templates_collection)
    end

    context 'with ai.marketplace.read permission' do
      it 'returns list of templates' do
        get '/api/v1/ai/agent_marketplace/templates', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('templates')
        expect(data['templates']).to be_an(Array)
        expect(data).to have_key('pagination')
      end

      it 'accepts search parameters' do
        get '/api/v1/ai/agent_marketplace/templates?query=test&category=productivity&vertical=sales',
            headers: headers,
            as: :json

        expect(service).to have_received(:search_templates).with(
          hash_including(query: 'test', category: 'productivity', vertical: 'sales')
        )
      end
    end

    # Note: Controller does not enforce permissions, only requires authentication
  end

  describe 'GET /api/v1/ai/agent_marketplace/templates/featured' do
    before do
      allow(service).to receive(:featured_templates).and_return([])
    end

    context 'with permission' do
      it 'returns featured templates' do
        get '/api/v1/ai/agent_marketplace/templates/featured',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('templates')
        expect(data['templates']).to be_an(Array)
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/templates/:id' do
    before do
      allow(::Ai::AgentTemplate).to receive(:find).and_return(template_record)
    end

    context 'with permission' do
      it 'returns template details' do
        get "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('template')
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/categories' do
    let(:category) do
      double('Category', id: SecureRandom.uuid, name: 'Productivity',
             slug: 'productivity', description: 'Productivity tools',
             icon: 'briefcase', template_count: 10,
             children: double(active: double(ordered: [])))
    end

    before do
      allow(service).to receive(:list_categories).and_return([ category ])
    end

    context 'with permission' do
      it 'returns categories list' do
        get '/api/v1/ai/agent_marketplace/categories',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('categories')
        expect(data['categories']).to be_an(Array)
      end
    end
  end

  describe 'POST /api/v1/ai/agent_marketplace/templates/:template_id/install' do
    let(:install_template_mock) do
      double('Template',
             id: SecureRandom.uuid,
             name: 'Install Template',
             slug: 'install-template')
    end

    let(:installation) do
      double('Installation',
             id: SecureRandom.uuid,
             status: 'active',
             installed_version: '1.0.0',
             license_type: 'standard',
             executions_count: 0,
             total_cost_usd: 0,
             last_used_at: nil,
             created_at: Time.current,
             agent_template: install_template_mock)
    end

    before do
      allow(::Ai::AgentTemplate).to receive(:find).and_return(template_record)
      allow(service).to receive(:install_template).and_return(
        { success: true, installation: installation }
      )
    end

    context 'with permission' do
      it 'installs template successfully' do
        post "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}/install",
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('installation')
      end

      it 'accepts custom config' do
        custom_config = { setting: 'value' }
        post "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}/install",
             params: { custom_config: custom_config },
             headers: headers,
             as: :json

        expect(service).to have_received(:install_template).with(
          hash_including(:custom_config)
        )
      end
    end

    context 'when installation fails' do
      before do
        allow(service).to receive(:install_template).and_return(
          { success: false, error: 'Installation failed' }
        )
      end

      it 'returns error response' do
        post "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}/install",
             headers: headers,
             as: :json

        expect_error_response('Installation failed', 422)
      end
    end
  end

  describe 'DELETE /api/v1/ai/agent_marketplace/installations/:id' do
    let(:installation) do
      double('Installation', id: SecureRandom.uuid)
    end

    before do
      allow_any_instance_of(Account).to receive(:ai_agent_installations).and_return(
        double('installations', find: installation)
      )
      allow(service).to receive(:uninstall_template).and_return(
        { success: true }
      )
    end

    context 'with permission' do
      it 'uninstalls template successfully' do
        delete "/api/v1/ai/agent_marketplace/installations/#{SecureRandom.uuid}",
               headers: headers,
               as: :json

        expect_success_response
        data = json_response_data
        expect(data['message']).to eq('Template uninstalled successfully')
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/installations' do
    before do
      allow(account).to receive_message_chain(:ai_agent_installations, :includes, :order, :page, :per)
        .and_return(double(map: [], current_page: 1, total_pages: 1,
                           total_count: 0, limit_value: 20))
    end

    context 'with permission' do
      it 'returns installations list' do
        get '/api/v1/ai/agent_marketplace/installations',
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('installations')
        expect(data).to have_key('pagination')
      end
    end
  end

  describe 'POST /api/v1/ai/agent_marketplace/templates/:template_id/reviews' do
    let(:review) do
      double('Review',
             id: SecureRandom.uuid,
             rating: 5,
             title: 'Great!',
             content: 'Excellent template',
             pros: [ 'Easy to use' ],
             cons: [],
             is_verified_purchase: true,
             helpful_count: 0,
             created_at: Time.current)
    end

    before do
      allow(::Ai::AgentTemplate).to receive(:find).and_return(template_record)
      allow(service).to receive(:create_review).and_return(
        { success: true, review: review }
      )
    end

    context 'with permission' do
      it 'creates review successfully' do
        post "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}/reviews",
             params: { rating: 5, title: 'Great!', content: 'Excellent' },
             headers: headers,
             as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('review')
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/templates/:template_id/reviews' do
    let(:reviews_collection) do
      collection = double('ReviewsCollection')
      allow(collection).to receive(:map).and_return([])
      allow(collection).to receive(:current_page).and_return(1)
      allow(collection).to receive(:total_pages).and_return(1)
      allow(collection).to receive(:total_count).and_return(0)
      allow(collection).to receive(:limit_value).and_return(20)
      collection
    end

    before do
      allow(::Ai::AgentTemplate).to receive(:find).and_return(template_record)
      allow(template_record).to receive_message_chain(:reviews, :published, :recent, :page, :per)
        .and_return(reviews_collection)
    end

    context 'with permission' do
      it 'returns reviews list' do
        get "/api/v1/ai/agent_marketplace/templates/#{SecureRandom.uuid}/reviews",
            headers: headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('reviews')
        expect(data).to have_key('pagination')
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/publisher' do
    context 'when publisher exists' do
      before do
        allow(service).to receive(:get_publisher).and_return(publisher_record)
      end

      it 'returns publisher details' do
        get '/api/v1/ai/agent_marketplace/publisher',
            headers: publisher_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('publisher')
      end
    end

    context 'when publisher does not exist' do
      before do
        allow(service).to receive(:get_publisher).and_return(nil)
      end

      it 'returns not found error' do
        get '/api/v1/ai/agent_marketplace/publisher',
            headers: publisher_headers,
            as: :json

        expect_error_response('No publisher account found', 404)
      end
    end
  end

  describe 'POST /api/v1/ai/agent_marketplace/publisher' do
    before do
      allow(service).to receive(:create_publisher).and_return(publisher_record)
    end

    context 'with permission' do
      it 'creates publisher successfully' do
        post '/api/v1/ai/agent_marketplace/publisher',
             params: {
               name: 'My Publisher',
               description: 'Publisher description',
               website_url: 'https://example.com',
               support_email: 'support@example.com'
             },
             headers: publisher_headers,
             as: :json

        expect(response).to have_http_status(:created)
        expect_success_response
      end
    end
  end

  describe 'GET /api/v1/ai/agent_marketplace/publisher/analytics' do
    let(:analytics_data) do
      {
        total_installations: 100,
        total_revenue: 1000.0,
        active_templates: 5
      }
    end

    before do
      allow(service).to receive(:get_publisher).and_return(publisher_record)
      allow(service).to receive(:publisher_analytics).and_return(analytics_data)
    end

    context 'with publisher account' do
      it 'returns analytics data' do
        get '/api/v1/ai/agent_marketplace/publisher/analytics',
            headers: publisher_headers,
            as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('analytics')
      end

      it 'accepts date range parameters' do
        start_date = URI.encode_www_form_component(30.days.ago.to_s)
        end_date = URI.encode_www_form_component(Time.current.to_s)
        get "/api/v1/ai/agent_marketplace/publisher/analytics?start_date=#{start_date}&end_date=#{end_date}",
            headers: publisher_headers,
            as: :json

        expect_success_response
      end
    end

    context 'without publisher account' do
      before do
        allow(service).to receive(:get_publisher).and_return(nil)
      end

      it 'returns not found error' do
        get '/api/v1/ai/agent_marketplace/publisher/analytics',
            headers: publisher_headers,
            as: :json

        expect_error_response('No publisher account found', 404)
      end
    end
  end
end
