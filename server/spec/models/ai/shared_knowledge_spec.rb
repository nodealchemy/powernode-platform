# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SharedKnowledge, type: :model do
  let(:account) { create(:account) }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:created_by).class_name('User').optional }
    it { should belong_to(:git_repository).class_name('Devops::GitRepository').optional }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_presence_of(:content) }
    it { should validate_length_of(:title).is_at_most(500) }
    it { should validate_inclusion_of(:content_type).in_array(described_class::CONTENT_TYPES) }
    it { should validate_inclusion_of(:access_level).in_array(%w[private team account global]) }
    it { should validate_numericality_of(:quality_score).is_greater_than_or_equal_to(0).is_less_than_or_equal_to(1).allow_nil }
  end

  describe 'scopes' do
    describe '.accessible_by' do
      let!(:private_knowledge) { create(:ai_shared_knowledge, :private_access, account: account) }
      let!(:team_knowledge) { create(:ai_shared_knowledge, account: account, access_level: "team") }
      let!(:account_knowledge) { create(:ai_shared_knowledge, :account_access, account: account) }
      let!(:global_knowledge) { create(:ai_shared_knowledge, :global_access, account: account) }

      it 'returns only global items for global access level' do
        results = described_class.accessible_by("global")
        expect(results).to include(global_knowledge)
        expect(results).not_to include(team_knowledge, private_knowledge)
      end

      it 'returns account and global items for account access level' do
        results = described_class.accessible_by("account")
        expect(results).to include(account_knowledge, global_knowledge)
        expect(results).not_to include(private_knowledge)
      end

      it 'returns team, account, and global items for team access level' do
        results = described_class.accessible_by("team")
        expect(results).to include(team_knowledge, account_knowledge, global_knowledge)
        expect(results).not_to include(private_knowledge)
      end
    end

    describe '.by_content_type' do
      let!(:text_knowledge) { create(:ai_shared_knowledge, account: account, content_type: "text") }
      let!(:code_knowledge) { create(:ai_shared_knowledge, :code, account: account) }

      it 'filters by content type' do
        expect(described_class.by_content_type("code")).to include(code_knowledge)
        expect(described_class.by_content_type("code")).not_to include(text_knowledge)
      end
    end

    describe '.with_tag' do
      let!(:tagged) { create(:ai_shared_knowledge, :with_tags, account: account) }
      let!(:untagged) { create(:ai_shared_knowledge, account: account, tags: []) }

      it 'returns knowledge entries with the given tag' do
        expect(described_class.with_tag("ruby")).to include(tagged)
        expect(described_class.with_tag("ruby")).not_to include(untagged)
      end
    end

    describe '.high_quality' do
      let!(:high_quality) { create(:ai_shared_knowledge, :high_quality, account: account) }
      let!(:low_quality) { create(:ai_shared_knowledge, :low_quality, account: account) }

      it 'returns entries with quality_score >= 0.7' do
        expect(described_class.high_quality).to include(high_quality)
        expect(described_class.high_quality).not_to include(low_quality)
      end
    end
  end

  describe '#touch_usage!' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account, usage_count: 5) }

    it 'increments usage_count' do
      expect { knowledge.touch_usage! }.to change { knowledge.reload.usage_count }.from(5).to(6)
    end

    it 'updates last_used_at' do
      freeze_time do
        knowledge.touch_usage!
        expect(knowledge.reload.last_used_at).to eq(Time.current)
      end
    end
  end

  describe '#touch_event_processed!' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account) }

    it 'sets last_event_processed_at to current time' do
      expect(knowledge.last_event_processed_at).to be_nil

      freeze_time do
        knowledge.touch_event_processed!
        expect(knowledge.reload.last_event_processed_at).to eq(Time.current)
      end
    end
  end

  describe '#touch_usage! quality recalculation' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account, usage_count: 4) }

    it 'triggers recalculate_quality_score! on every 5th use' do
      expect(knowledge).to receive(:recalculate_quality_score!).once
      knowledge.touch_usage!
    end

    it 'does not trigger recalculate_quality_score! on non-5th use' do
      knowledge = create(:ai_shared_knowledge, account: account, usage_count: 3)
      expect(knowledge).not_to receive(:recalculate_quality_score!)
      knowledge.touch_usage!
    end
  end

  describe '#record_rating!' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account, rating_sum: 0, rating_count: 0) }

    it 'sets last_event_processed_at' do
      knowledge.record_rating!(4)
      expect(knowledge.reload.last_event_processed_at).to be_within(2.seconds).of(Time.current)
    end

    context 'with source learning provenance' do
      let(:source_learning) do
        create(:ai_compound_learning, account: account, importance_score: 0.5, status: "active")
      end

      let(:knowledge_with_source) do
        create(:ai_shared_knowledge, account: account, rating_sum: 0, rating_count: 0,
               provenance: { "source_learning_id" => source_learning.id })
      end

      it 'boosts source learning importance on high rating' do
        knowledge_with_source.record_rating!(5)
        expect(source_learning.reload.importance_score).to be > 0.5
      end

      it 'decays source learning importance on low rating' do
        # Set updated_at far enough back for decay to take effect
        source_learning.update_columns(updated_at: 3.days.ago, decay_rate: 0.1)
        original = source_learning.importance_score

        knowledge_with_source.record_rating!(1)
        expect(source_learning.reload.importance_score).to be < original
      end

      it 'touches source learning event_processed' do
        knowledge_with_source.record_rating!(4)
        expect(source_learning.reload.last_event_processed_at).to be_within(2.seconds).of(Time.current)
      end

      it 'skips propagation for disproven source learnings' do
        source_learning.update_columns(status: "disproven")
        original = source_learning.importance_score

        knowledge_with_source.record_rating!(5)
        expect(source_learning.reload.importance_score).to eq(original)
      end
    end
  end

  describe '#verify_integrity!' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "test content") }

    it 'returns true when no integrity_hash is set' do
      expect(knowledge.verify_integrity!).to be true
    end

    it 'returns true when hash matches content' do
      knowledge.compute_integrity_hash!
      expect(knowledge.verify_integrity!).to be true
    end

    it 'returns false when content has been tampered with' do
      knowledge.compute_integrity_hash!
      knowledge.update_columns(content: "tampered content")
      expect(knowledge.verify_integrity!).to be false
    end
  end

  describe '#compute_integrity_hash!' do
    let(:knowledge) { create(:ai_shared_knowledge, account: account, content: "test content") }

    it 'stores the SHA256 hash of content' do
      knowledge.compute_integrity_hash!
      expected_hash = Digest::SHA256.hexdigest("test content")
      expect(knowledge.reload.integrity_hash).to eq(expected_hash)
    end
  end

  describe '.semantic_search' do
    it 'responds to semantic_search class method' do
      expect(described_class).to respond_to(:semantic_search)
    end
  end

  # ==========================================================================
  # PORTABILITY (Tier-2): repository scoping
  # ==========================================================================

  describe 'repository scoping' do
    let(:repo) { create(:git_repository, account: account) }
    let(:other_repo) { create(:git_repository, account: account) }

    describe '.for_account_and_repo' do
      let!(:in_repo) { create(:ai_shared_knowledge, account: account, git_repository: repo) }
      let!(:other_repo_knowledge) { create(:ai_shared_knowledge, account: account, git_repository: other_repo) }
      let!(:no_repo) { create(:ai_shared_knowledge, account: account) }

      it 'returns only knowledge for the given account + repository' do
        results = described_class.for_account_and_repo(account.id, repo.id)
        expect(results).to include(in_repo)
        expect(results).not_to include(other_repo_knowledge, no_repo)
      end
    end

    describe '.semantic_search with repository_id' do
      let(:embedding) { Array.new(1536, 0.1) }
      let!(:in_repo) { create(:ai_shared_knowledge, account: account, git_repository: repo, embedding: embedding) }
      let!(:other) { create(:ai_shared_knowledge, account: account, git_repository: other_repo, embedding: embedding) }

      it 'filters to the given repository when repository_id is present' do
        results = described_class.semantic_search(embedding, repository_id: repo.id)
        expect(results).to include(in_repo)
        expect(results).not_to include(other)
      end

      it 'returns all matching entries when repository_id is nil (back-compat)' do
        results = described_class.semantic_search(embedding)
        expect(results).to include(in_repo, other)
      end
    end
  end
end
