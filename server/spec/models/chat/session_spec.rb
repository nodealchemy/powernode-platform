# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Chat::Session, type: :model do
  describe 'associations' do
    it { should belong_to(:channel).class_name('Chat::Channel') }
    it { should belong_to(:assigned_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:ai_conversation).class_name('Ai::Conversation').optional }
    it { should have_many(:messages).class_name('Chat::Message').dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:chat_session) }

    it { should validate_presence_of(:platform_user_id) }
    it { should validate_inclusion_of(:status).in_array(%w[active idle closed blocked]) }

    context 'platform_user_id uniqueness' do
      let(:channel) { create(:chat_channel) }
      let!(:existing_session) { create(:chat_session, platform_user_id: 'user123', channel: channel) }

      it 'validates uniqueness within channel scope' do
        duplicate_session = build(:chat_session, platform_user_id: 'user123', channel: channel)
        expect(duplicate_session).not_to be_valid
        expect(duplicate_session.errors[:platform_user_id]).to include('has already been taken')
      end

      it 'allows same platform_user_id for different channels' do
        different_channel = create(:chat_channel)
        session = build(:chat_session, platform_user_id: 'user123', channel: different_channel)
        expect(session).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_session) { create(:chat_session, :active) }
    let!(:idle_session) { create(:chat_session, :idle) }
    let!(:closed_session) { create(:chat_session, :closed) }
    let!(:blocked_session) { create(:chat_session, :blocked) }

    describe '.active' do
      it 'returns only active sessions' do
        expect(Chat::Session.active).to include(active_session)
        expect(Chat::Session.active).not_to include(idle_session, closed_session, blocked_session)
      end
    end

    describe '.idle' do
      it 'returns only idle sessions' do
        expect(Chat::Session.idle).to include(idle_session)
        expect(Chat::Session.idle).not_to include(active_session)
      end
    end

    describe '.closed' do
      it 'returns only closed sessions' do
        expect(Chat::Session.closed).to include(closed_session)
      end
    end

    describe '.blocked' do
      it 'returns only blocked sessions' do
        expect(Chat::Session.blocked).to include(blocked_session)
      end
    end
  end

  describe 'status methods' do
    describe '#active?' do
      it 'returns true when status is active' do
        session = build(:chat_session, :active)
        expect(session.active?).to be true
      end
    end

    describe '#idle?' do
      it 'returns true when status is idle' do
        session = build(:chat_session, :idle)
        expect(session.idle?).to be true
      end
    end

    describe '#closed?' do
      it 'returns true when status is closed' do
        session = build(:chat_session, :closed)
        expect(session.closed?).to be true
      end
    end

    describe '#blocked?' do
      it 'returns true when status is blocked' do
        session = build(:chat_session, :blocked)
        expect(session.blocked?).to be true
      end
    end
  end

  describe '#close!' do
    let(:session) { create(:chat_session, :active) }

    it 'changes status to closed' do
      session.close!
      expect(session.reload.status).to eq('closed')
    end
  end

  describe '#reopen!' do
    let(:session) { create(:chat_session, :closed) }

    it 'changes status to active' do
      session.reopen!
      expect(session.reload.status).to eq('active')
    end
  end

  describe '#context_for_agent' do
    let(:session) { create(:chat_session) }

    it 'returns context for agent processing' do
      context = session.context_for_agent

      expect(context[:session_id]).to eq(session.id)
      expect(context[:platform_user_id]).to eq(session.platform_user_id)
      expect(context).to have_key(:message_history)
    end
  end

  describe '#session_summary' do
    let(:session) { create(:chat_session, :with_messages) }

    it 'returns session summary' do
      summary = session.session_summary
      expect(summary).to include(:id, :platform_user_id, :status, :message_count)
    end
  end
end
