# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Kb::Comments', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ 'kb.moderate', 'kb.manage' ]) }
  let(:moderator_user) { create(:user, account: account, permissions: [ 'kb.moderate' ]) }
  let(:regular_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:moderator_headers) { auth_headers_for(moderator_user) }
  let(:regular_headers) { auth_headers_for(regular_user) }

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
      content: 'Content',
      status: 'published',
      is_public: true,
      category: category,
      author: user,
      published_at: Time.current
    )
  end

  let!(:approved_comment) do
    comment = KnowledgeBase::Comment.create!(
      content: 'This is an approved comment',
      article: published_article,
      author: regular_user
    )
    # Override the before_create callback that sets status based on permissions
    comment.update_column(:status, 'approved')
    comment
  end

  let!(:pending_comment) do
    comment = KnowledgeBase::Comment.create!(
      content: 'This is a pending comment',
      article: published_article,
      author: regular_user
    )
    # regular_user has no permissions, so callback already sets status to 'pending'
    comment
  end

  # `published_article` above is GLOBAL (no account) so the public index/show/
  # create tests work unauthenticated. Moderation, however, is account-scoped:
  # a tenant may only moderate comments on its OWN articles. These owned fixtures
  # back the moderation happy-paths.
  let!(:owned_article) do
    KnowledgeBase::Article.create!(
      title: 'Owned Article', slug: 'owned-article', content: 'Content',
      status: 'published', is_public: true, category: category,
      account: account, author: user, published_at: Time.current
    )
  end

  let!(:owned_pending_comment) do
    KnowledgeBase::Comment.create!(
      content: 'Owned pending comment', article: owned_article, author: regular_user
    )
  end

  let!(:owned_approved_comment) do
    comment = KnowledgeBase::Comment.create!(
      content: 'Owned approved comment', article: owned_article, author: regular_user
    )
    comment.update_column(:status, 'approved')
    comment
  end

  describe 'GET /api/v1/kb/articles/:article_id/comments' do
    context 'public view (no auth)' do
      it 'returns only approved top-level comments' do
        get "/api/v1/kb/articles/#{published_article.id}/comments", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['comments']).to be_an(Array)
        expect(data['comments'].length).to eq(1)
        expect(data['comments'].first['content']).to eq('This is an approved comment')
        expect(data).to have_key('pagination')
      end

      it 'includes approved replies' do
        reply = KnowledgeBase::Comment.create!(
          content: 'This is a reply',
          article: published_article,
          author: regular_user,
          parent: approved_comment
        )
        reply.update_column(:status, 'approved')

        get "/api/v1/kb/articles/#{published_article.id}/comments", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['comments'].first['replies']).to be_an(Array)
        expect(data['comments'].first['replies'].length).to eq(1)
      end

      it 'supports pagination' do
        get "/api/v1/kb/articles/#{published_article.id}/comments?page=1&per_page=10", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['pagination']).to include('current_page', 'total_pages', 'total_count', 'per_page')
      end

      it 'returns not found for non-existent article' do
        get '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000/comments', as: :json

        expect_error_response('Article not found', 404)
      end
    end
  end

  describe 'POST /api/v1/kb/articles/:article_id/comments' do
    let(:comment_params) do
      {
        comment: {
          content: 'This is a new comment'
        }
      }
    end

    context 'with authentication' do
      it 'creates a new comment' do
        expect {
          post "/api/v1/kb/articles/#{published_article.id}/comments", params: comment_params, headers: regular_headers, as: :json
        }.to change(KnowledgeBase::Comment, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['content']).to eq('This is a new comment')
      end

      it 'assigns current user as author' do
        post "/api/v1/kb/articles/#{published_article.id}/comments", params: comment_params, headers: regular_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['user_name']).to eq(regular_user.full_name)
      end

      it 'creates a reply when parent_id provided' do
        reply_params = comment_params.deep_merge(
          comment: { parent_id: approved_comment.id }
        )

        post "/api/v1/kb/articles/#{published_article.id}/comments", params: reply_params, headers: regular_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['is_reply']).to be true
      end

      it 'returns validation errors for invalid data' do
        invalid_params = { comment: { content: '' } }

        post "/api/v1/kb/articles/#{published_article.id}/comments", params: invalid_params, headers: regular_headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end

      it 'returns not found for non-existent article' do
        post '/api/v1/kb/articles/00000000-0000-0000-0000-000000000000/comments', params: comment_params, headers: regular_headers, as: :json

        expect_error_response('Article not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        post "/api/v1/kb/articles/#{published_article.id}/comments", params: comment_params, as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/kb/comments/:id' do
    context 'for approved comment' do
      it 'returns comment details with replies' do
        reply = KnowledgeBase::Comment.create!(
          content: 'Reply',
          article: published_article,
          author: regular_user,
          parent: approved_comment
        )
        reply.update_column(:status, 'approved')

        get "/api/v1/kb/comments/#{approved_comment.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['id']).to eq(approved_comment.id)
        expect(data).to have_key('replies')
      end
    end

    context 'for pending comment' do
      it 'returns not found error' do
        get "/api/v1/kb/comments/#{pending_comment.id}", as: :json

        expect_error_response('Comment not found', 404)
      end
    end

    context 'for non-existent comment' do
      it 'returns not found error' do
        get '/api/v1/kb/comments/00000000-0000-0000-0000-000000000000', as: :json

        expect_error_response('Comment not found', 404)
      end
    end
  end

  describe 'GET /api/v1/kb/comments/moderate' do
    context 'with kb.moderate permission' do
      it 'returns comments for moderation' do
        get '/api/v1/kb/comments/moderate', headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comments']).to be_an(Array)
        expect(data['comments'].length).to be >= 2
        expect(data).to have_key('stats')
        expect(data['stats']).to include('total', 'pending', 'approved', 'rejected', 'spam')
        expect(data).to have_key('pagination')
      end

      it 'filters by status' do
        get '/api/v1/kb/comments/moderate?status=pending', headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comments'].all? { |c| c['status'] == 'pending' }).to be true
      end

      it 'filters by article' do
        get "/api/v1/kb/comments/moderate?article_id=#{owned_article.id}", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comments'].all? { |c| c['article']['id'] == owned_article.id }).to be true
      end

      it 'searches by content' do
        get '/api/v1/kb/comments/moderate?search=Owned', headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comments'].length).to be >= 1
      end

      it 'sorts comments' do
        get '/api/v1/kb/comments/moderate?sort=oldest', headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comments']).to be_an(Array)
      end

      # Cross-tenant isolation: the moderation queue and its stats must only ever
      # surface the current account's own comments — never GLOBAL-KB comments
      # (on `published_article`) nor another account's.
      context 'tenant isolation' do
        let(:other_account) { create(:account) }
        let!(:foreign_article) do
          KnowledgeBase::Article.create!(
            title: 'Foreign Article', slug: 'foreign-article', content: 'Content',
            status: 'published', is_public: true, category: category,
            account: other_account, published_at: Time.current
          )
        end
        let!(:foreign_comment) do
          KnowledgeBase::Comment.create!(
            content: 'Foreign tenant comment', article: foreign_article, author: regular_user
          )
        end

        it "excludes GLOBAL and other accounts' comments from the queue" do
          get '/api/v1/kb/comments/moderate?per_page=100', headers: moderator_headers, as: :json

          expect_success_response
          ids = json_response_data['comments'].map { |c| c['id'] }
          expect(ids).to include(owned_pending_comment.id, owned_approved_comment.id)
          # GLOBAL-KB comments and the foreign account's comment never leak.
          expect(ids).not_to include(approved_comment.id, pending_comment.id, foreign_comment.id)
        end

        it 'counts only the current account in stats' do
          get '/api/v1/kb/comments/moderate', headers: moderator_headers, as: :json

          expect_success_response
          stats = json_response_data['stats']
          # Exactly the 2 owned comments (1 pending + 1 approved); globals/foreign excluded.
          expect(stats['total']).to eq(2)
          expect(stats['pending']).to eq(1)
          expect(stats['approved']).to eq(1)
        end
      end
    end

    context 'without kb.moderate permission' do
      it 'returns forbidden error' do
        get '/api/v1/kb/comments/moderate', headers: regular_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'POST /api/v1/kb/comments/:id/approve' do
    context 'with kb.moderate permission' do
      it 'approves a pending comment' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/approve", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comment']['status']).to eq('approved')
        expect(owned_pending_comment.reload.status).to eq('approved')
      end
    end

    context 'without kb.moderate permission' do
      it 'returns forbidden error' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/approve", headers: regular_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent comment' do
      it 'returns not found error' do
        post '/api/v1/kb/comments/00000000-0000-0000-0000-000000000000/approve', headers: moderator_headers, as: :json

        expect_error_response('Comment not found', 404)
      end
    end
  end

  describe 'POST /api/v1/kb/comments/:id/reject' do
    context 'with kb.moderate permission' do
      it 'rejects a pending comment' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/reject", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comment']['status']).to eq('rejected')
        expect(owned_pending_comment.reload.status).to eq('rejected')
      end
    end

    context 'without kb.moderate permission' do
      it 'returns forbidden error' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/reject", headers: regular_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'POST /api/v1/kb/comments/:id/spam' do
    context 'with kb.moderate permission' do
      it 'marks comment as spam' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/spam", headers: moderator_headers, as: :json

        expect_success_response
        data = json_response_data
        expect(data['comment']['status']).to eq('spam')
        expect(owned_pending_comment.reload.status).to eq('spam')
      end
    end

    context 'without kb.moderate permission' do
      it 'returns forbidden error' do
        post "/api/v1/kb/comments/#{owned_pending_comment.id}/spam", headers: regular_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end
  end

  describe 'DELETE /api/v1/kb/comments/:id' do
    context 'with kb.moderate permission' do
      it 'deletes the comment' do
        comment_id = owned_pending_comment.id

        expect {
          delete "/api/v1/kb/comments/#{comment_id}", headers: moderator_headers, as: :json
        }.to change(KnowledgeBase::Comment, :count).by(-1)

        expect_success_response
      end
    end

    context 'without kb.moderate permission' do
      it 'returns forbidden error' do
        delete "/api/v1/kb/comments/#{owned_pending_comment.id}", headers: regular_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent comment' do
      it 'returns not found error' do
        delete '/api/v1/kb/comments/00000000-0000-0000-0000-000000000000', headers: moderator_headers, as: :json

        expect_error_response('Comment not found', 404)
      end
    end
  end

  # Cross-tenant moderation isolation: even WITH kb.moderate/kb.manage, a tenant
  # may not approve/reject/spam/delete comments on GLOBAL-KB articles (account_id
  # nil) nor on another account's articles. `pending_comment` lives on the GLOBAL
  # `published_article`; `foreign_comment` on another account's article.
  describe 'cross-tenant comment moderation isolation' do
    let(:other_account) { create(:account) }
    let!(:foreign_article) do
      KnowledgeBase::Article.create!(
        title: 'Foreign Article', slug: 'foreign-article', content: 'Content',
        status: 'published', is_public: true, category: category,
        account: other_account, published_at: Time.current
      )
    end
    let!(:foreign_comment) do
      KnowledgeBase::Comment.create!(
        content: 'Foreign tenant comment', article: foreign_article, author: regular_user
      )
    end

    it 'cannot approve a GLOBAL-KB comment (403, status unchanged)' do
      post "/api/v1/kb/comments/#{pending_comment.id}/approve", headers: headers, as: :json

      expect_error_response('Access denied', 403)
      expect(pending_comment.reload.status).to eq('pending')
    end

    it "cannot delete another account's comment (403, row preserved)" do
      expect {
        delete "/api/v1/kb/comments/#{foreign_comment.id}", headers: headers, as: :json
      }.not_to change(KnowledgeBase::Comment, :count)

      expect_error_response('Access denied', 403)
      expect(KnowledgeBase::Comment.exists?(foreign_comment.id)).to be true
    end

    it "cannot mark another account's comment as spam (403, status unchanged)" do
      post "/api/v1/kb/comments/#{foreign_comment.id}/spam", headers: headers, as: :json

      expect_error_response('Access denied', 403)
      expect(foreign_comment.reload.status).to eq('pending')
    end
  end
end
