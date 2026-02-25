# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TeamMessage, type: :model do
  let(:account) { create(:account) }
  let(:team) { create(:ai_agent_team, account: account) }
  let(:execution) { Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Test', started_at: Time.current) }

  describe 'associations' do
    it { should belong_to(:team_execution).class_name('Ai::TeamExecution').optional }
    it { should belong_to(:channel).class_name('Ai::TeamChannel').optional }
    it { should belong_to(:from_role).class_name('Ai::TeamRole').optional }
    it { should belong_to(:to_role).class_name('Ai::TeamRole').optional }
    it { should belong_to(:in_reply_to).class_name('Ai::TeamMessage').optional }
    it { should have_many(:replies).class_name('Ai::TeamMessage').with_foreign_key(:in_reply_to_id).dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:ai_team_message) }

    it { should validate_presence_of(:content) }
    it { should validate_inclusion_of(:message_type).in_array(Ai::TeamMessage::MESSAGE_TYPES) }
    it { should validate_inclusion_of(:priority).in_array(Ai::TeamMessage::PRIORITIES).allow_nil }
  end

  describe 'callbacks' do
    describe 'set_sequence_number' do
      it 'auto-increments sequence_number per execution' do
        m1 = Ai::TeamMessage.create!(team_execution: execution, message_type: 'task_update', content: 'First')
        m2 = Ai::TeamMessage.create!(team_execution: execution, message_type: 'task_update', content: 'Second')

        expect(m1.sequence_number).to eq(1)
        expect(m2.sequence_number).to eq(2)
      end

      it 'tracks separate sequences per execution' do
        exec2 = Ai::TeamExecution.create!(account: account, agent_team: team, status: 'running', objective: 'Other', started_at: Time.current)

        m1 = Ai::TeamMessage.create!(team_execution: execution, message_type: 'task_update', content: 'E1-M1')
        m2 = Ai::TeamMessage.create!(team_execution: exec2, message_type: 'task_update', content: 'E2-M1')

        expect(m1.sequence_number).to eq(1)
        expect(m2.sequence_number).to eq(1)
      end
    end

    describe 'record_message_on_execution' do
      it 'increments messages_exchanged on execution' do
        expect {
          Ai::TeamMessage.create!(team_execution: execution, message_type: 'task_update', content: 'Hello')
        }.to change { execution.reload.messages_exchanged }.by(1)
      end
    end
  end

  describe 'type predicates' do
    Ai::TeamMessage::MESSAGE_TYPES.each do |msg_type|
      method_name = "#{msg_type}?"

      it "##{method_name} returns true for #{msg_type}" do
        message = build(:ai_team_message, message_type: msg_type)
        expect(message.send(method_name)).to be true
      end

      it "##{method_name} returns false for other types" do
        other_type = (Ai::TeamMessage::MESSAGE_TYPES - [msg_type]).first
        message = build(:ai_team_message, message_type: other_type)
        expect(message.send(method_name)).to be false
      end
    end
  end

  describe 'read/response tracking' do
    let(:message) { Ai::TeamMessage.create!(team_execution: execution, message_type: 'question', content: 'Help?', requires_response: true) }

    describe '#mark_read!' do
      it 'sets read_at' do
        message.mark_read!
        expect(message.reload.read_at).to be_present
      end

      it 'is idempotent - does not change read_at on second call' do
        message.mark_read!
        first_read_at = message.reload.read_at
        sleep 0.01
        message.mark_read!
        expect(message.reload.read_at).to eq(first_read_at)
      end
    end

    describe '#mark_responded!' do
      it 'sets responded_at' do
        message.mark_responded!
        expect(message.reload.responded_at).to be_present
      end

      it 'is idempotent' do
        message.mark_responded!
        first_responded_at = message.reload.responded_at
        sleep 0.01
        message.mark_responded!
        expect(message.reload.responded_at).to eq(first_responded_at)
      end
    end

    describe '#read?' do
      it 'returns false when unread' do
        expect(message.read?).to be false
      end

      it 'returns true after mark_read!' do
        message.mark_read!
        expect(message.read?).to be true
      end
    end

    describe '#responded?' do
      it 'returns false when not responded' do
        expect(message.responded?).to be false
      end

      it 'returns true after mark_responded!' do
        message.mark_responded!
        expect(message.responded?).to be true
      end
    end

    describe '#pending_response?' do
      it 'returns true when requires_response and not responded' do
        expect(message.pending_response?).to be true
      end

      it 'returns false after being responded to' do
        message.mark_responded!
        expect(message.pending_response?).to be false
      end

      it 'returns false when requires_response is false' do
        no_response = Ai::TeamMessage.create!(team_execution: execution, message_type: 'task_update', content: 'FYI', requires_response: false)
        expect(no_response.pending_response?).to be false
      end
    end
  end

  describe '#reply!' do
    let(:role1) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'lead', role_type: 'manager') }
    let(:role2) { Ai::TeamRole.create!(account: account, agent_team: team, role_name: 'dev', role_type: 'worker') }
    let(:original) do
      Ai::TeamMessage.create!(
        team_execution: execution, from_role: role1, to_role: role2,
        message_type: 'question', content: 'Status?', requires_response: true
      )
    end

    it 'creates a linked reply message' do
      reply = original.reply!(from: role2, content: 'All good')
      expect(reply).to be_persisted
      expect(reply.in_reply_to).to eq(original)
      expect(reply.from_role).to eq(role2)
      expect(reply.to_role).to eq(role1)
      expect(reply.message_type).to eq('answer')
    end

    it 'marks the original as responded' do
      original.reply!(from: role2, content: 'Done')
      expect(original.reload.responded?).to be true
    end
  end

  describe 'priority helpers' do
    describe '#urgent?' do
      it 'returns true for urgent priority' do
        expect(build(:ai_team_message, priority: 'urgent').urgent?).to be true
      end

      it 'returns false for other priorities' do
        expect(build(:ai_team_message, priority: 'high').urgent?).to be false
      end
    end

    describe '#high_priority?' do
      it 'returns true for high priority' do
        expect(build(:ai_team_message, priority: 'high').high_priority?).to be true
      end

      it 'returns true for urgent priority' do
        expect(build(:ai_team_message, priority: 'urgent').high_priority?).to be true
      end

      it 'returns false for normal priority' do
        expect(build(:ai_team_message, priority: 'normal').high_priority?).to be false
      end
    end
  end
end
