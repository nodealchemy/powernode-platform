# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Api::V1::Devops::Docker::Images', type: :request do
  let(:account) { create(:account) }
  let(:user_with_read) { create(:user, account: account, permissions: ['docker.images.read']) }
  let(:user_with_manage) { create(:user, account: account, permissions: ['docker.images.read', 'docker.images.pull', 'docker.images.delete', 'docker.images.tag']) }
  let(:regular_user) { create(:user, account: account, permissions: []) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }

  describe 'GET /api/v1/devops/docker/hosts/:host_id/images' do
    let(:headers) { auth_headers_for(user_with_read) }

    before do
      create_list(:devops_docker_image, 3, docker_host: host)
    end

    it 'returns list of images' do
      get "/api/v1/devops/docker/hosts/#{host.id}/images", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
      expect(response_data['data']['items'].length).to eq(3)
    end

    it 'filters dangling images' do
      create(:devops_docker_image, :dangling, docker_host: host)

      get "/api/v1/devops/docker/hosts/#{host.id}/images?dangling=true",
          headers: headers, as: :json

      expect_success_response
    end

    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v1/devops/docker/hosts/#{host.id}/images", as: :json

        expect_error_response('Access token required', 401)
      end
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/images/:id' do
    let(:headers) { auth_headers_for(user_with_read) }
    let(:image) { create(:devops_docker_image, docker_host: host) }

    it 'returns image details' do
      get "/api/v1/devops/docker/hosts/#{host.id}/images/#{image.id}", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['image']['id']).to eq(image.id)
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/images/pull' do
    let(:headers) { auth_headers_for(user_with_manage) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
        .and_return({ "status" => "Downloaded newer image" })
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_list).and_return([])
    end

    it 'pulls an image' do
      post "/api/v1/devops/docker/hosts/#{host.id}/images/pull",
           params: { image: 'nginx', tag: 'latest' },
           headers: headers, as: :json

      expect_success_response
    end

    it 'defaults tag to latest' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
        .with("nginx", "latest", auth_config: nil)
        .and_return({})

      post "/api/v1/devops/docker/hosts/#{host.id}/images/pull",
           params: { image: 'nginx' },
           headers: headers, as: :json
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Pull access denied"))
      end

      it 'returns error' do
        post "/api/v1/devops/docker/hosts/#{host.id}/images/pull",
             params: { image: 'private/image' },
             headers: headers, as: :json

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe 'DELETE /api/v1/devops/docker/hosts/:host_id/images/:id' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:image) { create(:devops_docker_image, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove).and_return({})
    end

    it 'removes the image' do
      image_id = image.id

      delete "/api/v1/devops/docker/hosts/#{host.id}/images/#{image_id}",
             headers: headers, as: :json

      expect_success_response
      expect(Devops::DockerImage.find_by(id: image_id)).to be_nil
    end

    it 'supports force removal' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove)
        .with(image.docker_image_id, force: true)

      delete "/api/v1/devops/docker/hosts/#{host.id}/images/#{image.id}",
             params: { force: 'true' },
             headers: headers, as: :json

      expect_success_response
    end
  end

  describe 'POST /api/v1/devops/docker/hosts/:host_id/images/:id/tag' do
    let(:headers) { auth_headers_for(user_with_manage) }
    let(:image) { create(:devops_docker_image, docker_host: host) }

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_tag).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_inspect).and_return(
        { "RepoTags" => ["myrepo/nginx:v2"], "RepoDigests" => [], "Size" => 187_000_000, "Architecture" => "amd64", "Os" => "linux" }
      )
    end

    it 'tags the image' do
      post "/api/v1/devops/docker/hosts/#{host.id}/images/#{image.id}/tag",
           params: { repo: 'myrepo/nginx', tag: 'v2' },
           headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['image']).to be_present
    end
  end

  describe 'GET /api/v1/devops/docker/hosts/:host_id/images/registries' do
    let(:headers) { auth_headers_for(user_with_read) }

    it 'returns available registries' do
      get "/api/v1/devops/docker/hosts/#{host.id}/images/registries", headers: headers, as: :json

      expect_success_response
      response_data = json_response
      expect(response_data['data']['items']).to be_an(Array)
    end
  end
end
