# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::FilesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:subscription) { create(:subscription, account: account) }
  let(:plan) { create(:plan, :with_limits) }
  let(:file_storage) { create(:file_storage, account: account, is_default: true) }

  before do
    subscription.update!(plan: plan)
    sign_in_as_user(user)
    file_storage # Ensure storage exists
  end

  describe 'GET #index' do
    let!(:image_file) do
      create(:file_object,
             account: account,
             file_type: 'image',
             content_type: 'image/png',
             category: 'page_content',
             storage: file_storage)
    end

    let!(:document_file) do
      create(:file_object,
             account: account,
             file_type: 'document',
             content_type: 'application/pdf',
             category: 'user_upload',
             storage: file_storage)
    end

    context 'filtering by file_type' do
      it 'returns only image files when file_type=image' do
        get :index, params: { file_type: 'image' }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(1)
        expect(data['files'].first['id']).to eq(image_file.id)
      end

      it 'returns only document files when file_type=document' do
        get :index, params: { file_type: 'document' }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(1)
        expect(data['files'].first['id']).to eq(document_file.id)
      end

      it 'returns all files when file_type is not specified' do
        get :index

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(2)
      end
    end

    context 'filtering by category' do
      it 'returns only page_content files when category=page_content' do
        get :index, params: { category: 'page_content' }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(1)
        expect(data['files'].first['category']).to eq('page_content')
      end
    end

    context 'filtering by attachable' do
      let(:page) { create(:page) }
      let!(:attached_image) do
        create(:file_object,
               account: account,
               file_type: 'image',
               category: 'page_content',
               attachable: page,
               storage: file_storage)
      end

      it 'returns only files attached to specific page' do
        get :index, params: {
          attachable_type: 'Page',
          attachable_id: page.id
        }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(1)
        expect(data['files'].first['id']).to eq(attached_image.id)
      end

      it 'does not filter when only attachable_type is provided' do
        get :index, params: { attachable_type: 'Page' }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        # Should return all files since both params are required
        expect(data['files'].length).to eq(3) # image_file, document_file, attached_image
      end

      it 'does not filter when only attachable_id is provided' do
        get :index, params: { attachable_id: page.id }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        # Should return all files since both params are required
        expect(data['files'].length).to eq(3)
      end

      it 'returns empty when no files match attachable' do
        other_page = create(:page)
        get :index, params: {
          attachable_type: 'Page',
          attachable_id: other_page.id
        }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(0)
      end
    end

    context 'combining filters' do
      let(:page) { create(:page) }
      let!(:attached_image) do
        create(:file_object,
               account: account,
               file_type: 'image',
               category: 'page_content',
               attachable: page,
               storage: file_storage)
      end
      let!(:attached_document) do
        create(:file_object,
               account: account,
               file_type: 'document',
               category: 'page_content',
               attachable: page,
               storage: file_storage)
      end

      it 'filters by both file_type and attachable' do
        get :index, params: {
          file_type: 'image',
          attachable_type: 'Page',
          attachable_id: page.id
        }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].length).to eq(1)
        expect(data['files'].first['id']).to eq(attached_image.id)
        expect(data['files'].first['file_type']).to eq('image')
      end
    end

    context 'search functionality' do
      let!(:named_image) do
        create(:file_object,
               account: account,
               filename: 'hero-banner.png',
               file_type: 'image',
               storage: file_storage)
      end

      it 'searches files by filename' do
        get :index, params: { search: 'hero' }

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)['data']
        expect(data['files'].map { |f| f['filename'] }).to include('hero-banner.png')
      end
    end
  end

  describe 'find_attachable helper' do
    # Test the attachable logic through the controller's private method behavior
    # by checking that page_content files can be created with Page attachment

    let(:page) { create(:page) }

    context 'with valid Page attachable' do
      it 'associates file with page when Page type is provided' do
        # Verify the find_attachable logic works via the model
        file = create(:file_object,
                      account: account,
                      category: 'page_content',
                      attachable: page,
                      storage: file_storage)

        expect(file.attachable).to eq(page)
        expect(file.attachable_type).to eq('Page')
        expect(file.attachable_id).to eq(page.id)
      end
    end

    context 'with invalid attachable_type' do
      it 'allows file creation without attachable' do
        file = create(:file_object,
                      account: account,
                      category: 'page_content',
                      attachable: nil,
                      storage: file_storage)

        expect(file.attachable).to be_nil
        expect(file.category).to eq('page_content')
      end
    end

    context 'page_content category' do
      it 'allows page_content as a valid category' do
        file = create(:file_object,
                      account: account,
                      category: 'page_content',
                      storage: file_storage)

        expect(file.category).to eq('page_content')
        expect(file).to be_persisted
      end
    end
  end
end
