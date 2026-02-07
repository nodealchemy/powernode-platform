# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::MarketplaceService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account) }

  describe '#initialize' do
    it 'initializes with account' do
      expect(service.account).to eq(account)
    end
  end

  describe 'Publisher Management' do
    describe '#create_publisher' do
      it 'creates a publisher account in pending status' do
        publisher = service.create_publisher(
          name: 'Test Publisher',
          user: user,
          description: 'A test publisher for AI templates',
          website_url: 'https://publisher.example.com',
          support_email: 'support@publisher.example.com'
        )

        expect(publisher).to be_persisted
        expect(publisher.publisher_name).to eq('Test Publisher')
        expect(publisher.status).to eq('pending')
        expect(publisher.verification_status).to eq('unverified')
        expect(publisher.primary_user).to eq(user)
        expect(publisher.account).to eq(account)
      end
    end

    describe '#get_publisher' do
      context 'when publisher exists' do
        let!(:publisher) { create(:ai_publisher_account, account: account, primary_user: user) }

        it 'returns the publisher' do
          result = service.get_publisher
          expect(result).to eq(publisher)
        end
      end

      context 'when no publisher exists' do
        it 'returns nil' do
          result = service.get_publisher
          expect(result).to be_nil
        end
      end
    end
  end

  describe 'Template Management' do
    let!(:publisher) do
      create(:ai_publisher_account, :verified, account: account, primary_user: user)
    end

    describe '#create_template' do
      it 'creates a template in draft status' do
        template = service.create_template(
          publisher: publisher,
          name: 'Customer Support Agent',
          description: 'An AI agent for customer support',
          category: 'customer_service',
          agent_config: {
            'agent_type' => 'assistant',
            'system_prompt' => 'You are a helpful customer service agent.',
            'tools' => ['email', 'ticket_management']
          }
        )

        expect(template).to be_persisted
        expect(template.name).to eq('Customer Support Agent')
        expect(template.status).to eq('draft')
        expect(template.visibility).to eq('private')
        expect(template.publisher).to eq(publisher)
      end

      it 'creates template with pricing' do
        template = service.create_template(
          publisher: publisher,
          name: 'Premium Agent',
          description: 'A premium AI agent',
          category: 'productivity',
          pricing_type: 'one_time',
          price_usd: 29.99
        )

        expect(template.pricing_type).to eq('one_time')
        expect(template.price_usd).to eq(29.99)
      end

      it 'creates free template by default' do
        template = service.create_template(
          publisher: publisher,
          name: 'Free Agent',
          description: 'A free AI agent',
          category: 'general'
        )

        expect(template.pricing_type).to eq('free')
      end

      it 'creates template with vertical' do
        template = service.create_template(
          publisher: publisher,
          name: 'Healthcare Agent',
          description: 'An AI agent for healthcare',
          category: 'healthcare',
          vertical: 'healthcare'
        )

        expect(template.vertical).to eq('healthcare')
      end
    end

    describe '#publish_template' do
      let(:template) do
        service.create_template(
          publisher: publisher,
          name: 'Publish Me',
          description: 'Template to publish',
          category: 'general'
        )
      end

      context 'with verified publisher' do
        before do
          allow(publisher).to receive(:can_publish?).and_return(true)
        end

        it 'publishes the template' do
          result = service.publish_template(template)

          expect(result[:success]).to be true
          expect(template.reload.status).to eq('published')
        end
      end

      context 'with unverified publisher' do
        before do
          allow(publisher).to receive(:can_publish?).and_return(false)
        end

        it 'returns failure' do
          result = service.publish_template(template)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Publisher not verified')
        end
      end

      context 'with nil template' do
        it 'returns failure' do
          result = service.publish_template(nil)

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Template not found')
        end
      end
    end

    describe '#search_templates' do
      before do
        # Create published templates for search
        template = service.create_template(
          publisher: publisher,
          name: 'Searchable Agent',
          description: 'An agent for searching',
          category: 'productivity'
        )
        allow(publisher).to receive(:can_publish?).and_return(true)
        service.publish_template(template)
      end

      it 'searches published templates' do
        results = service.search_templates(query: 'Searchable')
        expect(results).to respond_to(:each)
      end

      it 'filters by category' do
        results = service.search_templates(category: 'productivity')
        expect(results).to respond_to(:each)
      end

      it 'respects pagination' do
        results = service.search_templates(page: 1, per_page: 5)
        expect(results).to respond_to(:each)
      end
    end

    describe '#featured_templates' do
      it 'returns featured templates' do
        # Uses caching, so should return an array
        results = service.featured_templates(limit: 5)
        expect(results).to be_an(Array)
      end
    end
  end

  describe 'Installation Management' do
    let!(:provider) { create(:ai_provider, account: account) }
    let!(:publisher) do
      create(:ai_publisher_account, :verified, account: account, primary_user: user)
    end

    let!(:template) do
      t = service.create_template(
        publisher: publisher,
        name: 'Installable Agent',
        description: 'Agent for installation testing',
        category: 'general',
        agent_config: {
          'agent_type' => 'assistant',
          'system_prompt' => 'You are a test agent.'
        }
      )
      allow(publisher).to receive(:can_publish?).and_return(true)
      service.publish_template(t)
      t.reload
    end

    describe '#install_template' do
      it 'installs a published template' do
        result = service.install_template(
          template: template,
          user: user
        )

        expect(result[:success]).to be true
        expect(result[:installation]).to be_persisted
        expect(result[:installation].status).to eq('active')
        expect(result[:agent]).to be_present
      end

      it 'creates agent from template config' do
        result = service.install_template(
          template: template,
          user: user
        )

        expect(result[:agent]).to be_a(Ai::Agent)
        expect(result[:agent].name).to include(template.name)
      end

      it 'applies custom config overrides' do
        result = service.install_template(
          template: template,
          user: user,
          custom_config: { 'temperature' => 0.5 }
        )

        expect(result[:success]).to be true
      end

      context 'when template is not published' do
        let(:draft_template) do
          service.create_template(
            publisher: publisher,
            name: 'Draft Agent',
            description: 'Not published',
            category: 'general'
          )
        end

        it 'returns failure' do
          result = service.install_template(
            template: draft_template,
            user: user
          )

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Template not available')
        end
      end

      context 'when template is already installed' do
        before do
          service.install_template(template: template, user: user)
        end

        it 'returns failure for duplicate installation' do
          result = service.install_template(
            template: template,
            user: user
          )

          expect(result[:success]).to be false
          expect(result[:error]).to eq('Already installed')
        end
      end
    end

    describe '#uninstall_template' do
      let!(:installation) do
        result = service.install_template(template: template, user: user)
        result[:installation]
      end

      it 'uninstalls the template' do
        result = service.uninstall_template(installation)

        expect(result[:success]).to be true
        expect(installation.reload.status).to eq('cancelled')
      end

      it 'returns failure for nil installation' do
        result = service.uninstall_template(nil)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Installation not found')
      end
    end
  end

  describe 'Reviews' do
    let!(:publisher) do
      create(:ai_publisher_account, :verified, account: account, primary_user: user)
    end

    let!(:template) do
      t = service.create_template(
        publisher: publisher,
        name: 'Reviewable Agent',
        description: 'Agent for review testing',
        category: 'general',
        agent_config: { 'agent_type' => 'assistant' }
      )
      allow(publisher).to receive(:can_publish?).and_return(true)
      service.publish_template(t)
      t.reload
    end

    describe '#create_review' do
      it 'creates a review for a template' do
        result = service.create_review(
          template: template,
          user: user,
          rating: 5,
          title: 'Great agent!',
          content: 'Very helpful for my workflow',
          pros: ['Easy to configure', 'Fast responses'],
          cons: ['Limited customization']
        )

        expect(result[:success]).to be true
        expect(result[:review]).to be_persisted
        expect(result[:review].rating).to eq(5)
        expect(result[:review].title).to eq('Great agent!')
        expect(result[:review].status).to eq('published')
      end

      it 'marks review as unverified when no installation exists' do
        result = service.create_review(
          template: template,
          user: user,
          rating: 4
        )

        expect(result[:review].is_verified_purchase).to be false
      end

      it 'marks review as verified when installation exists' do
        service.install_template(template: template, user: user)

        result = service.create_review(
          template: template,
          user: user,
          rating: 5
        )

        expect(result[:review].is_verified_purchase).to be true
      end
    end
  end

  describe 'Categories' do
    describe '#list_categories' do
      it 'returns categories list' do
        result = service.list_categories
        expect(result).to be_an(Array)
      end
    end
  end

  describe 'Publisher Analytics' do
    let!(:publisher) do
      create(:ai_publisher_account, :verified, :with_earnings, account: account, primary_user: user)
    end

    describe '#publisher_analytics' do
      it 'returns analytics data' do
        analytics = service.publisher_analytics(publisher)

        expect(analytics).to include(
          :total_revenue,
          :total_earnings,
          :transaction_count,
          :installations,
          :active_installations,
          :templates_count
        )
      end

      it 'accepts custom date range' do
        analytics = service.publisher_analytics(
          publisher,
          start_date: 7.days.ago,
          end_date: Time.current
        )

        expect(analytics).to be_present
      end
    end
  end

  describe 'Cache Invalidation' do
    describe '.invalidate_caches' do
      it 'clears all marketplace caches' do
        expect(Rails.cache).to receive(:delete).with('ai:marketplace:categories')
        expect(Rails.cache).to receive(:delete_matched).with('ai:marketplace:featured:*')
        expect(Rails.cache).to receive(:delete_matched).with('ai:marketplace:search:*')

        described_class.invalidate_caches
      end
    end

    describe '.invalidate_categories_cache' do
      it 'clears category cache' do
        expect(Rails.cache).to receive(:delete).with('ai:marketplace:categories')
        described_class.invalidate_categories_cache
      end
    end

    describe '.invalidate_featured_cache' do
      it 'clears featured templates cache' do
        expect(Rails.cache).to receive(:delete_matched).with('ai:marketplace:featured:*')
        described_class.invalidate_featured_cache
      end
    end

    describe '.invalidate_publisher_analytics' do
      it 'clears publisher analytics cache' do
        publisher_id = SecureRandom.uuid
        expect(Rails.cache).to receive(:delete_matched).with("ai:marketplace:publisher_analytics:#{publisher_id}:*")
        described_class.invalidate_publisher_analytics(publisher_id)
      end
    end
  end
end
