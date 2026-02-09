# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::TeamChannel, type: :model do
  describe 'associations' do
    it { should belong_to(:agent_team).class_name('Ai::AgentTeam') }
    it { should have_many(:messages).class_name('Ai::TeamMessage').with_foreign_key(:channel_id).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_team_channel) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:channel_type) }
    it { should validate_inclusion_of(:channel_type).in_array(Ai::TeamChannel::CHANNEL_TYPES) }

    context 'name uniqueness' do
      let(:team) { create(:ai_agent_team) }
      let!(:existing) { create(:ai_team_channel, name: 'General', agent_team: team) }

      it 'validates uniqueness scoped to agent_team_id' do
        dup = build(:ai_team_channel, name: 'General', agent_team: team)
        expect(dup).not_to be_valid
        expect(dup.errors[:name]).to include('has already been taken')
      end

      it 'allows same name for different teams' do
        other_team = create(:ai_agent_team)
        channel = build(:ai_team_channel, name: 'General', agent_team: other_team)
        expect(channel).to be_valid
      end
    end
  end

  describe 'scopes' do
    let(:team) { create(:ai_agent_team) }
    let!(:broadcast_ch) { create(:ai_team_channel, :broadcast, agent_team: team) }
    let!(:direct_ch) { create(:ai_team_channel, :direct, agent_team: team) }
    let!(:topic_ch) { create(:ai_team_channel, :topic, agent_team: team) }
    let!(:task_ch) { create(:ai_team_channel, :task, agent_team: team) }
    let!(:escalation_ch) { create(:ai_team_channel, :escalation, agent_team: team) }
    let!(:persistent_ch) { create(:ai_team_channel, agent_team: team, is_persistent: true) }
    let!(:non_persistent_ch) { create(:ai_team_channel, :non_persistent, agent_team: team) }

    describe '.broadcast' do
      it 'returns only broadcast channels' do
        expect(described_class.broadcast).to include(broadcast_ch)
        expect(described_class.broadcast).not_to include(direct_ch, topic_ch)
      end
    end

    describe '.direct' do
      it 'returns only direct channels' do
        expect(described_class.direct).to include(direct_ch)
        expect(described_class.direct).not_to include(broadcast_ch)
      end
    end

    describe '.topic_channels' do
      it 'returns only topic channels' do
        expect(described_class.topic_channels).to include(topic_ch)
        expect(described_class.topic_channels).not_to include(broadcast_ch)
      end
    end

    describe '.task_channels' do
      it 'returns only task channels' do
        expect(described_class.task_channels).to include(task_ch)
        expect(described_class.task_channels).not_to include(broadcast_ch)
      end
    end

    describe '.escalation' do
      it 'returns only escalation channels' do
        expect(described_class.escalation).to include(escalation_ch)
        expect(described_class.escalation).not_to include(broadcast_ch)
      end
    end

    describe '.persistent' do
      it 'returns only persistent channels' do
        expect(described_class.persistent).to include(persistent_ch)
        expect(described_class.persistent).not_to include(non_persistent_ch)
      end
    end
  end

  describe 'type predicates' do
    it '#broadcast? returns true for broadcast type' do
      expect(build(:ai_team_channel, :broadcast).broadcast?).to be true
      expect(build(:ai_team_channel, :direct).broadcast?).to be false
    end

    it '#direct? returns true for direct type' do
      expect(build(:ai_team_channel, :direct).direct?).to be true
      expect(build(:ai_team_channel, :broadcast).direct?).to be false
    end

    it '#topic? returns true for topic type' do
      expect(build(:ai_team_channel, :topic).topic?).to be true
      expect(build(:ai_team_channel, :broadcast).topic?).to be false
    end

    it '#task_channel? returns true for task type' do
      expect(build(:ai_team_channel, :task).task_channel?).to be true
      expect(build(:ai_team_channel, :broadcast).task_channel?).to be false
    end

    it '#escalation? returns true for escalation type' do
      expect(build(:ai_team_channel, :escalation).escalation?).to be true
      expect(build(:ai_team_channel, :broadcast).escalation?).to be false
    end
  end

  describe 'participant management' do
    let(:channel) { create(:ai_team_channel, :direct, participant_roles: []) }
    let(:role_id) { SecureRandom.uuid }

    describe '#add_participant' do
      it 'adds a role ID to participant_roles' do
        channel.add_participant(role_id)
        expect(channel.reload.participant_roles).to include(role_id)
      end

      it 'does not add duplicate role IDs' do
        channel.add_participant(role_id)
        channel.add_participant(role_id)
        expect(channel.reload.participant_roles.count(role_id)).to eq(1)
      end
    end

    describe '#remove_participant' do
      it 'removes a role ID from participant_roles' do
        channel.add_participant(role_id)
        channel.remove_participant(role_id)
        expect(channel.reload.participant_roles).not_to include(role_id)
      end
    end

    describe '#has_participant?' do
      it 'returns true when role is a participant' do
        channel.add_participant(role_id)
        expect(channel.has_participant?(role_id)).to be true
      end

      it 'returns false when role is not a participant' do
        expect(channel.has_participant?(SecureRandom.uuid)).to be false
      end

      it 'returns true for any role on broadcast channels' do
        broadcast = create(:ai_team_channel, :broadcast)
        expect(broadcast.has_participant?(SecureRandom.uuid)).to be true
      end
    end
  end

  describe 'message retention' do
    describe '#cleanup_old_messages!' do
      let(:channel) { create(:ai_team_channel, :with_retention, message_retention_hours: 24) }
      let(:execution) { create(:ai_team_execution, agent_team: channel.agent_team) }

      it 'destroys messages older than retention period' do
        old_msg = Ai::TeamMessage.create!(
          team_execution: execution, channel: channel,
          message_type: 'task_update', content: 'Old message'
        )
        old_msg.update_column(:created_at, 25.hours.ago)

        recent_msg = Ai::TeamMessage.create!(
          team_execution: execution, channel: channel,
          message_type: 'task_update', content: 'Recent message'
        )

        channel.cleanup_old_messages!

        expect(Ai::TeamMessage.exists?(old_msg.id)).to be false
        expect(Ai::TeamMessage.exists?(recent_msg.id)).to be true
      end

      it 'is a no-op when message_retention_hours is nil' do
        channel_no_retention = create(:ai_team_channel)
        expect { channel_no_retention.cleanup_old_messages! }.not_to raise_error
      end
    end
  end

  describe 'helpers' do
    let(:channel) { create(:ai_team_channel) }
    let(:execution) { create(:ai_team_execution, agent_team: channel.agent_team) }

    describe '#message_count' do
      it 'returns the number of messages' do
        3.times do
          Ai::TeamMessage.create!(
            team_execution: execution, channel: channel,
            message_type: 'task_update', content: 'msg'
          )
        end

        expect(channel.message_count).to eq(3)
      end
    end

    describe '#recent_messages' do
      it 'returns messages ordered by newest first with limit' do
        msgs = 5.times.map do |i|
          msg = Ai::TeamMessage.create!(
            team_execution: execution, channel: channel,
            message_type: 'task_update', content: "msg #{i}"
          )
          msg.update_column(:created_at, i.hours.ago)
          msg
        end

        recent = channel.recent_messages(3)
        expect(recent.count).to eq(3)
        expect(recent.first.content).to eq('msg 0')
      end
    end
  end
end
