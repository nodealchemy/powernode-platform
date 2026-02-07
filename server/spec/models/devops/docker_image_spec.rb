# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::DockerImage, type: :model do
  subject(:image) { build(:devops_docker_image) }

  describe 'associations' do
    it { is_expected.to belong_to(:docker_host) }
    it { is_expected.to have_many(:docker_activities).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:docker_image_id) }

    context 'docker_image_id uniqueness scoped to docker_host' do
      let(:host) { create(:devops_docker_host) }

      before { create(:devops_docker_image, docker_host: host, docker_image_id: 'sha256:abc123') }

      it 'rejects duplicate image IDs on the same host' do
        duplicate = build(:devops_docker_image, docker_host: host, docker_image_id: 'sha256:abc123')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:docker_image_id]).to include('has already been taken')
      end

      it 'allows same image ID on a different host' do
        other_host = create(:devops_docker_host)
        img = build(:devops_docker_image, docker_host: other_host, docker_image_id: 'sha256:abc123')
        expect(img).to be_valid
      end
    end
  end

  describe 'instance methods' do
    describe '#primary_tag' do
      it 'returns the first valid tag' do
        image = build(:devops_docker_image, :with_tags)
        expect(image.primary_tag).to eq('nginx:latest')
      end

      it 'returns "<none>" for dangling images' do
        image = build(:devops_docker_image, :dangling)
        expect(image.primary_tag).to eq('<none>')
      end

      it 'returns "<none>" when repo_tags is nil' do
        image = build(:devops_docker_image, repo_tags: nil)
        expect(image.primary_tag).to eq('<none>')
      end

      it 'skips blank and <none>:<none> tags' do
        image = build(:devops_docker_image, repo_tags: ['<none>:<none>', '', 'myapp:v1'])
        expect(image.primary_tag).to eq('myapp:v1')
      end
    end

    describe '#size_mb' do
      it 'converts bytes to megabytes' do
        image = build(:devops_docker_image, size_bytes: 187_000_000)
        expect(image.size_mb).to eq(178.3)
      end

      it 'returns nil when size_bytes is nil' do
        image = build(:devops_docker_image, size_bytes: nil)
        expect(image.size_mb).to be_nil
      end
    end

    describe '#dangling?' do
      it 'returns true for empty repo_tags' do
        image = build(:devops_docker_image, :dangling)
        expect(image.dangling?).to be true
      end

      it 'returns true for nil repo_tags' do
        image = build(:devops_docker_image, repo_tags: nil)
        expect(image.dangling?).to be true
      end

      it 'returns true when all tags are blank or <none>' do
        image = build(:devops_docker_image, repo_tags: ['<none>:<none>', ''])
        expect(image.dangling?).to be true
      end

      it 'returns false for images with valid tags' do
        image = build(:devops_docker_image, :with_tags)
        expect(image.dangling?).to be false
      end
    end

    describe '#image_summary' do
      it 'returns a hash with summary fields' do
        image = create(:devops_docker_image)
        summary = image.image_summary

        expect(summary).to include(
          id: image.id,
          docker_image_id: image.docker_image_id,
          repo_tags: image.repo_tags,
          size_bytes: image.size_bytes,
          size_mb: image.size_mb
        )
      end
    end

    describe '#image_details' do
      it 'returns summary merged with detail fields' do
        image = create(:devops_docker_image)
        details = image.image_details

        expect(details).to include(:id, :docker_image_id, :repo_tags, :size_bytes)
        expect(details).to include(:repo_digests, :virtual_size, :architecture,
                                   :os, :labels, :last_seen_at, :docker_host_id,
                                   :updated_at)
      end
    end
  end
end
