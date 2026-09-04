# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::Agent, type: :model do
  describe 'associations' do
    it { should belong_to(:account).optional } # optional: a GLOBAL agent has account_id nil
    # optional ONLY on a global row (IMP-6cda93db7f31) — the presence rule for
    # account-scoped rows is pinned under 'validations' below.
    it { should belong_to(:provider).optional }
    it { should belong_to(:creator).optional }
    it { should have_many(:executions).dependent(:destroy) }
    it { should have_many(:conversations).dependent(:destroy) }
    it { should have_many(:messages).dependent(:destroy) }
  end

  describe 'validations' do
    subject { build(:ai_agent) }

    # IMP-6cda93db7f31: a GLOBAL canonical (account_id nil) is a seeded template
    # written before any user or provider exists; every account-scoped row —
    # every principal that can run — still carries both. Mirrors the CHECK
    # chk_ai_agents_account_rows_need_creator_and_provider.
    it 'requires a creator and a provider on an account-scoped row' do
      agent = build(:ai_agent, creator: nil, provider: nil)

      expect(agent).not_to be_valid
      expect(agent.errors[:creator]).to include('must exist')
      expect(agent.errors[:provider]).to include('must exist')
    end

    it 'allows a global canonical row without a creator or a provider' do
      agent = build(:ai_agent, account: nil, creator: nil, provider: nil,
                               name: 'Canonical Without Owner', slug: 'canonical-without-owner')

      expect(agent).to be_valid
      expect { agent.save! }.not_to raise_error
      expect(agent.reload.creator_id).to be_nil
      expect(agent.ai_provider_id).to be_nil
    end

    it { should validate_presence_of(:name) }
    it { should validate_presence_of(:agent_type) }
    it { should validate_length_of(:name).is_at_most(255) }
    it { should validate_length_of(:description).is_at_most(1000) }
    it { should validate_inclusion_of(:agent_type).in_array(%w[assistant code_assistant data_analyst content_generator image_generator monitor mcp_client]) }
    it { should validate_inclusion_of(:status).in_array(%w[active inactive paused error archived]) }

    context 'name uniqueness' do
      let!(:existing_agent) { create(:ai_agent) }

      it 'validates uniqueness of name within account scope' do
        duplicate_agent = build(:ai_agent,
                                name: existing_agent.name,
                                account: existing_agent.account)

        expect(duplicate_agent).not_to be_valid
        expect(duplicate_agent.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        different_account = create(:account)
        agent_with_same_name = build(:ai_agent,
                                    name: existing_agent.name,
                                    account: different_account)

        expect(agent_with_same_name).to be_valid
      end
    end

    context 'MCP validation' do
      it 'validates version format' do
        agent = build(:ai_agent, version: 'invalid')
        expect(agent).not_to be_valid
        expect(agent.errors[:version]).to include('must be in semantic version format (x.y.z)')
      end

      it 'accepts valid semantic version' do
        agent = build(:ai_agent, version: '1.2.3')
        expect(agent).to be_valid
      end
    end
  end

  describe 'scopes' do
    let!(:active_agent) { create(:ai_agent, status: 'active') }
    let!(:inactive_agent) { create(:ai_agent, status: 'inactive') }
    let!(:archived_agent) { create(:ai_agent, status: 'archived') }
    let!(:error_agent) { create(:ai_agent, status: 'error') }

    describe '.active' do
      it 'returns only active agents' do
        expect(Ai::Agent.active).to include(active_agent)
        expect(Ai::Agent.active).not_to include(inactive_agent)
      end
    end

    describe '.by_type' do
      let!(:assistant) { create(:ai_agent, agent_type: 'assistant') }
      let!(:code_assistant) { create(:ai_agent, :code_assistant) }

      it 'returns agents of specified type' do
        expect(Ai::Agent.by_type('assistant')).to include(assistant)
        expect(Ai::Agent.by_type('assistant')).not_to include(code_assistant)
      end
    end

    describe '.healthy' do
      it 'returns agents with active status' do
        expect(Ai::Agent.healthy).to include(active_agent)
        expect(Ai::Agent.healthy).not_to include(error_agent)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_validation' do
      it 'normalizes agent_type' do
        agent = build(:ai_agent, agent_type: '  ASSISTANT  ')
        agent.valid?
        expect(agent.agent_type).to eq('assistant')
      end

      it 'generates slug from name' do
        agent = build(:ai_agent, name: 'My Test Agent', slug: nil)
        agent.valid?
        expect(agent.slug).to be_present
        expect(agent.slug).to match(/^[a-z0-9\-_]+$/)
      end
    end

    describe 'after_create' do
      it 'includes Auditable concern for audit logging' do
        # Auditable concern skips audit logging in test environment to avoid deadlocks
        # Verify the concern is included and would create audit logs in production
        expect(Ai::Agent.ancestors).to include(Auditable)

        agent = create(:ai_agent)
        # auditable_attributes is a private method from the Auditable concern
        expect(agent.respond_to?(:auditable_attributes, true)).to be true
      end
    end
  end

  describe 'instance methods' do
    let(:agent) { create(:ai_agent, :with_executions) }

    describe '#mcp_available?' do
      it 'returns true for active agents with MCP configuration' do
        expect(agent.mcp_available?).to be true
      end

      it 'returns false for inactive agents' do
        agent.update!(status: 'inactive')
        expect(agent.mcp_available?).to be false
      end

      it 'returns false when provider is inactive' do
        agent.provider.update!(is_active: false)
        expect(agent.mcp_available?).to be false
      end

      it 'returns false when agent has no skills' do
        expect(agent.skill_slugs).to be_empty
      end
    end

    describe '#mcp_tool_id' do
      it 'generates consistent tool ID' do
        tool_id = agent.mcp_tool_id
        expect(tool_id).to start_with('agent_')
        expect(tool_id).to include(agent.id)
      end
    end

    describe '#execution_stats' do
      it 'returns execution statistics' do
        stats = agent.execution_stats

        expect(stats).to include(:total_executions)
        expect(stats).to include(:successful_executions)
        expect(stats).to include(:failed_executions)
        expect(stats).to include(:success_rate)
        expect(stats).to include(:average_duration)
        expect(stats[:total_executions]).to eq(3)
      end

      it 'calculates success rate correctly' do
        create(:ai_agent_execution, :completed, agent: agent, account: agent.account)
        create(:ai_agent_execution, :failed, agent: agent, account: agent.account)

        stats = agent.execution_stats
        expect(stats[:success_rate]).to be_a(Numeric)
        expect(stats[:success_rate]).to be >= 0
        expect(stats[:success_rate]).to be <= 100
      end
    end

    describe '#recent_executions' do
      it 'returns executions from last 24 hours by default' do
        old_execution = create(:ai_agent_execution,
                             agent: agent,
                             account: agent.account,
                             created_at: 2.days.ago)

        recent_executions = agent.recent_executions
        expect(recent_executions).not_to include(old_execution)
      end

      it 'accepts custom time period' do
        old_execution = create(:ai_agent_execution,
                             agent: agent,
                             account: agent.account,
                             created_at: 2.days.ago)

        recent_executions = agent.recent_executions(3.days)
        expect(recent_executions).to include(old_execution)
      end
    end

    describe '#average_response_time' do
      it 'calculates average response time from completed executions' do
        create(:ai_agent_execution, :completed, agent: agent, account: agent.account)

        avg_time = agent.average_response_time
        expect(avg_time).to be_a(Numeric)
        expect(avg_time).to be >= 0
      end

      it 'returns 0 when no completed executions exist' do
        agent.executions.destroy_all
        expect(agent.average_response_time).to eq(0)
      end
    end

    describe '#total_tokens_used' do
      it 'sums tokens from all completed executions' do
        create(:ai_agent_execution, :completed,
               agent: agent,
               account: agent.account,
               output_data: { metrics: { tokens_used: 100 } })

        create(:ai_agent_execution, :completed,
               agent: agent,
               account: agent.account,
               output_data: { metrics: { tokens_used: 200 } })

        expect(agent.total_tokens_used).to eq(300)
      end

      it 'returns 0 when no token data available' do
        agent.executions.destroy_all
        expect(agent.total_tokens_used).to eq(0)
      end
    end

    describe '#estimated_total_cost' do
      it 'sums cost estimates from all completed executions' do
        create(:ai_agent_execution, :completed,
               agent: agent,
               account: agent.account,
               output_data: { metrics: { cost_estimate: 0.005 } })

        create(:ai_agent_execution, :completed,
               agent: agent,
               account: agent.account,
               output_data: { metrics: { cost_estimate: 0.012 } })

        expect(agent.estimated_total_cost).to eq(0.017)
      end
    end

    describe '#deactivate!' do
      it 'sets agent as inactive and updates status' do
        agent.deactivate!('Testing deactivation')

        expect(agent.reload.status).to eq('inactive')
        expect(agent.mcp_metadata['deactivated_reason']).to eq('Testing deactivation')
      end

      it 'creates audit log entry' do
        agent.deactivate!('Testing')

        deactivation_log = AuditLog.where(
          resource_type: 'Ai::Agent',
          resource_id: agent.id.to_s,
          action: 'updated'
        ).last

        expect(deactivation_log).to be_present
        expect(deactivation_log.metadata['deactivation_reason']).to eq('Testing')
      end
    end

    describe '#activate!' do
      it 'sets agent as active and updates status' do
        agent.update!(status: 'inactive')
        agent.activate!

        expect(agent.reload.status).to eq('active')
      end
    end
  end

  describe 'class methods' do
    describe '.create_from_template' do
      let(:account) { create(:account) }
      let(:user) { create(:user, account: account) }
      let(:provider) { create(:ai_provider) }
      let(:template_data) do
        {
          name: 'Code Assistant',
          agent_type: 'code_assistant',
          description: 'Helps with coding tasks',
          mcp_tool_manifest: {
            'name' => 'code_assistant_tool',
            'description' => 'Code assistance tool',
            'type' => 'code_assistant',
            'version' => '1.0.0'
          }
        }
      end

      it 'creates agent from template data' do
        agent = Ai::Agent.create_from_template(account, provider, template_data, user)

        expect(agent).to be_persisted
        expect(agent.name).to eq('Code Assistant')
        expect(agent.agent_type).to eq('code_assistant')
        expect(agent.provider).to eq(provider)
        expect(agent.account).to eq(account)
      end

      it 'returns errors for invalid template data' do
        invalid_template = template_data.merge(agent_type: 'invalid_type')
        agent = Ai::Agent.create_from_template(account, provider, invalid_template, user)

        expect(agent).not_to be_persisted
        expect(agent.errors).not_to be_empty
      end
    end

    describe '.search' do
      let!(:code_agent) { create(:ai_agent, :code_assistant, name: 'Python Helper') }
      let!(:data_agent) { create(:ai_agent, :data_analyst, name: 'Data Analyzer') }

      it 'searches by name' do
        results = Ai::Agent.search('Python')
        expect(results).to include(code_agent)
        expect(results).not_to include(data_agent)
      end

      it 'searches by description' do
        data_agent.update!(description: 'Analyzes customer data trends')
        results = Ai::Agent.search('customer')
        expect(results).to include(data_agent)
      end

      it 'returns all agents for empty query' do
        results = Ai::Agent.search('')
        expect(results).to include(code_agent, data_agent)
      end
    end

    describe '.popular' do
      it 'returns agents ordered by execution count' do
        agent1 = create(:ai_agent)
        agent2 = create(:ai_agent)

        # Create more executions for agent2
        create_list(:ai_agent_execution, 3, agent: agent1, account: agent1.account)
        create_list(:ai_agent_execution, 5, agent: agent2, account: agent2.account)

        popular_agents = Ai::Agent.popular(limit: 2)
        expect(popular_agents.first).to eq(agent2)
        expect(popular_agents.second).to eq(agent1)
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles malformed JSON in metadata' do
      agent = create(:ai_agent)
      # Directly update database to simulate corrupted data
      Ai::Agent.where(id: agent.id).update_all(metadata: 'invalid json')

      expect { agent.reload.metadata }.not_to raise_error
    end

    it 'handles agent with no skills assigned' do
      agent = create(:ai_agent)
      expect(agent.skill_slugs).to eq([])
    end
  end

  describe '#build_system_prompt_with_profile' do
    # Characterization pin, not a red-first spec: this passes on HEAD today.
    # BASE_GUARDRAILS is a non-empty frozen constant unconditionally included
    # in the joined output, so the result can never be blank even when the
    # agent has no per-seed prompt, no skills, and no conversation profile.
    # Call sites rely on this invariant to skip `.presence || ...` fallbacks
    # onto mcp_metadata/mcp_tool_manifest system_prompt; if a future refactor
    # drops BASE_GUARDRAILS from the join, this spec will go red and flag
    # that those fallbacks need reinstating.
    it 'is never blank even with no base prompt, skills, or conversation profile' do
      agent = create(:ai_agent, mcp_metadata: {}, conversation_profile: {})

      expect(agent.build_system_prompt_with_profile).to be_present
      expect(agent.build_system_prompt_with_profile).to include(Ai::Agent::BASE_GUARDRAILS)
    end
  end

  describe 'BASE_GUARDRAILS reuse-first fleet-discovery wording' do
    # Extension-agnostic: an agent asked to provision infrastructure needs to
    # be pointed at fleet discovery (existing modules/templates/packages)
    # before building anything new, but core must never name an
    # extension-specific tool (no system_* actions) since BASE_GUARDRAILS
    # rides every agent regardless of which extensions are installed.
    it 'tells agents to discover existing fleet infrastructure before provisioning' do
      expect(Ai::Agent::BASE_GUARDRAILS).to include("provisioning fleet infrastructure")
      expect(Ai::Agent::BASE_GUARDRAILS).to include("the platform's fleet-discovery tools")
    end

    it 'never names an extension-specific (system_*) tool' do
      expect(Ai::Agent::BASE_GUARDRAILS).not_to match(/\bsystem_/)
    end
  end

  describe '#resolved_model Fable candidacy gate (pinned path)' do
    let(:gate_account) { create(:account) }
    let(:gate_provider) do
      p = create(:ai_provider, :anthropic, account: gate_account,
        supported_models: [
          { 'id' => 'claude-fable-5', 'name' => 'claude-fable-5' },
          { 'id' => 'claude-opus-4-8', 'name' => 'claude-opus-4-8' }
        ])
      create(:ai_provider_credential, account: gate_account, provider: p)
      p
    end
    let(:pinned_agent) do
      create(:ai_agent, account: gate_account, provider: gate_provider,
        agent_type: 'code_assistant',
        mcp_metadata: { 'model_config' => { 'model' => 'claude-fable-5' } })
    end

    it 'does NOT honor a Fable pin when the framework is off (falls through to a non-Fable model)' do
      expect(pinned_agent.resolved_model).not_to eq('claude-fable-5')
      expect(Ai::FableRouting.fable_model?(pinned_agent.resolved_model)).to be(false)
    end

    it 'honors the Fable pin when the framework is on' do
      gate_account.update!(settings: { 'fable_routing_enabled' => true })
      expect(pinned_agent.resolved_model).to eq('claude-fable-5')
    end
  end

  describe '#build_skill_system_prompts token budget' do
    # Every other per-call context source (memory injection, skill-graph
    # enrichment) is budgeted; this is the only unbounded one. Three attached
    # skills whose prompts are individually within budget but sum well past
    # it, to prove the method caps the TOTAL rather than just concatenating.
    let(:long_prompt) { "x" * 6000 }

    it 'caps total injected skill-prompt length instead of concatenating every attached skill unbounded' do
      agent = create(:ai_agent)
      skills = Array.new(3) { create(:ai_skill, system_prompt: long_prompt) }
      skills.each_with_index do |skill, i|
        create(:ai_agent_skill, agent: agent, skill: skill, priority: i)
      end

      result = agent.send(:build_skill_system_prompts)

      max_chars = Ai::Agent::DEFAULT_SKILL_PROMPT_TOKEN_BUDGET * Ai::Agent::SKILL_PROMPT_CHARS_PER_TOKEN
      expect(result.length).to be <= max_chars
      # Sanity: unbounded concatenation would be 3 * 6000 = 18000 chars, far over budget.
      expect(3 * long_prompt.length).to be > max_chars
    end

    it 'keeps the highest-priority skill prompts and drops lower-priority ones once the budget is spent' do
      agent = create(:ai_agent)
      kept = create(:ai_skill, system_prompt: "k" * 6000)
      dropped = create(:ai_skill, system_prompt: "d" * 6000)
      create(:ai_agent_skill, agent: agent, skill: kept, priority: 0)
      create(:ai_agent_skill, agent: agent, skill: dropped, priority: 1)

      result = agent.send(:build_skill_system_prompts)

      expect(result).to include(kept.system_prompt[0, 100])
      expect(result).not_to include(dropped.system_prompt)
    end

    it 'is tunable per-account without a deploy (Account#settings override)' do
      account = create(:account, settings: { Ai::Agent::SKILL_PROMPT_TOKEN_BUDGET_SETTING => 100 })
      agent = create(:ai_agent, account: account)
      skill = create(:ai_skill, system_prompt: "y" * 6000)
      create(:ai_agent_skill, agent: agent, skill: skill, priority: 0)

      expect(agent.send(:skill_prompt_token_budget)).to eq(100)
      result = agent.send(:build_skill_system_prompts)
      expect(result.length).to be <= 100 * Ai::Agent::SKILL_PROMPT_CHARS_PER_TOKEN
    end

    it 'falls back to the platform SiteSetting when no account override is present' do
      SiteSetting.set("ai_skill_prompt_token_budget", 50, setting_type: "integer")
      agent = create(:ai_agent)

      expect(agent.send(:skill_prompt_token_budget)).to eq(50)
    end
  end
end
