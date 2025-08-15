require 'rails_helper'

RSpec.describe User, 'Password Security', type: :model do
  include ActiveSupport::Testing::TimeHelpers
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'password complexity validation' do
    context 'with strong password' do
      it 'accepts password meeting all requirements' do
        user = build(:user, account: account, password: 'MySecure$Phrase2024!')
        expect(user).to be_valid
      end
    end

    context 'with weak passwords' do
      it 'rejects password that is too short' do
        user = build(:user, account: account, password: 'Short1!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must be at least 12 characters long')
      end

      it 'rejects password without uppercase' do
        user = build(:user, account: account, password: 'nouppercase123!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one uppercase letter')
      end

      it 'rejects password without lowercase' do
        user = build(:user, account: account, password: 'NOLOWERCASE123!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one lowercase letter')
      end

      it 'rejects password without numbers' do
        user = build(:user, account: account, password: 'NoNumbersHere!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one number')
      end

      it 'rejects password without special characters' do
        user = build(:user, account: account, password: 'NoSpecialChars123')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one special character')
      end

      it 'rejects common passwords' do
        user = build(:user, account: account, password: 'password123')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password is too common and easily guessable')
      end

      it 'rejects passwords with low strength score' do
        user = build(:user, account: account, password: 'WeakPassword1!')
        allow(PasswordStrengthService).to receive(:validate_password)
          .and_return({
            valid: false,
            errors: [ 'Password is not strong enough (minimum strength score: 60)' ],
            score: 45,
            strength: 'weak'
          })

        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password is not strong enough (minimum strength score: 60)')
      end
    end
  end

  describe 'password history validation' do
    before do
      # Create user with initial password
      user.save!

      # Simulate password history by creating entries
      3.times do |i|
        digest = BCrypt::Password.create("old_password_#{i}!")
        create(:password_history, user: user, password_digest: digest)
      end
    end

    it 'prevents reuse of recent passwords' do
      allow(PasswordHistory).to receive(:password_recently_used?)
        .with(user, 'old_password_1!')
        .and_return(true)

      user.password = 'old_password_1!'
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include('cannot be the same as any of your last 12 passwords')
    end

    it 'allows passwords not in history' do
      allow(PasswordHistory).to receive(:password_recently_used?)
        .with(user, 'NewUniquePhrase98!')
        .and_return(false)

      user.password = 'NewUniquePhrase98!'
      expect(user).to be_valid
    end
  end

  describe 'password history tracking' do
    it 'saves password to history after update' do
      user.save!
      original_password = 'UncommonStr0ngP@ssw0rd#99' # Factory password

      expect {
        user.update!(password: 'NewSecurePhrase789!')
      }.to change { user.password_histories.count }.by(1)

      history_entry = user.password_histories.last
      expect(BCrypt::Password.new(history_entry.password_digest)).to eq(original_password)
    end

    it 'cleans up old password history entries' do
      user.save!

      # Create 15 password history entries
      15.times do |i|
        create(:password_history, user: user, created_at: (i + 1).days.ago)
      end

      expect {
        user.update!(password: 'NewSecurePhrase789!')
      }.to change { user.password_histories.count }.from(15).to(12)
    end

    it 'sets password_changed_at timestamp' do
      user.save!
      original_time = user.password_changed_at

      travel_to 1.day.from_now do
        user.update!(password: 'NewSecurePhrase789!')
        expect(user.password_changed_at).to be > original_time
        expect(user.password_changed_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'account lockout mechanism' do
    describe '#locked?' do
      it 'returns false when locked_until is nil' do
        user.locked_until = nil
        expect(user.locked?).to be false
      end

      it 'returns false when locked_until is in the past' do
        user.locked_until = 1.hour.ago
        expect(user.locked?).to be false
      end

      it 'returns true when locked_until is in the future' do
        user.locked_until = 1.hour.from_now
        expect(user.locked?).to be true
      end
    end

    describe '#record_failed_login!' do
      it 'increments failed_login_attempts' do
        expect {
          user.record_failed_login!
        }.to change { user.failed_login_attempts }.by(1)
      end

      it 'locks account after max failed attempts' do
        user.update!(failed_login_attempts: User::MAX_FAILED_ATTEMPTS - 1)

        expect {
          user.record_failed_login!
        }.to change { user.locked? }.from(false).to(true)
      end

      it 'uses exponential backoff for lockout duration' do
        user.update!(failed_login_attempts: User::MAX_FAILED_ATTEMPTS - 1)

        travel_to Time.current do
          user.record_failed_login!

          # First lockout should be base duration (30 minutes)
          expected_lockout = Time.current + User::LOCKOUT_DURATION
          expect(user.locked_until).to be_within(1.second).of(expected_lockout)
        end

        user.update!(failed_login_attempts: User::MAX_FAILED_ATTEMPTS)

        travel_to 1.hour.from_now do
          user.record_failed_login!

          # Second lockout should be doubled (60 minutes)
          expected_lockout = Time.current + (User::LOCKOUT_DURATION * 2)
          expect(user.locked_until).to be_within(1.second).of(expected_lockout)
        end
      end
    end

    describe '#record_successful_login!' do
      before do
        user.update!(
          failed_login_attempts: 3,
          locked_until: 1.hour.from_now
        )
      end

      it 'resets failed login attempts' do
        user.record_successful_login!
        expect(user.failed_login_attempts).to eq(0)
      end

      it 'clears lockout' do
        user.record_successful_login!
        expect(user.locked_until).to be_nil
      end

      it 'updates last_login_at' do
        travel_to Time.current do
          user.record_successful_login!
          expect(user.last_login_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    describe '#unlock!' do
      before do
        user.update!(
          failed_login_attempts: 5,
          locked_until: 1.hour.from_now
        )
      end

      it 'resets failed login attempts and clears lockout' do
        user.unlock!
        expect(user.failed_login_attempts).to eq(0)
        expect(user.locked_until).to be_nil
      end
    end
  end

  describe 'enhanced authentication' do
    let(:password) { 'MySecurePhrase654!' }
    let(:user) { create(:user, account: account, password: password) }

    context 'when account is locked' do
      before do
        user.update!(locked_until: 1.hour.from_now)
      end

      it 'returns false even with correct password' do
        expect(user.authenticate(password)).to be false
      end

      it 'does not update failed login attempts' do
        original_attempts = user.failed_login_attempts
        user.authenticate(password)
        expect(user.reload.failed_login_attempts).to eq(original_attempts)
      end
    end

    context 'when account is not locked' do
      context 'with correct password' do
        it 'returns user object' do
          expect(user.authenticate(password)).to eq(user)
        end

        it 'records successful login' do
          expect(user).to receive(:record_successful_login!)
          user.authenticate(password)
        end
      end

      context 'with incorrect password' do
        it 'returns false' do
          expect(user.authenticate('wrong_password')).to be false
        end

        it 'records failed login' do
          expect(user).to receive(:record_failed_login!)
          user.authenticate('wrong_password')
        end
      end
    end
  end

  describe 'password utility methods' do
    describe '#password_age_days' do
      it 'returns nil when password_changed_at is nil' do
        user.password_changed_at = nil
        expect(user.password_age_days).to be_nil
      end

      it 'calculates days since password was changed' do
        user.password_changed_at = 5.days.ago
        expect(user.password_age_days).to eq(5)
      end
    end

    describe '#password_expired?' do
      it 'returns false when password_changed_at is nil' do
        user.password_changed_at = nil
        expect(user.password_expired?).to be false
      end

      it 'returns false when password is within age limit' do
        user.password_changed_at = 30.days.ago
        expect(user.password_expired?(90)).to be false
      end

      it 'returns true when password exceeds age limit' do
        user.password_changed_at = 100.days.ago
        expect(user.password_expired?(90)).to be true
      end
    end
  end

  describe 'scopes' do
    let!(:locked_user) { create(:user, account: account, locked_until: 1.hour.from_now) }
    let!(:unlocked_user) { create(:user, account: account, locked_until: nil) }
    let!(:previously_locked_user) { create(:user, account: account, locked_until: 1.hour.ago) }

    describe '.locked' do
      it 'returns only currently locked users' do
        expect(User.locked).to contain_exactly(locked_user)
      end
    end

    describe '.unlocked' do
      it 'returns users who are not currently locked' do
        expect(User.unlocked).to contain_exactly(unlocked_user, previously_locked_user, user)
      end
    end
  end
end
