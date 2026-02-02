# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Kb::Tags', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'kb.update' ]) }

  let(:headers) { auth_headers_for(user) }

  let!(:category) do
    KnowledgeBase::Category.create!(
      name: 'Test Category',
      slug: 'test-category',
      is_public: true
    )
  end

  let!(:tag1) do
    KnowledgeBase::Tag.create!(
      name: 'Ruby',
      slug: 'ruby',
      description: 'Ruby programming language',
      color: '#CC342D'
    )
  end

  let!(:tag2) do
    KnowledgeBase::Tag.create!(
      name: 'Rails',
      slug: 'rails',
      description: 'Ruby on Rails framework',
      color: '#D30001'
    )
  end

  let!(:tag3) do
    KnowledgeBase::Tag.create!(
      name: 'Python',
      slug: 'python',
      description: 'Python programming language',
      color: '#F7DF1E'
    )
  end

  let!(:published_article) do
    article = KnowledgeBase::Article.create!(
      title: 'Ruby Article',
      slug: 'ruby-article',
      content: 'Content about Ruby',
      excerpt: 'Excerpt',
      status: 'published',
      is_public: true,
      category: category,
      author: user,
      published_at: Time.current
    )
    article.tags << tag1
    article.tags << tag2
    article
  end

  describe 'GET /api/v1/kb/tags' do
    context 'public view (no auth)' do
      it 'returns list of popular tags' do
        get '/api/v1/kb/tags', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data).to be_an(Array)
        expect(data.length).to be <= 50
        expect(data.first).to include('id', 'name', 'slug', 'description', 'color', 'usage_count')
      end

      it 'includes tag metadata' do
        get '/api/v1/kb/tags', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        tag = data.first
        expect(tag).to have_key('color')
        expect(tag).to have_key('usage_count')
      end
    end
  end

  describe 'GET /api/v1/kb/tags/:id/articles' do
    context 'public view (no auth)' do
      it 'returns tag with associated published articles' do
        get "/api/v1/kb/tags/#{tag1.id}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['tag']).to include(
          'id' => tag1.id,
          'name' => 'Ruby',
          'slug' => 'ruby'
        )
        expect(data['articles']).to be_an(Array)
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['title']).to eq('Ruby Article')
        expect(data).to have_key('pagination')
      end

      it 'returns tag by slug' do
        get "/api/v1/kb/tags/#{tag1.slug}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['tag']['slug']).to eq(tag1.slug)
      end

      it 'supports pagination' do
        get "/api/v1/kb/tags/#{tag1.id}/articles?page=1&per_page=10", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end

      it 'returns only published public articles' do
        draft_article = KnowledgeBase::Article.create!(
          title: 'Draft Ruby Article',
          slug: 'draft-ruby-article',
          content: 'Draft content',
          excerpt: 'Draft excerpt',
          status: 'draft',
          is_public: false,
          category: category,
          author: user
        )
        draft_article.tags << tag1

        get "/api/v1/kb/tags/#{tag1.id}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['title']).to eq('Ruby Article')
      end

      it 'returns not found for non-existent tag' do
        get '/api/v1/kb/tags/00000000-0000-0000-0000-000000000000/articles', as: :json

        expect_error_response('Tag not found', 404)
      end

      it 'returns empty articles array for tag with no published articles' do
        get "/api/v1/kb/tags/#{tag3.id}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['tag']['name']).to eq('Python')
        expect(data['articles']).to be_an(Array)
        expect(data['articles'].length).to eq(0)
      end
    end

    context 'with multiple articles' do
      before do
        article2 = KnowledgeBase::Article.create!(
          title: 'Another Ruby Article',
          slug: 'another-ruby-article',
          content: 'More Ruby content',
          excerpt: 'Excerpt',
          status: 'published',
          is_public: true,
          category: category,
          author: user,
          published_at: Time.current
        )
        article2.tags << tag1

        article3 = KnowledgeBase::Article.create!(
          title: 'Third Ruby Article',
          slug: 'third-ruby-article',
          content: 'Even more Ruby',
          excerpt: 'Excerpt',
          status: 'published',
          is_public: true,
          category: category,
          author: user,
          published_at: Time.current
        )
        article3.tags << tag1
      end

      it 'returns all published articles for tag' do
        get "/api/v1/kb/tags/#{tag1.id}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles'].length).to eq(3)
      end

      it 'includes article metadata' do
        get "/api/v1/kb/tags/#{tag1.id}/articles", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        article = data['articles'].first
        expect(article).to include(
          'id',
          'title',
          'slug',
          'excerpt',
          'author_name',
          'published_at',
          'reading_time',
          'views_count'
        )
        expect(article).to have_key('category')
        expect(article['category']).to include('id', 'name')
      end
    end
  end
end
