require 'rails_helper'

RSpec.describe BlacklistedToken, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:token) { "eyJhbGciOiJIUzI1NiJ9.eyJ1c2VyX2lkIjoiMTIzIiwiZXhwIjoxNzU1MzAzMTAwfQ.test_token" }
  let(:expires_at) { 1.hour.from_now }

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    subject { build(:blacklisted_token) }

    it { should validate_presence_of(:token) }
    it { should validate_uniqueness_of(:token) }
    it { should validate_presence_of(:expires_at) }
  end

  describe 'scopes' do
    let!(:valid_token) { create(:blacklisted_token, user: user, expires_at: 1.hour.from_now) }
    let!(:expired_token) { create(:blacklisted_token, user: user, expires_at: 1.hour.ago) }

    describe '.valid' do
      it 'returns tokens that have not expired' do
        expect(BlacklistedToken.valid).to include(valid_token)
        expect(BlacklistedToken.valid).not_to include(expired_token)
      end
    end

    describe '.expired' do
      it 'returns tokens that have expired' do
        expect(BlacklistedToken.expired).to include(expired_token)
        expect(BlacklistedToken.expired).not_to include(valid_token)
      end
    end
  end

  describe '.blacklisted?' do
    context 'when token is blacklisted and valid' do
      before do
        create(:blacklisted_token, user: user, token: token, expires_at: 1.hour.from_now)
      end

      it 'returns true' do
        expect(BlacklistedToken.blacklisted?(token)).to be true
      end
    end

    context 'when token is blacklisted but expired' do
      before do
        create(:blacklisted_token, user: user, token: token, expires_at: 1.hour.ago)
      end

      it 'returns false' do
        expect(BlacklistedToken.blacklisted?(token)).to be false
      end
    end

    context 'when token is not blacklisted' do
      it 'returns false' do
        expect(BlacklistedToken.blacklisted?('unknown_token')).to be false
      end
    end
  end

  describe '.cleanup_expired' do
    let!(:valid_token) { create(:blacklisted_token, user: user, expires_at: 1.hour.from_now) }
    let!(:expired_token1) { create(:blacklisted_token, user: user, expires_at: 1.hour.ago) }
    let!(:expired_token2) { create(:blacklisted_token, user: user, expires_at: 2.hours.ago) }

    it 'deletes expired tokens but keeps valid ones' do
      expect { BlacklistedToken.cleanup_expired }.to change { BlacklistedToken.count }.by(-2)
      expect(BlacklistedToken.exists?(valid_token.id)).to be true
      expect(BlacklistedToken.exists?(expired_token1.id)).to be false
      expect(BlacklistedToken.exists?(expired_token2.id)).to be false
    end
  end

  describe '#expired?' do
    context 'when expires_at is in the future' do
      let(:blacklisted_token) { build(:blacklisted_token, expires_at: 1.hour.from_now) }

      it 'returns false' do
        expect(blacklisted_token.expired?).to be false
      end
    end

    context 'when expires_at is in the past' do
      let(:blacklisted_token) { build(:blacklisted_token, expires_at: 1.hour.ago) }

      it 'returns true' do
        expect(blacklisted_token.expired?).to be true
      end
    end

    context 'when expires_at is exactly now' do
      let(:blacklisted_token) { build(:blacklisted_token, expires_at: Time.current) }

      it 'returns true' do
        expect(blacklisted_token.expired?).to be true
      end
    end
  end

  describe 'creating a blacklisted token' do
    it 'can be created with valid attributes' do
      blacklisted_token = BlacklistedToken.create!(
        user: user,
        token: token,
        expires_at: expires_at,
        reason: 'logout'
      )

      expect(blacklisted_token).to be_persisted
      expect(blacklisted_token.user).to eq(user)
      expect(blacklisted_token.token).to eq(token)
      expect(blacklisted_token.expires_at).to be_within(1.second).of(expires_at)
      expect(blacklisted_token.reason).to eq('logout')
    end

    it 'defaults reason to logout if not specified' do
      blacklisted_token = BlacklistedToken.create!(
        user: user,
        token: token,
        expires_at: expires_at
      )

      expect(blacklisted_token.reason).to eq('logout')
    end
  end
end
