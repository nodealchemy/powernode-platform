# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chat::Channel, type: :model do
  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:default_agent).class_name('Ai::Agent').optional }
    it { should have_many(:sessions).class_name('Chat::Session').dependent(:destroy) }
    it { should have_many(:blacklists).class_name('Chat::Blacklist').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:chat_channel) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:platform) }
    it { should validate_inclusion_of(:platform).in_array(%w[whatsapp telegram discord slack mattermost]) }
    it { should validate_inclusion_of(:status).in_array(%w[connected disconnected connecting error]) }
    it { should validate_numericality_of(:rate_limit_per_minute).is_greater_than(0).is_less_than_or_equal_to(1000) }

    context 'name uniqueness' do
      let(:account) { create(:account) }
      let!(:existing_channel) { create(:chat_channel, name: 'Test Channel', platform: 'telegram', account: account) }

      it 'validates uniqueness of name within account and platform scope' do
        duplicate_channel = build(:chat_channel, name: 'Test Channel', platform: 'telegram', account: account)
        expect(duplicate_channel).not_to be_valid
        expect(duplicate_channel.errors[:name]).to include('has already been taken')
      end

      it 'allows same name for different platforms' do
        channel = build(:chat_channel, name: 'Test Channel', platform: 'discord', account: account)
        expect(channel).to be_valid
      end

      it 'allows same name for different accounts' do
        different_account = create(:account)
        channel = build(:chat_channel, name: 'Test Channel', platform: 'telegram', account: different_account)
        expect(channel).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:connected_channel) { create(:chat_channel, :connected) }
    let!(:disconnected_channel) { create(:chat_channel, :disconnected) }
    let!(:telegram_channel) { create(:chat_channel, :telegram) }
    let!(:discord_channel) { create(:chat_channel, :discord) }

    describe '.connected' do
      it 'returns only connected channels' do
        expect(Chat::Channel.connected).to include(connected_channel)
        expect(Chat::Channel.connected).not_to include(disconnected_channel)
      end
    end

    describe '.by_platform' do
      it 'filters by platform' do
        expect(Chat::Channel.by_platform('telegram')).to include(telegram_channel)
        expect(Chat::Channel.by_platform('telegram')).not_to include(discord_channel)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create' do
      it 'generates webhook_token if not provided' do
        channel = create(:chat_channel, webhook_token: nil)
        expect(channel.webhook_token).to be_present
        expect(channel.webhook_token.length).to be >= 32
      end
    end
  end

  describe 'status check methods' do
    describe '#connected?' do
      it 'returns true when status is connected' do
        channel = build(:chat_channel, :connected)
        expect(channel.connected?).to be true
      end

      it 'returns false when status is not connected' do
        channel = build(:chat_channel, :disconnected)
        expect(channel.connected?).to be false
      end
    end

    describe '#disconnected?' do
      it 'returns true when status is disconnected' do
        channel = build(:chat_channel, :disconnected)
        expect(channel.disconnected?).to be true
      end
    end
  end

  describe '#channel_summary' do
    let(:channel) { create(:chat_channel, :connected) }

    it 'returns channel summary information' do
      summary = channel.channel_summary
      expect(summary).to include(:id, :name, :platform, :status)
    end
  end

  describe '#channel_details' do
    let(:channel) { create(:chat_channel, :connected) }

    it 'returns detailed channel information' do
      details = channel.channel_details
      expect(details).to include(:id, :name, :platform, :status, :rate_limit_per_minute)
    end
  end

  describe 'has_many :messages through :sessions' do
    let(:channel) { create(:chat_channel) }
    let!(:session) { create(:chat_session, channel: channel) }
    let!(:message) { create(:chat_message, session: session) }

    it 'accesses messages through sessions' do
      expect(channel.messages).to include(message)
    end
  end

  describe '#regenerate_webhook_token!' do
    let(:channel) { create(:chat_channel) }

    it 'generates a new webhook token' do
      old_token = channel.webhook_token
      channel.regenerate_webhook_token!
      expect(channel.reload.webhook_token).not_to eq(old_token)
      expect(channel.webhook_token).to be_present
    end
  end

  describe '#rate_limited?' do
    let(:channel) { create(:chat_channel, rate_limit_per_minute: 5) }

    it 'returns false when under limit' do
      Rails.cache.write(channel.rate_limit_key, 3, expires_in: 1.minute)
      expect(channel.rate_limited?).to be false
    end

    it 'returns true when at or above limit' do
      Rails.cache.write(channel.rate_limit_key, 5, expires_in: 1.minute)
      expect(channel.rate_limited?).to be true
    end
  end

  describe '#find_or_create_session' do
    let(:channel) { create(:chat_channel, :with_default_agent) }

    it 'creates a new session for unknown user' do
      session = channel.find_or_create_session(platform_user_id: 'new_user_123', platform_username: 'NewUser')
      expect(session).to be_persisted
      expect(session.platform_user_id).to eq('new_user_123')
      expect(session.assigned_agent).to eq(channel.default_agent)
    end

    it 'returns existing session for known user' do
      existing = channel.find_or_create_session(platform_user_id: 'existing_user')
      found = channel.find_or_create_session(platform_user_id: 'existing_user')
      expect(found.id).to eq(existing.id)
    end
  end

  describe '#user_blacklisted?' do
    let(:channel) { create(:chat_channel) }

    it 'returns false for non-blacklisted user' do
      expect(channel.user_blacklisted?('good_user')).to be false
    end

    it 'returns true for channel-blacklisted user' do
      create(:chat_blacklist, :channel_specific, channel: channel, account: channel.account,
             platform_user_id: 'bad_user')
      expect(channel.user_blacklisted?('bad_user')).to be true
    end

    it 'returns false for expired blacklist' do
      create(:chat_blacklist, :channel_specific, :expired, channel: channel, account: channel.account,
             platform_user_id: 'temp_user')
      expect(channel.user_blacklisted?('temp_user')).to be false
    end
  end
end
