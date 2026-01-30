# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Kb::Attachments', type: :request do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: ['kb.update', 'kb.manage']) }
  let(:editor_user) { create(:user, account: account, permissions: ['kb.update']) }
  let(:read_only_user) { create(:user, account: account, permissions: []) }

  let(:headers) { auth_headers_for(user) }
  let(:editor_headers) { auth_headers_for(editor_user) }
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
      content: 'Content',
      status: 'published',
      is_public: true,
      category: category,
      author: user,
      published_at: Time.current
    )
  end

  let!(:attachment) do
    KnowledgeBase::Attachment.create!(
      filename: 'test-file.pdf',
      content_type: 'application/pdf',
      file_size: 1024,
      file_path: '/uploads/kb/test-file.pdf',
      uploaded_by: user,
      article: published_article
    )
  end

  describe 'GET /api/v1/kb/attachments/:id' do
    context 'for published article attachment' do
      it 'returns attachment details without authentication' do
        get "/api/v1/kb/attachments/#{attachment.id}", as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['attachment']).to include(
          'id' => attachment.id,
          'filename' => 'test-file.pdf',
          'content_type' => 'application/pdf'
        )
      end
    end

    context 'for draft article attachment' do
      let(:draft_article) do
        KnowledgeBase::Article.create!(
          title: 'Draft Article',
          slug: 'draft-article',
          content: 'Content',
          status: 'draft',
          is_public: false,
          category: category,
          author: user
        )
      end

      let(:draft_attachment) do
        KnowledgeBase::Attachment.create!(
          filename: 'draft-file.pdf',
          content_type: 'application/pdf',
          file_size: 1024,
          file_path: '/uploads/kb/draft-file.pdf',
          uploaded_by: user,
          article: draft_article
        )
      end

      it 'returns forbidden for public access' do
        get "/api/v1/kb/attachments/#{draft_attachment.id}", as: :json

        expect_error_response('Access denied', 403)
      end

      it 'returns attachment for editor with permissions' do
        get "/api/v1/kb/attachments/#{draft_attachment.id}", headers: editor_headers, as: :json

        expect(response).to have_http_status(:success)
        data = json_response_data
        expect(data['attachment']['id']).to eq(draft_attachment.id)
      end
    end

    context 'for non-existent attachment' do
      it 'returns not found error' do
        get '/api/v1/kb/attachments/00000000-0000-0000-0000-000000000000', as: :json

        expect_error_response('Attachment not found', 404)
      end
    end
  end

  describe 'POST /api/v1/kb/attachments' do
    let(:file) { fixture_file_upload('spec/fixtures/files/test.pdf', 'application/pdf') }

    context 'with kb.update permission' do
      it 'uploads a new attachment' do
        params = { file: file, article_id: published_article.id }

        expect {
          post '/api/v1/kb/attachments', params: params, headers: editor_headers
        }.to change(KnowledgeBase::Attachment, :count).by(1)

        expect_success_response
        data = json_response_data
        expect(data['attachment']).to include('filename', 'content_type', 'size')
        expect(data).to have_key('url')
      end

      it 'assigns current user as uploader' do
        params = { file: file, article_id: published_article.id }

        post '/api/v1/kb/attachments', params: params, headers: editor_headers

        expect_success_response
        data = json_response_data
        expect(data['attachment']['uploader_name']).to eq(editor_user.full_name)
      end
    end

    context 'without file parameter' do
      it 'returns bad request error' do
        post '/api/v1/kb/attachments', params: {}, headers: editor_headers, as: :json

        expect_error_response('No file provided', 400)
      end
    end

    context 'without kb.update permission' do
      it 'returns forbidden error' do
        params = { file: file, article_id: published_article.id }

        post '/api/v1/kb/attachments', params: params, headers: read_only_headers

        expect_error_response('Access denied', 403)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        params = { file: file, article_id: published_article.id }

        post '/api/v1/kb/attachments', params: params

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'DELETE /api/v1/kb/attachments/:id' do
    context 'with kb.update permission' do
      it 'deletes the attachment' do
        attachment_id = attachment.id

        expect {
          delete "/api/v1/kb/attachments/#{attachment_id}", headers: editor_headers, as: :json
        }.to change(KnowledgeBase::Attachment, :count).by(-1)

        expect_success_response
      end
    end

    context 'without kb.update permission' do
      it 'returns forbidden error' do
        delete "/api/v1/kb/attachments/#{attachment.id}", headers: read_only_headers, as: :json

        expect_error_response('Access denied', 403)
      end
    end

    context 'for non-existent attachment' do
      it 'returns not found error' do
        delete '/api/v1/kb/attachments/00000000-0000-0000-0000-000000000000', headers: editor_headers, as: :json

        expect_error_response('Attachment not found', 404)
      end
    end

    context 'without authentication' do
      it 'returns unauthorized error' do
        delete "/api/v1/kb/attachments/#{attachment.id}", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end
end
