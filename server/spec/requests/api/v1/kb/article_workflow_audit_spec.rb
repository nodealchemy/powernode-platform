# frozen_string_literal: true

require 'rails_helper'

# Every article state transition made through the API must leave a row in
# knowledge_base_workflows saying who moved it and between which statuses.
# Without these, KnowledgeBase::Workflow is a well-formed model of a table
# nothing ever writes to.
RSpec.describe 'Api::V1::Kb::Articles workflow audit trail', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'kb.update', 'kb.manage' ]) }
  let(:publisher_user) { create(:user, account: account, permissions: [ 'kb.publish' ]) }

  let(:headers) { auth_headers_for(user) }
  let(:publisher_headers) { auth_headers_for(publisher_user) }

  let!(:category) do
    KnowledgeBase::Category.create!(name: 'Audit Category', slug: 'audit-category', is_public: true)
  end

  let!(:draft_article) do
    KnowledgeBase::Article.create!(
      title: 'Draft Article', slug: 'audit-draft-article', content: 'Draft content',
      excerpt: 'Draft excerpt', status: 'draft', is_public: false,
      category: category, author: user, account: account
    )
  end

  let!(:published_article) do
    KnowledgeBase::Article.create!(
      title: 'Published Article', slug: 'audit-published-article', content: 'Published content',
      excerpt: 'Published excerpt', status: 'published', is_public: true,
      category: category, author: user, account: account, published_at: 2.days.ago
    )
  end

  def workflows_for(article)
    KnowledgeBase::Workflow.for_article(article.id).chronological
  end

  describe 'POST /api/v1/kb/articles' do
    it 'records a create row naming the status the article landed in' do
      expect {
        post '/api/v1/kb/articles',
             params: { article: { title: 'Brand New', content: 'Body', category_id: category.id } },
             headers: headers, as: :json
      }.to change(KnowledgeBase::Workflow, :count).by(1)

      expect(response).to have_http_status(:ok)

      workflow = KnowledgeBase::Workflow.recent.first
      expect(workflow).to have_attributes(
        action: 'create',
        from_status: nil,
        to_status: 'draft',
        user_id: user.id
      )
      expect(workflow.metadata).to include('source' => 'api')
    end

    it 'records the landing status when the article is created already published' do
      post '/api/v1/kb/articles',
           params: { article: { title: 'Born Live', content: 'Body', category_id: category.id, status: 'published' } },
           headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(KnowledgeBase::Workflow.recent.first).to have_attributes(action: 'create', to_status: 'published')
    end

    it 'writes no row when the article is invalid' do
      expect {
        post '/api/v1/kb/articles',
             params: { article: { title: '', content: '', category_id: category.id } },
             headers: headers, as: :json
      }.not_to change(KnowledgeBase::Workflow, :count)
    end
  end

  describe 'PATCH /api/v1/kb/articles/:id' do
    it 'records an edit naming the fields that changed when the status holds' do
      patch "/api/v1/kb/articles/#{draft_article.id}",
            params: { article: { title: 'Retitled' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)

      workflow = workflows_for(draft_article).last
      expect(workflow).to have_attributes(
        action: 'edit',
        from_status: 'draft',
        to_status: 'draft',
        user_id: user.id
      )
      expect(workflow.comment).to eq('Updated: title')
      expect(workflow).not_to be_status_change
    end

    it 'records a publish when an update moves the status to published' do
      patch "/api/v1/kb/articles/#{draft_article.id}",
            params: { article: { status: 'published' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(workflows_for(draft_article).last).to have_attributes(
        action: 'publish', from_status: 'draft', to_status: 'published'
      )
    end

    it 'records an archive when an update moves the status to archived' do
      patch "/api/v1/kb/articles/#{published_article.id}",
            params: { article: { status: 'archived' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(workflows_for(published_article).last).to have_attributes(
        action: 'archive', from_status: 'published', to_status: 'archived'
      )
    end

    it 'records an unpublish when an update moves the status back to draft' do
      patch "/api/v1/kb/articles/#{published_article.id}",
            params: { article: { status: 'draft' } }, headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(workflows_for(published_article).last).to have_attributes(
        action: 'unpublish', from_status: 'published', to_status: 'draft'
      )
    end

    it 'writes no row when the update is rejected' do
      expect {
        patch "/api/v1/kb/articles/#{draft_article.id}",
              params: { article: { title: '' } }, headers: headers, as: :json
      }.not_to change(KnowledgeBase::Workflow, :count)
    end
  end

  describe 'POST /api/v1/kb/articles/:id/publish' do
    it 'records who published the article, when, and from what' do
      expect {
        post "/api/v1/kb/articles/#{draft_article.id}/publish", headers: publisher_headers, as: :json
      }.to change(KnowledgeBase::Workflow, :count).by(1)

      expect(response).to have_http_status(:ok)

      workflow = workflows_for(draft_article).last
      expect(workflow).to have_attributes(
        action: 'publish',
        from_status: 'draft',
        to_status: 'published',
        user_id: publisher_user.id
      )
      expect(workflow).to be_status_change
      expect(workflow.metadata['published_at']).to eq(draft_article.reload.published_at.iso8601)
      expect(workflow.created_at).to be_present
    end
  end

  describe 'POST /api/v1/kb/articles/:id/unpublish' do
    it 'preserves the published_at the transition is about to erase' do
      was_published_at = published_article.published_at

      expect {
        post "/api/v1/kb/articles/#{published_article.id}/unpublish", headers: publisher_headers, as: :json
      }.to change(KnowledgeBase::Workflow, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(published_article.reload.published_at).to be_nil

      workflow = workflows_for(published_article).last
      expect(workflow).to have_attributes(
        action: 'unpublish',
        from_status: 'published',
        to_status: 'draft',
        user_id: publisher_user.id
      )
      expect(workflow.metadata['was_published_at']).to eq(was_published_at.iso8601)
    end
  end

  describe 'the trail as a whole' do
    it 'reads back as an ordered history of one article' do
      patch "/api/v1/kb/articles/#{draft_article.id}",
            params: { article: { title: 'Renamed' } }, headers: headers, as: :json
      post "/api/v1/kb/articles/#{draft_article.id}/publish", headers: publisher_headers, as: :json
      post "/api/v1/kb/articles/#{draft_article.id}/unpublish", headers: publisher_headers, as: :json

      expect(workflows_for(draft_article).map(&:action)).to eq(%w[edit publish unpublish])
      expect(workflows_for(draft_article).map(&:user_id))
        .to eq([ user.id, publisher_user.id, publisher_user.id ])
    end

    it 'never records an action the database constraint would reject' do
      patch "/api/v1/kb/articles/#{draft_article.id}",
            params: { article: { status: 'review' } }, headers: headers, as: :json

      expect(KnowledgeBase::Workflow.pluck(:action).uniq)
        .to all(be_in(KnowledgeBase::Workflow::VALID_ACTIONS))
    end
  end
end
