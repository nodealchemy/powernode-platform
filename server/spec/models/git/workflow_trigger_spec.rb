# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::WorkflowTrigger, type: :model do
  subject(:trigger) { build(:git_workflow_trigger) }

  describe 'associations' do
    it { is_expected.to belong_to(:ai_workflow_trigger) }
    it { is_expected.to belong_to(:repository).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:branch_pattern) }
    it { is_expected.to validate_presence_of(:status) }

    context 'event_type inclusion' do
      it 'accepts valid event types' do
        valid_types = %w[push pull_request workflow_run check_run release tag]

        valid_types.each do |type|
          trigger = build(:git_workflow_trigger, event_type: type)
          expect(trigger).to be_valid
        end
      end

      it 'rejects invalid event types' do
        trigger = build(:git_workflow_trigger, event_type: 'invalid_event')
        expect(trigger).not_to be_valid
        expect(trigger.errors[:event_type]).to include('must be a valid git event type')
      end
    end

    context 'status inclusion' do
      it 'accepts valid statuses' do
        %w[active paused disabled error].each do |status|
          trigger = build(:git_workflow_trigger, status: status)
          expect(trigger).to be_valid
        end
      end

      it 'rejects invalid statuses' do
        trigger = build(:git_workflow_trigger, status: 'unknown')
        expect(trigger).not_to be_valid
        expect(trigger.errors[:status]).to include('must be a valid status')
      end
    end
  end

  describe 'scopes' do
    let!(:active_trigger) { create(:git_workflow_trigger, is_active: true, status: 'active') }
    let!(:paused_trigger) { create(:git_workflow_trigger, :paused) }
    let!(:push_trigger) { create(:git_workflow_trigger, :push) }
    let!(:pr_trigger) { create(:git_workflow_trigger, :pull_request) }

    describe '.active' do
      it 'returns only active triggers' do
        expect(described_class.active).to include(active_trigger)
        expect(described_class.active).not_to include(paused_trigger)
      end
    end

    describe '.for_event' do
      it 'filters by event type' do
        expect(described_class.for_event('push')).to include(push_trigger)
        expect(described_class.for_event('push')).not_to include(pr_trigger)
      end
    end
  end

  describe '#active?' do
    context 'when trigger is active' do
      let(:trigger) { create(:git_workflow_trigger, is_active: true, status: 'active') }

      it 'returns true' do
        expect(trigger.active?).to be true
      end
    end

    context 'when trigger is paused' do
      let(:trigger) { create(:git_workflow_trigger, :paused) }

      it 'returns false' do
        expect(trigger.active?).to be false
      end
    end
  end

  describe '#matches_event?' do
    let(:trigger) { create(:git_workflow_trigger, event_type: 'push', branch_pattern: 'main') }

    context 'when event matches' do
      let(:webhook_event) do
        instance_double(
          Git::WebhookEvent,
          event_type: 'push',
          git_repository_id: nil,
          payload: { 'ref' => 'refs/heads/main' }
        )
      end

      it 'returns true' do
        expect(trigger.matches_event?(webhook_event)).to be true
      end
    end

    context 'when event type does not match' do
      let(:webhook_event) do
        instance_double(
          Git::WebhookEvent,
          event_type: 'pull_request',
          git_repository_id: nil,
          payload: { 'ref' => 'refs/heads/main' }
        )
      end

      it 'returns false' do
        expect(trigger.matches_event?(webhook_event)).to be false
      end
    end

    context 'when branch does not match' do
      let(:webhook_event) do
        instance_double(
          Git::WebhookEvent,
          event_type: 'push',
          git_repository_id: nil,
          payload: { 'ref' => 'refs/heads/develop' }
        )
      end

      it 'returns false' do
        expect(trigger.matches_event?(webhook_event)).to be false
      end
    end
  end

  describe '#extract_variables' do
    let(:trigger) do
      create(:git_workflow_trigger, :with_payload_mapping, event_type: 'push')
    end

    let(:webhook_event) do
      instance_double(
        Git::WebhookEvent,
        id: 'event-123',
        event_type: 'push',
        provider: 'github',
        git_repository_id: 'repo-123',
        payload: {
          'ref' => 'refs/heads/main',
          'head_commit' => {
            'id' => 'abc123def',
            'message' => 'Fix bug in payment processing',
            'author' => { 'name' => 'Test User' }
          },
          'repository' => { 'full_name' => 'owner/repo' }
        }
      )
    end

    it 'extracts variables from payload' do
      variables = trigger.extract_variables(webhook_event)

      expect(variables['commit_sha']).to eq('abc123def')
      expect(variables['commit_message']).to eq('Fix bug in payment processing')
      expect(variables['branch']).to eq('refs/heads/main')
      expect(variables['author']).to eq('Test User')
    end

    it 'includes standard git context variables' do
      variables = trigger.extract_variables(webhook_event)

      expect(variables['git_event_type']).to eq('push')
      expect(variables['git_provider']).to eq('github')
      expect(variables['git_repository_id']).to eq('repo-123')
    end
  end

  describe '#activate!' do
    let(:trigger) { create(:git_workflow_trigger, :paused) }

    it 'sets status to active' do
      trigger.activate!
      expect(trigger.reload.status).to eq('active')
      expect(trigger.is_active).to be true
    end
  end

  describe '#pause!' do
    let(:trigger) { create(:git_workflow_trigger) }

    it 'sets status to paused' do
      trigger.pause!
      expect(trigger.reload.status).to eq('paused')
    end
  end

  describe '#disable!' do
    let(:trigger) { create(:git_workflow_trigger) }

    it 'sets status to disabled and deactivates' do
      trigger.disable!
      expect(trigger.reload.status).to eq('disabled')
      expect(trigger.is_active).to be false
    end
  end

  describe 'branch pattern matching' do
    describe 'with wildcard pattern' do
      let(:trigger) { create(:git_workflow_trigger, branch_pattern: 'feature/*') }

      it 'matches feature branches' do
        webhook_event = instance_double(
          Git::WebhookEvent,
          event_type: 'push',
          git_repository_id: nil,
          payload: { 'ref' => 'refs/heads/feature/new-login' }
        )
        expect(trigger.matches_event?(webhook_event)).to be true
      end

      it 'does not match other branches' do
        webhook_event = instance_double(
          Git::WebhookEvent,
          event_type: 'push',
          git_repository_id: nil,
          payload: { 'ref' => 'refs/heads/main' }
        )
        expect(trigger.matches_event?(webhook_event)).to be false
      end
    end

    describe 'with catch-all pattern' do
      let(:trigger) { create(:git_workflow_trigger, branch_pattern: '*') }

      it 'matches any branch' do
        %w[main develop feature/test release/1.0].each do |branch|
          webhook_event = instance_double(
            Git::WebhookEvent,
            event_type: 'push',
            git_repository_id: nil,
            payload: { 'ref' => "refs/heads/#{branch}" }
          )
          expect(trigger.matches_event?(webhook_event)).to be true
        end
      end
    end
  end
end
