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

  # A deletion is the one transition knowledge_base_workflows structurally
  # cannot hold. Article declares `has_many :workflows, dependent: :destroy`
  # (article.rb:22) and Workflow's `belongs_to :article` is required, so a row
  # recording a deletion is cascaded away by the very act it records — which is
  # why `delete` sits in VALID_ACTIONS unwritten. Deletions are recorded in
  # audit_logs instead: resource_id there is a plain string with NO foreign key
  # (schema.rb:4808), so the row outlives its subject.
  describe 'DELETE /api/v1/kb/articles/:id' do
    def deletion_rows_for(article)
      AuditLog.where(resource_type: 'KnowledgeBase::Article', resource_id: article.id, action: 'delete')
    end

    it 'records the deletion somewhere that outlives the article' do
      article_id = draft_article.id

      delete "/api/v1/kb/articles/#{article_id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(KnowledgeBase::Article.where(id: article_id)).to be_empty
      expect(deletion_rows_for(draft_article).count).to eq(1)
    end

    it 'names who deleted it — the question the trail exists to answer' do
      delete "/api/v1/kb/articles/#{draft_article.id}", headers: headers, as: :json

      expect(deletion_rows_for(draft_article).first.user_id).to eq(user.id)
    end

    it 'keeps the article identity in metadata, since resource_id now points at nothing' do
      delete "/api/v1/kb/articles/#{draft_article.id}", headers: headers, as: :json

      expect(deletion_rows_for(draft_article).first.metadata).to include(
        'title' => 'Draft Article',
        'slug' => 'audit-draft-article',
        'status' => 'draft'
      )
    end

    # The account is the ACTOR's, not the article's. A GLOBAL article has no
    # account, audit_logs.account_id is NOT NULL, and KnowledgeBase::Article is
    # in the audit optional-account set — so an article-scoped row would be
    # unwritable for exactly the 53 globals the KB ships.
    it 'records the deletion of a GLOBAL article, which owns no account' do
      global_article = KnowledgeBase::Article.create!(
        title: 'Global Article', slug: 'audit-global-article', content: 'Global content',
        status: 'draft', is_public: true, category: category, account: nil
      )

      delete "/api/v1/kb/articles/#{global_article.id}", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      row = deletion_rows_for(global_article).first
      expect(row).to be_present
      expect(row.account_id).to eq(account.id)
      expect(row.metadata['account_id']).to be_nil
    end

    it 'records nothing when the caller is not allowed to delete' do
      outsider = create(:user, account: create(:account), permissions: [ 'kb.update' ])

      delete "/api/v1/kb/articles/#{draft_article.id}",
             headers: auth_headers_for(outsider), as: :json

      expect(deletion_rows_for(draft_article)).to be_empty
      expect(KnowledgeBase::Article.where(id: draft_article.id)).to be_present
    end

    # A row asserting a deletion that never happened is the same false record
    # as a workflow row naming the wrong actor. (The response shape on a failed
    # destroy is pre-existing behaviour and deliberately unchanged.)
    it 'records nothing when the destroy itself does not happen' do
      allow_any_instance_of(KnowledgeBase::Article).to receive(:destroy).and_return(false)

      delete "/api/v1/kb/articles/#{draft_article.id}", headers: headers, as: :json

      expect(deletion_rows_for(draft_article)).to be_empty
    end

    # Characterization, not a wish: this is WHY the sink had to change. It
    # passes before and after, and pins the cascade that makes a workflow-row
    # fix impossible without a schema change.
    it 'cannot use the workflow trail: the cascade takes it with the article' do
      patch "/api/v1/kb/articles/#{draft_article.id}",
            params: { article: { title: 'About To Go' } }, headers: headers, as: :json
      expect(workflows_for(draft_article).count).to be >= 1

      delete "/api/v1/kb/articles/#{draft_article.id}", headers: headers, as: :json

      expect(KnowledgeBase::Workflow.where(article_id: draft_article.id)).to be_empty
    end
  end

  describe 'DELETE /api/v1/kb/articles/bulk' do
    it 'records one deletion row per article removed' do
      delete '/api/v1/kb/articles/bulk',
             params: { article_ids: [ draft_article.id, published_article.id ] },
             headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      rows = AuditLog.where(
        resource_type: 'KnowledgeBase::Article',
        resource_id: [ draft_article.id, published_article.id ],
        action: 'delete'
      )
      expect(rows.count).to eq(2)
      expect(rows.map(&:user_id).uniq).to eq([ user.id ])
    end
  end
end
