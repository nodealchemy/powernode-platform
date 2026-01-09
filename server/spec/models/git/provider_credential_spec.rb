# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Git::ProviderCredential, type: :model do
  subject(:credential) { build(:git_provider_credential) }

  describe 'associations' do
    it { is_expected.to belong_to(:provider) }
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to have_many(:repositories).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:auth_type) }
    it { is_expected.to validate_inclusion_of(:auth_type).in_array(%w[oauth personal_access_token]) }
    it { is_expected.to validate_presence_of(:encrypted_credentials) }
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:other_account) { create(:account) }
    let(:provider) { create(:git_provider) }
    let(:other_provider) { create(:git_provider) }

    describe '.active' do
      let!(:active_cred) { create(:git_provider_credential, provider: provider, account: account, is_active: true) }
      let!(:inactive_cred) { create(:git_provider_credential, provider: other_provider, account: account, is_active: false) }

      it 'returns only active credentials' do
        expect(described_class.active).to include(active_cred)
        expect(described_class.active).not_to include(inactive_cred)
      end
    end

    describe '.default' do
      let!(:first_cred) { create(:git_provider_credential, provider: provider, account: account) }
      let!(:non_default) { create(:git_provider_credential, provider: other_provider, account: account) }

      it 'returns only default credentials' do
        # First cred becomes default automatically
        expect(described_class.default).to include(first_cred)
      end
    end

    describe '.for_provider' do
      let!(:cred1) { create(:git_provider_credential, provider: provider, account: account) }
      let!(:cred2) { create(:git_provider_credential, provider: other_provider, account: account) }

      it 'returns credentials for specific provider' do
        expect(described_class.for_provider(provider)).to include(cred1)
        expect(described_class.for_provider(provider)).not_to include(cred2)
      end
    end

    describe '.healthy' do
      let!(:healthy_cred) { create(:git_provider_credential, provider: provider, account: account, consecutive_failures: 0) }
      let!(:unhealthy_cred) { create(:git_provider_credential, provider: other_provider, account: account, consecutive_failures: 5) }

      it 'returns credentials with low consecutive failures' do
        expect(described_class.healthy).to include(healthy_cred)
        expect(described_class.healthy).not_to include(unhealthy_cred)
      end
    end
  end

  describe 'instance methods' do
    describe '#healthy?' do
      it 'returns true for active credentials with low failures' do
        credential = build(:git_provider_credential, is_active: true, consecutive_failures: 0)
        expect(credential.healthy?).to be true
      end

      it 'returns false for credentials with too many failures' do
        credential = build(:git_provider_credential, is_active: true, consecutive_failures: 3)
        expect(credential.healthy?).to be false
      end

      it 'returns false for inactive credentials' do
        credential = build(:git_provider_credential, is_active: false, consecutive_failures: 0)
        expect(credential.healthy?).to be false
      end
    end

    describe '#can_be_used?' do
      it 'returns true for active credentials with acceptable failures' do
        credential = build(:git_provider_credential, is_active: true, consecutive_failures: 0)
        expect(credential.can_be_used?).to be true
      end

      it 'returns false for inactive credentials' do
        credential = build(:git_provider_credential, is_active: false)
        expect(credential.can_be_used?).to be false
      end

      it 'returns false for credentials with too many failures' do
        # MAX_CONSECUTIVE_FAILURES is 5, so 6 should fail
        credential = build(:git_provider_credential, is_active: true, consecutive_failures: 6)
        expect(credential.can_be_used?).to be false
      end
    end

    describe '#expired?' do
      it 'returns false for credentials without expiration' do
        credential = build(:git_provider_credential, expires_at: nil)
        expect(credential.expired?).to be false
      end

      it 'returns false for credentials not yet expired' do
        credential = build(:git_provider_credential, expires_at: 1.hour.from_now)
        expect(credential.expired?).to be false
      end

      it 'returns true for expired credentials' do
        credential = build(:git_provider_credential)
        credential.expires_at = 1.hour.ago
        expect(credential.expired?).to be true
      end
    end

    describe '#record_success!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account, consecutive_failures: 2, failure_count: 5) }

      it 'resets consecutive failures' do
        credential.record_success!
        expect(credential.reload.consecutive_failures).to eq(0)
      end

      it 'increments success count' do
        expect { credential.record_success! }.to change { credential.reload.success_count }.by(1)
      end

      it 'updates last_test_at' do
        credential.record_success!
        expect(credential.reload.last_test_at).to be_within(1.second).of(Time.current)
      end

      it 'sets last_test_status to success' do
        credential.record_success!
        expect(credential.reload.last_test_status).to eq('success')
      end
    end

    describe '#record_failure!' do
      let(:account) { create(:account) }
      let(:provider) { create(:git_provider) }
      let(:credential) { create(:git_provider_credential, provider: provider, account: account, consecutive_failures: 0) }

      it 'increments consecutive failures' do
        credential.record_failure!('Connection error')
        expect(credential.reload.consecutive_failures).to be >= 1
      end

      it 'increments failure count' do
        expect { credential.record_failure!('Error') }.to change { credential.reload.failure_count }
      end

      it 'sets last_error' do
        credential.record_failure!('Connection timeout')
        expect(credential.reload.last_error).to eq('Connection timeout')
      end

      it 'deactivates after exceeding max consecutive failures' do
        credential.update_column(:consecutive_failures, 5)
        credential.record_failure!('Final failure')
        expect(credential.reload.is_active).to be false
      end
    end
  end

  describe 'credential encryption' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }

    describe 'credentials=' do
      it 'encrypts credentials when setting' do
        credential = build(:git_provider_credential, provider: provider, account: account, encrypted_credentials: nil, encryption_key_id: nil)
        credential.credentials = { 'access_token' => 'secret_token' }
        expect(credential.encrypted_credentials).to be_present
        expect(credential.encrypted_credentials).not_to include('secret_token')
      end
    end

    describe '#credentials' do
      it 'decrypts stored credentials' do
        credential = create(:git_provider_credential, provider: provider, account: account)
        expect(credential.credentials).to be_a(Hash)
        expect(credential.credentials['access_token']).to be_present
      end
    end
  end

  describe 'default management' do
    let(:account) { create(:account) }
    let(:provider) { create(:git_provider) }

    it 'sets first credential as default automatically' do
      cred = create(:git_provider_credential, provider: provider, account: account)
      expect(cred.reload.is_default).to be true
    end

    it 'ensures only one default per provider per account' do
      cred1 = create(:git_provider_credential, provider: provider, account: account)
      expect(cred1.reload.is_default).to be true

      cred2 = create(:git_provider_credential, provider: provider, account: account, is_default: false)
      cred2.make_default!

      expect(cred1.reload.is_default).to be false
      expect(cred2.reload.is_default).to be true
    end
  end

  describe '#oauth? and #pat?' do
    it 'returns true for oauth credentials' do
      credential = build(:git_provider_credential, auth_type: 'oauth')
      expect(credential.oauth?).to be true
      expect(credential.pat?).to be false
    end

    it 'returns true for PAT credentials' do
      credential = build(:git_provider_credential, auth_type: 'personal_access_token')
      expect(credential.pat?).to be true
      expect(credential.oauth?).to be false
    end
  end
end
