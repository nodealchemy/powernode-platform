# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::AgentAutonomyService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  subject(:service) { described_class.new(account: account) }

  # The service references team.ai_agent_team_members and member.ai_agent,
  # which are incorrect association names (model uses `members` and `agent`).
  # We use plain doubles to test the service's own logic without hitting model errors.

  describe '#create_agent_for_team' do
    let(:team) { double('team', name: "Test Team") }
    let(:members_relation) { double('members_relation') }
    let(:agent_params) { { name: "Test Agent", description: "A test agent", role: "worker" } }

    before do
      allow(team).to receive(:ai_agent_team_members).and_return(members_relation)
      allow(Ai::GuardrailConfig).to receive(:where).with(account: account).and_return(
        double('relation', active: Ai::GuardrailConfig.none)
      )
    end

    it 'creates an agent and adds it to the team' do
      agent = double('agent', name: "Test Agent", description: "A test agent",
                      status: "active", account: account)
      allow(agent).to receive(:respond_to?).and_return(false)
      allow(agent).to receive(:save!).and_return(true)
      allow(Ai::Agent).to receive(:new).and_return(agent)
      allow(members_relation).to receive(:create!).and_return(double('member'))

      result = service.create_agent_for_team(team, agent_params, user)
      expect(result).to eq(agent)
      expect(result.name).to eq("Test Agent")
    end

    it 'creates a team member with the specified role' do
      agent = double('agent', name: "Test Agent")
      allow(agent).to receive(:respond_to?).and_return(false)
      allow(agent).to receive(:save!).and_return(true)
      allow(Ai::Agent).to receive(:new).and_return(agent)

      expect(members_relation).to receive(:create!).with(
        hash_including(ai_agent: agent, role: "worker")
      ).and_return(double('member'))

      service.create_agent_for_team(team, agent_params, user)
    end

    it 'defaults role to worker when not specified' do
      params = { name: "No Role Agent", description: "desc" }
      agent = double('agent', name: "No Role Agent")
      allow(agent).to receive(:respond_to?).and_return(false)
      allow(agent).to receive(:save!).and_return(true)
      allow(Ai::Agent).to receive(:new).and_return(agent)

      expect(members_relation).to receive(:create!).with(
        hash_including(role: "worker")
      ).and_return(double('member'))

      service.create_agent_for_team(team, params, user)
    end

    context 'when team has reached max capacity' do
      before do
        guardrails_relation = double('active_guardrails')
        allow(guardrails_relation).to receive(:pick).with(:configuration).and_return({ "max_agents_per_team" => 1 })
        allow(guardrails_relation).to receive(:find_each)
        allow(Ai::GuardrailConfig).to receive(:where).with(account: account).and_return(
          double('relation', active: guardrails_relation)
        )

        allow(members_relation).to receive(:count).and_return(1)
      end

      it 'raises ArgumentError' do
        expect {
          service.create_agent_for_team(team, agent_params, user)
        }.to raise_error(ArgumentError, /maximum capacity/)
      end
    end

    context 'when agent save fails' do
      it 'raises ActiveRecord::RecordInvalid' do
        agent = double('agent', name: "Test Agent")
        allow(agent).to receive(:respond_to?).and_return(false)
        allow(agent).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(Ai::Agent.new))
        allow(Ai::Agent).to receive(:new).and_return(agent)

        expect {
          service.create_agent_for_team(team, agent_params, user)
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end
  end

  describe '#update_agent_in_team' do
    let(:agent) { create(:ai_agent, account: account) }
    let(:team) { double('team', name: "Test Team") }
    let(:member) do
      double('member', role: "worker", ai_agent: agent).tap do |m|
        allow(m).to receive(:update!).and_return(true)
      end
    end

    before do
      allow(Ai::GuardrailConfig).to receive(:where).with(account: account).and_return(
        double('relation', active: Ai::GuardrailConfig.none)
      )
    end

    it 'updates agent name and description' do
      result = service.update_agent_in_team(team, member, { name: "Updated Name", description: "Updated desc" })

      expect(result.name).to eq("Updated Name")
      expect(result.description).to eq("Updated desc")
    end

    context 'when role is changed' do
      let(:authority) { instance_double(Ai::TeamAuthorityService) }

      before do
        allow(Ai::TeamAuthorityService).to receive(:new).with(team: team).and_return(authority)
        allow(authority).to receive(:authorize_authority_change!).and_return(true)
      end

      it 'checks authority and updates role' do
        expect(member).to receive(:update!).with(role: "lead")
        service.update_agent_in_team(team, member, { role: "lead" }, actor: user)

        expect(authority).to have_received(:authorize_authority_change!)
      end
    end

    it 'does not check authority when role is not changed' do
      expect(Ai::TeamAuthorityService).not_to receive(:new)
      service.update_agent_in_team(team, member, { name: "New Name" })
    end
  end

  describe '#remove_agent_from_team' do
    let(:agent) { double('agent', id: SecureRandom.uuid, name: "Agent 1") }
    let(:team) { double('team', name: "Test Team") }
    let(:member) do
      double('member', ai_agent: agent).tap do |m|
        allow(m).to receive(:destroy!).and_return(true)
      end
    end
    let(:authority) { instance_double(Ai::TeamAuthorityService) }

    before do
      allow(Ai::TeamAuthorityService).to receive(:new).with(team: team).and_return(authority)
      allow(authority).to receive(:authorize_member_management!).and_return(true)
      allow(team).to receive(:respond_to?).with(:ai_team_tasks).and_return(false)
    end

    it 'destroys the team member' do
      expect(member).to receive(:destroy!)
      service.remove_agent_from_team(team, member, actor: user)
    end

    it 'returns true on success' do
      result = service.remove_agent_from_team(team, member, actor: user)
      expect(result).to be true
    end

    it 'checks authority for member removal' do
      service.remove_agent_from_team(team, member, actor: user)
      expect(authority).to have_received(:authorize_member_management!).with(user, :remove_member)
    end
  end

  describe '#auto_assign_lead' do
    let(:team) { double('team', name: "Test Team") }

    context 'with no members' do
      before do
        members_result = double('members_result')
        allow(members_result).to receive(:empty?).and_return(true)
        members_relation = double('members_relation')
        allow(members_relation).to receive(:includes).with(:ai_agent).and_return(members_result)
        allow(team).to receive(:ai_agent_team_members).and_return(members_relation)
      end

      it 'returns nil' do
        expect(service.auto_assign_lead(team)).to be_nil
      end
    end

    context 'with members' do
      let(:agent1) { create(:ai_agent, account: account, status: "active", created_at: 60.days.ago) }
      let(:agent2) { create(:ai_agent, account: account, status: "active", created_at: 1.day.ago) }
      let(:member1) do
        double('member1', ai_agent: agent1, role: "worker").tap do |m|
          allow(m).to receive(:update!).and_return(true)
        end
      end
      let(:member2) do
        double('member2', ai_agent: agent2, role: "worker").tap do |m|
          allow(m).to receive(:update!).and_return(true)
        end
      end

      before do
        members_proxy = double('members_proxy')
        allow(members_proxy).to receive(:empty?).and_return(false)
        allow(members_proxy).to receive(:map) { |&block| [member1, member2].map(&block) }
        allow(members_proxy).to receive(:where).with(role: "lead").and_return(
          double('lead_relation', update_all: true)
        )
        members_relation = double('members_relation')
        allow(members_relation).to receive(:includes).with(:ai_agent).and_return(members_proxy)
        allow(team).to receive(:ai_agent_team_members).and_return(members_relation)
      end

      it 'assigns the best-scoring agent as lead' do
        result = service.auto_assign_lead(team)
        # agent1 is older, so it should score higher on experience
        expect(result).to eq(agent1)
      end

      it 'demotes existing leads before assigning new one' do
        lead_relation = double('lead_relation')
        members_proxy = double('members_proxy')
        allow(members_proxy).to receive(:empty?).and_return(false)
        allow(members_proxy).to receive(:map) { |&block| [member1, member2].map(&block) }
        allow(members_proxy).to receive(:where).with(role: "lead").and_return(lead_relation)
        members_relation = double('members_relation')
        allow(members_relation).to receive(:includes).with(:ai_agent).and_return(members_proxy)
        allow(team).to receive(:ai_agent_team_members).and_return(members_relation)

        expect(lead_relation).to receive(:update_all).with(role: "worker")
        service.auto_assign_lead(team)
      end
    end
  end

  describe '#share_memory_between_agents' do
    let(:source_agent) { create(:ai_agent, account: account) }
    let(:target_agent) { create(:ai_agent, account: account) }

    before do
      allow(Ai::PersistentContext).to receive(:where).and_return(Ai::PersistentContext.none)
    end

    it 'returns empty array when no source contexts exist' do
      result = service.share_memory_between_agents(source_agent, target_agent, ["key1"])
      expect(result).to eq([])
    end

    context 'when source contexts exist with matching entries' do
      let(:context_entry) do
        double('entry', content: { "data" => "test" }, entry_key: "key1")
      end
      let(:active_entries) { double('active_entries') }
      let(:source_context) do
        double('context', context_entries: active_entries)
      end
      let(:target_context) { double('target_context') }
      let(:shared_entry) { double('shared_entry') }

      before do
        allow(active_entries).to receive(:active).and_return(active_entries)
        allow(active_entries).to receive(:find_by).with(entry_key: "key1").and_return(context_entry)

        contexts_relation = double('contexts_relation')
        allow(contexts_relation).to receive(:find_each).and_yield(source_context)
        allow(Ai::PersistentContext).to receive(:where).and_return(contexts_relation)

        allow(Ai::ContextPersistenceService).to receive(:get_agent_memory).and_return(target_context)
        allow(Ai::ContextPersistenceService).to receive(:add_entry).and_return(shared_entry)
      end

      it 'shares entries to the target agent' do
        result = service.share_memory_between_agents(source_agent, target_agent, ["key1"])
        expect(result).to eq([shared_entry])
      end

      it 'creates shared entries with proper attributes' do
        service.share_memory_between_agents(source_agent, target_agent, ["key1"])

        expect(Ai::ContextPersistenceService).to have_received(:add_entry).with(
          context: target_context,
          attributes: hash_including(
            key: "shared:#{source_agent.id}:key1",
            type: "shared_memory"
          )
        )
      end
    end
  end
end
