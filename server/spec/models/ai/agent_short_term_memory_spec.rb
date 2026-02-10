# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentShortTermMemory, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
  let(:session_id) { SecureRandom.uuid }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:agent).class_name('Ai::Agent') }
  end

  describe 'validations' do
    subject do
      build(:ai_agent_short_term_memory,
            agent: agent,
            account: account,
            session_id: session_id)
    end

    it { should validate_presence_of(:session_id) }
    it { should validate_presence_of(:memory_key) }
    it { should validate_presence_of(:memory_value) }
    it { should validate_inclusion_of(:memory_type).in_array(%w[general conversation tool_result observation plan state]) }

    it 'enforces uniqueness of memory_key scoped to agent_id and session_id' do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             memory_key: "test_key")

      duplicate = build(:ai_agent_short_term_memory,
                        agent: agent,
                        account: account,
                        session_id: session_id,
                        memory_key: "test_key")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:memory_key]).to include('has already been taken')
    end

    it 'allows same key for different sessions' do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: "session_1",
             memory_key: "shared_key")

      different_session = build(:ai_agent_short_term_memory,
                                agent: agent,
                                account: account,
                                session_id: "session_2",
                                memory_key: "shared_key")

      expect(different_session).to be_valid
    end
  end

  describe 'scopes' do
    let!(:active_memory) do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             memory_key: "active_key",
             expires_at: 1.hour.from_now)
    end

    let!(:expired_memory) do
      create(:ai_agent_short_term_memory, :expired,
             agent: agent,
             account: account,
             session_id: session_id,
             memory_key: "expired_key")
    end

    let(:other_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
    let(:other_session) { SecureRandom.uuid }
    let!(:other_agent_memory) do
      create(:ai_agent_short_term_memory,
             agent: other_agent,
             account: account,
             session_id: other_session)
    end

    describe '.active' do
      it 'returns only non-expired memories' do
        expect(described_class.active).to include(active_memory)
        expect(described_class.active).not_to include(expired_memory)
      end
    end

    describe '.expired' do
      it 'returns only expired memories' do
        expect(described_class.expired).to include(expired_memory)
        expect(described_class.expired).not_to include(active_memory)
      end
    end

    describe '.for_session' do
      it 'returns memories for the given session' do
        expect(described_class.for_session(session_id)).to include(active_memory, expired_memory)
        expect(described_class.for_session(session_id)).not_to include(other_agent_memory)
      end
    end

    describe '.for_agent' do
      it 'returns memories for the given agent' do
        expect(described_class.for_agent(agent.id)).to include(active_memory, expired_memory)
        expect(described_class.for_agent(agent.id)).not_to include(other_agent_memory)
      end
    end

    describe '.by_type' do
      let!(:conversation_memory) do
        create(:ai_agent_short_term_memory, :conversation,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "conv_key")
      end

      it 'returns memories of the given type' do
        expect(described_class.by_type("conversation")).to include(conversation_memory)
        expect(described_class.by_type("conversation")).not_to include(active_memory)
      end
    end
  end

  describe '#expired?' do
    it 'returns true when expires_at is in the past' do
      memory = create(:ai_agent_short_term_memory, :expired,
                      agent: agent,
                      account: account,
                      session_id: session_id)

      expect(memory.expired?).to be true
    end

    it 'returns false when expires_at is in the future' do
      memory = create(:ai_agent_short_term_memory,
                      agent: agent,
                      account: account,
                      session_id: session_id,
                      expires_at: 1.hour.from_now)

      expect(memory.expired?).to be false
    end

    it 'returns false when expires_at is nil' do
      memory = create(:ai_agent_short_term_memory,
                      agent: agent,
                      account: account,
                      session_id: session_id)
      memory.update_columns(expires_at: nil)

      expect(memory.expired?).to be false
    end
  end

  describe '#touch_access!' do
    let(:memory) do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             access_count: 5)
    end

    it 'increments access_count' do
      expect { memory.touch_access! }.to change { memory.reload.access_count }.from(5).to(6)
    end

    it 'updates last_accessed_at' do
      freeze_time do
        memory.touch_access!
        expect(memory.reload.last_accessed_at).to eq(Time.current)
      end
    end
  end

  describe '#refresh_ttl!' do
    let(:memory) do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             ttl_seconds: 3600,
             expires_at: 10.minutes.from_now)
    end

    it 'extends expires_at by ttl_seconds from now' do
      freeze_time do
        memory.refresh_ttl!
        expect(memory.reload.expires_at).to eq(Time.current + 3600.seconds)
      end
    end
  end

  describe '.cleanup_expired!' do
    it 'deletes all expired memories' do
      create(:ai_agent_short_term_memory, :expired,
             agent: agent, account: account, session_id: session_id, memory_key: "exp1")
      create(:ai_agent_short_term_memory, :expired,
             agent: agent, account: account, session_id: session_id, memory_key: "exp2")
      active = create(:ai_agent_short_term_memory,
                      agent: agent, account: account, session_id: session_id, memory_key: "active1",
                      expires_at: 1.hour.from_now)

      expect { described_class.cleanup_expired! }.to change(described_class, :count).by(-2)
      expect(described_class.all).to include(active)
    end
  end

  describe 'callbacks' do
    it 'sets expiration on create when not provided' do
      memory = create(:ai_agent_short_term_memory,
                      agent: agent,
                      account: account,
                      session_id: session_id,
                      ttl_seconds: nil,
                      expires_at: nil)

      expect(memory.ttl_seconds).to eq(Ai::AgentShortTermMemory::DEFAULT_TTL)
      expect(memory.expires_at).to be_present
    end

    it 'sets last_accessed_at on create' do
      memory = create(:ai_agent_short_term_memory,
                      agent: agent,
                      account: account,
                      session_id: session_id,
                      last_accessed_at: nil)

      expect(memory.last_accessed_at).to be_present
    end
  end
end
