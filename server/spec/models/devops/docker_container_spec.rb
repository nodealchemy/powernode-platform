# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::DockerContainer, type: :model do
  subject(:container) { build(:devops_docker_container) }

  describe 'associations' do
    it { is_expected.to belong_to(:docker_host) }
    it { is_expected.to have_many(:docker_activities).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:docker_container_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:image) }
    it { is_expected.to validate_presence_of(:state) }

    context 'docker_container_id uniqueness scoped to docker_host' do
      let(:host) { create(:devops_docker_host) }

      before { create(:devops_docker_container, docker_host: host, docker_container_id: 'abc123') }

      it 'rejects duplicate container IDs on the same host' do
        duplicate = build(:devops_docker_container, docker_host: host, docker_container_id: 'abc123')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:docker_container_id]).to include('has already been taken')
      end

      it 'allows same container ID on a different host' do
        other_host = create(:devops_docker_host)
        container = build(:devops_docker_container, docker_host: other_host, docker_container_id: 'abc123')
        expect(container).to be_valid
      end
    end

    context 'state inclusion' do
      it 'accepts valid states' do
        %w[created running paused restarting exited removing dead].each do |s|
          container.state = s
          expect(container).to be_valid
        end
      end

      it 'rejects invalid states' do
        container.state = 'invalid'
        expect(container).not_to be_valid
        expect(container.errors[:state]).to be_present
      end
    end
  end

  describe 'scopes' do
    let!(:running_container) { create(:devops_docker_container, :running) }
    let!(:exited_container) { create(:devops_docker_container, :exited) }
    let!(:paused_container) { create(:devops_docker_container, :paused) }

    describe '.running' do
      it 'returns only running containers' do
        expect(described_class.running).to include(running_container)
        expect(described_class.running).not_to include(exited_container)
      end
    end

    describe '.stopped' do
      it 'returns exited, created, and dead containers' do
        expect(described_class.stopped).to include(exited_container)
        expect(described_class.stopped).not_to include(running_container)
        expect(described_class.stopped).not_to include(paused_container)
      end
    end

    describe '.by_state' do
      it 'filters by state' do
        expect(described_class.by_state('paused')).to include(paused_container)
        expect(described_class.by_state('paused')).not_to include(running_container)
      end
    end
  end

  describe 'instance methods' do
    describe '#running?' do
      it 'returns true for running containers' do
        container = build(:devops_docker_container, :running)
        expect(container.running?).to be true
      end

      it 'returns false for non-running containers' do
        container = build(:devops_docker_container, :exited)
        expect(container.running?).to be false
      end
    end

    describe '#exited?' do
      it 'returns true for exited containers' do
        container = build(:devops_docker_container, :exited)
        expect(container.exited?).to be true
      end

      it 'returns false for running containers' do
        container = build(:devops_docker_container, :running)
        expect(container.exited?).to be false
      end
    end

    describe '#paused?' do
      it 'returns true for paused containers' do
        container = build(:devops_docker_container, :paused)
        expect(container.paused?).to be true
      end

      it 'returns false for running containers' do
        container = build(:devops_docker_container, :running)
        expect(container.paused?).to be false
      end
    end

    describe '#stopped?' do
      it 'returns true for exited containers' do
        container = build(:devops_docker_container, :exited)
        expect(container.stopped?).to be true
      end

      it 'returns true for dead containers' do
        container = build(:devops_docker_container, state: 'dead')
        expect(container.stopped?).to be true
      end

      it 'returns true for created containers' do
        container = build(:devops_docker_container, state: 'created')
        expect(container.stopped?).to be true
      end

      it 'returns false for running containers' do
        container = build(:devops_docker_container, :running)
        expect(container.stopped?).to be false
      end
    end

    describe '#container_summary' do
      it 'returns a hash with summary fields' do
        container = create(:devops_docker_container, :running)
        summary = container.container_summary

        expect(summary).to include(
          id: container.id,
          docker_container_id: container.docker_container_id,
          name: container.name,
          image: container.image,
          state: 'running'
        )
      end
    end

    describe '#container_details' do
      it 'returns summary merged with detail fields' do
        container = create(:devops_docker_container, :running)
        details = container.container_details

        expect(details).to include(:id, :name, :image, :state)
        expect(details).to include(:image_id, :mounts, :networks, :labels,
                                   :environment, :command, :restart_policy,
                                   :restart_count, :docker_host_id, :updated_at)
      end
    end
  end
end
