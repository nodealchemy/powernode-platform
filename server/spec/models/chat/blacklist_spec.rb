# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chat::Blacklist, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:channel).class_name('Chat::Channel').optional }
    it { should belong_to(:blocked_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:chat_blacklist) }

    it { should validate_presence_of(:platform_user_id) }
    it { should validate_presence_of(:block_type) }
    it { should validate_inclusion_of(:block_type).in_array(%w[temporary permanent]) }

    context 'uniqueness' do
      let(:account) { create(:account) }
      let(:channel) { create(:chat_channel, account: account) }
      let!(:existing_blacklist) { create(:chat_blacklist, platform_user_id: 'blocked123', channel: channel, account: account) }

      it 'validates uniqueness within channel scope' do
        duplicate = build(:chat_blacklist, platform_user_id: 'blocked123', channel: channel, account: account)
        expect(duplicate).not_to be_valid
      end

      it 'allows same platform_user_id for different channels' do
        different_channel = create(:chat_channel, account: account)
        blacklist = build(:chat_blacklist, platform_user_id: 'blocked123', channel: different_channel, account: account)
        expect(blacklist).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let!(:permanent_block) { create(:chat_blacklist, :permanent, account: account) }
    let!(:temporary_block) { create(:chat_blacklist, :temporary, account: account) }
    let!(:expired_block) { create(:chat_blacklist, :expired, account: account) }

    describe '.permanent' do
      it 'returns only permanent blocks' do
        expect(Chat::Blacklist.permanent).to include(permanent_block)
        expect(Chat::Blacklist.permanent).not_to include(temporary_block)
      end
    end

    describe '.temporary' do
      it 'returns only temporary blocks' do
        expect(Chat::Blacklist.temporary).to include(temporary_block)
        expect(Chat::Blacklist.temporary).not_to include(permanent_block)
      end
    end

    describe '.active' do
      it 'returns non-expired blocks' do
        expect(Chat::Blacklist.active).to include(permanent_block, temporary_block)
        expect(Chat::Blacklist.active).not_to include(expired_block)
      end
    end

    describe '.expired' do
      it 'returns only expired blocks' do
        expect(Chat::Blacklist.expired).to include(expired_block)
        expect(Chat::Blacklist.expired).not_to include(permanent_block)
      end
    end
  end

  describe 'block type methods' do
    describe '#permanent?' do
      it 'returns true for permanent blocks' do
        blacklist = build(:chat_blacklist, :permanent)
        expect(blacklist.permanent?).to be true
      end
    end

    describe '#temporary?' do
      it 'returns true for temporary blocks' do
        blacklist = build(:chat_blacklist, :temporary)
        expect(blacklist.temporary?).to be true
      end
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      blacklist = build(:chat_blacklist, :expired)
      expect(blacklist.expired?).to be true
    end

    it 'returns false for permanent blocks' do
      blacklist = build(:chat_blacklist, :permanent)
      expect(blacklist.expired?).to be false
    end

    it 'returns false for non-expired temporary blocks' do
      blacklist = build(:chat_blacklist, :temporary)
      expect(blacklist.expired?).to be false
    end
  end

  describe '#remaining_time' do
    it 'returns remaining duration for temporary blocks' do
      blacklist = create(:chat_blacklist, :temporary, expires_at: 2.days.from_now)
      expect(blacklist.remaining_time).to be > 0
    end

    it 'returns nil for permanent blocks' do
      blacklist = build(:chat_blacklist, :permanent)
      expect(blacklist.remaining_time).to be_nil
    end
  end

  describe '.block_user' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }

    it 'creates a permanent block' do
      blacklist = Chat::Blacklist.block_user(
        account: account,
        platform_user_id: 'user123',
        reason: 'Spam',
        blocked_by: user
      )

      expect(blacklist).to be_persisted
      expect(blacklist.block_type).to eq('permanent')
    end

    it 'creates a temporary block with duration' do
      blacklist = Chat::Blacklist.block_user(
        account: account,
        platform_user_id: 'user123',
        reason: 'Spam',
        blocked_by: user,
        duration: 7.days
      )

      expect(blacklist.block_type).to eq('temporary')
      expect(blacklist.expires_at).to be_present
    end
  end
end
