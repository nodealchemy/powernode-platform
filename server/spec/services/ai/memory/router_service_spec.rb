# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::RouterService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
  let(:session_id) { SecureRandom.uuid }
  let(:redis_double) { double("Redis", get: nil, setex: true, del: 1, keys: []) }

  subject(:service) { described_class.new(account: account, agent: agent) }

  before do
    # Redis.current is used by the service but may not be defined in all Redis gem versions.
    # Define it as a class method so stubs work.
    unless Redis.respond_to?(:current)
      Redis.define_singleton_method(:current) { Redis.new }
    end
    allow(Redis).to receive(:current).and_return(redis_double)
  end

  describe '#read' do
    context 'cascading through tiers' do
      it 'returns found: false when key not in any tier' do
        result = service.read(key: "nonexistent", session_id: session_id)

        expect(result[:found]).to be false
        expect(result[:value]).to be_nil
      end

      it 'returns from short_term when memory exists' do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "test_key",
               memory_value: { data: "hello" },
               expires_at: 1.hour.from_now)

        result = service.read(key: "test_key", session_id: session_id)

        expect(result[:found]).to be true
        expect(result[:tier]).to eq("short_term")
      end
    end

    context 'reading from specific tier' do
      it 'only checks the requested tier' do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "test_key",
               memory_value: { data: "hello" },
               expires_at: 1.hour.from_now)

        result = service.read(key: "test_key", session_id: session_id, tier: "short_term")

        expect(result[:found]).to be true
        expect(result[:tier]).to eq("short_term")
      end

      it 'does not cascade when tier is specified' do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "test_key",
               memory_value: { data: "hello" },
               expires_at: 1.hour.from_now)

        result = service.read(key: "test_key", session_id: session_id, tier: "long_term")

        expect(result[:found]).to be false
      end
    end
  end

  describe '#write' do
    context 'to short_term tier' do
      it 'creates a short-term memory record' do
        result = service.write(
          key: "new_key",
          value: { data: "test" },
          tier: "short_term",
          session_id: session_id
        )

        expect(result[:success]).to be true
        expect(result[:tier]).to eq("short_term")

        memory = Ai::AgentShortTermMemory.find_by(memory_key: "new_key", agent_id: agent.id)
        expect(memory).to be_present
        expect(memory.memory_value).to eq({ "data" => "test" })
      end

      it 'defaults to short_term when no tier specified' do
        result = service.write(
          key: "default_key",
          value: "some value",
          session_id: session_id
        )

        expect(result[:tier]).to eq("short_term")
      end
    end

    context 'to working tier' do
      it 'writes to Redis' do
        result = service.write(
          key: "working_key",
          value: { fast: true },
          tier: "working",
          session_id: session_id
        )

        expect(result[:success]).to be true
        expect(result[:tier]).to eq("working")
        expect(redis_double).to have_received(:setex)
      end

      it 'requires session_id for working memory' do
        result = service.write(
          key: "working_key",
          value: { fast: true },
          tier: "working",
          session_id: nil
        )

        expect(result[:success]).to be false
        expect(result[:error]).to include("session_id")
      end
    end

    context 'with unknown tier' do
      it 'defaults to short_term' do
        result = service.write(
          key: "unknown_tier_key",
          value: "data",
          tier: "nonexistent",
          session_id: session_id
        )

        expect(result[:tier]).to eq("short_term")
      end
    end
  end

  describe '#delete' do
    context 'from short_term' do
      it 'deletes short-term memory records' do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "delete_me",
               expires_at: 1.hour.from_now)

        result = service.delete(key: "delete_me", tier: "short_term", session_id: session_id)

        expect(result[:success]).to be true
        expect(Ai::AgentShortTermMemory.find_by(memory_key: "delete_me")).to be_nil
      end
    end

    context 'from working' do
      it 'deletes from Redis' do
        result = service.delete(key: "working_key", tier: "working", session_id: session_id)

        expect(result[:success]).to be true
        expect(redis_double).to have_received(:del)
      end
    end

    context 'from long_term' do
      it 'deprecates rather than deletes' do
        result = service.delete(key: "lt_key", tier: "long_term")

        expect(result[:success]).to be true
        expect(result[:tier]).to eq("long_term")
      end
    end

    context 'from shared' do
      it 'returns error — shared knowledge cannot be deleted via router' do
        result = service.delete(key: "shared_key", tier: "shared")

        expect(result[:success]).to be false
        expect(result[:error]).to include("cannot be deleted")
      end
    end
  end

  describe '#consolidate!' do
    it 'promotes frequently accessed short-term memories' do
      3.times do |i|
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               session_id: session_id,
               memory_key: "freq_key_#{i}",
               memory_value: { data: "important_#{i}" },
               access_count: 5,
               expires_at: 1.hour.from_now)
      end

      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             memory_key: "rare_key",
             memory_value: { data: "not_important" },
             access_count: 1,
             expires_at: 1.hour.from_now)

      result = service.consolidate!(session_id: session_id)

      expect(result[:consolidated]).to eq(3)
      expect(result[:session_id]).to eq(session_id)
    end
  end

  describe '#stats' do
    it 'returns stats from all tiers' do
      create(:ai_agent_short_term_memory,
             agent: agent,
             account: account,
             session_id: session_id,
             expires_at: 1.hour.from_now)

      result = service.stats

      expect(result).to include(:working, :short_term, :long_term, :shared)
      expect(result[:working]).to include(:count)
      expect(result[:short_term]).to include(:total, :active, :expired)
      expect(result[:long_term]).to include(:total, :active)
      expect(result[:shared]).to include(:total, :with_embedding)
    end
  end
end
