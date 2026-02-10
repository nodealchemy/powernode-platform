# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::IntegrityService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account) }

  # ============================================================
  # seal
  # ============================================================
  describe '#seal' do
    context 'with SharedKnowledge' do
      let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "Rails best practices") }

      it 'computes and stores an integrity hash' do
        result = service.seal(knowledge)

        expect(result[:sealed]).to be true
        expect(result[:hash]).to be_a(String)
        expect(result[:hash].length).to eq(64) # SHA-256 hex digest
        expect(result[:entry_id]).to eq(knowledge.id)
      end

      it 'persists the hash on the model' do
        service.seal(knowledge)

        knowledge.reload
        expect(knowledge.integrity_hash).to be_present
        expect(knowledge.integrity_hash.length).to eq(64)
      end

      it 'produces deterministic hashes for the same content' do
        result1 = service.seal(knowledge)

        knowledge.reload
        # Seal again without changing content should produce same hash
        hash = Digest::SHA256.hexdigest({
          content: knowledge.content.to_s,
          metadata: {
            "title" => knowledge.title,
            "content_type" => knowledge.content_type,
            "source_type" => knowledge.source_type,
            "account_id" => knowledge.account_id
          }.sort.to_h
        }.to_json)

        expect(result1[:hash]).to eq(hash)
      end
    end

    context 'with AgentShortTermMemory' do
      let(:memory) do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "test_key",
               memory_value: { "data" => "important_info" },
               memory_type: "observation",
               session_id: SecureRandom.uuid)
      end

      it 'computes and stores a hash in memory_value' do
        result = service.seal(memory)

        expect(result[:sealed]).to be true
        expect(result[:hash]).to be_present

        memory.reload
        expect(memory.memory_value["_integrity_hash"]).to eq(result[:hash])
        expect(memory.memory_value["_sealed_at"]).to be_present
      end

      it 'preserves the original memory value data' do
        service.seal(memory)

        memory.reload
        expect(memory.memory_value["data"]).to eq("important_info")
      end
    end

    context 'with ContextEntry' do
      let(:persistent_context) do
        Ai::PersistentContext.create!(
          account: account,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: agent.id,
          name: "Test Context",
          entry_count: 0
        )
      end

      let(:context_entry) do
        Ai::ContextEntry.create!(
          persistent_context: persistent_context,
          ai_agent_id: agent.id,
          entry_key: "test_entry",
          entry_type: "fact",
          memory_type: "factual",
          content: { "text" => "Test content" },
          version: 1,
          importance_score: 0.8,
          access_count: 0,
          metadata: {}
        )
      end

      it 'computes and stores a hash in metadata' do
        result = service.seal(context_entry)

        expect(result[:sealed]).to be true
        expect(result[:hash]).to be_present

        context_entry.reload
        expect(context_entry.metadata["integrity_hash"]).to eq(result[:hash])
        expect(context_entry.metadata["sealed_at"]).to be_present
      end
    end

    context 'with unsupported entry type' do
      it 'returns sealed: false with the error message' do
        unsupported = User.new(id: SecureRandom.uuid)

        result = service.seal(unsupported)

        expect(result[:sealed]).to be false
        expect(result[:error]).to include("Unsupported entry type")
      end
    end
  end

  # ============================================================
  # verify
  # ============================================================
  describe '#verify' do
    context 'with an untampered entry' do
      let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "Verified content") }

      before { service.seal(knowledge) }

      it 'returns valid for an untampered entry' do
        knowledge.reload
        result = service.verify(knowledge)

        expect(result[:valid]).to be true
        expect(result[:tampered]).to be false
        expect(result[:expected_hash]).to be_present
        expect(result[:actual_hash]).to eq(result[:expected_hash])
      end
    end

    context 'when tampering is detected' do
      let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "Original content") }

      before do
        service.seal(knowledge)
        # Tamper with content without updating hash
        knowledge.update_column(:content, "Tampered content")
      end

      it 'detects the tampering' do
        knowledge.reload
        result = service.verify(knowledge)

        expect(result[:valid]).to be false
        expect(result[:tampered]).to be true
        expect(result[:expected_hash]).not_to eq(result[:actual_hash])
      end
    end

    context 'with an unsealed entry' do
      let(:knowledge) { create(:ai_shared_knowledge, account: account) }

      it 'returns valid with unsealed flag' do
        result = service.verify(knowledge)

        expect(result[:valid]).to be true
        expect(result[:unsealed]).to be true
        expect(result[:tampered]).to be false
      end
    end

    context 'with an AgentShortTermMemory' do
      let(:memory) do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "verify_key",
               memory_value: { "data" => "verify_me" },
               session_id: SecureRandom.uuid)
      end

      it 'verifies an untampered sealed memory' do
        service.seal(memory)
        memory.reload

        result = service.verify(memory)

        expect(result[:valid]).to be true
        expect(result[:tampered]).to be false
      end

      it 'detects tampering in memory_value' do
        service.seal(memory)
        memory.reload

        # Tamper: change data but preserve the integrity hash
        stored_hash = memory.memory_value["_integrity_hash"]
        sealed_at = memory.memory_value["_sealed_at"]
        tampered_value = {
          "data" => "tampered_data",
          "_integrity_hash" => stored_hash,
          "_sealed_at" => sealed_at
        }
        # Use update! to properly serialize jsonb
        memory.update!(memory_value: tampered_value)
        memory.reload

        result = service.verify(memory)

        expect(result[:valid]).to be false
        expect(result[:tampered]).to be true
      end
    end
  end

  # ============================================================
  # audit
  # ============================================================
  describe '#audit' do
    let(:session_id) { SecureRandom.uuid }

    before do
      # Create some STM entries
      3.times do |i|
        mem = create(:ai_agent_short_term_memory,
                     agent: agent,
                     account: account,
                     memory_key: "audit_key_#{i}",
                     memory_value: { "data" => "value_#{i}" },
                     session_id: session_id)
        service.seal(mem) if i < 2 # Only seal first 2
      end
    end

    it 'audits all memory tiers for an agent' do
      result = service.audit(agent: agent)

      expect(result[:total]).to be >= 3
      expect(result[:verified]).to be >= 2
      expect(result[:unsealed]).to be >= 1
      expect(result[:entries]).to be_an(Array)
    end

    it 'filters by tier when specified' do
      result = service.audit(agent: agent, tier: "short_term")

      expect(result[:total]).to be >= 3
    end

    it 'returns zero results for empty tiers' do
      result = service.audit(agent: agent, tier: "long_term")

      expect(result[:total]).to eq(0)
    end
  end

  # ============================================================
  # audit_shared_knowledge
  # ============================================================
  describe '#audit_shared_knowledge' do
    before do
      3.times do |i|
        sk = create(:ai_shared_knowledge, account: account, content: "Knowledge #{i}")
        service.seal(sk) if i < 2 # Only seal first 2
      end
    end

    it 'checks all SharedKnowledge entries for the account' do
      result = service.audit_shared_knowledge

      expect(result[:total]).to eq(3)
      expect(result[:verified]).to eq(2)
      expect(result[:unsealed]).to eq(1)
      expect(result[:failed]).to eq(0)
    end

    it 'detects tampered entries' do
      sk = Ai::SharedKnowledge.where(account_id: account.id).first
      service.seal(sk)
      sk.update_column(:content, "Tampered!")

      result = service.audit_shared_knowledge

      expect(result[:failed]).to be >= 1
      expect(result[:entries].any? { |e| e[:type] == "SharedKnowledge" }).to be true
    end
  end
end
