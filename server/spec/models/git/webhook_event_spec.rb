# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::WebhookEvent, type: :model do
  subject(:event) { build(:git_webhook_event) }

  describe 'associations' do
    it { is_expected.to belong_to(:git_provider) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:repository).optional }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:event_type) }
    it { is_expected.to validate_presence_of(:payload) }

    it 'validates status inclusion' do
      valid_statuses = %w[pending processing processed failed]
      valid_statuses.each do |status|
        event = build(:git_webhook_event, status: status)
        expect(event).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:repo) { create(:git_repository, credential: credential, account: account) }

    let!(:pending_event) { create(:git_webhook_event, :pending, git_provider: provider, account: account, repository: repo) }
    let!(:processing_event) { create(:git_webhook_event, :processing, git_provider: provider, account: account, repository: repo) }
    let!(:processed_event) { create(:git_webhook_event, :processed, git_provider: provider, account: account, repository: repo) }
    let!(:failed_event) { create(:git_webhook_event, :failed, git_provider: provider, account: account, repository: repo) }

    describe '.pending' do
      it 'returns only pending events' do
        expect(described_class.pending).to include(pending_event)
        expect(described_class.pending).not_to include(processed_event, failed_event)
      end
    end

    describe '.processing' do
      it 'returns only processing events' do
        expect(described_class.processing).to include(processing_event)
        expect(described_class.processing).not_to include(pending_event)
      end
    end

    describe '.processed' do
      it 'returns only processed events' do
        expect(described_class.processed).to include(processed_event)
        expect(described_class.processed).not_to include(pending_event)
      end
    end

    describe '.failed' do
      it 'returns only failed events' do
        expect(described_class.failed).to include(failed_event)
        expect(described_class.failed).not_to include(processed_event)
      end
    end

    describe '.unprocessed' do
      it 'returns pending and processing events' do
        expect(described_class.unprocessed).to include(pending_event, processing_event)
        expect(described_class.unprocessed).not_to include(processed_event, failed_event)
      end
    end

    describe '.retryable' do
      let!(:retryable_event) { create(:git_webhook_event, :retrying, git_provider: provider, account: account, repository: repo) }
      let!(:max_retries_event) { create(:git_webhook_event, :max_retries, git_provider: provider, account: account, repository: repo) }

      it 'returns failed events that can be retried' do
        expect(described_class.retryable).to include(retryable_event)
      end

      it 'excludes events at max retry count' do
        expect(described_class.retryable).not_to include(max_retries_event)
      end
    end

    describe '.by_event_type' do
      let!(:push_event) { create(:git_webhook_event, :push, git_provider: provider, account: account, repository: repo) }
      let!(:pr_event) { create(:git_webhook_event, :pull_request, git_provider: provider, account: account, repository: repo) }

      it 'filters by event type' do
        expect(described_class.by_event_type('push')).to include(push_event)
        expect(described_class.by_event_type('push')).not_to include(pr_event)
      end
    end

    describe '.by_type (alias)' do
      let!(:push_event) { create(:git_webhook_event, :push, git_provider: provider, account: account, repository: repo) }

      it 'works like by_event_type' do
        expect(described_class.by_type('push')).to include(push_event)
      end
    end

    describe '.by_action' do
      let!(:opened_event) { create(:git_webhook_event, :pull_request, action: 'opened', git_provider: provider, account: account, repository: repo) }
      let!(:closed_event) { create(:git_webhook_event, :pull_request, action: 'closed', git_provider: provider, account: account, repository: repo) }

      it 'filters by action' do
        expect(described_class.by_action('opened')).to include(opened_event)
        expect(described_class.by_action('opened')).not_to include(closed_event)
      end
    end

    describe '.recent' do
      it 'returns events ordered by created_at desc with limit' do
        result = described_class.recent(2)
        expect(result.count).to eq(2)
      end
    end

    describe '.for_repository' do
      let(:other_repo) { create(:git_repository, credential: credential, account: account) }
      let!(:other_event) { create(:git_webhook_event, git_provider: provider, account: account, repository: other_repo) }

      it 'filters by repository' do
        expect(described_class.for_repository(repo)).to include(pending_event)
        expect(described_class.for_repository(repo)).not_to include(other_event)
      end
    end
  end

  describe 'instance methods' do
    describe 'status predicates' do
      it '#pending? returns true for pending events' do
        event = build(:git_webhook_event, :pending)
        expect(event.pending?).to be true
        expect(event.processed?).to be false
      end

      it '#processing? returns true for processing events' do
        event = build(:git_webhook_event, :processing)
        expect(event.processing?).to be true
      end

      it '#processed? returns true for processed events' do
        event = build(:git_webhook_event, :processed)
        expect(event.processed?).to be true
      end

      it '#failed? returns true for failed events' do
        event = build(:git_webhook_event, :failed)
        expect(event.failed?).to be true
      end
    end

    describe '#retryable?' do
      it 'returns true for failed events under max retries' do
        event = build(:git_webhook_event, :failed)
        expect(event.retryable?).to be true
      end

      it 'returns false for events at max retries' do
        event = build(:git_webhook_event, :max_retries)
        expect(event.retryable?).to be false
      end

      it 'returns false for processed events' do
        event = build(:git_webhook_event, :processed)
        expect(event.retryable?).to be false
      end
    end

    describe '#can_retry? (alias)' do
      it 'works like retryable?' do
        event = build(:git_webhook_event, :failed)
        expect(event.can_retry?).to be true
      end
    end

    describe '#mark_processing!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:event) { create(:git_webhook_event, :pending, git_provider: provider, account: account) }

      it 'transitions to processing status' do
        event.mark_processing!
        expect(event.status).to eq('processing')
      end
    end

    describe '#mark_processed!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:event) { create(:git_webhook_event, :processing, git_provider: provider, account: account) }

      it 'transitions to processed status with result' do
        event.mark_processed!({ success: true })

        expect(event.status).to eq('processed')
        expect(event.processed_at).to be_present
        expect(event.processing_result).to eq({ 'success' => true })
      end
    end

    describe '#mark_failed!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:event) { create(:git_webhook_event, :processing, git_provider: provider, account: account) }

      it 'transitions to failed status and increments retry count' do
        event.mark_failed!('Processing error')

        expect(event.status).to eq('failed')
        expect(event.error_message).to eq('Processing error')
        expect(event.retry_count).to eq(1)
      end
    end

    describe '#retry!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:event) { create(:git_webhook_event, :failed, git_provider: provider, account: account) }

      before do
        # Stub the job class since it lives in the worker service
        stub_const('Git::WebhookProcessingJob', Class.new do
          def self.perform_async(*_args)
            true
          end
        end)
      end

      it 'resets to pending status' do
        event.retry!
        expect(event.status).to eq('pending')
      end

      it 'raises error when max retries exceeded' do
        event.update!(retry_count: 3)
        expect { event.retry! }.to raise_error(StandardError, /Max retries exceeded/)
      end
    end

    describe '#push_event?' do
      it 'returns true for push events' do
        event = build(:git_webhook_event, :push)
        expect(event.push_event?).to be true
      end

      it 'returns false for other events' do
        event = build(:git_webhook_event, :pull_request)
        expect(event.push_event?).to be false
      end
    end

    describe '#pull_request_event?' do
      it 'returns true for PR events' do
        event = build(:git_webhook_event, :pull_request)
        expect(event.pull_request_event?).to be true
      end
    end

    describe '#workflow_event?' do
      it 'returns true for workflow events' do
        event = build(:git_webhook_event, :workflow_run)
        expect(event.workflow_event?).to be true
      end

      it 'returns false for non-workflow events' do
        event = build(:git_webhook_event, :push)
        expect(event.workflow_event?).to be false
      end
    end

    describe '#ci_event?' do
      it 'returns true for CI-related events' do
        %w[workflow_run workflow_job check_run check_suite].each do |type|
          event = build(:git_webhook_event, event_type: type)
          expect(event.ci_event?).to be true
        end
      end

      it 'returns false for non-CI events' do
        event = build(:git_webhook_event, :push)
        expect(event.ci_event?).to be false
      end
    end

    describe '#repository_full_name' do
      it 'extracts repository name from payload' do
        event = build(:git_webhook_event, payload: { 'repository' => { 'full_name' => 'owner/repo' } })
        expect(event.repository_full_name).to eq('owner/repo')
      end

      it 'returns nil when not in payload' do
        event = build(:git_webhook_event, payload: {})
        expect(event.repository_full_name).to be_nil
      end
    end

    describe '#commit_sha' do
      it 'returns sha when present' do
        event = build(:git_webhook_event, sha: 'abc123')
        expect(event.commit_sha).to eq('abc123')
      end

      it 'falls back to head_commit id' do
        event = build(:git_webhook_event, sha: nil, payload: { 'head_commit' => { 'id' => 'def456' } })
        expect(event.commit_sha).to eq('def456')
      end

      it 'falls back to after field' do
        event = build(:git_webhook_event, sha: nil, payload: { 'after' => 'ghi789' })
        expect(event.commit_sha).to eq('ghi789')
      end
    end

    describe '#branch_name' do
      it 'extracts branch name from ref' do
        event = build(:git_webhook_event, ref: 'refs/heads/main')
        expect(event.branch_name).to eq('main')
      end

      it 'returns nil when ref is nil' do
        event = build(:git_webhook_event, ref: nil)
        expect(event.branch_name).to be_nil
      end
    end

    describe '#tag_name' do
      it 'extracts tag name from ref' do
        event = build(:git_webhook_event, ref: 'refs/tags/v1.0.0')
        expect(event.tag_name).to eq('v1.0.0')
      end

      it 'returns nil for non-tag refs' do
        event = build(:git_webhook_event, ref: 'refs/heads/main')
        expect(event.tag_name).to be_nil
      end
    end

    describe '#sender_info' do
      it 'returns sender information' do
        event = build(:git_webhook_event,
          sender_username: 'testuser',
          payload: { 'sender' => { 'avatar_url' => 'https://example.com/avatar.png' } }
        )
        info = event.sender_info
        expect(info[:username]).to eq('testuser')
        expect(info[:avatar_url]).to eq('https://example.com/avatar.png')
      end
    end

    describe '#payload_summary' do
      it 'summarizes push events' do
        event = build(:git_webhook_event, :push, ref: 'refs/heads/main',
          payload: { 'commits' => [{ id: '1' }, { id: '2' }], 'ref' => 'refs/heads/main' }
        )
        expect(event.payload_summary).to eq('2 commit(s) to main')
      end

      it 'summarizes pull request events' do
        event = build(:git_webhook_event, event_type: 'pull_request', action: 'opened',
          payload: { 'pull_request' => { 'number' => 42 } }
        )
        expect(event.payload_summary).to eq('PR #42: opened')
      end

      it 'summarizes workflow run events' do
        event = build(:git_webhook_event, event_type: 'workflow_run',
          payload: { 'workflow_run' => { 'name' => 'CI', 'conclusion' => 'success' } }
        )
        expect(event.payload_summary).to eq('Workflow: CI - success')
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }

      it 'sets default status to pending' do
        event = create(:git_webhook_event, status: nil, git_provider: provider, account: account)
        expect(event.status).to eq('pending')
      end

      it 'generates delivery_id if not provided' do
        event = create(:git_webhook_event, delivery_id: nil, git_provider: provider, account: account)
        expect(event.delivery_id).to be_present
      end

      it 'preserves provided delivery_id' do
        event = create(:git_webhook_event, delivery_id: 'custom-id', git_provider: provider, account: account)
        expect(event.delivery_id).to eq('custom-id')
      end
    end
  end
end
