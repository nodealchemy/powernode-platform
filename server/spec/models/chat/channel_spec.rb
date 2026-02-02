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
end
