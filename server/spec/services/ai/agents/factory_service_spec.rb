# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agents::FactoryService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:parent_agent) do
    create(:ai_agent,
           account: account,
           creator: user,
           provider: provider,
           trust_level: "monitored",
           max_spawn_depth: 3)
  end

  subject(:service) { described_class.new(account: account) }

  describe '#spawn' do
    let(:config) { { name: "Child Agent", creator_id: user.id, provider_id: provider.id } }

    context 'with valid config' do
      it 'creates a new agent' do
        result = service.spawn(parent: parent_agent, config: config)

        expect(result[:success]).to be true
        expect(result[:agent]).to be_persisted
        expect(result[:agent].name).to eq("Child Agent")
        expect(result[:agent].account).to eq(account)
      end

      it 'creates a lineage record' do
        result = service.spawn(parent: parent_agent, config: config)

        expect(result[:lineage]).to be_persisted
        expect(result[:lineage].parent_agent).to eq(parent_agent)
        expect(result[:lineage].child_agent).to eq(result[:agent])
      end

      it 'creates a trust score starting at supervised' do
        result = service.spawn(parent: parent_agent, config: config)

        expect(result[:trust_score]).to be_persisted
        expect(result[:trust_score].tier).to eq("supervised")
      end

      it 'returns no lineage for root agents (nil parent)' do
        result = service.spawn(parent: nil, config: config)

        expect(result[:success]).to be true
        expect(result[:lineage]).to be_nil
      end
    end

    context 'spawn validation' do
      it 'raises error when name is missing' do
        result = service.spawn(parent: parent_agent, config: { name: nil })

        expect(result[:success]).to be false
        expect(result[:error]).to include("name is required")
      end

      it 'raises error when spawn depth limit is exceeded' do
        # Create a chain of agents at max depth
        parent_agent.update!(max_spawn_depth: 1)

        # First spawn succeeds
        first = service.spawn(parent: parent_agent, config: { name: "Gen 1", creator_id: user.id, provider_id: provider.id })
        expect(first[:success]).to be true

        # Second spawn from child should fail (depth exceeded)
        first[:agent].update!(max_spawn_depth: 0)
        result = service.spawn(parent: first[:agent], config: { name: "Gen 2", creator_id: user.id, provider_id: provider.id })

        expect(result[:success]).to be false
        expect(result[:error]).to include("spawn depth")
      end

      it 'raises error when children limit is exceeded' do
        # Create MAX_ACTIVE_CHILDREN lineages
        Ai::Agents::FactoryService::MAX_ACTIVE_CHILDREN.times do |i|
          child = create(:ai_agent, account: account, creator: user, provider: provider)
          create(:ai_agent_lineage,
                 account: account,
                 parent_agent: parent_agent,
                 child_agent: child,
                 spawned_at: Time.current)
        end

        result = service.spawn(parent: parent_agent, config: config)

        expect(result[:success]).to be false
        expect(result[:error]).to include("children")
      end

      it 'prevents supervised agents from spawning' do
        create(:ai_agent_trust_score,
               agent: parent_agent,
               account: account,
               tier: "supervised")

        result = service.spawn(parent: parent_agent, config: config)

        expect(result[:success]).to be false
        expect(result[:error]).to include("Supervised")
      end
    end
  end

  describe '#terminate' do
    let(:child_agent) do
      create(:ai_agent, account: account, creator: user, provider: provider, status: "active")
    end
    let!(:lineage) do
      create(:ai_agent_lineage,
             account: account,
             parent_agent: parent_agent,
             child_agent: child_agent,
             spawned_at: Time.current)
    end

    context 'with cascade policy' do
      let(:grandchild) do
        create(:ai_agent, account: account, creator: user, provider: provider, status: "active")
      end
      let!(:child_lineage) do
        create(:ai_agent_lineage,
               account: account,
               parent_agent: child_agent,
               child_agent: grandchild,
               spawned_at: Time.current)
      end

      it 'terminates the agent and all children' do
        result = service.terminate(agent: child_agent, policy: "cascade", reason: "test")

        expect(result[:success]).to be true
        expect(child_agent.reload.status).to eq("archived")
        expect(grandchild.reload.status).to eq("archived")
      end

      it 'terminates lineage records' do
        service.terminate(agent: child_agent, policy: "cascade", reason: "test")

        expect(child_lineage.reload.terminated_at).to be_present
      end
    end

    context 'with orphan policy' do
      let(:grandchild) do
        create(:ai_agent, account: account, creator: user, provider: provider, status: "active")
      end
      let!(:child_lineage) do
        create(:ai_agent_lineage,
               account: account,
               parent_agent: child_agent,
               child_agent: grandchild,
               spawned_at: Time.current)
      end

      it 'terminates the agent but detaches children' do
        result = service.terminate(agent: child_agent, policy: "orphan", reason: "test")

        expect(result[:success]).to be true
        expect(child_agent.reload.status).to eq("archived")
        expect(grandchild.reload.status).to eq("active")
      end

      it 'terminates the child lineage (orphaning children)' do
        service.terminate(agent: child_agent, policy: "orphan", reason: "test")

        expect(child_lineage.reload.terminated_at).to be_present
        expect(child_lineage.termination_reason).to eq("parent_orphaned")
      end
    end

    context 'with graceful policy' do
      it 'archives agent when no active children exist' do
        # Terminate the child's own lineage so child_agent has no children
        result = service.terminate(agent: child_agent, policy: "graceful", reason: "done")

        expect(result[:success]).to be true
        expect(child_agent.reload.status).to eq("archived")
      end

      it 'marks for pending termination when active children exist' do
        grandchild = create(:ai_agent, account: account, creator: user, provider: provider, status: "active")
        create(:ai_agent_lineage,
               account: account,
               parent_agent: child_agent,
               child_agent: grandchild,
               spawned_at: Time.current)

        result = service.terminate(agent: child_agent, policy: "graceful", reason: "waiting")

        expect(result[:success]).to be true
        expect(child_agent.reload.status).to eq("inactive")
        expect(child_agent.metadata["pending_termination"]).to be true
      end
    end
  end

  describe '#lineage_tree' do
    it 'returns correct tree structure' do
      child = create(:ai_agent, account: account, creator: user, provider: provider)
      create(:ai_agent_lineage,
             account: account,
             parent_agent: parent_agent,
             child_agent: child,
             spawned_at: Time.current)

      tree = service.lineage_tree(agent: parent_agent)

      expect(tree[:id]).to eq(parent_agent.id)
      expect(tree[:name]).to eq(parent_agent.name)
      expect(tree[:children]).to be_an(Array)
      expect(tree[:children].size).to eq(1)
      expect(tree[:children].first[:id]).to eq(child.id)
    end

    it 'respects depth limit' do
      child = create(:ai_agent, account: account, creator: user, provider: provider)
      grandchild = create(:ai_agent, account: account, creator: user, provider: provider)

      create(:ai_agent_lineage, account: account, parent_agent: parent_agent, child_agent: child, spawned_at: Time.current)
      create(:ai_agent_lineage, account: account, parent_agent: child, child_agent: grandchild, spawned_at: Time.current)

      tree = service.lineage_tree(agent: parent_agent, depth: 1)

      expect(tree[:children].size).to eq(1)
      expect(tree[:children].first[:children]).to be_empty
    end
  end

  describe '#active_children' do
    it 'returns child agents from active lineages' do
      child1 = create(:ai_agent, account: account, creator: user, provider: provider)
      child2 = create(:ai_agent, account: account, creator: user, provider: provider)
      terminated_child = create(:ai_agent, account: account, creator: user, provider: provider)

      create(:ai_agent_lineage, account: account, parent_agent: parent_agent, child_agent: child1, spawned_at: Time.current)
      create(:ai_agent_lineage, account: account, parent_agent: parent_agent, child_agent: child2, spawned_at: Time.current)
      create(:ai_agent_lineage, :terminated, account: account, parent_agent: parent_agent, child_agent: terminated_child, spawned_at: Time.current)

      children = service.active_children(agent: parent_agent)

      expect(children).to include(child1, child2)
      expect(children).not_to include(terminated_child)
    end
  end
end
