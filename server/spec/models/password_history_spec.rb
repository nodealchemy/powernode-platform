require 'rails_helper'

RSpec.describe PasswordHistory, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    it { should validate_presence_of(:password_digest) }
    it { should validate_presence_of(:created_at) }
  end

  describe 'scopes' do
    let!(:old_entry) { create(:password_history, user: user, created_at: 1.month.ago) }
    let!(:recent_entry) { create(:password_history, user: user, created_at: 1.day.ago) }

    describe '.recent' do
      it 'orders by created_at descending' do
        expect(described_class.recent).to eq([ recent_entry, old_entry ])
      end
    end

    describe '.for_user' do
      let(:other_user) { create(:user, account: account) }
      let!(:other_entry) { create(:password_history, user: other_user) }

      it 'returns only entries for the specified user' do
        expect(described_class.for_user(user)).to contain_exactly(old_entry, recent_entry)
        expect(described_class.for_user(other_user)).to contain_exactly(other_entry)
      end
    end
  end

  describe '.add_for_user' do
    let(:password_digest) { BCrypt::Password.create('new_password123!') }

    it 'creates a new password history entry' do
      expect {
        described_class.add_for_user(user, password_digest)
      }.to change(described_class, :count).by(1)

      entry = described_class.last
      expect(entry.user).to eq(user)
      expect(entry.password_digest).to eq(password_digest)
      expect(entry.created_at).to be_within(1.second).of(Time.current)
    end
  end

  describe '.cleanup_old_entries' do
    let!(:entries) do
      15.times.map do |i|
        create(:password_history,
               user: user,
               created_at: (i + 1).days.ago)
      end
    end

    it 'keeps only the specified number of recent entries' do
      expect {
        described_class.cleanup_old_entries(user, 12)
      }.to change { user.password_histories.count }.from(15).to(12)

      remaining_entries = user.password_histories.recent
      expect(remaining_entries.count).to eq(12)

      # Should keep the 12 most recent entries
      expected_dates = entries.sort_by(&:created_at).reverse.first(12).map(&:created_at)
      actual_dates = remaining_entries.map(&:created_at)

      expect(actual_dates).to match_array(expected_dates)
    end

    it 'does nothing if user has fewer entries than keep_count' do
      user.password_histories.destroy_all
      create(:password_history, user: user)

      expect {
        described_class.cleanup_old_entries(user, 12)
      }.not_to change { user.password_histories.count }
    end
  end

  describe '.password_recently_used?' do
    let(:password) { 'test_password123!' }
    let(:different_password) { 'different_password456!' }

    context 'with new user' do
      let(:new_user) { build(:user, account: account) }

      it 'returns false for new user' do
        expect(described_class.password_recently_used?(new_user, password)).to be false
      end
    end

    context 'with existing user' do
      before do
        # Create password history entries
        3.times do |i|
          digest = BCrypt::Password.create("old_password_#{i}!")
          create(:password_history,
                 user: user,
                 password_digest: digest,
                 created_at: (i + 1).days.ago)
        end

        # Add the test password to history
        digest = BCrypt::Password.create(password)
        create(:password_history,
               user: user,
               password_digest: digest,
               created_at: 2.days.ago)
      end

      it 'returns true for recently used password' do
        expect(described_class.password_recently_used?(user, password)).to be true
      end

      it 'returns false for password not in history' do
        expect(described_class.password_recently_used?(user, different_password)).to be false
      end

      it 'only checks last 12 passwords' do
        # Add 12 more password history entries, all more recent than the test password
        # This will push the test password (which was added 2 days ago) out of the 12 most recent
        12.times do |i|
          digest = BCrypt::Password.create("newer_password_#{i}!")
          create(:password_history,
                 user: user,
                 password_digest: digest,
                 created_at: 1.hour.ago + (i * 10.minutes))  # All more recent than the test password
        end

        # The original test password should now be outside the 12 most recent
        expect(described_class.password_recently_used?(user, password)).to be false
      end
    end
  end

  describe 'database constraints' do
    it 'requires password_digest' do
      history = build(:password_history, password_digest: nil)
      expect(history).not_to be_valid
      expect(history.errors[:password_digest]).to include("can't be blank")
    end

    it 'requires created_at' do
      history = build(:password_history, created_at: nil)
      expect(history).not_to be_valid
      expect(history.errors[:created_at]).to include("can't be blank")
    end
  end
end
