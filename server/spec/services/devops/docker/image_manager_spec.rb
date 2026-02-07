# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::Docker::ImageManager do
  let(:account) { create(:account) }
  let(:host) { create(:devops_docker_host, :connected, account: account) }
  let(:user) { create(:user, account: account) }
  let(:manager) { described_class.new(host: host, user: user) }
  let(:image) { create(:devops_docker_image, docker_host: host) }

  describe '#pull_image' do
    let(:pull_result) { { "status" => "Downloaded newer image" } }
    let(:mock_image_list) do
      [
        {
          "Id" => "sha256:newimg001",
          "RepoTags" => ["nginx:latest"],
          "RepoDigests" => [],
          "Size" => 187_000_000,
          "VirtualSize" => 187_000_000,
          "Containers" => 0,
          "Labels" => {},
          "Created" => Time.current.to_i
        }
      ]
    end

    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull).and_return(pull_result)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_list).and_return(mock_image_list)
    end

    it 'calls API to pull image' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
        .with("nginx", "latest", auth_config: nil)
        .and_return(pull_result)

      manager.pull_image(image: "nginx", tag: "latest")
    end

    it 'creates an activity record' do
      expect {
        manager.pull_image(image: "nginx")
      }.to change(Devops::DockerActivity, :count).by(1)

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("pull")
      expect(activity.status).to eq("completed")
      expect(activity.triggered_by).to eq(user)
    end

    it 'syncs images after pull' do
      manager.pull_image(image: "nginx")

      synced_image = host.docker_images.find_by(docker_image_id: "sha256:newimg001")
      expect(synced_image).to be_present
    end

    context 'with credential_id' do
      let(:git_provider) { create(:git_provider, provider_type: "github") }
      let(:credential) do
        create(:git_provider_credential,
          name: "GitHub Registry",
          provider: git_provider,
          account: account,
          user: user
        )
      end

      it 'creates RegistryService and passes auth_config' do
        registry_service = instance_double(Devops::Docker::RegistryService)
        allow(Devops::Docker::RegistryService).to receive(:new).and_return(registry_service)
        allow(registry_service).to receive(:docker_auth_config).and_return("base64encodedauth")

        expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
          .with("ghcr.io/org/app", "latest", auth_config: "base64encodedauth")

        manager.pull_image(image: "ghcr.io/org/app", tag: "latest", credential_id: credential.id)
      end
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_pull)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Pull access denied"))
      end

      it 'marks activity as failed and re-raises' do
        expect {
          manager.pull_image(image: "private/image")
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        activity = Devops::DockerActivity.last
        expect(activity.status).to eq("failed")
      end
    end
  end

  describe '#remove_image' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove).and_return({})
    end

    it 'calls API to remove image' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove)
        .with(image.docker_image_id, force: false)

      manager.remove_image(image)
    end

    it 'creates activity and destroys image record' do
      image_id = image.id

      manager.remove_image(image)

      expect(Devops::DockerImage.find_by(id: image_id)).to be_nil

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("image_remove")
      expect(activity.status).to eq("completed")
    end

    it 'supports force removal' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove)
        .with(image.docker_image_id, force: true)

      manager.remove_image(image, force: true)
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_remove)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("Image in use"))
      end

      it 'marks activity as failed and does not destroy record' do
        expect {
          manager.remove_image(image)
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        expect(image.reload).to be_present
      end
    end
  end

  describe '#tag_image' do
    before do
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_tag).and_return(nil)
      allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_inspect).and_return(
        {
          "RepoTags" => ["nginx:latest", "myrepo/nginx:v2"],
          "RepoDigests" => [],
          "Size" => 187_000_000,
          "Architecture" => "amd64",
          "Os" => "linux"
        }
      )
    end

    it 'calls API with repo and tag' do
      expect_any_instance_of(Devops::Docker::ApiClient).to receive(:image_tag)
        .with(image.docker_image_id, "myrepo/nginx", "v2")

      manager.tag_image(image, repo: "myrepo/nginx", tag: "v2")
    end

    it 'creates activity record' do
      manager.tag_image(image, repo: "myrepo/nginx", tag: "v2")

      activity = Devops::DockerActivity.last
      expect(activity.activity_type).to eq("image_tag")
      expect(activity.status).to eq("completed")
      expect(activity.params).to include("repo" => "myrepo/nginx", "tag" => "v2")
    end

    it 'refreshes image data' do
      manager.tag_image(image, repo: "myrepo/nginx", tag: "v2")

      image.reload
      expect(image.repo_tags).to include("myrepo/nginx:v2")
    end

    context 'when API error occurs' do
      before do
        allow_any_instance_of(Devops::Docker::ApiClient).to receive(:image_tag)
          .and_raise(Devops::Docker::ApiClient::ApiError.new("No such image"))
      end

      it 'marks activity as failed and re-raises' do
        expect {
          manager.tag_image(image, repo: "repo", tag: "tag")
        }.to raise_error(Devops::Docker::ApiClient::ApiError)

        expect(Devops::DockerActivity.last.status).to eq("failed")
      end
    end
  end
end
