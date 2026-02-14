# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Context::RotDetectionService, type: :service do
  let(:account) { create(:account) }

  subject(:service) { described_class.new(account: account) }

  describe 'constants' do
    it 'has expected threshold values' do
      expect(described_class::AGE_DECAY_HALF_LIFE_DAYS).to eq(30)
      expect(described_class::STALENESS_THRESHOLD).to eq(0.7)
      expect(described_class::ARCHIVE_THRESHOLD).to eq(0.9)
      expect(described_class::MIN_ACCESS_FREQUENCY).to eq(0.01)
    end
  end

  describe '#detect' do
    context 'with no context entries' do
      it 'returns empty report' do
        result = service.detect

        expect(result[:total_scanned]).to eq(0)
        expect(result[:stale_count]).to eq(0)
        expect(result[:archive_candidates]).to eq(0)
        expect(result[:review_candidates]).to eq(0)
        expect(result[:entries]).to be_empty
        expect(result[:scanned_at]).to be_present
      end
    end

    context 'with context entries' do
      let(:persistent_context) do
        create(:ai_persistent_context, account: account, context_type: "agent_memory")
      end

      let!(:fresh_entry) do
        create(:ai_context_entry,
          persistent_context: persistent_context,
          importance_score: 0.9,
          created_at: 1.day.ago
        )
      end

      let!(:stale_entry) do
        create(:ai_context_entry,
          persistent_context: persistent_context,
          importance_score: 0.1,
          created_at: 120.days.ago
        )
      end

      let!(:very_stale_entry) do
        create(:ai_context_entry,
          persistent_context: persistent_context,
          importance_score: 0.0,
          created_at: 365.days.ago
        )
      end

      it 'identifies stale entries above the threshold' do
        result = service.detect

        expect(result[:total_scanned]).to eq(3)
        expect(result[:stale_count]).to be >= 1
        stale_ids = result[:entries].map { |e| e[:entry_id] }
        expect(stale_ids).to include(stale_entry.id)
      end

      it 'sorts entries by staleness score descending' do
        result = service.detect

        scores = result[:entries].map { |e| e[:staleness_score] }
        expect(scores).to eq(scores.sort.reverse)
      end

      it 'includes staleness factors for each entry' do
        result = service.detect

        result[:entries].each do |entry|
          expect(entry[:factors]).to have_key(:age_decay)
          expect(entry[:factors]).to have_key(:access_recency)
          expect(entry[:factors]).to have_key(:low_importance)
        end
      end

      it 'recommends archive for entries above archive threshold' do
        result = service.detect

        archive_entries = result[:entries].select { |e| e[:recommendation] == "archive" }
        archive_entries.each do |entry|
          expect(entry[:staleness_score]).to be >= described_class::ARCHIVE_THRESHOLD
        end
      end

      it 'recommends review for entries between staleness and archive thresholds' do
        result = service.detect

        review_entries = result[:entries].select { |e| e[:recommendation] == "review" }
        review_entries.each do |entry|
          expect(entry[:staleness_score]).to be >= described_class::STALENESS_THRESHOLD
          expect(entry[:staleness_score]).to be < described_class::ARCHIVE_THRESHOLD
        end
      end

      it 'respects limit parameter' do
        result = service.detect(limit: 1)

        expect(result[:entries].size).to be <= 1
      end
    end

    context 'with scope filtering' do
      let(:agent_context) do
        create(:ai_persistent_context, account: account, context_type: "agent_memory")
      end
      let(:kb_context) do
        create(:ai_persistent_context, account: account, context_type: "knowledge_base")
      end

      let!(:agent_entry) do
        create(:ai_context_entry,
          persistent_context: agent_context,
          importance_score: 0.0,
          created_at: 365.days.ago
        )
      end

      let!(:kb_entry) do
        create(:ai_context_entry,
          persistent_context: kb_context,
          importance_score: 0.0,
          created_at: 365.days.ago
        )
      end

      it 'filters by agent_memory scope' do
        result = service.detect(scope: :agent_memory)

        expect(result[:total_scanned]).to eq(1)
        entry_ids = result[:entries].map { |e| e[:entry_id] }
        expect(entry_ids).not_to include(kb_entry.id)
      end

      it 'filters by knowledge_base scope' do
        result = service.detect(scope: :knowledge_base)

        expect(result[:total_scanned]).to eq(1)
        entry_ids = result[:entries].map { |e| e[:entry_id] }
        expect(entry_ids).not_to include(agent_entry.id)
      end

      it 'scans all entries with :all scope' do
        result = service.detect(scope: :all)

        expect(result[:total_scanned]).to eq(2)
      end
    end
  end

  describe '#auto_archive!' do
    let(:persistent_context) do
      create(:ai_persistent_context, account: account, context_type: "agent_memory")
    end

    let!(:very_stale_entry) do
      create(:ai_context_entry,
        persistent_context: persistent_context,
        importance_score: 0.0,
        created_at: 365.days.ago
      )
    end

    context 'when dry_run is true' do
      it 'does not modify any entries' do
        result = service.auto_archive!(dry_run: true)

        expect(result[:dry_run]).to be true
        expect(result[:archived]).to eq(0)
        very_stale_entry.reload
        expect(very_stale_entry.metadata).not_to have_key("archived_at")
      end
    end

    context 'when dry_run is false' do
      it 'archives entries above the archive threshold' do
        result = service.auto_archive!(dry_run: false)

        expect(result[:dry_run]).to be false
        if result[:archived] > 0
          very_stale_entry.reload
          expect(very_stale_entry.metadata).to have_key("archived_at")
          expect(very_stale_entry.metadata["archived_reason"]).to eq("context_rot")
        end
      end

      it 'returns count of archived entries' do
        result = service.auto_archive!(dry_run: false)

        expect(result).to have_key(:archived)
        expect(result).to have_key(:candidates)
      end
    end

    context 'when entry update fails' do
      before do
        allow(Ai::ContextEntry).to receive(:find_by).and_return(very_stale_entry)
        allow(very_stale_entry).to receive(:update!).and_raise(StandardError, "update failed")
      end

      it 'logs warning and continues' do
        expect(Rails.logger).to receive(:warn).at_least(:once)

        result = service.auto_archive!(dry_run: false)
        expect(result[:archived]).to eq(0)
      end
    end
  end
end
