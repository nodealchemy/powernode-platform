# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Pages', type: :request do
  describe 'GET /api/v1/pages' do
    before do
      create(:page, :published, title: 'First Page', slug: 'first-page')
      create(:page, :published, title: 'Second Page', slug: 'second-page')
      create(:page, :draft, title: 'Draft Page', slug: 'draft-page')
    end

    context 'without authentication (public endpoint)' do
      it 'returns published pages' do
        get '/api/v1/pages', as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']['pages']).to be_an(Array)
        expect(response_data['data']['pages'].length).to eq(2) # Only published
      end

      it 'excludes draft pages' do
        get '/api/v1/pages', as: :json

        response_data = json_response
        slugs = response_data['data']['pages'].map { |p| p['slug'] }

        expect(slugs).not_to include('draft-page')
      end

      it 'includes page metadata' do
        get '/api/v1/pages', as: :json

        response_data = json_response
        first_page = response_data['data']['pages'].first

        expect(first_page).to have_key('id')
        expect(first_page).to have_key('title')
        expect(first_page).to have_key('slug')
        expect(first_page).to have_key('meta_description')
        expect(first_page).to have_key('published_at')
      end

      it 'includes pagination metadata' do
        get '/api/v1/pages', as: :json

        response_data = json_response

        expect(response_data['data']['meta']).to include(
          'current_page', 'per_page', 'total_count', 'total_pages'
        )
      end

      it 'paginates results' do
        get '/api/v1/pages?page=1&per_page=1', as: :json

        response_data = json_response

        expect(response_data['data']['pages'].length).to eq(1)
        expect(response_data['data']['meta']['per_page']).to eq(1)
      end
    end
  end

  describe 'GET /api/v1/pages/:slug' do
    let(:published_page) { create(:page, :published, title: 'Published Page', slug: 'published-page') }
    let(:draft_page) { create(:page, :draft, title: 'Draft Page', slug: 'draft-page') }

    context 'with published page' do
      it 'returns page details' do
        get "/api/v1/pages/#{published_page.slug}", as: :json

        expect_success_response
        response_data = json_response

        expect(response_data['data']).to include(
          'id' => published_page.id,
          'title' => 'Published Page',
          'slug' => 'published-page'
        )
      end

      it 'includes content and rendered content' do
        get "/api/v1/pages/#{published_page.slug}", as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('content')
        expect(response_data['data']).to have_key('rendered_content')
      end

      it 'includes SEO information' do
        get "/api/v1/pages/#{published_page.slug}", as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('seo')
        expect(response_data['data']['seo']).to include('title', 'description', 'keywords')
      end

      it 'includes reading metrics' do
        get "/api/v1/pages/#{published_page.slug}", as: :json

        response_data = json_response

        expect(response_data['data']).to have_key('word_count')
        expect(response_data['data']).to have_key('estimated_read_time')
      end
    end

    context 'with draft page' do
      before do
        allow_any_instance_of(Page).to receive(:published?).and_return(false)
      end

      it 'returns not found error' do
        get "/api/v1/pages/#{draft_page.slug}", as: :json

        expect_error_response('The requested page is not available', 404)
      end
    end

    context 'when page does not exist' do
      it 'returns not found error' do
        get '/api/v1/pages/nonexistent-page', as: :json

        expect_error_response('The requested page could not be found', 404)
      end
    end
  end
end
