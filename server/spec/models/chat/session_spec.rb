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

  describe '#activate!' do
    let(:session) { create(:chat_session, :idle) }

    it 'changes status to active' do
      session.activate!
      expect(session.reload.status).to eq('active')
    end
  end

  describe '#mark_idle!' do
    let(:session) { create(:chat_session, :active) }

    it 'changes status to idle when active' do
      session.mark_idle!
      expect(session.reload.status).to eq('idle')
    end

    it 'does not change status when not active' do
      closed_session = create(:chat_session, :closed)
      closed_session.mark_idle!
      expect(closed_session.reload.status).to eq('closed')
    end
  end

  describe '#block!' do
    let(:session) { create(:chat_session, :active) }

    it 'changes status to blocked' do
      session.block!(reason: 'spam')
      expect(session.reload.status).to eq('blocked')
      expect(session.user_metadata['block_reason']).to eq('spam')
    end
  end

  describe '#reopen!' do
    it 'changes closed session to active' do
      session = create(:chat_session, :closed)
      session.reopen!
      expect(session.reload.status).to eq('active')
    end

    it 'returns false when session is blocked' do
      session = create(:chat_session, :blocked)
      expect(session.reopen!).to be false
      expect(session.reload.status).to eq('blocked')
    end
  end

  describe '#add_inbound_message' do
    let(:session) { create(:chat_session) }

    it 'creates an inbound message with sanitized content' do
      message = session.add_inbound_message(content: 'Hello')
      expect(message).to be_persisted
      expect(message.direction).to eq('inbound')
      expect(message.delivery_status).to eq('delivered')
      expect(message.sanitized_content).to include('Hello')
    end

    it 'increments message_count' do
      expect { session.add_inbound_message(content: 'Test') }.to change { session.reload.message_count }.by(1)
    end
  end

  describe '#add_outbound_message' do
    let(:session) { create(:chat_session) }

    it 'creates an outbound message' do
      message = session.add_outbound_message(content: 'Reply')
      expect(message).to be_persisted
      expect(message.direction).to eq('outbound')
      expect(message.delivery_status).to eq('pending')
    end

    it 'increments message_count' do
      expect { session.add_outbound_message(content: 'Reply') }.to change { session.reload.message_count }.by(1)
    end
  end

  describe '#transfer_to_agent!' do
    let(:session) { create(:chat_session, :with_agent) }
    let(:new_agent) { create(:ai_agent, account: session.channel.account) }

    it 'updates assigned agent' do
      session.transfer_to_agent!(new_agent)
      expect(session.reload.assigned_agent).to eq(new_agent)
    end

    it 'increments agent_handoff_count' do
      expect { session.transfer_to_agent!(new_agent) }.to change { session.reload.agent_handoff_count }.by(1)
    end
  end

  describe 'context window management' do
    let(:session) { create(:chat_session) }

    it 'updates context_window when adding messages' do
      session.add_inbound_message(content: 'User message')
      session.reload
      messages = session.context_window['messages']
      expect(messages).to be_present
      expect(messages.last['role']).to eq('user')
    end
  end
end
