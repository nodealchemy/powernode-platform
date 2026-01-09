# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::Runner, type: :model do
  subject(:runner) { build(:git_runner) }

  describe 'associations' do
    it { is_expected.to belong_to(:credential) }
    it { is_expected.to belong_to(:repository).optional }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_one(:provider).through(:credential) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:external_id) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_presence_of(:runner_scope) }
    it { is_expected.to validate_length_of(:name).is_at_most(255) }

    it 'validates status inclusion' do
      Git::Runner::STATUSES.each do |status|
        runner = build(:git_runner, status: status)
        expect(runner).to be_valid
      end
    end

    it 'validates runner_scope inclusion' do
      Git::Runner::SCOPES.each do |scope|
        runner = build(:git_runner, runner_scope: scope)
        expect(runner).to be_valid
      end
    end

    it 'validates external_id uniqueness scoped to credential' do
      existing = create(:git_runner)
      duplicate = build(:git_runner,
                        credential: existing.credential,
                        external_id: existing.external_id)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include('has already been taken')
    end

    it 'validates job counters are non-negative integers' do
      runner = build(:git_runner, total_jobs_run: -1)
      expect(runner).not_to be_valid

      runner = build(:git_runner, successful_jobs: -1)
      expect(runner).not_to be_valid

      runner = build(:git_runner, failed_jobs: -1)
      expect(runner).not_to be_valid
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

    let!(:online_runner) { create(:git_runner, :online, credential: credential, account: account) }
    let!(:offline_runner) { create(:git_runner, :offline, credential: credential, account: account) }
    let!(:busy_runner) { create(:git_runner, :busy, credential: credential, account: account) }

    describe '.online' do
      it 'returns only online runners' do
        expect(described_class.online).to include(online_runner)
        expect(described_class.online).not_to include(offline_runner, busy_runner)
      end
    end

    describe '.offline' do
      it 'returns only offline runners' do
        expect(described_class.offline).to include(offline_runner)
        expect(described_class.offline).not_to include(online_runner, busy_runner)
      end
    end

    describe '.busy' do
      it 'returns busy runners' do
        expect(described_class.busy).to include(busy_runner)
        expect(described_class.busy).not_to include(offline_runner)
      end
    end

    describe '.available' do
      it 'returns online runners that are not busy' do
        expect(described_class.available).to include(online_runner)
        expect(described_class.available).not_to include(busy_runner, offline_runner)
      end
    end

    describe '.by_scope' do
      let!(:repo_runner) { create(:git_runner, runner_scope: 'repository', credential: credential, account: account) }
      let!(:org_runner) { create(:git_runner, :organization_scope, credential: credential, account: account) }

      it 'filters by runner scope' do
        expect(described_class.by_scope('repository')).to include(repo_runner)
        expect(described_class.by_scope('organization')).to include(org_runner)
      end
    end

    describe '.repository_runners' do
      it 'returns repository-scoped runners' do
        expect(described_class.repository_runners).to all(have_attributes(runner_scope: 'repository'))
      end
    end

    describe '.organization_runners' do
      let!(:org_runner) { create(:git_runner, :organization_scope, credential: credential, account: account) }

      it 'returns organization-scoped runners' do
        expect(described_class.organization_runners).to include(org_runner)
      end
    end

    describe '.recently_seen' do
      let!(:recent_runner) { create(:git_runner, last_seen_at: 1.minute.ago, credential: credential, account: account) }
      let!(:stale_runner) { create(:git_runner, last_seen_at: 10.minutes.ago, credential: credential, account: account) }

      it 'returns runners seen within 5 minutes' do
        expect(described_class.recently_seen).to include(recent_runner)
        expect(described_class.recently_seen).not_to include(stale_runner)
      end
    end

    describe '.stale' do
      let!(:recent_runner) { create(:git_runner, last_seen_at: 1.minute.ago, credential: credential, account: account) }
      let!(:stale_runner) { create(:git_runner, last_seen_at: 10.minutes.ago, credential: credential, account: account) }
      let!(:never_seen_runner) { create(:git_runner, last_seen_at: nil, credential: credential, account: account) }

      it 'returns runners not seen for over 5 minutes or never seen' do
        expect(described_class.stale).to include(stale_runner, never_seen_runner)
        expect(described_class.stale).not_to include(recent_runner)
      end
    end

    describe '.with_label' do
      let!(:labeled_runner) { create(:git_runner, labels: ['linux', 'x64'], credential: credential, account: account) }

      it 'returns runners with specific label' do
        expect(described_class.with_label('linux')).to include(labeled_runner)
        expect(described_class.with_label('windows')).not_to include(labeled_runner)
      end
    end
  end

  describe 'instance methods' do
    describe '#online?' do
      it 'returns true for online status' do
        expect(build(:git_runner, :online).online?).to be true
        expect(build(:git_runner, :offline).online?).to be false
      end
    end

    describe '#offline?' do
      it 'returns true for offline status' do
        expect(build(:git_runner, :offline).offline?).to be true
        expect(build(:git_runner, :online).offline?).to be false
      end
    end

    describe '#busy?' do
      it 'returns true for busy status or busy flag' do
        expect(build(:git_runner, :busy).busy?).to be true
        expect(build(:git_runner, status: 'online', busy: true).busy?).to be true
        expect(build(:git_runner, :online).busy?).to be false
      end
    end

    describe '#available?' do
      it 'returns true only for online and not busy runners' do
        expect(build(:git_runner, :online).available?).to be true
        expect(build(:git_runner, :busy).available?).to be false
        expect(build(:git_runner, :offline).available?).to be false
      end
    end

    describe '#repository_runner?' do
      it 'returns true for repository scope' do
        expect(build(:git_runner, runner_scope: 'repository').repository_runner?).to be true
        expect(build(:git_runner, runner_scope: 'organization').repository_runner?).to be false
      end
    end

    describe '#organization_runner?' do
      it 'returns true for organization scope' do
        expect(build(:git_runner, runner_scope: 'organization').organization_runner?).to be true
        expect(build(:git_runner, runner_scope: 'repository').organization_runner?).to be false
      end
    end

    describe '#success_rate' do
      it 'calculates success percentage' do
        runner = build(:git_runner, total_jobs_run: 100, successful_jobs: 80, failed_jobs: 20)
        expect(runner.success_rate).to eq(80.0)
      end

      it 'returns 0 when no jobs run' do
        runner = build(:git_runner, total_jobs_run: 0)
        expect(runner.success_rate).to eq(0.0)
      end
    end

    describe '#failure_rate' do
      it 'calculates failure percentage' do
        runner = build(:git_runner, total_jobs_run: 100, successful_jobs: 80, failed_jobs: 20)
        expect(runner.failure_rate).to eq(20.0)
      end

      it 'returns 0 when no jobs run' do
        runner = build(:git_runner, total_jobs_run: 0)
        expect(runner.failure_rate).to eq(0.0)
      end
    end

    describe '#workload_percentage' do
      it 'returns 100 for busy runners' do
        expect(build(:git_runner, :busy).workload_percentage).to eq(100)
      end

      it 'returns 0 for offline runners' do
        expect(build(:git_runner, :offline).workload_percentage).to eq(0)
      end

      it 'returns 50 for online but not busy runners' do
        expect(build(:git_runner, :online).workload_percentage).to eq(50)
      end
    end

    describe '#recently_active?' do
      it 'returns true when seen within 5 minutes' do
        runner = build(:git_runner, last_seen_at: 1.minute.ago)
        expect(runner.recently_active?).to be true
      end

      it 'returns false when not seen recently' do
        runner = build(:git_runner, last_seen_at: 10.minutes.ago)
        expect(runner.recently_active?).to be false
      end

      it 'returns false when never seen' do
        runner = build(:git_runner, last_seen_at: nil)
        expect(runner.recently_active?).to be false
      end
    end

    describe '#stale?' do
      it 'returns true when not seen for over 5 minutes' do
        runner = build(:git_runner, last_seen_at: 10.minutes.ago)
        expect(runner.stale?).to be true
      end

      it 'returns true when never seen' do
        runner = build(:git_runner, last_seen_at: nil)
        expect(runner.stale?).to be true
      end

      it 'returns false when recently seen' do
        runner = build(:git_runner, last_seen_at: 1.minute.ago)
        expect(runner.stale?).to be false
      end
    end

    describe '#has_label?' do
      it 'checks if runner has specific label' do
        runner = build(:git_runner, labels: ['linux', 'x64'])
        expect(runner.has_label?('linux')).to be true
        expect(runner.has_label?('windows')).to be false
      end
    end

    describe '#label_list' do
      it 'returns comma-separated labels' do
        runner = build(:git_runner, labels: ['linux', 'x64', 'docker'])
        expect(runner.label_list).to eq('linux, x64, docker')
      end
    end
  end

  describe 'status updates' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

    describe '#mark_online!' do
      let(:runner) { create(:git_runner, :offline, credential: credential, account: account) }

      it 'sets status to online and updates last_seen_at' do
        runner.mark_online!
        expect(runner.status).to eq('online')
        expect(runner.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    describe '#mark_offline!' do
      let(:runner) { create(:git_runner, :online, credential: credential, account: account) }

      it 'sets status to offline' do
        runner.mark_offline!
        expect(runner.status).to eq('offline')
      end
    end

    describe '#mark_busy!' do
      let(:runner) { create(:git_runner, :online, credential: credential, account: account) }

      it 'sets status to busy and busy flag' do
        runner.mark_busy!
        expect(runner.status).to eq('busy')
        expect(runner.busy).to be true
        expect(runner.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    describe '#mark_available!' do
      let(:runner) { create(:git_runner, :busy, credential: credential, account: account) }

      it 'sets status to online and clears busy flag' do
        runner.mark_available!
        expect(runner.status).to eq('online')
        expect(runner.busy).to be false
        expect(runner.last_seen_at).to be_within(1.second).of(Time.current)
      end
    end

    describe '#record_job_completion!' do
      let(:runner) { create(:git_runner, total_jobs_run: 10, successful_jobs: 8, failed_jobs: 2, credential: credential, account: account) }

      it 'increments total and successful jobs on success' do
        runner.record_job_completion!(success: true)
        expect(runner.total_jobs_run).to eq(11)
        expect(runner.successful_jobs).to eq(9)
        expect(runner.failed_jobs).to eq(2)
      end

      it 'increments total and failed jobs on failure' do
        runner.record_job_completion!(success: false)
        expect(runner.total_jobs_run).to eq(11)
        expect(runner.successful_jobs).to eq(8)
        expect(runner.failed_jobs).to eq(3)
      end
    end

    describe '#record_success!' do
      let(:runner) { create(:git_runner, total_jobs_run: 5, successful_jobs: 4, failed_jobs: 1, credential: credential, account: account) }

      it 'delegates to record_job_completion with success: true' do
        runner.record_success!
        expect(runner.total_jobs_run).to eq(6)
        expect(runner.successful_jobs).to eq(5)
        expect(runner.failed_jobs).to eq(1)
      end
    end

    describe '#record_failure!' do
      let(:runner) { create(:git_runner, total_jobs_run: 5, successful_jobs: 4, failed_jobs: 1, credential: credential, account: account) }

      it 'delegates to record_job_completion with success: false' do
        runner.record_failure!
        expect(runner.total_jobs_run).to eq(6)
        expect(runner.successful_jobs).to eq(4)
        expect(runner.failed_jobs).to eq(2)
      end
    end
  end

  describe 'label management' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }
    let(:runner) { create(:git_runner, labels: ['linux', 'x64'], credential: credential, account: account) }

    describe '#update_labels!' do
      it 'replaces all labels' do
        runner.update_labels!(['windows', 'arm64'])
        expect(runner.labels).to eq(['windows', 'arm64'])
      end
    end

    describe '#add_labels!' do
      it 'adds new labels without duplicates' do
        runner.add_labels!(['docker', 'linux'])
        expect(runner.labels).to contain_exactly('linux', 'x64', 'docker')
      end
    end

    describe '#remove_labels!' do
      it 'removes specified labels' do
        runner.remove_labels!(['x64'])
        expect(runner.labels).to eq(['linux'])
      end
    end
  end

  describe '.sync_from_provider' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:credential) { create(:git_provider_credential, provider: provider, account: account) }

    let(:runner_data) do
      {
        'id' => '12345',
        'name' => 'test-runner',
        'status' => 'online',
        'busy' => false,
        'os' => 'Linux',
        'architecture' => 'X64',
        'version' => '2.311.0',
        'labels' => [{ 'name' => 'self-hosted' }, { 'name' => 'linux' }]
      }
    end

    it 'creates a new runner from provider data' do
      runner = described_class.sync_from_provider(credential, runner_data)
      expect(runner).to be_persisted
      expect(runner.external_id).to eq('12345')
      expect(runner.name).to eq('test-runner')
      expect(runner.status).to eq('online')
      expect(runner.os).to eq('Linux')
      expect(runner.labels).to contain_exactly('self-hosted', 'linux')
    end

    it 'updates an existing runner' do
      existing = create(:git_runner, credential: credential, account: account, external_id: '12345', name: 'old-name')
      runner = described_class.sync_from_provider(credential, runner_data)
      expect(runner.id).to eq(existing.id)
      expect(runner.name).to eq('test-runner')
    end

    it 'normalizes status values' do
      runner_data['status'] = 'active'
      runner = described_class.sync_from_provider(credential, runner_data)
      expect(runner.status).to eq('online')
    end
  end
end
