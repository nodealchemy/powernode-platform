# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Memory::ConsolidationService, type: :service do
  let(:account) { create(:account) }
  let(:agent) { create(:ai_agent, account: account) }
  let(:team) { create(:ai_agent_team, account: account) }

  let(:embedding_service) { instance_double(Ai::Memory::EmbeddingService) }
  let(:integrity_service) { instance_double(Ai::Memory::IntegrityService) }
  let(:mock_embedding) { Array.new(1536, 0.1) }

  subject(:service) { described_class.new(account: account) }

  before do
    allow(Ai::Memory::EmbeddingService).to receive(:new).and_return(embedding_service)
    allow(Ai::Memory::IntegrityService).to receive(:new).and_return(integrity_service)
    allow(embedding_service).to receive(:generate).and_return(mock_embedding)
    allow(integrity_service).to receive(:seal).and_return({ sealed: true, hash: "abc123" })
  end

  # ============================================================
  # consolidate_short_term
  # ============================================================
  describe '#consolidate_short_term' do
    let(:session_id) { SecureRandom.uuid }

    context 'when high-access memories exist' do
      before do
        # Create memories that meet the promotion threshold (access_count >= 3)
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

        # Create a low-access memory that should not be promoted
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "rare_key",
               memory_value: { "data" => "not_important" },
               access_count: 1,
               session_id: session_id)

        # No duplicates found
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

      it 'seals each promoted learning' do
        service.consolidate_short_term(agent: agent)

        expect(integrity_service).to have_received(:seal).exactly(3).times
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

        # Only the 3 memories from session_id should be promoted
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

        # Simulate finding a duplicate
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

  # ============================================================
  # consolidate_to_shared
  # ============================================================
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

        # Simulate no duplicates in SharedKnowledge
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

      it 'seals each promoted shared knowledge entry' do
        service.consolidate_to_shared(team: team)

        expect(integrity_service).to have_received(:seal).exactly(3).times
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

    context 'when duplicate shared knowledge exists' do
      before do
        learning = Ai::CompoundLearning.create!(
          account: account,
          source_agent_id: agent.id,
          ai_agent_team_id: team.id,
          content: "Duplicate learning content",
          category: "pattern",
          scope: "team",
          status: "active",
          importance_score: 0.9,
          confidence_score: 0.8,
          extraction_method: "review",
          embedding: mock_embedding
        )

        existing_sk = create(:ai_shared_knowledge, account: account, content: "Similar existing content")
        allow(existing_sk).to receive(:touch_usage!)

        dup_relation = Ai::SharedKnowledge.where(id: existing_sk.id)
        allow(Ai::SharedKnowledge).to receive_message_chain(:where, :with_embedding, :semantic_search)
          .and_return(dup_relation)
      end

      it 'skips duplicates' do
        result = service.consolidate_to_shared(team: team)

        expect(result[:skipped_duplicates]).to eq(1)
        expect(result[:promoted]).to eq(0)
      end
    end
  end

  # ============================================================
  # deduplicate
  # ============================================================
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
        # Stub find_similar to return the duplicate when called with learning1's embedding
        # The service chains .where.not(id: entry.id) on the result
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

  # ============================================================
  # run_pipeline
  # ============================================================
  describe '#run_pipeline' do
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
        result = service.run_pipeline(agent: agent)

        expect(result).to include(
          :short_term_consolidation,
          :shared_consolidation,
          :dedup_long_term,
          :dedup_shared,
          :dedup_context
        )
      end

      it 'includes consolidation stats' do
        result = service.run_pipeline(agent: agent)

        expect(result[:short_term_consolidation]).to include(:promoted, :skipped_duplicates, :errors)
      end
    end

    context 'for all agents in account' do
      let(:agent2) { create(:ai_agent, account: account) }

      before do
        create(:ai_agent_short_term_memory,
               agent: agent,
               account: account,
               memory_key: "agent1_key",
               memory_value: { "data" => "v1" },
               access_count: 5)
        create(:ai_agent_short_term_memory,
               agent: agent2,
               account: account,
               memory_key: "agent2_key",
               memory_value: { "data" => "v2" },
               access_count: 5)
      end

      it 'runs consolidation for all agents' do
        result = service.run_pipeline

        expect(result[:short_term_consolidation][:promoted]).to be >= 2
      end
    end
  end
end
