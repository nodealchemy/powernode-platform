# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Api::V1::Devops::ContainerTemplatesController, type: :controller do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  before { sign_in_as_user(user) }

  describe 'POST #create_image_repo (cross-account isolation)' do
    let(:repo_service) { instance_spy(Devops::ContainerImageRepoService) }

    before do
      allow(Devops::ContainerImageRepoService).to receive(:new).and_return(repo_service)
    end

    it 'creates a repo using a parent template owned by the current account' do
      parent = create(:devops_container_template, account: account)
      result_template = create(:devops_container_template, account: account)
      allow(repo_service).to receive(:create_image_repo).and_return(
        template: result_template, repository: { 'name' => 'repo' }, files_created: []
      )

      post :create_image_repo, params: {
        image_repo: { name: 'my-repo', variant_type: 'base', parent_template_id: parent.id }
      }

      expect(response).to have_http_status(:created)
    end

    it 'does not allow another account\'s private parent_template_id (IDOR)' do
      other_account = create(:account)
      foreign_parent = create(:devops_container_template, account: other_account, visibility: 'private')

      post :create_image_repo, params: {
        image_repo: { name: 'my-repo', variant_type: 'base', parent_template_id: foreign_parent.id }
      }

      expect(response).to have_http_status(:not_found)
      expect(repo_service).not_to have_received(:create_image_repo)
    end
  end
end
