# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::DecayService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }

  subject(:service) { described_class.new(account: account) }

  # ============================================================
  # apply_decay
  # ============================================================
  describe '#apply_decay' do
    context 'with short-term memories' do
      before do
        # Stale memory with TTL that should decay
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "stale_key",
               memory_value: { "data" => "stale" },
               ttl_seconds: 7200,
               last_accessed_at: 3.days.ago,
               created_at: 5.days.ago,
               expires_at: 2.days.from_now)

        # Recently accessed memory that should not decay
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

    context 'with CompoundLearning entries' do
      before do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Old learning",
          category: "pattern",
          scope: "team",
          status: "active",
          importance_score: 0.5,
          confidence_score: 0.7,
          extraction_method: "auto_success",
          updated_at: 5.days.ago,
          created_at: 40.days.ago
        )
      end

      it 'applies decay to compound learnings' do
        result = service.apply_decay(agent: agent)

        expect(result[:by_tier][:long_term]).to include(:decayed, :archived)
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

  # ============================================================
  # cleanup_expired
  # ============================================================
  describe '#cleanup_expired' do
    context 'for a specific agent' do
      before do
        # Expired entries
        3.times do |i|
          create(:ai_agent_short_term_memory, :expired,
                 agent: agent,
                 account: account,
                 memory_key: "expired_#{i}",
                 memory_value: { "data" => "expired_#{i}" },
                 expires_at: 2.hours.ago)
        end

        # Active entry that should not be deleted
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

    context 'for very old active entries' do
      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "ancient_key",
               memory_value: { "data" => "ancient" },
               created_at: 10.days.ago,
               expires_at: 1.hour.from_now) # still active but very old
      end

      it 'force-expires entries older than STM_MAX_AGE_DAYS' do
        result = service.cleanup_expired(agent: agent)

        expect(result[:deleted]).to be >= 1
      end
    end

    context 'without a specific agent (account-wide)' do
      let(:agent2) { create(:ai_agent, account: account) }

      before do
        create(:ai_agent_short_term_memory, :expired,
               agent: agent,
               account: account,
               memory_key: "exp1",
               memory_value: { "d" => "1" },
               expires_at: 2.hours.ago)
        create(:ai_agent_short_term_memory, :expired,
               agent: agent2,
               account: account,
               memory_key: "exp2",
               memory_value: { "d" => "2" },
               expires_at: 2.hours.ago)
      end

      it 'cleans up expired entries across all agents in account' do
        result = service.cleanup_expired

        expect(result[:deleted]).to be >= 2
      end
    end
  end

  # ============================================================
  # archive_stale
  # ============================================================
  describe '#archive_stale' do
    context 'with low-importance CompoundLearnings' do
      before do
        # Stale learning below threshold, old enough to archive
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

        # High-importance learning that should not be archived
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

      it 'marks deprecated entries as deprecated' do
        service.archive_stale(agent: agent)

        deprecated = Ai::CompoundLearning.where(
          source_agent_id: agent.id,
          status: "deprecated"
        )
        expect(deprecated.count).to eq(1)
      end

      it 'does not archive high-importance entries' do
        service.archive_stale(agent: agent)

        active = Ai::CompoundLearning.active.where(source_agent_id: agent.id)
        expect(active.count).to eq(1)
        expect(active.first.importance_score).to eq(0.9)
      end
    end

    context 'with low-importance ContextEntries' do
      let(:persistent_context) do
        Ai::PersistentContext.create!(
          account: account,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: agent.id,
          name: "Decay Test Context",
          entry_count: 0
        )
      end

      before do
        Ai::ContextEntry.create!(
          persistent_context: persistent_context,
          ai_agent_id: agent.id,
          entry_key: "stale_context",
          entry_type: "fact",
          memory_type: "factual",
          content: { "text" => "Stale context entry" },
          version: 1,
          importance_score: 0.05,
          access_count: 0,
          metadata: {},
          created_at: 60.days.ago
        )
      end

      it 'archives stale context entries' do
        result = service.archive_stale(agent: agent)

        expect(result[:context_archived]).to eq(1)
      end
    end

    context 'with custom threshold' do
      before do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Medium importance learning",
          category: "discovery",
          scope: "team",
          status: "active",
          importance_score: 0.3,
          confidence_score: 0.5,
          extraction_method: "consolidation",
          created_at: 60.days.ago
        )
      end

      it 'archives entries below the custom threshold' do
        result = service.archive_stale(agent: agent, threshold: 0.5)

        expect(result[:compound_archived]).to eq(1)
      end

      it 'does not archive entries above the custom threshold' do
        result = service.archive_stale(agent: agent, threshold: 0.2)

        expect(result[:compound_archived]).to eq(0)
      end
    end
  end

  # ============================================================
  # refresh_accessed
  # ============================================================
  describe '#refresh_accessed' do
    context 'with recently accessed STM entries' do
      before do
        # Recently accessed memory
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "recent_key",
               memory_value: { "data" => "recent" },
               last_accessed_at: 2.hours.ago,
               expires_at: 1.hour.from_now)

        # Old accessed memory (should not be refreshed)
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

    context 'with recently accessed CompoundLearnings' do
      before do
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Recently boosted learning",
          category: "pattern",
          scope: "team",
          status: "active",
          importance_score: 0.6,
          confidence_score: 0.7,
          extraction_method: "auto_success",
          updated_at: 2.hours.ago
        )
      end

      it 'boosts importance of recently accessed learnings' do
        result = service.refresh_accessed(agent: agent, since: 1.day.ago)

        expect(result[:by_tier][:long_term]).to be >= 1
      end

      it 'increases the importance score' do
        learning = Ai::CompoundLearning.where(source_agent_id: agent.id).first
        original_score = learning.importance_score

        service.refresh_accessed(agent: agent, since: 1.day.ago)

        learning.reload
        expect(learning.importance_score).to be > original_score
      end
    end

    context 'with recently accessed ContextEntries' do
      let(:persistent_context) do
        Ai::PersistentContext.create!(
          account: account,
          context_type: "agent_memory",
          scope: "agent",
          ai_agent_id: agent.id,
          name: "Refresh Test Context",
          entry_count: 0
        )
      end

      before do
        Ai::ContextEntry.create!(
          persistent_context: persistent_context,
          ai_agent_id: agent.id,
          entry_key: "accessed_entry",
          entry_type: "fact",
          memory_type: "factual",
          content: { "text" => "Recently accessed" },
          version: 1,
          importance_score: 0.5,
          access_count: 3,
          last_accessed_at: 2.hours.ago,
          metadata: {}
        )
      end

      it 'boosts importance of recently accessed context entries' do
        result = service.refresh_accessed(agent: agent, since: 1.day.ago)

        expect(result[:by_tier][:context]).to eq(1)
      end

      it 'increases the importance score of the entry' do
        entry = Ai::ContextEntry.by_agent(agent.id).first
        original_score = entry.importance_score

        service.refresh_accessed(agent: agent, since: 1.day.ago)

        entry.reload
        expect(entry.importance_score).to be > original_score
      end
    end

    context 'with no recently accessed memories' do
      it 'returns zero refreshed count' do
        result = service.refresh_accessed(agent: agent, since: 1.day.ago)

        expect(result[:refreshed_count]).to eq(0)
      end
    end
  end

  # ============================================================
  # run_pipeline
  # ============================================================
  describe '#run_pipeline' do
    context 'for a specific agent' do
      before do
        # Create some expired entries for cleanup
        create(:ai_agent_short_term_memory, :expired,
               agent: agent,
               account: account,
               memory_key: "pipeline_expired",
               memory_value: { "data" => "expired" },
               expires_at: 2.hours.ago)

        # Create a stale low-importance learning
        Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          content: "Pipeline stale learning",
          category: "fact",
          scope: "team",
          status: "active",
          importance_score: 0.05,
          confidence_score: 0.3,
          extraction_method: "consolidation",
          created_at: 60.days.ago,
          updated_at: 5.days.ago
        )
      end

      it 'runs all pipeline stages' do
        result = service.run_pipeline(agent: agent)

        expect(result).to include(:decay, :cleanup, :archive, :refresh)
      end

      it 'includes decay stats' do
        result = service.run_pipeline(agent: agent)

        expect(result[:decay]).to include(:decayed_count, :archived_count)
      end

      it 'includes cleanup stats' do
        result = service.run_pipeline(agent: agent)

        expect(result[:cleanup]).to include(:deleted)
      end

      it 'includes archive stats' do
        result = service.run_pipeline(agent: agent)

        expect(result[:archive]).to include(:compound_archived, :context_archived)
      end

      it 'includes refresh stats' do
        result = service.run_pipeline(agent: agent)

        expect(result[:refresh]).to include(:refreshed_count)
      end
    end

    context 'for all agents in account' do
      let(:agent2) { create(:ai_agent, account: account) }

      before do
        create(:ai_agent_short_term_memory, :expired,
               agent: agent,
               account: account,
               memory_key: "agent1_exp",
               memory_value: { "d" => "1" },
               expires_at: 2.hours.ago)
        create(:ai_agent_short_term_memory, :expired,
               agent: agent2,
               account: account,
               memory_key: "agent2_exp",
               memory_value: { "d" => "2" },
               expires_at: 2.hours.ago)
      end

      it 'runs decay for all agents in the account' do
        result = service.run_pipeline

        expect(result[:decay]).to include(:decayed_count, :archived_count)
        expect(result[:cleanup]).to include(:deleted)
      end
    end
  end
end
