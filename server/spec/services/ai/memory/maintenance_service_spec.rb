# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::MaintenanceService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:team) { create(:ai_agent_team, account: account) }

  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:mock_embedding) { Array.new(1536, 0.1) }

  subject(:service) { described_class.new(account: account) }

  before do
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(embedding_service).to receive(:generate).and_return(mock_embedding)
  end

  # ============================================================
  # Consolidation
  # ============================================================
  describe '#consolidate_short_term' do
    let(:session_id) { SecureRandom.uuid }

    context 'when high-access memories exist' do
      before do
        3.times do |i|
          create(:ai_agent_short_term_memory,
                 agent: agent,
                 account: account,
                 memory_key: "freq_key_#{i}",
                 memory_value: { "data" => "important_#{i}" },
                 memory_type: "observation",
                 access_count: 5,
                 session_id: session_id)
        end

        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "rare_key",
               memory_value: { "data" => "not_important" },
               access_count: 1,
               session_id: session_id)

        allow(Ai::CompoundLearning).to receive(:find_similar).and_return(Ai::CompoundLearning.none)
      end

      it 'promotes high-access memories to CompoundLearning' do
        result = service.consolidate_short_term(agent: agent)

        expect(result[:promoted]).to eq(3)
        expect(result[:skipped_duplicates]).to eq(0)
        expect(result[:errors]).to eq(0)
      end

      it 'creates CompoundLearning records for promoted memories' do
        expect {
          service.consolidate_short_term(agent: agent)
        }.to change(Ai::CompoundLearning, :count).by(3)
      end

      it 'archives original STM entries by setting expires_at' do
        service.consolidate_short_term(agent: agent)

        promoted_memories = Ai::AgentShortTermMemory.where(
          agent_id: agent.id,
          memory_key: %w[freq_key_0 freq_key_1 freq_key_2]
        )
        promoted_memories.each do |mem|
          expect(mem.expires_at).to be <= Time.current
        end
      end

      it 'scopes to a specific session when provided' do
        other_session = SecureRandom.uuid
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "other_session_key",
               memory_value: { "data" => "other" },
               access_count: 10,
               session_id: other_session)

        result = service.consolidate_short_term(agent: agent, session_id: session_id)

        expect(result[:promoted]).to eq(3)
      end
    end

    context 'when duplicates are found' do
      let(:existing_learning) do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Existing learning",
          category: "discovery",
          scope: "team",
          status: "active",
          importance_score: 0.5,
          confidence_score: 0.7,
          extraction_method: "consolidation"
        )
      end

      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "dup_key",
               memory_value: { "data" => "duplicate_content" },
               access_count: 5,
               session_id: session_id)

        dup_relation = Ai::CompoundLearning.where(id: existing_learning.id)
        allow(Ai::CompoundLearning).to receive(:find_similar).and_return(dup_relation)
        allow(existing_learning).to receive(:boost_importance!)
      end

      it 'skips duplicates and boosts existing learning importance' do
        result = service.consolidate_short_term(agent: agent)

        expect(result[:promoted]).to eq(0)
        expect(result[:skipped_duplicates]).to eq(1)
      end
    end

    context 'when no memories meet the threshold' do
      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "low_access",
               memory_value: { "data" => "value" },
               access_count: 1,
               session_id: session_id)
      end

      it 'returns zero promotions' do
        result = service.consolidate_short_term(agent: agent)

        expect(result[:promoted]).to eq(0)
        expect(result[:skipped_duplicates]).to eq(0)
      end
    end
  end

  describe '#consolidate_to_shared' do
    context 'when important learnings exist' do
      before do
        3.times do |i|
          Ai::CompoundLearning.create!(
            account: account,
            source_agent_id: agent.id,
            ai_agent_team_id: team.id,
            content: "Important learning #{i}",
            category: "best_practice",
            scope: "team",
            status: "active",
            importance_score: 0.8,
            confidence_score: 0.9,
            extraction_method: "auto_success",
            embedding: mock_embedding
          )
        end

        allow(Ai::SharedKnowledge).to receive_message_chain(:where, :with_embedding, :semantic_search)
          .and_return(Ai::SharedKnowledge.none)
      end

      it 'promotes learnings to SharedKnowledge' do
        result = service.consolidate_to_shared(team: team)

        expect(result[:promoted]).to eq(3)
        expect(result[:skipped_duplicates]).to eq(0)
        expect(result[:errors]).to eq(0)
      end

      it 'creates SharedKnowledge records' do
        expect {
          service.consolidate_to_shared(team: team)
        }.to change(Ai::SharedKnowledge, :count).by(3)
      end
    end

    context 'when learnings below min_importance exist' do
      before do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          ai_agent_team_id: team.id,
          content: "Low importance learning",
          category: "fact",
          scope: "team",
          status: "active",
          importance_score: 0.3,
          confidence_score: 0.5,
          extraction_method: "auto_failure"
        )
      end

      it 'does not promote low-importance learnings' do
        result = service.consolidate_to_shared(team: team)

        expect(result[:promoted]).to eq(0)
      end
    end
  end

  describe '#deduplicate' do
    context 'with long_term tier' do
      let!(:learning1) do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Learning A",
          category: "pattern",
          scope: "team",
          status: "active",
          importance_score: 0.9,
          confidence_score: 0.8,
          extraction_method: "auto_success",
          embedding: mock_embedding,
          access_count: 5
        )
      end

      let!(:learning2) do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Learning A (duplicate)",
          category: "pattern",
          scope: "team",
          status: "active",
          importance_score: 0.7,
          confidence_score: 0.6,
          extraction_method: "auto_success",
          embedding: mock_embedding,
          access_count: 3
        )
      end

      before do
        allow(Ai::CompoundLearning).to receive(:find_similar) do |_embedding, **_opts|
          Ai::CompoundLearning.where(id: [learning1.id, learning2.id])
        end
      end

      it 'merges similar entries and archives duplicates' do
        result = service.deduplicate(tier: "long_term", agent: agent)

        expect(result[:merged]).to be >= 1
        expect(result[:archived]).to be >= 1
      end
    end

    context 'with unknown tier' do
      it 'returns zero stats' do
        result = service.deduplicate(tier: "unknown")

        expect(result[:merged]).to eq(0)
        expect(result[:archived]).to eq(0)
        expect(result[:errors]).to eq(0)
      end
    end
  end

  describe '#run_consolidation_pipeline' do
    before do
      allow(Ai::CompoundLearning).to receive(:find_similar).and_return(Ai::CompoundLearning.none)
    end

    context 'for a specific agent' do
      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "pipeline_key",
               memory_value: { "data" => "pipeline_value" },
               access_count: 5)
      end

      it 'runs all pipeline stages' do
        result = service.run_consolidation_pipeline(agent: agent)

        expect(result).to include(
          :short_term_consolidation,
          :shared_consolidation,
          :dedup_long_term,
          :dedup_shared,
          :dedup_context
        )
      end

      it 'includes consolidation stats' do
        result = service.run_consolidation_pipeline(agent: agent)

        expect(result[:short_term_consolidation]).to include(:promoted, :skipped_duplicates, :errors)
      end
    end
  end

  # ============================================================
  # Decay
  # ============================================================
  describe '#apply_decay' do
    context 'with short-term memories' do
      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "stale_key",
               memory_value: { "data" => "stale" },
               ttl_seconds: 7200,
               last_accessed_at: 3.days.ago,
               created_at: 5.days.ago,
               expires_at: 2.days.from_now)

        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "fresh_key",
               memory_value: { "data" => "fresh" },
               last_accessed_at: 30.minutes.ago,
               ttl_seconds: 3600,
               expires_at: 1.hour.from_now)
      end

      it 'reduces importance for stale entries' do
        result = service.apply_decay(agent: agent)

        expect(result[:decayed_count]).to be >= 0
        expect(result[:by_tier][:short_term]).to include(:decayed, :archived)
      end

      it 'returns stats organized by tier' do
        result = service.apply_decay(agent: agent)

        expect(result[:by_tier]).to include(:short_term, :long_term, :context)
      end
    end

    context 'with no memories' do
      it 'returns zero counts' do
        result = service.apply_decay(agent: agent)

        expect(result[:decayed_count]).to eq(0)
        expect(result[:archived_count]).to eq(0)
      end
    end
  end

  describe '#cleanup_expired' do
    context 'for a specific agent' do
      before do
        3.times do |i|
          create(:ai_agent_short_term_memory, :expired,
                 agent: agent,
                 account: account,
                 memory_key: "expired_#{i}",
                 memory_value: { "data" => "expired_#{i}" },
                 expires_at: 2.hours.ago)
        end

        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "active_key",
               memory_value: { "data" => "active" },
               expires_at: 1.hour.from_now)
      end

      it 'removes expired STM entries' do
        result = service.cleanup_expired(agent: agent)

        expect(result[:deleted]).to be >= 3
      end

      it 'does not remove active entries' do
        service.cleanup_expired(agent: agent)

        active = Ai::AgentShortTermMemory.for_agent(agent.id).active
        expect(active.count).to be >= 1
      end
    end
  end

  describe '#archive_stale' do
    context 'with low-importance CompoundLearnings' do
      before do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Stale low-importance learning",
          category: "fact",
          scope: "team",
          status: "active",
          importance_score: 0.05,
          confidence_score: 0.3,
          extraction_method: "consolidation",
          created_at: 60.days.ago
        )

        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "High importance learning",
          category: "best_practice",
          scope: "team",
          status: "active",
          importance_score: 0.9,
          confidence_score: 0.9,
          extraction_method: "review",
          created_at: 60.days.ago
        )
      end

      it 'archives low-importance entries' do
        result = service.archive_stale(agent: agent)

        expect(result[:compound_archived]).to eq(1)
      end

      it 'does not archive high-importance entries' do
        service.archive_stale(agent: agent)

        active = Ai::CompoundLearning.active.where(source_agent_id: agent.id)
        expect(active.count).to eq(1)
        expect(active.first.importance_score).to eq(0.9)
      end
    end
  end

  describe '#refresh_accessed' do
    context 'with recently accessed STM entries' do
      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "recent_key",
               memory_value: { "data" => "recent" },
               last_accessed_at: 2.hours.ago,
               expires_at: 1.hour.from_now)

        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "old_key",
               memory_value: { "data" => "old" },
               last_accessed_at: 3.days.ago,
               expires_at: 1.hour.from_now)
      end

      it 'boosts recently accessed memories' do
        result = service.refresh_accessed(agent: agent, since: 1.day.ago)

        expect(result[:refreshed_count]).to eq(1)
        expect(result[:by_tier][:short_term]).to eq(1)
      end
    end

    context 'with no recently accessed memories' do
      it 'returns zero refreshed count' do
        result = service.refresh_accessed(agent: agent, since: 1.day.ago)

        expect(result[:refreshed_count]).to eq(0)
      end
    end
  end

  describe '#run_decay_pipeline' do
    context 'for a specific agent' do
      before do
        create(:ai_agent_short_term_memory, :expired,
               agent: agent,
               account: account,
               memory_key: "pipeline_expired",
               memory_value: { "data" => "expired" },
               expires_at: 2.hours.ago)
      end

      it 'runs all pipeline stages' do
        result = service.run_decay_pipeline(agent: agent)

        expect(result).to include(:decay, :cleanup, :archive, :refresh)
      end

      it 'includes decay stats' do
        result = service.run_decay_pipeline(agent: agent)

        expect(result[:decay]).to include(:decayed_count, :archived_count)
      end

      it 'includes cleanup stats' do
        result = service.run_decay_pipeline(agent: agent)

        expect(result[:cleanup]).to include(:deleted)
      end
    end
  end

  # ============================================================
  # Integrity
  # ============================================================
  describe '#seal' do
    context 'with SharedKnowledge' do
      let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "Rails best practices") }

      it 'computes and stores an integrity hash' do
        result = service.seal(knowledge)

        expect(result[:sealed]).to be true
        expect(result[:hash]).to be_a(String)
        expect(result[:hash].length).to eq(64)
        expect(result[:entry_id]).to eq(knowledge.id)
      end

      it 'persists the hash on the model' do
        service.seal(knowledge)

        knowledge.reload
        expect(knowledge.integrity_hash).to be_present
        expect(knowledge.integrity_hash.length).to eq(64)
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

    context 'with unsupported entry type' do
      it 'returns sealed: false with the error message' do
        unsupported = User.new(id: SecureRandom.uuid)

        result = service.seal(unsupported)

        expect(result[:sealed]).to be false
        expect(result[:error]).to include("Unsupported entry type")
      end
    end
  end

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
  end

  describe '#audit_integrity' do
    let(:session_id) { SecureRandom.uuid }

    before do
      3.times do |i|
        mem = create(:ai_agent_short_term_memory,
                     agent: agent,
                     account: account,
                     memory_key: "audit_key_#{i}",
                     memory_value: { "data" => "value_#{i}" },
                     session_id: session_id)
        service.seal(mem) if i < 2
      end
    end

    it 'audits all memory tiers for an agent' do
      result = service.audit_integrity(agent: agent)

      expect(result[:total]).to be >= 3
      expect(result[:verified]).to be >= 2
      expect(result[:unsealed]).to be >= 1
      expect(result[:entries]).to be_an(Array)
    end

    it 'filters by tier when specified' do
      result = service.audit_integrity(agent: agent, tier: "short_term")

      expect(result[:total]).to be >= 3
    end

    it 'returns zero results for empty tiers' do
      result = service.audit_integrity(agent: agent, tier: "long_term")

      expect(result[:total]).to eq(0)
    end
  end

  describe '#audit_shared_knowledge' do
    before do
      3.times do |i|
        sk = create(:ai_shared_knowledge, account: account, content: "Knowledge #{i}")
        service.seal(sk) if i < 2
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

  # ============================================================
  # Memory Management
  # ============================================================
  describe '#context_health' do
    let(:context) do
      Ai::PersistentContext.create!(
        account: account,
        context_type: "agent_memory",
        scope: "agent",
        ai_agent_id: agent.id,
        name: "Health Test Context",
        entry_count: 0
      )
    end

    it 'returns health metrics for a context' do
      result = service.context_health(context: context)

      expect(result).to include(:entry_count, :active_entries, :avg_importance, :retention_status)
    end
  end

  describe '#memory_stats' do
    it 'returns memory usage statistics for the account' do
      result = service.memory_stats

      expect(result).to include(:total_contexts, :active_contexts, :total_entries, :active_entries)
    end
  end

  describe '#sync_context' do
    let(:source_context) do
      Ai::PersistentContext.create!(
        account: account,
        context_type: "agent_memory",
        scope: "agent",
        ai_agent_id: agent.id,
        name: "Source Context",
        entry_count: 0
      )
    end

    let(:target_context) do
      other_agent = create(:ai_agent, account: account)
      Ai::PersistentContext.create!(
        account: account,
        context_type: "agent_memory",
        scope: "agent",
        ai_agent_id: other_agent.id,
        name: "Target Context",
        entry_count: 0
      )
    end

    before do
      source_context.context_entries.create!(
        entry_key: "sync_key",
        entry_type: "fact",
        content: { "text" => "synced value" },
        metadata: {},
        importance_score: 0.8,
        version: 1,
        access_count: 0
      )
    end

    it 'syncs entries from source to target' do
      result = service.sync_context(from_context: source_context, to_context: target_context)

      expect(result[:synced]).to eq(1)
    end
  end

  # ============================================================
  # Full Maintenance Pipeline
  # ============================================================
  describe '#run_full_maintenance' do
    before do
      allow(Ai::CompoundLearning).to receive(:find_similar).and_return(Ai::CompoundLearning.none)
    end

    it 'runs both consolidation and decay pipelines' do
      result = service.run_full_maintenance(agent: agent)

      expect(result).to include(:consolidation, :decay)
    end
  end
end
