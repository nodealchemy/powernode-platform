# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::DockerActivity, type: :model do
  subject(:activity) { build(:devops_docker_activity) }

  describe 'associations' do
    it { is_expected.to belong_to(:docker_host) }
    it { is_expected.to belong_to(:container).optional }
    it { is_expected.to belong_to(:image).optional }
    it { is_expected.to belong_to(:triggered_by).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:activity_type) }
    it { is_expected.to validate_presence_of(:status) }

    context 'activity_type inclusion' do
      it 'accepts valid activity types' do
        %w[create start stop restart remove pull image_remove image_tag].each do |type|
          activity.activity_type = type
          expect(activity).to be_valid
        end
      end

      it 'rejects invalid activity types' do
        activity.activity_type = 'invalid'
        expect(activity).not_to be_valid
        expect(activity.errors[:activity_type]).to be_present
      end
    end

    context 'status inclusion' do
      it 'accepts valid statuses' do
        %w[pending running completed failed].each do |s|
          activity.status = s
          expect(activity).to be_valid
        end
      end

      it 'rejects invalid statuses' do
        activity.status = 'invalid'
        expect(activity).not_to be_valid
        expect(activity.errors[:status]).to be_present
      end
    end
  end

  describe 'scopes' do
    let(:host) { create(:devops_docker_host) }
    let(:container) { create(:devops_docker_container, docker_host: host) }
    let(:image) { create(:devops_docker_image, docker_host: host) }
    let!(:create_activity) { create(:devops_docker_activity, docker_host: host, activity_type: 'create', container: container) }
    let!(:pull_activity) { create(:devops_docker_activity, docker_host: host, activity_type: 'pull', image: image) }

    describe '.recent' do
      it 'orders by created_at descending' do
        results = described_class.recent
        expect(results.first.created_at).to be >= results.last.created_at
      end
    end

    describe '.by_type' do
      it 'filters by activity type' do
        expect(described_class.by_type('create')).to include(create_activity)
        expect(described_class.by_type('create')).not_to include(pull_activity)
      end
    end

    describe '.for_container' do
      it 'filters by container' do
        expect(described_class.for_container(container.id)).to include(create_activity)
        expect(described_class.for_container(container.id)).not_to include(pull_activity)
      end
    end

    describe '.for_image' do
      it 'filters by image' do
        expect(described_class.for_image(image.id)).to include(pull_activity)
        expect(described_class.for_image(image.id)).not_to include(create_activity)
      end
    end
  end

  describe 'instance methods' do
    describe '#start!' do
      it 'sets status to running and started_at' do
        activity = create(:devops_docker_activity)
        activity.start!
        activity.reload

        expect(activity.status).to eq('running')
        expect(activity.started_at).to be_within(2.seconds).of(Time.current)
      end
    end

    describe '#complete!' do
      it 'sets status to completed, completed_at, and duration_ms' do
        activity = create(:devops_docker_activity, :running)
        activity.complete!
        activity.reload

        expect(activity.status).to eq('completed')
        expect(activity.completed_at).to be_within(2.seconds).of(Time.current)
        expect(activity.duration_ms).to be_a(Integer)
      end

      it 'accepts optional result data' do
        activity = create(:devops_docker_activity, :running)
        activity.complete!({ 'message' => 'success' })
        activity.reload

        expect(activity.result).to eq({ 'message' => 'success' })
      end
    end

    describe '#fail!' do
      it 'sets status to failed, completed_at, and duration_ms' do
        activity = create(:devops_docker_activity, :running)
        activity.fail!
        activity.reload

        expect(activity.status).to eq('failed')
        expect(activity.completed_at).to be_within(2.seconds).of(Time.current)
        expect(activity.duration_ms).to be_a(Integer)
      end

      it 'accepts optional error data' do
        activity = create(:devops_docker_activity, :running)
        activity.fail!({ 'error' => 'timeout' })
        activity.reload

        expect(activity.result).to eq({ 'error' => 'timeout' })
      end
    end

    describe '#activity_summary' do
      it 'returns a hash with summary fields' do
        activity = create(:devops_docker_activity, :completed)
        summary = activity.activity_summary

        expect(summary).to include(
          id: activity.id,
          activity_type: activity.activity_type,
          status: 'completed',
          started_at: activity.started_at,
          completed_at: activity.completed_at,
          duration_ms: activity.duration_ms
        )
      end
    end

    describe '#activity_details' do
      it 'returns summary merged with detail fields' do
        activity = create(:devops_docker_activity, :completed)
        details = activity.activity_details

        expect(details).to include(:id, :activity_type, :status)
        expect(details).to include(:params, :result, :docker_host_id)
      end
    end
  end
end
