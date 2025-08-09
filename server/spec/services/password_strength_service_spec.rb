require 'rails_helper'

RSpec.describe PasswordStrengthService, type: :service do
  describe '.validate_password' do
    subject { described_class.validate_password(password) }

    context 'with a strong password' do
      let(:password) { 'MySecure$Phrase2024!' }

      it 'returns valid result' do
        expect(subject[:valid]).to be true
        expect(subject[:errors]).to be_empty
        expect(subject[:score]).to be >= 60
        expect([ 'strong', 'very_strong' ]).to include(subject[:strength])
      end
    end

    context 'with password too short' do
      let(:password) { 'Short1!' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password must be at least 12 characters long')
      end
    end

    context 'with password too long' do
      let(:password) { 'A' * 129 }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password cannot be longer than 128 characters')
      end
    end

    context 'without uppercase letter' do
      let(:password) { 'mylowercasepassword123!' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password must contain at least one uppercase letter')
      end
    end

    context 'without lowercase letter' do
      let(:password) { 'MYUPPERCASEPASSWORD123!' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password must contain at least one lowercase letter')
      end
    end

    context 'without number' do
      let(:password) { 'MyPasswordWithoutNumbers!' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password must contain at least one number')
      end
    end

    context 'without special character' do
      let(:password) { 'MyPasswordWithoutSpecial123' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password must contain at least one special character')
      end
    end

    context 'with common password' do
      let(:password) { 'password123' }

      it 'returns validation error' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password is too common and easily guessable')
      end
    end

    context 'with repeated characters' do
      let(:password) { 'MyPasswordaaa123!' }

      it 'returns validation error for common patterns' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password contains common patterns that make it weak')
      end
    end

    context 'with sequential patterns' do
      let(:password) { 'MyPassword123abc!' }

      it 'returns validation error for sequential patterns' do
        expect(subject[:valid]).to be false
        expect(subject[:errors]).to include('Password contains common patterns that make it weak')
      end
    end
  end

  describe '.score_password' do
    subject { described_class.score_password(password) }

    context 'with empty password' do
      let(:password) { '' }

      it 'returns zero score' do
        expect(subject).to eq(0)
      end
    end

    context 'with very weak password' do
      let(:password) { 'abc' }

      it 'returns very low score' do
        expect(subject).to be < 30
      end
    end

    context 'with moderate password' do
      let(:password) { 'MyPassword123!' }

      it 'returns moderate score' do
        expect(subject).to be_between(50, 70)
      end
    end

    context 'with strong password' do
      let(:password) { 'MyVerySecure$Password2024!' }

      it 'returns high score' do
        expect(subject).to be > 70
      end
    end

    context 'with very strong password' do
      let(:password) { 'Th1s!s@V3ryC0mpl3x&S3cur3P@ssw0rd2024#' }

      it 'returns very high score' do
        expect(subject).to be >= 85
      end
    end

    it 'never returns score above 100' do
      password = 'A' * 50 + 'a' * 50 + '1' * 20 + '!' * 8
      expect(described_class.score_password(password)).to be <= 100
    end
  end

  describe '#strength_level' do
    let(:service) { described_class.new(password) }
    subject { service.strength_level }

    context 'with very weak password' do
      let(:password) { 'abc' }

      it 'returns very_weak' do
        expect(subject).to eq('very_weak')
      end
    end

    context 'with weak password' do
      let(:password) { 'password' }

      it 'returns very_weak' do
        expect(subject).to eq('very_weak')
      end
    end

    context 'with moderate password' do
      let(:password) { 'MyPassword123!' }

      it 'returns moderate' do
        expect(subject).to eq('moderate')
      end
    end

    context 'with strong password' do
      let(:password) { 'MyVerySecure$Password2024!' }

      it 'returns very_strong' do
        expect(subject).to eq('very_strong')
      end
    end

    context 'with very strong password' do
      let(:password) { 'Th1s!s@V3ryC0mpl3x&S3cur3P@ssw0rd2024#' }

      it 'returns very_strong' do
        expect(subject).to eq('very_strong')
      end
    end
  end

  describe 'entropy calculation' do
    let(:service) { described_class.new(password) }

    context 'with mixed character sets' do
      let(:password) { 'Abc123!@#' }

      it 'calculates proper character space' do
        score = service.score
        expect(score).to be > 40  # Should get entropy bonus
      end
    end

    context 'with single character set' do
      let(:password) { 'abcdefghijkl' }

      it 'calculates lower entropy' do
        score = service.score
        mixed_score = described_class.new('Abcd1234!@#$').score
        expect(score).to be < mixed_score
      end
    end
  end

  describe 'common password detection' do
    PasswordStrengthService::COMMON_PASSWORDS.sample(5).each do |common_password|
      context "with common password '#{common_password}'" do
        let(:password) { common_password }

        it 'detects as common password' do
          result = described_class.validate_password(password)
          expect(result[:valid]).to be false
          expect(result[:errors]).to include('Password is too common and easily guessable')
        end
      end
    end
  end
end
