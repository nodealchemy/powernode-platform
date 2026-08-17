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

    context 'parent skill inheritance' do
      let(:parent_skill) { create(:ai_skill, account: account) }
      let(:related_skill) { create(:ai_skill, account: account) }
      let(:bridge) { instance_double(Ai::SkillGraph::BridgeService) }

      before do
        create(:ai_agent_skill, agent: parent_agent, skill: parent_skill)
        # Ai::Skill's after_commit sync_to_knowledge_graph creates the active KG
        # skill node the auto-assignment guard requires; assert it to keep the
        # guard's precondition honest rather than relying on it implicitly.
        expect(account.ai_knowledge_graph_nodes.active.skill_nodes).to exist
        allow(Ai::SkillGraph::BridgeService).to receive(:new).with(account).and_return(bridge)
        # Ai::Agent#sync_to_knowledge_graph and Ai::Skill#sync_to_knowledge_graph
        # also reach the bridge on create; incidental to the path under test.
        allow(bridge).to receive(:sync_agent)
        allow(bridge).to receive(:sync_skill)
      end

      context 'when the skill graph reports related skills' do
        before do
          allow(bridge).to receive(:auto_detect_relationships).with(parent_skill).and_return(
            [{ skill_id: related_skill.id, skill_name: related_skill.name,
               similarity: 0.91, confidence: 0.91 }]
          )
        end

        it 'assigns the graph-related skills to the spawned child agent' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be true
          expect(result[:agent].agent_skills.where(ai_skill_id: related_skill.id)).to exist
          expect(result[:agent].skills).to include(related_skill)
        end
      end

      # IMP-a3394f916399's property, re-seated onto the defect it was written
      # for. That defect was `agent.ai_agent_skills` — a dead reflection on THIS
      # service's own record — so the loud-failure guard belongs on the
      # association call, not on the bridge. It was originally injected through
      # the bridge stub because that was the convenient seam, which had the side
      # effect of pinning "any NoMethodError from the bridge aborts the spawn"
      # (see IMP-997a7f6b7db7 below). This example is green both before and
      # after that fix.
      context "when the factory's own association reflection is dead" do
        before do
          allow(bridge).to receive(:auto_detect_relationships).with(parent_skill).and_return(
            [{ skill_id: related_skill.id, skill_name: related_skill.name,
               similarity: 0.91, confidence: 0.91 }]
          )
          # Injected on the CHILD's write association — the exact call the
          # original defect got wrong — and only once the child exists.
          #
          # Two injection sites were tried and rejected, both of which pass
          # while proving nothing. allow_any_instance_of(Ai::Agent) fires inside
          # ensure_mcp_tool_manifest -> skill_slugs during create_agent, so the
          # spawn dies before this method runs. Stubbing parent.skills simulates
          # a failure that cannot occur: a genuinely absent method early-returns
          # at the respond_to? guard, and a genuinely dead has_many :through
          # raises ActiveRecord::HasManyThroughAssociationNotFoundError, which
          # is not a NameError at all. Factories build through save!, so
          # wrapping create! catches only the spawned child.
          allow(Ai::Agent).to receive(:create!).and_wrap_original do |orig, **kwargs|
            orig.call(**kwargs).tap do |child|
              allow(child).to receive(:agent_skills)
                .and_raise(NoMethodError, "undefined method 'ai_agent_skills'")
            end
          end
        end

        it 'surfaces the failure instead of swallowing it into a warn' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be false
          expect(result[:error]).to include("ai_agent_skills")
        end
      end

      # Containment is per-skill, not per-spawn: before IMP-997a7f6b7db7 the
      # detection call sat directly in the loop under one method-level rescue,
      # so the first skill whose detection failed ended the loop and every
      # LATER parent skill silently inherited nothing. Driven by call count
      # rather than by which skill sorts first, since parent.skills is unordered.
      context 'when neighbour detection fails for one of several parent skills' do
        let(:other_parent_skill) { create(:ai_skill, account: account) }

        before do
          create(:ai_agent_skill, agent: parent_agent, skill: other_parent_skill)
          calls = 0
          allow(bridge).to receive(:auto_detect_relationships) do |_skill|
            calls += 1
            raise StandardError, 'graph temporarily unavailable' if calls == 1

            [{ skill_id: related_skill.id, skill_name: related_skill.name,
               similarity: 0.91, confidence: 0.91 }]
          end
        end

        it 'still inherits neighbours for the remaining parent skills' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be true
          expect(result[:agent].agent_skills.where(ai_skill_id: related_skill.id)).to exist
        end
      end

      # The containment covers the collaborator CALL, not the shaping of its
      # result. Reading :skill_id off each neighbour is this service's own code,
      # so a bridge whose contract shifted to objects that do not answer #[] is
      # a programming error on our side and must still fail loudly.
      context 'when the skill graph returns neighbours this service cannot read' do
        before do
          allow(bridge).to receive(:auto_detect_relationships).and_return([Object.new])
        end

        it 'surfaces the failure instead of degrading to no neighbours' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be false
          expect(result[:error]).to include('[]')
        end
      end

      # IMP-997a7f6b7db7 — NoMethodError is a subclass of NameError, so the
      # `rescue NameError => raise` added for the dead reflection also caught
      # every nil receiver inside the collaborator, rolling back the whole
      # spawn over a best-effort enrichment step.
      context 'when the skill graph bridge raises a programming error from its own internals' do
        before do
          allow(bridge).to receive(:auto_detect_relationships)
            .and_raise(NoMethodError, "undefined method 'name' for nil")
          allow(Rails.logger).to receive(:warn).and_call_original
        end

        it 'keeps the spawn best-effort rather than rolling it back' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be true
          expect(result[:agent]).to be_persisted
          expect(result[:agent].agent_skills).to be_empty
          expect(Rails.logger).to have_received(:warn)
            .with(a_string_matching(/NoMethodError: undefined method 'name' for nil/))
        end
      end

      context 'when the skill graph bridge raises an operational error' do
        before do
          allow(bridge).to receive(:auto_detect_relationships)
            .and_raise(StandardError, "graph temporarily unavailable")
          allow(Rails.logger).to receive(:warn).and_call_original
        end

        it 'keeps the spawn best-effort and logs the failure class' do
          result = service.spawn(parent: parent_agent, config: config)

          expect(result[:success]).to be true
          expect(result[:agent]).to be_persisted
          expect(result[:agent].agent_skills).to be_empty
          expect(Rails.logger).to have_received(:warn)
            .with(a_string_matching(/StandardError: graph temporarily unavailable/))
        end
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
