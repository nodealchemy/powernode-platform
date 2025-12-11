# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User, 'Password Security Integration', type: :model do
  describe 'Strong Password Complexity Requirements' do
    let(:account) { create(:account) }
    let(:valid_password) { 'MySecurePhrase789!@#$' }

    context 'password requirements enforcement' do
      it 'requires minimum 12 characters' do
        user = build(:user, account: account, password: 'Short1!', password_confirmation: 'Short1!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must be at least 12 characters long')
      end

      it 'requires uppercase letter' do
        user = build(:user, account: account, password: 'nocapitalletters123!', password_confirmation: 'nocapitalletters123!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one uppercase letter')
      end

      it 'requires lowercase letter' do
        user = build(:user, account: account, password: 'NOLOWERCASELETTERS123!', password_confirmation: 'NOLOWERCASELETTERS123!')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one lowercase letter')
      end

      it 'requires number' do
        user = build(:user, account: account, password: 'NoNumbersHere!@#$', password_confirmation: 'NoNumbersHere!@#$')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one number')
      end

      it 'requires special character' do
        user = build(:user, account: account, password: 'NoSpecialChars123', password_confirmation: 'NoSpecialChars123')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password must contain at least one special character')
      end

      it 'rejects common passwords' do
        user = build(:user, account: account, password: 'password123', password_confirmation: 'password123')
        expect(user).not_to be_valid
        expect(user.errors[:password]).to include('Password is too common and easily guessable')
      end

      it 'validates password using strength service' do
        # Use password that will definitely be validated by service
        user = build(:user, account: account, password: valid_password, password_confirmation: valid_password)
        expect(user).to be_valid
        
        # Test that validation service is called
        expect(PasswordStrengthService).to receive(:validate_password).with(valid_password).and_call_original
        user.valid?
      end
    end

    context 'strong password acceptance' do
      it 'accepts password meeting all requirements' do
        user = build(:user, account: account, password: valid_password, password_confirmation: valid_password)
        expect(user).to be_valid
      end

      it 'calculates password strength correctly' do
        user = build(:user, account: account, password: valid_password)
        expect(user.password_strength).to be >= 70
      end
    end
  end

  describe 'Password History Tracking' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'StrongTe$tP@5w0rd!', password_confirmation: 'StrongTe$tP@5w0rd!') }

    it 'prevents reusing recent passwords' do
      # Change password multiple times
      (2..5).each do |i|
        user.update!(password: "StrongTst#{i}P@5w0rd!", password_confirmation: "StrongTst#{i}P@5w0rd!")
      end

      # Try to reuse first password
      user.password = 'StrongTe$tP@5w0rd!'
      user.password_confirmation = 'StrongTe$tP@5w0rd!'
      expect(user).not_to be_valid
      expect(user.errors[:password]).to include("has been used recently. For security, please choose a different password that you haven't used in your last 12 password changes")
    end

    it 'allows reusing password after 12 different passwords' do
      original_password = 'OriginalStr0ng!P@5w'
      user.update!(password: original_password, password_confirmation: original_password)

      # Change password 13 times to push original password out of the last 12
      (1..13).each do |i|
        user.update!(password: "TempStr0ng#{i}!P@5w", password_confirmation: "TempStr0ng#{i}!P@5w")
      end

      # Should now be able to reuse original password
      user.password = original_password
      user.password_confirmation = original_password
      expect(user).to be_valid
    end

    it 'creates password history entries' do
      expect {
        user.update!(password: 'NewStr0ng!P@5w0rd', password_confirmation: 'NewStr0ng!P@5w0rd')
      }.to change(PasswordHistory, :count).by(1)
    end

    it 'cleans up old password history entries' do
      # Create 15 password changes
      (1..15).each do |i|
        user.update!(password: "Str0ng#{i}!P@5w0rd", password_confirmation: "Str0ng#{i}!P@5w0rd")
      end

      # Should only keep last 12
      expect(user.password_histories.count).to eq(12)
    end
  end

  describe 'Account Lockout Mechanism' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'SecureEntry4!9@', password_confirmation: 'SecureEntry4!9@') }

    it 'locks account after 5 failed attempts' do
      5.times { user.record_failed_login! }
      expect(user).to be_locked
    end

    it 'implements exponential backoff for lockout duration' do
      # First lockout (5 failed attempts)
      5.times { user.record_failed_login! }
      first_lockout = user.locked_until

      # Additional failed attempts should increase lockout duration
      user.record_failed_login!
      second_lockout = user.locked_until

      expect(second_lockout).to be > first_lockout
    end

    it 'resets failed attempts on successful login' do
      3.times { user.record_failed_login! }
      expect(user.failed_login_attempts).to eq(3)

      user.record_successful_login!
      expect(user.failed_login_attempts).to eq(0)
      expect(user.locked_until).to be_nil
    end

    it 'can manually unlock account' do
      5.times { user.record_failed_login! }
      expect(user).to be_locked

      user.unlock!
      expect(user).not_to be_locked
      expect(user.failed_login_attempts).to eq(0)
    end

    it 'tracks last login time' do
      expect {
        user.record_successful_login!
      }.to change(user, :last_login_at).from(nil)
    end
  end

  describe 'Password Reset Security' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'OriginalEntry4!9@', password_confirmation: 'OriginalEntry4!9@') }

    it 'generates secure time-limited reset token' do
      token = user.generate_reset_token!
      
      expect(token).to be_present
      expect(user.reset_token_digest).to be_present
      # Check that expiration is set to sometime in the future
      expect(user.reset_token_expires_at).to be > Time.current
    end

    it 'validates reset token correctly' do
      token = user.generate_reset_token!
      expect(user.reset_token_valid?(token)).to be true
    end

    it 'rejects expired reset tokens' do
      token = user.generate_reset_token!
      
      # Simulate token expiration
      user.update!(reset_token_expires_at: 1.hour.ago)
      
      expect(user.reset_token_valid?(token)).to be false
    end

    it 'rejects invalid reset tokens' do
      user.generate_reset_token!
      fake_token = 'invalid.token.here'
      
      expect(user.reset_token_valid?(fake_token)).to be false
    end

    it 'successfully resets password with valid token' do
      token = user.generate_reset_token!
      new_password = 'NewSecureEntry4!9@'
      
      expect(user.reset_password!(new_password, token)).to be true
      expect(user.reset_token_digest).to be_nil
      expect(user.reset_token_expires_at).to be_nil
    end

    it 'clears reset token after password change' do
      token = user.generate_reset_token!
      
      user.update!(password: 'AnotherEntry4!9@', password_confirmation: 'AnotherEntry4!9@')
      
      expect(user.reset_token_digest).to be_nil
      expect(user.reset_token_expires_at).to be_nil
    end

    it 'single-use reset tokens' do
      token = user.generate_reset_token!
      new_password = 'NewSecureEntry4!9@'
      
      user.reset_password!(new_password, token)
      
      # Token should no longer be valid
      expect(user.reset_token_valid?(token)).to be false
    end
  end

  describe 'Password Aging and Security Metrics' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'TestEntry4!9@', password_confirmation: 'TestEntry4!9@') }

    it 'tracks password age' do
      user.update!(password_changed_at: 30.days.ago)
      expect(user.password_age_days).to eq(30)
    end

    it 'returns nil for password age when not set' do
      user.update!(password_changed_at: nil)
      expect(user.password_age_days).to be_nil
    end

    it 'calculates password strength for new passwords' do
      strong_password = 'VerySecureEntry4!9@#'
      user.password = strong_password
      expect(user.password_strength).to be >= 70
    end
  end

  describe 'Integration with Authentication Controllers' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account, password: 'SecureEntry4!9@', password_confirmation: 'SecureEntry4!9@') }

    it 'enforces password requirements during registration' do
      expect {
        create(:user, account: account, password: 'weak', password_confirmation: 'weak')
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'allows registration with strong password' do
      expect {
        create(:user, account: account, password: 'StrongRegistration4!9@', password_confirmation: 'StrongRegistration4!9@')
      }.not_to raise_error
    end
  end
end