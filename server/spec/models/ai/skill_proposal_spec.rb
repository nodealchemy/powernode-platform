# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::SkillProposal, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  before do
    allow_any_instance_of(Ai::Skill).to receive(:sync_to_knowledge_graph)
  end

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:proposed_by_agent).class_name('Ai::Agent').optional }
    it { should belong_to(:proposed_by_user).class_name('User').optional }
    it { should belong_to(:reviewed_by).class_name('User').optional }
    it { should belong_to(:created_skill).class_name('Ai::Skill').optional }
    it { should belong_to(:parent_proposal).class_name('Ai::SkillProposal').optional }
    it { should have_many(:child_proposals).class_name('Ai::SkillProposal').dependent(:nullify) }
  end

  describe 'validations' do
    subject { build(:ai_skill_proposal, account: account, proposed_by_agent: agent) }

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:status) }
    it { should validate_inclusion_of(:status).in_array(%w[draft proposed approved created rejected]) }
    it { should validate_inclusion_of(:category).in_array(Ai::Skill::CATEGORIES) }

    it 'allows nil category' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, category: nil)
      expect(proposal).to be_valid
    end

    it 'rejects an invalid category' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, category: "nonexistent")
      expect(proposal).not_to be_valid
      expect(proposal.errors[:category]).to be_present
    end

    it 'rejects an invalid status' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "invalid")
      expect(proposal).not_to be_valid
      expect(proposal.errors[:status]).to be_present
    end
  end

  describe 'slug generation' do
    it 'auto-generates slug from name on create' do
      proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, name: "My Test Skill", slug: nil)
      expect(proposal.slug).to eq("my-test-skill")
    end

    it 'does not overwrite an existing slug' do
      proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, name: "My Skill", slug: "custom-slug")
      expect(proposal.slug).to eq("custom-slug")
    end

    it 'appends a counter when slug already exists' do
      # First proposal is rejected so name uniqueness doesn't block, but slug still exists in DB
      create(:ai_skill_proposal, :rejected, account: account, proposed_by_agent: agent, name: "Duplicate Skill", slug: "duplicate-skill")
      second = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, name: "Duplicate Skill", slug: nil)
      expect(second.slug).to eq("duplicate-skill-1")
    end
  end

  describe 'state transitions' do
    describe '#submit!' do
      it 'transitions from draft to proposed' do
        proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "draft")
        proposal.submit!
        expect(proposal.reload.status).to eq("proposed")
      end

      it 'sets proposed_at timestamp' do
        proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "draft")
        freeze_time do
          proposal.submit!
          expect(proposal.proposed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'raises when not in draft status' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        expect { proposal.submit! }.to raise_error(RuntimeError, /Can only submit draft proposals/)
      end
    end

    describe '#approve!' do
      it 'transitions from proposed to approved' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        proposal.approve!(user)
        expect(proposal.reload.status).to eq("approved")
      end

      it 'sets reviewed_by and reviewed_at' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        freeze_time do
          proposal.approve!(user)
          expect(proposal.reviewed_by).to eq(user)
          expect(proposal.reviewed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'raises when not in proposed status' do
        proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "draft")
        expect { proposal.approve!(user) }.to raise_error(RuntimeError, /Can only approve proposed proposals/)
      end
    end

    describe '#reject!' do
      it 'transitions from proposed to rejected' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        proposal.reject!(user, reason: "Not needed")
        expect(proposal.reload.status).to eq("rejected")
      end

      it 'stores the rejection reason' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        proposal.reject!(user, reason: "Overlaps with existing")
        expect(proposal.rejection_reason).to eq("Overlaps with existing")
      end

      it 'sets reviewed_by and reviewed_at' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        freeze_time do
          proposal.reject!(user, reason: "Rejected")
          expect(proposal.reviewed_by).to eq(user)
          expect(proposal.reviewed_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'raises when not in proposed status' do
        proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "draft")
        expect { proposal.reject!(user, reason: "nope") }.to raise_error(RuntimeError, /Can only reject proposed proposals/)
      end
    end

    describe '#mark_created!' do
      let(:skill) { create(:ai_skill, account: account) }

      it 'transitions from approved to created' do
        proposal = create(:ai_skill_proposal, :approved, account: account, proposed_by_agent: agent)
        proposal.mark_created!(skill)
        expect(proposal.reload.status).to eq("created")
      end

      it 'associates the created skill' do
        proposal = create(:ai_skill_proposal, :approved, account: account, proposed_by_agent: agent)
        proposal.mark_created!(skill)
        expect(proposal.created_skill).to eq(skill)
      end

      it 'raises when not in approved status' do
        proposal = create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent)
        expect { proposal.mark_created!(skill) }.to raise_error(RuntimeError, /Can only create from approved proposals/)
      end
    end
  end

  describe '#can_auto_approve?' do
    it 'returns true when trust_tier_at_proposal is trusted' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, trust_tier_at_proposal: "trusted")
      expect(proposal.can_auto_approve?).to be true
    end

    it 'returns true when trust_tier_at_proposal is autonomous' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, trust_tier_at_proposal: "autonomous")
      expect(proposal.can_auto_approve?).to be true
    end

    it 'returns false when trust_tier_at_proposal is monitored' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, trust_tier_at_proposal: "monitored")
      expect(proposal.can_auto_approve?).to be false
    end

    it 'returns false when trust_tier_at_proposal is supervised' do
      proposal = build(:ai_skill_proposal, account: account, proposed_by_agent: agent, trust_tier_at_proposal: "supervised")
      expect(proposal.can_auto_approve?).to be false
    end
  end

  describe '#proposal_summary' do
    it 'returns expected hash structure' do
      proposal = create(:ai_skill_proposal, account: account, proposed_by_agent: agent)
      summary = proposal.proposal_summary

      expect(summary).to include(
        :id, :name, :description, :category, :status,
        :confidence_score, :auto_approved,
        :proposed_by_agent_id, :proposed_by_user_id,
        :proposed_at, :reviewed_at, :created_at
      )
      expect(summary[:id]).to eq(proposal.id)
      expect(summary[:name]).to eq(proposal.name)
      expect(summary[:status]).to eq(proposal.status)
      expect(summary[:confidence_score]).to eq(proposal.confidence_score)
    end
  end

  describe 'scopes' do
    let!(:draft_proposal) { create(:ai_skill_proposal, account: account, proposed_by_agent: agent, status: "draft") }
    let!(:proposed_proposal) { create(:ai_skill_proposal, :proposed, account: account, proposed_by_agent: agent) }
    let!(:rejected_proposal) { create(:ai_skill_proposal, :rejected, account: account, proposed_by_agent: agent) }

    describe '.active' do
      it 'excludes rejected and created proposals' do
        skill = create(:ai_skill, account: account)
        created_proposal = create(:ai_skill_proposal, :created, account: account, proposed_by_agent: agent, created_skill: skill)

        results = described_class.active
        expect(results).to include(draft_proposal, proposed_proposal)
        expect(results).not_to include(rejected_proposal, created_proposal)
      end
    end

    describe '.pending_review' do
      it 'returns only proposed proposals' do
        results = described_class.pending_review
        expect(results).to include(proposed_proposal)
        expect(results).not_to include(draft_proposal, rejected_proposal)
      end
    end
  end

  describe 'parent-child relationship' do
    it 'supports self-referential parent proposals' do
      parent = create(:ai_skill_proposal, account: account, proposed_by_agent: agent)
      child = create(:ai_skill_proposal, account: account, proposed_by_agent: agent, parent_proposal: parent)

      expect(child.parent_proposal).to eq(parent)
      expect(parent.child_proposals).to include(child)
    end
  end
end
