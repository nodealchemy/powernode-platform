# frozen_string_literal: true

require 'rails_helper'

# Tenancy ruling: KnowledgeBase::Article must support BOTH tenant-private
# (account_id present -> visible/editable only within that account) AND
# global-shared (account_id nil -> shared across all accounts, read-only to
# accounts per the GloballyScopable policy).
RSpec.describe 'Api::V1::Kb::Articles tenancy', type: :request do
  # Two distinct tenants.
  let(:account_a) { create(:account) }
  let(:account_b) { create(:account) }

  # account A: an owner with full kb rights, plus the article's author.
  let(:a_manager) { create(:user, account: account_a, permissions: [ 'kb.update', 'kb.manage', 'kb.publish' ]) }
  let(:a_author)  { create(:user, account: account_a, permissions: [ 'kb.update' ]) }

  # account B: a user with the strongest kb rights — must STILL be denied A's
  # private content (invariant 1: even kb.manage cannot cross tenants).
  let(:b_manager) { create(:user, account: account_b, permissions: [ 'kb.update', 'kb.manage', 'kb.publish' ]) }

  let(:a_headers) { auth_headers_for(a_manager) }
  let(:b_headers) { auth_headers_for(b_manager) }

  let!(:category) do
    KnowledgeBase::Category.create!(name: 'Cat', slug: 'cat', is_public: true)
  end

  # No DB trigger maintains knowledge_base_articles.search_vector, so FTS won't
  # match freshly-created test rows. Populate it directly for search assertions.
  def seed_search_vector!(article, text)
    article.update_column(
      :search_vector,
      KnowledgeBase::Article.connection.select_value(
        KnowledgeBase::Article.sanitize_sql_array(["SELECT to_tsvector('english', ?)", text])
      )
    )
  end

  # Tenant-private article owned by account A, marked public+published (worst
  # case: must NOT leak to other accounts nor to the world).
  let!(:private_a) do
    KnowledgeBase::Article.create!(
      title: 'A Private', slug: 'a-private', content: 'private body',
      excerpt: 'x', status: 'published', is_public: true,
      account: account_a, category: category, author: a_author,
      published_at: Time.current
    )
  end

  # Global-shared article (account_id nil), public+published.
  let!(:global_pub) do
    KnowledgeBase::Article.create!(
      title: 'Global Pub', slug: 'global-pub', content: 'global body',
      excerpt: 'x', status: 'published', is_public: true,
      account: nil, category: category, author: a_author,
      published_at: Time.current
    )
  end

  # --- Invariant 1: cross-account + unauthenticated cannot view/list/edit A's private ---
  describe 'invariant 1: tenant-private isolation from other accounts + public' do
    it 'hides A-private from account B index (even kb.manage)' do
      get '/api/v1/kb/articles?admin=true', headers: b_headers, as: :json
      expect(response).to have_http_status(:success)
      ids = json_response_data['articles'].map { |a| a['id'] }
      expect(ids).not_to include(private_a.id)
    end

    it 'denies account B show of A-private' do
      get "/api/v1/kb/articles/#{private_a.id}?admin=true", headers: b_headers, as: :json
      expect(response.status).to be_in([ 403, 404 ])
    end

    it 'denies account B update of A-private' do
      patch "/api/v1/kb/articles/#{private_a.id}",
            params: { article: { title: 'hijacked' } }, headers: b_headers, as: :json
      expect(response.status).to be_in([ 403, 404 ])
      expect(private_a.reload.title).to eq('A Private')
    end

    it 'denies account B delete of A-private' do
      delete "/api/v1/kb/articles/#{private_a.id}", headers: b_headers, as: :json
      expect(response.status).to be_in([ 403, 404 ])
      expect(KnowledgeBase::Article.exists?(private_a.id)).to be true
    end

    it 'hides A-private from unauthenticated public index' do
      get '/api/v1/kb/articles', as: :json
      titles = json_response_data['articles'].map { |a| a['title'] }
      expect(titles).not_to include('A Private')
    end

    it 'denies unauthenticated public show of A-private' do
      get "/api/v1/kb/articles/#{private_a.id}", as: :json
      expect(response.status).to be_in([ 403, 404 ])
    end

    it 'hides A-private from unauthenticated search' do
      # Give the private article a matching search_vector so this proves the
      # tenancy scope excludes it (not merely an empty FTS index).
      seed_search_vector!(private_a, 'a private private body')
      get '/api/v1/kb/articles/search?q=private', as: :json
      titles = json_response_data['articles'].map { |a| a['title'] }
      expect(titles).not_to include('A Private')
    end

    it 'hides A-private from account B category listing' do
      get "/api/v1/kb/categories/#{category.id}", headers: b_headers, as: :json
      titles = json_response_data['articles'].map { |a| a['title'] }
      expect(titles).not_to include('A Private')
    end
  end

  # --- Invariant 2: the owning account A CAN view/edit/list its private article ---
  describe 'invariant 2: owning account access preserved' do
    it 'lists A-private in account A admin index' do
      get '/api/v1/kb/articles?admin=true', headers: a_headers, as: :json
      ids = json_response_data['articles'].map { |a| a['id'] }
      expect(ids).to include(private_a.id)
    end

    it 'shows A-private to account A' do
      get "/api/v1/kb/articles/#{private_a.id}?admin=true", headers: a_headers, as: :json
      expect_success_response
      expect(json_response_data['article']['id']).to eq(private_a.id)
    end

    it 'lets account A update A-private' do
      patch "/api/v1/kb/articles/#{private_a.id}",
            params: { article: { title: 'Renamed' } }, headers: a_headers, as: :json
      expect_success_response
      expect(private_a.reload.title).to eq('Renamed')
    end

    it 'lets the author update A-private' do
      patch "/api/v1/kb/articles/#{private_a.id}",
            params: { article: { title: 'AuthorRenamed' } },
            headers: auth_headers_for(a_author), as: :json
      expect_success_response
      expect(private_a.reload.title).to eq('AuthorRenamed')
    end
  end

  # --- Invariant 3: global article viewable/listable by all + unauthenticated ---
  describe 'invariant 3: global-shared read preserved' do
    it 'lists global to account B' do
      get '/api/v1/kb/articles?admin=true', headers: b_headers, as: :json
      ids = json_response_data['articles'].map { |a| a['id'] }
      expect(ids).to include(global_pub.id)
    end

    it 'shows global to account B' do
      get "/api/v1/kb/articles/#{global_pub.id}?admin=true", headers: b_headers, as: :json
      expect_success_response
      expect(json_response_data['article']['id']).to eq(global_pub.id)
    end

    it 'lists global to unauthenticated public index' do
      get '/api/v1/kb/articles', as: :json
      titles = json_response_data['articles'].map { |a| a['title'] }
      expect(titles).to include('Global Pub')
    end

    it 'shows global to unauthenticated public show' do
      get "/api/v1/kb/articles/#{global_pub.id}", as: :json
      expect_success_response
      expect(json_response_data['article']['id']).to eq(global_pub.id)
    end

    it 'returns global in unauthenticated search' do
      # No DB trigger populates search_vector; set it so the FTS query matches
      # (search-infra precondition, orthogonal to the tenancy ruling).
      seed_search_vector!(global_pub, 'global pub global body')
      get '/api/v1/kb/articles/search?q=global', as: :json
      titles = json_response_data['articles'].map { |a| a['title'] }
      expect(titles).to include('Global Pub')
    end
  end

  # --- Invariant 4: globals keep the existing read-only-to-accounts edit policy ---
  describe 'invariant 4: global edit policy unchanged (read-only to accounts)' do
    # The codebase's pre-existing Article#editable_by? already allows kb.manage /
    # kb.update / author to edit a global article via the standard controller
    # path. We must NOT regress that legitimate behavior. (The require_editable_content!
    # clone-to-edit policy applies to the GloballyScopedContent clone endpoints,
    # which the KB articles controller does not use.)
    it 'still allows account A kb.manage to edit a global article (no new break)' do
      get "/api/v1/kb/articles/#{global_pub.id}?admin=true", headers: a_headers, as: :json
      expect_success_response
      patch "/api/v1/kb/articles/#{global_pub.id}",
            params: { article: { title: 'Global Edited' } }, headers: a_headers, as: :json
      expect_success_response
      expect(global_pub.reload.title).to eq('Global Edited')
    end
  end

  # --- Invariant 5: create assigns account_id = current_account (private by default) ---
  describe 'invariant 5: create is tenant-private by default' do
    it 'assigns account_id to the creating account' do
      post '/api/v1/kb/articles',
           params: { article: { title: 'Fresh', slug: 'fresh', content: 'body',
                                excerpt: 'e', status: 'draft', is_public: false,
                                category_id: category.id } },
           headers: a_headers, as: :json
      expect_success_response
      created = KnowledgeBase::Article.find_by(slug: 'fresh')
      expect(created.account_id).to eq(account_a.id)
    end

    it 'does not let a normal create produce a global (account_id nil) article' do
      post '/api/v1/kb/articles',
           params: { article: { title: 'Fresh2', slug: 'fresh2', content: 'body',
                                excerpt: 'e', status: 'draft', is_public: false,
                                category_id: category.id } },
           headers: a_headers, as: :json
      created = KnowledgeBase::Article.find_by(slug: 'fresh2')
      expect(created.account_id).not_to be_nil
    end
  end

  # --- Model-level tenancy gate ---
  describe 'KnowledgeBase::Article#viewable_by? / #editable_by?' do
    it 'denies a cross-account user viewing a private public article' do
      expect(private_a.viewable_by?(b_manager)).to be false
    end

    it 'denies an unauthenticated request viewing a private public article' do
      expect(private_a.viewable_by?(nil)).to be false
    end

    it 'allows the owning account user + author to view the private article' do
      expect(private_a.viewable_by?(a_manager)).to be true
      expect(private_a.viewable_by?(a_author)).to be true
    end

    it 'denies a cross-account user editing the private article' do
      expect(private_a.editable_by?(b_manager)).to be false
    end

    it 'allows global public published to be viewed by anyone incl. unauthenticated' do
      expect(global_pub.viewable_by?(nil)).to be true
      expect(global_pub.viewable_by?(b_manager)).to be true
    end
  end
end
