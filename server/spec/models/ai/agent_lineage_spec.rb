# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentLineage, type: :model do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:parent_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }
  let(:child_agent) { create(:ai_agent, account: account, creator: user, provider: provider) }

  describe 'associations' do
    it { should belong_to(:account) }
    it { should belong_to(:parent_agent).class_name('Ai::Agent') }
    it { should belong_to(:child_agent).class_name('Ai::Agent') }
  end

  describe 'validations' do
    it { should validate_presence_of(:parent_agent_id) }
    it { should validate_presence_of(:child_agent_id) }
    it { should validate_presence_of(:spawned_at) }

    context 'parent and child differ' do
      it 'is invalid when parent and child are the same agent' do
        lineage = build(:ai_agent_lineage,
                        account: account,
                        parent_agent: parent_agent,
                        child_agent: parent_agent)

        expect(lineage).not_to be_valid
        expect(lineage.errors[:child_agent_id]).to include('cannot be the same as parent agent')
      end

      it 'is valid when parent and child are different agents' do
        lineage = build(:ai_agent_lineage,
                        account: account,
                        parent_agent: parent_agent,
                        child_agent: child_agent,
                        spawned_at: Time.current)

        expect(lineage).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_lineage) do
      create(:ai_agent_lineage,
             account: account,
             parent_agent: parent_agent,
             child_agent: child_agent,
             spawned_at: Time.current)
    end
    let(:another_parent) { create(:ai_agent, account: account, creator: user, provider: provider) }
    let(:another_child) { create(:ai_agent, account: account, creator: user, provider: provider) }
    let!(:terminated_lineage) do
      create(:ai_agent_lineage, :terminated,
             account: account,
             parent_agent: another_parent,
             child_agent: another_child,
             spawned_at: 1.day.ago)
    end

    describe '.active' do
      it 'returns only lineages without terminated_at' do
        expect(described_class.active).to include(active_lineage)
        expect(described_class.active).not_to include(terminated_lineage)
      end
    end

    describe '.terminated' do
      it 'returns only lineages with terminated_at' do
        expect(described_class.terminated).to include(terminated_lineage)
        expect(described_class.terminated).not_to include(active_lineage)
      end
    end

    describe '.for_parent' do
      it 'returns lineages for the given parent agent' do
        expect(described_class.for_parent(parent_agent.id)).to include(active_lineage)
        expect(described_class.for_parent(parent_agent.id)).not_to include(terminated_lineage)
      end
    end

    describe '.for_child' do
      it 'returns lineages for the given child agent' do
        expect(described_class.for_child(child_agent.id)).to include(active_lineage)
        expect(described_class.for_child(child_agent.id)).not_to include(terminated_lineage)
      end
    end

    describe '.recent' do
      it 'returns lineages ordered by spawned_at desc' do
        results = described_class.recent
        expect(results.first).to eq(active_lineage)
        expect(results.last).to eq(terminated_lineage)
      end
    end
  end

  describe '#active?' do
    it 'returns true when terminated_at is nil' do
      lineage = create(:ai_agent_lineage,
                       account: account,
                       parent_agent: parent_agent,
                       child_agent: child_agent,
                       spawned_at: Time.current)

      expect(lineage.active?).to be true
    end

    it 'returns false when terminated_at is set' do
      lineage = create(:ai_agent_lineage, :terminated,
                       account: account,
                       parent_agent: parent_agent,
                       child_agent: child_agent,
                       spawned_at: Time.current)

      expect(lineage.active?).to be false
    end
  end

  describe '#terminate!' do
    let(:lineage) do
      create(:ai_agent_lineage,
             account: account,
             parent_agent: parent_agent,
             child_agent: child_agent,
             spawned_at: Time.current)
    end

    it 'sets terminated_at to current time' do
      freeze_time do
        lineage.terminate!
        expect(lineage.reload.terminated_at).to eq(Time.current)
      end
    end

    it 'stores the termination reason' do
      lineage.terminate!(reason: "budget_exceeded")
      expect(lineage.reload.termination_reason).to eq("budget_exceeded")
    end

    it 'marks the lineage as no longer active' do
      lineage.terminate!(reason: "manual")
      expect(lineage.reload.active?).to be false
    end
  end

  describe '#spawn_depth' do
    it 'returns 0 for a direct parent-child relationship' do
      lineage = create(:ai_agent_lineage,
                       account: account,
                       parent_agent: parent_agent,
                       child_agent: child_agent,
                       spawned_at: Time.current)

      expect(lineage.spawn_depth).to eq(0)
    end

    it 'returns correct depth for nested lineages' do
      grandparent = create(:ai_agent, account: account, creator: user, provider: provider)
      mid_agent = create(:ai_agent, account: account, creator: user, provider: provider)
      leaf_agent = create(:ai_agent, account: account, creator: user, provider: provider)

      create(:ai_agent_lineage,
             account: account,
             parent_agent: grandparent,
             child_agent: mid_agent,
             spawned_at: Time.current)

      leaf_lineage = create(:ai_agent_lineage,
                            account: account,
                            parent_agent: mid_agent,
                            child_agent: leaf_agent,
                            spawned_at: Time.current)

      expect(leaf_lineage.spawn_depth).to eq(1)
    end
  end
end
