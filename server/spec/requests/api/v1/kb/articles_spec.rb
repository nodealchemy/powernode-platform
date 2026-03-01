# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Kb::Articles', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'kb.update', 'kb.manage' ]) }
  let(:editor_user) { create(:user, account: account, permissions: [ 'kb.update' ]) }
  let(:publisher_user) { create(:user, account: account, permissions: [ 'kb.publish' ]) }
  let(:read_only_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:editor_headers) { auth_headers_for(editor_user) }
  let(:publisher_headers) { auth_headers_for(publisher_user) }
  let(:read_only_headers) { auth_headers_for(read_only_user) }

  let!(:category) do
    KnowledgeBase::Category.create!(
      name: 'Test Category',
      slug: 'test-category',
      is_public: true
    )
  end

  let!(:published_article) do
    KnowledgeBase::Article.create!(
      title: 'Published Article',
      slug: 'published-article',
      content: 'This is published content',
      excerpt: 'Published excerpt',
      status: 'published',
      is_public: true,
      category: category,
      author: user,
      published_at: Time.current
    )
  end

  let!(:draft_article) do
    KnowledgeBase::Article.create!(
      title: 'Draft Article',
      slug: 'draft-article',
      content: 'This is draft content',
      excerpt: 'Draft excerpt',
      status: 'draft',
      is_public: false,
      category: category,
      author: user
    )
  end

  describe 'GET /api/v1/kb/articles' do
    context 'public view (no auth)' do
      it 'returns only published public articles' do
        get '/api/v1/kb/articles', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles']).to be_an(Array)
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['title']).to eq('Published Article')
        expect(data).to have_key('pagination')
      end

      it 'filters by category' do
        get "/api/v1/kb/articles?category_id=#{category.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['category']['id']).to eq(category.id)
      end

      it 'filters by featured' do
        published_article.update!(is_featured: true)

        get '/api/v1/kb/articles?featured=true', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles'].all? { |a| a['is_featured'] }).to be true
      end

      it 'supports pagination' do
        get '/api/v1/kb/articles?page=1&per_page=10', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end
    end

    context 'admin view (with edit permissions)' do
      it 'returns all articles including drafts when admin flag set' do
        get '/api/v1/kb/articles?admin=true', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['articles'].length).to eq(2)
        expect(data).to have_key('stats')
        expect(data['stats']).to include('total', 'published', 'draft')
      end

      it 'filters by status' do
        get '/api/v1/kb/articles?admin=true&status=draft', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['status']).to eq('draft')
      end

      it 'filters by author' do
        get "/api/v1/kb/articles?admin=true&author_id=#{user.id}", headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['articles'].all? { |a| a['author_name'] == user.full_name }).to be true
      end

      it 'searches by title' do
        get '/api/v1/kb/articles?admin=true&search=Published', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['articles'].length).to eq(1)
        expect(data['articles'].first['title']).to eq('Published Article')
      end
    end

    context 'without edit permissions' do
      it 'returns forbidden when trying admin view' do
        get '/api/v1/kb/articles?admin=true', headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'GET /api/v1/kb/articles/:id' do
    context 'public view' do
      it 'returns published article details' do
        get "/api/v1/kb/articles/#{published_article.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['article']).to include(
          'id' => published_article.id,
          'title' => 'Published Article',
          'content' => 'This is published content'
        )
        expect(data).to have_key('related_articles')
      end

      it 'returns article by slug' do
        get "/api/v1/kb/articles/#{published_article.slug}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['article']['slug']).to eq(published_article.slug)
      end

      it 'returns forbidden for draft article' do
        get "/api/v1/kb/articles/#{draft_article.id}", as: :json

        expect_error_response('Access denied', 403)
      end

      it 'returns not found for non-existent article' do
        get '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000', as: :json

        expect_error_response('Article not found', 404)
      end
    end

    context 'admin view' do
      it 'returns draft article for editor' do
        get "/api/v1/kb/articles/#{draft_article.id}?admin=true", headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['id']).to eq(draft_article.id)
        expect(data['article']['status']).to eq('draft')
      end

      it 'returns forbidden for non-editor' do
        get "/api/v1/kb/articles/#{draft_article.id}?admin=true", headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'POST /api/v1/kb/articles' do
    let(:article_params) do
      {
        article: {
          title: 'New Article',
          slug: 'new-article',
          content: 'Article content',
          excerpt: 'Article excerpt',
          category_id: category.id,
          status: 'draft',
          is_public: false
        }
      }
    end

    context 'with kb.update permission' do
      it 'creates a new article' do
        expect {
          post '/api/v1/kb/articles', params: article_params, headers: editor_headers, as: :json
        }.to change(KnowledgeBase::Article, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['article']).to include(
          'title' => 'New Article',
          'slug' => 'new-article',
          'status' => 'draft'
        )
      end

      it 'assigns current user as author' do
        post '/api/v1/kb/articles', params: article_params, headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['author_name']).to eq(editor_user.full_name)
      end

      it 'assigns tags when provided' do
        params_with_tags = article_params.deep_merge(
          article: { tag_names: [ 'tag1', 'tag2' ] }
        )

        post '/api/v1/kb/articles', params: params_with_tags, headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['tags']).to contain_exactly('Tag1', 'Tag2')
      end

      it 'returns validation errors for invalid data' do
        invalid_params = { article: { title: '' } }

        post '/api/v1/kb/articles', params: invalid_params, headers: editor_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(json_response['success']).to be false
      end
    end

    context 'without kb.update permission' do
      it 'returns forbidden error' do
        post '/api/v1/kb/articles', params: article_params, headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post '/api/v1/kb/articles', params: article_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'PATCH /api/v1/kb/articles/:id' do
    let(:update_params) do
      {
        article: {
          title: 'Updated Title',
          content: 'Updated content'
        }
      }
    end

    context 'with proper permissions' do
      it 'updates the article' do
        patch "/api/v1/kb/articles/#{draft_article.id}", params: update_params, headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['title']).to eq('Updated Title')
        expect(draft_article.reload.title).to eq('Updated Title')
      end

      it 'updates tags when provided' do
        params_with_tags = update_params.deep_merge(
          article: { tag_names: [ 'updated-tag' ] }
        )

        patch "/api/v1/kb/articles/#{draft_article.id}", params: params_with_tags, headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['tags']).to contain_exactly('Updated Tag')
      end

      it 'returns validation errors for invalid data' do
        invalid_params = { article: { title: '' } }

        patch "/api/v1/kb/articles/#{draft_article.id}", params: invalid_params, headers: editor_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        patch "/api/v1/kb/articles/#{draft_article.id}", params: update_params, headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent article' do
      it 'returns not found error' do
        patch '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000', params: update_params, headers: editor_headers, as: :json

        expect_error_response('Article not found', 404)
      end
    end
  end

  describe 'DELETE /api/v1/kb/articles/:id' do
    context 'with proper permissions' do
      it 'deletes the article' do
        article_id = draft_article.id

        expect {
          delete "/api/v1/kb/articles/#{article_id}", headers: editor_headers, as: :json
        }.to change(KnowledgeBase::Article, :count).by(-1)

        expect_success_response
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        delete "/api/v1/kb/articles/#{draft_article.id}", headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent article' do
      it 'returns not found error' do
        delete '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000', headers: editor_headers, as: :json

        expect_error_response('Article not found', 404)
      end
    end
  end

  describe 'POST /api/v1/kb/articles/:id/publish' do
    context 'with kb.publish permission' do
      it 'publishes the article' do
        post "/api/v1/kb/articles/#{draft_article.id}/publish", headers: publisher_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['status']).to eq('published')
        expect(draft_article.reload.status).to eq('published')
        expect(draft_article.published_at).not_to be_nil
      end
    end

    context 'without kb.publish permission' do
      it 'returns forbidden error' do
        post "/api/v1/kb/articles/#{draft_article.id}/publish", headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent article' do
      it 'returns not found error' do
        post '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000/publish', headers: publisher_headers, as: :json

        expect_error_response('Article not found', 404)
      end
    end
  end

  describe 'POST /api/v1/kb/articles/:id/unpublish' do
    context 'with kb.publish permission' do
      it 'unpublishes the article' do
        post "/api/v1/kb/articles/#{published_article.id}/unpublish", headers: publisher_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['article']['status']).to eq('draft')
        expect(published_article.reload.status).to eq('draft')
        expect(published_article.published_at).to be_nil
      end
    end

    context 'without kb.publish permission' do
      it 'returns forbidden error' do
        post "/api/v1/kb/articles/#{published_article.id}/unpublish", headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'GET /api/v1/kb/articles/search' do
    context 'with search query' do
      it 'searches and returns matching articles' do
        get '/api/v1/kb/articles/search?q=Published', as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['query']).to eq('Published')
        expect(data['articles']).to be_an(Array)
        expect(data).to have_key('pagination')
      end

      it 'applies filters to search results' do
        get "/api/v1/kb/articles/search?q=Article&category_id=#{category.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['articles'].all? { |a| a['category']['id'] == category.id }).to be true
      end
    end

    context 'without search query' do
      it 'returns bad request error' do
        get '/api/v1/kb/articles/search', as: :json

        expect_error_response('Search query is required', 400)
      end
    end
  end

  describe 'GET /api/v1/kb/articles/analytics' do
    context 'with kb.manage permission' do
      it 'returns analytics data' do
        get '/api/v1/kb/articles/analytics', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to include(
          'total_articles',
          'published_articles',
          'draft_articles',
          'total_views',
          'top_articles',
          'views_by_day'
        )
      end

      it 'accepts custom period parameter' do
        get '/api/v1/kb/articles/analytics?period=7', headers: headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data).to have_key('views_by_day')
      end
    end

    context 'without kb.manage permission' do
      it 'returns forbidden error' do
        get '/api/v1/kb/articles/analytics', headers: editor_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'PATCH /api/v1/kb/articles/bulk' do
    let(:article1) { draft_article }
    let(:article2) do
      KnowledgeBase::Article.create!(
        title: 'Another Draft',
        slug: 'another-draft',
        content: 'Content',
        status: 'draft',
        category: category,
        author: user
      )
    end

    let(:bulk_update_params) do
      {
        article_ids: [ article1.id, article2.id ],
        status: 'published',
        is_featured: true
      }
    end

    context 'with proper permissions' do
      it 'updates multiple articles' do
        patch '/api/v1/kb/articles/bulk', params: bulk_update_params, headers: editor_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['updated_count']).to eq(2)
        expect(article1.reload.status).to eq('published')
        expect(article2.reload.status).to eq('published')
        expect(article1.is_featured).to be true
      end
    end

    context 'without article IDs' do
      it 'returns bad request error' do
        patch '/api/v1/kb/articles/bulk', params: { status: 'published' }, headers: editor_headers, as: :json

        expect_error_response('No article IDs provided', 400)
      end
    end

    context 'with non-existent article IDs' do
      it 'returns not found error' do
        params = { article_ids: [ '00000000-0000-0000-0000-000000000000' ], status: 'published' }

        patch '/api/v1/kb/articles/bulk', params: params, headers: editor_headers, as: :json

        expect_error_response('No articles found', 404)
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        patch '/api/v1/kb/articles/bulk', params: bulk_update_params, headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'DELETE /api/v1/kb/articles/bulk' do
    let(:article1) { draft_article }
    let(:article2) do
      KnowledgeBase::Article.create!(
        title: 'Another Draft',
        slug: 'another-draft',
        content: 'Content',
        status: 'draft',
        category: category,
        author: user
      )
    end

    let(:bulk_delete_params) do
      {
        article_ids: [ article1.id, article2.id ]
      }
    end

    context 'with proper permissions' do
      it 'deletes multiple articles' do
        article1_id = article1.id
        article2_id = article2.id

        expect {
          delete '/api/v1/kb/articles/bulk', params: bulk_delete_params, headers: editor_headers, as: :json
        }.to change(KnowledgeBase::Article, :count).by(-2)

        expect_success_response
        data = json_response_data
        expect(data['deleted_count']).to eq(2)
      end
    end

    context 'without article IDs' do
      it 'returns bad request error' do
        delete '/api/v1/kb/articles/bulk', headers: editor_headers, as: :json

        expect_error_response('No article IDs provided', 400)
      end
    end

    context 'without proper permissions' do
      it 'returns forbidden error' do
        delete '/api/v1/kb/articles/bulk', params: bulk_delete_params, headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end
end
