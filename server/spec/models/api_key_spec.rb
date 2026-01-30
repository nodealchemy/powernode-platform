# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ApiKey, type: :model do
  describe 'associations' do
    it { should belong_to(:created_by).class_name('User').optional }
    it { should belong_to(:account).optional }
    it { should have_many(:api_key_usages).dependent(:destroy) }
  end

  describe 'validations' do
    subject { create(:api_key) }

    it { should validate_presence_of(:name) }
    it { should validate_length_of(:name).is_at_most(100) }
    it { should validate_presence_of(:key_digest) }
    # key_digest uniqueness can't be tested with shoulda-matchers because
    # before_validation :generate_key callback always generates a new digest
    it 'has a uniqueness validation on key_digest' do
      expect(ApiKey.validators_on(:key_digest).map(&:class)).to include(ActiveRecord::Validations::UniquenessValidator)
    end
    it { should validate_inclusion_of(:is_active).in_array([true, false]) }
  end

  describe 'scopes' do
    let!(:active_key) { create(:api_key, :active, expires_at: 1.day.from_now) }
    let!(:inactive_key) { create(:api_key, is_active: false) }
    let!(:expired_key) do
      key = create(:api_key, :active, expires_at: 1.day.from_now)
      key.update_columns(expires_at: 1.day.ago)
      key
    end
    let!(:revoked_key) { create(:api_key, :revoked) }

    describe '.active' do
      it 'returns only active and non-expired keys' do
        expect(ApiKey.active).to include(active_key)
        expect(ApiKey.active).not_to include(inactive_key, expired_key, revoked_key)
      end
    end

    describe '.inactive' do
      it 'returns only inactive keys' do
        expect(ApiKey.inactive).to include(inactive_key, revoked_key)
        expect(ApiKey.inactive).not_to include(active_key)
      end
    end

    describe '.expired' do
      it 'returns only expired keys' do
        expect(ApiKey.expired).to include(expired_key)
        expect(ApiKey.expired).not_to include(active_key, inactive_key)
      end
    end

    describe '.revoked' do
      it 'returns only revoked keys' do
        expect(ApiKey.revoked).to include(revoked_key, inactive_key)
        expect(ApiKey.revoked).not_to include(active_key)
      end
    end
  end

  describe 'instance methods' do
    let(:api_key) { create(:api_key) }

    describe '#active?' do
      it 'returns true when key is active and not expired' do
        api_key.is_active = true
        api_key.expires_at = 1.day.from_now
        expect(api_key.active?).to be true
      end

      it 'returns false when key is inactive' do
        api_key.is_active = false
        expect(api_key.active?).to be false
      end

      it 'returns false when key is expired' do
        api_key.is_active = true
        api_key.expires_at = 1.day.ago
        expect(api_key.active?).to be false
      end
    end

    describe '#revoked?' do
      it 'returns true when key is inactive' do
        api_key.is_active = false
        expect(api_key.revoked?).to be true
      end

      it 'returns false when key is active' do
        api_key.is_active = true
        expect(api_key.revoked?).to be false
      end
    end

    describe '#expired?' do
      it 'returns true when expires_at is in the past' do
        api_key.expires_at = 1.day.ago
        expect(api_key.expired?).to be true
      end

      it 'returns false when expires_at is in the future' do
        api_key.expires_at = 1.day.from_now
        expect(api_key.expired?).to be false
      end

      it 'returns false when expires_at is nil' do
        api_key.expires_at = nil
        expect(api_key.expired?).to be false
      end
    end

    describe '#valid_for_use?' do
      it 'returns true when active and not rate limited' do
        allow(api_key).to receive(:active?).and_return(true)
        allow(api_key).to receive(:rate_limited?).and_return(false)
        expect(api_key.valid_for_use?).to be true
      end

      it 'returns false when rate limited' do
        allow(api_key).to receive(:active?).and_return(true)
        allow(api_key).to receive(:rate_limited?).and_return(true)
        expect(api_key.valid_for_use?).to be false
      end

      it 'returns false when not active' do
        allow(api_key).to receive(:active?).and_return(false)
        allow(api_key).to receive(:rate_limited?).and_return(false)
        expect(api_key.valid_for_use?).to be false
      end
    end

    describe '#has_scope?' do
      it 'returns true when permissions is blank' do
        api_key.permissions = []
        expect(api_key.has_scope?('read:users')).to be true
      end

      it 'returns true when permissions include wildcard' do
        api_key.permissions = ['*']
        expect(api_key.has_scope?('read:users')).to be true
      end

      it 'returns true when scope is included in permissions' do
        api_key.permissions = ['read:users', 'write:accounts']
        expect(api_key.has_scope?('read:users')).to be true
      end

      it 'returns false when scope is not included' do
        api_key.permissions = ['read:users']
        expect(api_key.has_scope?('write:accounts')).to be false
      end
    end

    describe '#masked_key' do
      it 'returns masked key with prefix' do
        api_key.prefix = 'pk_test_12345678'
        expect(api_key.masked_key).to eq('pk_test_12345678...****')
      end

      it 'returns nil when prefix is blank' do
        api_key.prefix = nil
        expect(api_key.masked_key).to be_nil
      end
    end

    describe '#regenerate_key!' do
      it 'generates a new key and updates key_digest' do
        old_digest = api_key.key_digest
        api_key.regenerate_key!
        expect(api_key.key_digest).not_to eq(old_digest)
        expect(api_key.key_value).to be_present
      end

      it 'persists the changes' do
        api_key.regenerate_key!
        api_key.reload
        expect(api_key.key_digest).to be_present
      end
    end
  end

  describe 'callbacks' do
    describe 'generate_key on create' do
      it 'generates key_value and key_digest' do
        api_key = create(:api_key)
        expect(api_key.key_value).to be_present
        expect(api_key.key_digest).to be_present
        expect(api_key.prefix).to be_present
      end
    end

    describe 'set_defaults' do
      it 'sets is_active to true by default' do
        api_key = ApiKey.new(name: 'Test Key')
        api_key.valid?
        expect(api_key.is_active).to be true
      end

      it 'sets permissions to empty array by default' do
        api_key = ApiKey.new(name: 'Test Key')
        api_key.valid?
        expect(api_key.permissions).to eq([])
      end

      it 'sets rate_limits to empty hash by default' do
        api_key = ApiKey.new(name: 'Test Key')
        api_key.valid?
        expect(api_key.rate_limits).to eq({})
      end
    end
  end
end
