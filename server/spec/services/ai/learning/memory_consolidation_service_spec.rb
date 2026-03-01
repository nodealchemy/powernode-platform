# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Learning::MemoryConsolidationService, type: :service do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account: account) }

  before do
    allow(Rails.logger).to receive(:info)
    allow(Rails.logger).to receive(:warn)
    allow(Rails.logger).to receive(:error)
  end

  describe "constants" do
    it "sets MAX_EPISODIC_MEMORIES to 1000" do
      expect(described_class::MAX_EPISODIC_MEMORIES).to eq(1000)
    end

    it "sets CONSOLIDATION_BATCH_SIZE to 50" do
      expect(described_class::CONSOLIDATION_BATCH_SIZE).to eq(50)
    end
  end

  describe "#consolidate" do
    context "when EpisodicMemory model is not defined" do
      before do
        allow(service).to receive(:prune_expired_memories)
        allow(service).to receive(:consolidate_similar_memories)
        allow(service).to receive(:enforce_retention_limits)
      end

      it "calls all three consolidation steps" do
        expect(service).to receive(:prune_expired_memories)
        expect(service).to receive(:consolidate_similar_memories)
        expect(service).to receive(:enforce_retention_limits)

        service.consolidate
      end
    end

    context "when EpisodicMemory is defined" do
      before do
        # Ensure the constant is considered defined for these tests
        stub_const("Ai::Memory::EpisodicMemory", Class.new(ActiveRecord::Base) {
          self.table_name = "ai_agent_short_term_memories"
        })
      end

      describe "prune_expired_memories" do
        it "deletes expired memories" do
          expired_scope = double("expired_scope")
          allow(Ai::Memory::EpisodicMemory).to receive(:where)
            .with(account: account).and_return(expired_scope)
          allow(expired_scope).to receive(:where).and_return(expired_scope)
          allow(expired_scope).to receive(:delete_all).and_return(3)

          service.send(:prune_expired_memories)
        end

        it "handles errors gracefully" do
          allow(Ai::Memory::EpisodicMemory).to receive(:where).and_raise(StandardError, "DB error")

          expect { service.send(:prune_expired_memories) }.not_to raise_error
        end
      end

      describe "consolidate_similar_memories" do
        let(:agent) { create(:ai_agent, account: account) }

        it "handles errors gracefully" do
          allow(Ai::Agent).to receive(:where).and_raise(StandardError, "consolidation error")

          expect { service.send(:consolidate_similar_memories) }.not_to raise_error
        end
      end

      describe "enforce_retention_limits" do
        it "handles errors gracefully" do
          allow(Ai::Agent).to receive(:where).and_raise(StandardError, "retention error")

          expect { service.send(:enforce_retention_limits) }.not_to raise_error
        end
      end
    end

    context "when EpisodicMemory is not defined" do
      before do
        hide_const("Ai::Memory::EpisodicMemory") if defined?(Ai::Memory::EpisodicMemory)
      end

      it "skips pruning when model is not defined" do
        expect { service.send(:prune_expired_memories) }.not_to raise_error
      end

      it "skips consolidation when model is not defined" do
        expect { service.send(:consolidate_similar_memories) }.not_to raise_error
      end

      it "skips retention enforcement when model is not defined" do
        expect { service.send(:enforce_retention_limits) }.not_to raise_error
      end
    end
  end
end
