# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Devops::GitRepository, type: :model do
  subject(:repository) { build(:git_repository) }

  describe 'associations' do
    it { is_expected.to belong_to(:credential).without_validating_presence }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:provider).optional }
    it { is_expected.to have_many(:pipelines).dependent(:destroy) }
    it { is_expected.to have_many(:webhook_events).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:full_name) }
    it { is_expected.to validate_presence_of(:owner) }

    context 'uniqueness' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

      before do
        create(:git_repository, credential: credential, account: account, full_name: 'owner/repo1')
      end

      it 'validates full_name uniqueness per account' do
        duplicate = build(:git_repository, credential: credential, account: account, full_name: 'owner/repo1')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:full_name]).to include('repository already synced for this account')
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

    let!(:public_repo) { create(:git_repository, credential: credential, account: account, is_private: false) }
    let!(:private_repo) { create(:git_repository, :private, credential: credential, account: account) }
    let!(:archived_repo) { create(:git_repository, :archived, credential: credential, account: account) }
    let!(:webhook_repo) { create(:git_repository, :with_webhook, credential: credential, account: account) }

    describe '.public_repos' do
      it 'returns only public repositories' do
        expect(described_class.public_repos).to include(public_repo, webhook_repo)
        expect(described_class.public_repos).not_to include(private_repo)
      end
    end

    describe '.private_repos' do
      it 'returns only private repositories' do
        expect(described_class.private_repos).to include(private_repo)
        expect(described_class.private_repos).not_to include(public_repo)
      end
    end

    describe '.active' do
      it 'excludes archived repositories' do
        expect(described_class.active).to include(public_repo, private_repo, webhook_repo)
        expect(described_class.active).not_to include(archived_repo)
      end
    end

    describe '.with_webhook' do
      it 'returns repositories with webhooks configured' do
        expect(described_class.with_webhook).to include(webhook_repo)
        expect(described_class.with_webhook).not_to include(public_repo)
      end
    end

    describe '.with_webhooks (alias)' do
      it 'returns repositories with webhooks configured' do
        expect(described_class.with_webhooks).to include(webhook_repo)
      end
    end
  end

  describe 'instance methods' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider, :github) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

    describe '#provider_type' do
      it 'returns the provider type from the credential' do
        repo = build(:git_repository, credential: credential)
        expect(repo.provider_type).to eq('github')
      end
    end

    describe '#sync_needed?' do
      it 'returns true when never synced' do
        repo = build(:git_repository, last_synced_at: nil)
        expect(repo.sync_needed?).to be true
      end

      it 'returns true when last sync is older than 1 hour' do
        repo = build(:git_repository, last_synced_at: 2.hours.ago)
        expect(repo.sync_needed?).to be true
      end

      it 'returns false when recently synced' do
        repo = build(:git_repository, last_synced_at: 30.minutes.ago)
        expect(repo.sync_needed?).to be false
      end
    end

    describe '#needs_sync? (alias)' do
      it 'works like sync_needed?' do
        repo = build(:git_repository, last_synced_at: nil)
        expect(repo.needs_sync?).to be true
      end
    end

    describe '#mark_synced!' do
      let(:repo) { create(:git_repository, credential: credential, account: account, last_synced_at: nil) }

      it 'updates last_synced_at' do
        repo.mark_synced!
        expect(repo.last_synced_at).to be_within(1.second).of(Time.current)
      end
    end

    describe '#primary_language' do
      it 'returns the most used language' do
        repo = build(:git_repository, languages: { 'Ruby' => 70, 'JavaScript' => 30 })
        expect(repo.primary_language).to eq('Ruby')
      end

      it 'returns nil when no languages' do
        repo = build(:git_repository, languages: {})
        expect(repo.primary_language).to be_nil
      end
    end

    describe '#github?' do
      it 'returns true for github provider' do
        repo = build(:git_repository, credential: credential)
        expect(repo.github?).to be true
      end
    end

    describe '#latest_pipeline' do
      let(:repo) { create(:git_repository, credential: credential, account: account) }

      it 'returns the most recent pipeline' do
        old_pipeline = create(:git_pipeline, repository: repo, account: account, created_at: 1.day.ago)
        new_pipeline = create(:git_pipeline, repository: repo, account: account, created_at: 1.hour.ago)

        expect(repo.latest_pipeline).to eq(new_pipeline)
      end

      it 'returns nil when no pipelines' do
        expect(repo.latest_pipeline).to be_nil
      end
    end

    describe '#pipeline_stats' do
      let(:repo) { create(:git_repository, credential: credential, account: account) }

      it 'returns pipeline statistics' do
        create(:git_pipeline, :success, repository: repo, account: account)
        create(:git_pipeline, :success, repository: repo, account: account)
        create(:git_pipeline, :failure, repository: repo, account: account)

        stats = repo.pipeline_stats
        expect(stats[:total]).to eq(3)
        expect(stats[:successful]).to eq(2)
        expect(stats[:failed]).to eq(1)
        expect(stats[:success_rate]).to eq(66.67)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

      it 'generates webhook_secret' do
        repo = create(:git_repository, credential: credential, account: account, webhook_secret: nil)
        expect(repo.webhook_secret).to be_present
        expect(repo.webhook_secret.length).to eq(64)
      end
    end
  end
end
