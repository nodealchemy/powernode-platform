require 'rails_helper'

RSpec.describe User, 'Comprehensive Password Security', type: :model do
  let(:account) { create(:account) }

  describe 'Password Complexity Enforcement' do
    it 'enforces all password requirements through PasswordStrengthService' do
      # Test minimum length
      expect(build(:user, account: account, password: 'Short1!', password_confirmation: 'Short1!')).not_to be_valid
      
      # Test uppercase requirement
      expect(build(:user, account: account, password: 'nouppercase123!', password_confirmation: 'nouppercase123!')).not_to be_valid
      
      # Test lowercase requirement
      expect(build(:user, account: account, password: 'NOLOWERCASE123!', password_confirmation: 'NOLOWERCASE123!')).not_to be_valid
      
      # Test number requirement
      expect(build(:user, account: account, password: 'NoNumbers!@#$', password_confirmation: 'NoNumbers!@#$')).not_to be_valid
      
      # Test special character requirement
      expect(build(:user, account: account, password: 'NoSpecialChars123', password_confirmation: 'NoSpecialChars123')).not_to be_valid
      
      # Test common password rejection
      expect(build(:user, account: account, password: 'password123', password_confirmation: 'password123')).not_to be_valid
      
      # Test strong password acceptance
      strong_password = 'MyCustomPhrase2024!@#$'
      expect(build(:user, account: account, password: strong_password, password_confirmation: strong_password)).to be_valid
    end

    it 'calculates password strength correctly' do
      user = build(:user, account: account, password: 'VeryStrongPhrase789!@#$')
      strength = user.password_strength
      expect(strength).to be >= 70
    end

    it 'integrates with PasswordStrengthService validation' do
      weak_password = 'weak'
      user = build(:user, account: account, password: weak_password, password_confirmation: weak_password)
      
      expect(PasswordStrengthService).to receive(:validate_password).with(weak_password).and_call_original
      user.valid?
    end
  end

  describe 'Password History Protection' do
    let(:user) { create(:user, account: account, password: 'InitialPhrase2024!@#', password_confirmation: 'InitialPhrase2024!@#') }

    it 'prevents password reuse within history limit' do
      original_password = 'OriginalPhrase2025!@#'
      user.update!(password: original_password, password_confirmation: original_password)
      
      # Change password a few times
      3.times do |i|
        user.update!(password: "TempPhrase#{i}789!@#", password_confirmation: "TempPhrase#{i}789!@#")
      end
      
      # Try to reuse original password - should fail
      user.password = original_password
      user.password_confirmation = original_password
      expect(user).not_to be_valid
      expect(user.errors[:password].first).to include('cannot be the same as any of your last')
    end

    it 'creates password history entries on password change' do
      expect {
        user.update!(password: 'NewCustomPhrase789!@#', password_confirmation: 'NewCustomPhrase789!@#')
      }.to change(PasswordHistory, :count).by(1)
    end

    it 'limits password history to configured count' do
      # Generate 15 password changes
      15.times do |i|
        user.update!(password: "CustomPhrase#{i}789!@#", password_confirmation: "CustomPhrase#{i}789!@#")
      end
      
      # Should only keep the last 12
      expect(user.password_histories.count).to eq(12)
    end
  end

  describe 'Account Lockout Security' do
    let(:user) { create(:user, account: account, password: 'RandomPhrase2024!@#', password_confirmation: 'RandomPhrase2024!@#') }

    it 'implements progressive lockout after failed attempts' do
      expect(user).not_to be_locked
      
      # Record failed attempts
      5.times { user.record_failed_login! }
      
      expect(user).to be_locked
      expect(user.failed_login_attempts).to eq(5)
    end

    it 'implements exponential backoff for lockout duration' do
      5.times { user.record_failed_login! }
      first_lockout = user.locked_until
      
      user.record_failed_login!
      second_lockout = user.locked_until
      
      expect(second_lockout).to be > first_lockout
    end

    it 'clears lockout on successful authentication' do
      3.times { user.record_failed_login! }
      user.record_successful_login!
      
      expect(user.failed_login_attempts).to eq(0)
      expect(user.locked_until).to be_nil
      expect(user.last_login_at).to be_within(1.second).of(Time.current)
    end
  end

  describe 'Secure Password Reset' do
    let(:user) { create(:user, account: account, password: 'OriginalPhrase2026!@#', password_confirmation: 'OriginalPhrase2026!@#') }

    it 'generates secure time-limited reset tokens' do
      token = user.generate_reset_token!
      
      expect(token).to be_present
      expect(user.reset_token_digest).to be_present
      expect(user.reset_token_expires_at).to be_within(1.minute).of(1.hour.from_now)
    end

    it 'validates reset tokens correctly' do
      token = user.generate_reset_token!
      expect(user.reset_token_valid?(token)).to be true
      
      # Invalid token
      expect(user.reset_token_valid?('invalid')).to be false
      
      # Expired token
      user.update!(reset_token_expires_at: 1.hour.ago)
      expect(user.reset_token_valid?(token)).to be false
    end

    it 'successfully resets password with valid token' do
      token = user.generate_reset_token!
      new_password = 'NewCustomPhrase2026!@#'
      
      result = user.reset_password!(new_password, token)
      
      expect(result).to be true
      expect(user.reset_token_digest).to be_nil
      expect(user.reset_token_expires_at).to be_nil
    end

    it 'clears reset tokens when password changes' do
      user.generate_reset_token!
      expect(user.reset_token_digest).to be_present
      
      user.update!(password: 'AnotherCustom789!@#', password_confirmation: 'AnotherCustom789!@#')
      
      expect(user.reset_token_digest).to be_nil
      expect(user.reset_token_expires_at).to be_nil
    end
  end

  describe 'Password Aging and Metrics' do
    let(:user) { create(:user, account: account, password: 'TestPhrase2024!@#', password_confirmation: 'TestPhrase2024!@#') }

    it 'tracks password age correctly' do
      user.update!(password_changed_at: 30.days.ago)
      expect(user.password_age_days).to eq(30)
      
      user.update!(password_changed_at: nil)
      expect(user.password_age_days).to be_nil
    end

    it 'updates password change timestamp on password update' do
      expect {
        user.update!(password: 'UpdatedPhrase456!@#', password_confirmation: 'UpdatedPhrase456!@#')
      }.to change(user, :password_changed_at)
    end
  end

  describe 'Integration with Authentication System' do
    it 'enforces password requirements during user creation' do
      expect {
        create(:user, account: account, password: 'weak', password_confirmation: 'weak')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'allows creation with compliant passwords' do
      expect {
        create(:user, account: account, password: 'CompliantPhrase789!@#', password_confirmation: 'CompliantPhrase789!@#')
      }.not_to raise_error
    end
  end
end