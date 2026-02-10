# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Security::PrivilegeEnforcementService, type: :service do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  subject(:service) { described_class.new(account: account) }

  describe "#check_action!" do
    context "with no policies" do
      it "allows the action" do
        result = service.check_action!(agent: agent, action: "read_data")
        expect(result[:allowed]).to be true
        expect(result[:reason]).to be_nil
      end
    end

    context "with a restrictive policy" do
      let!(:policy) do
        create(:ai_agent_privilege_policy,
          account: account,
          agent_id: agent.id,
          policy_name: "agent_restriction_#{agent.id}",
          denied_actions: ["delete_data", "modify_system"],
          active: true
        )
      end

      it "blocks denied actions" do
        result = service.check_action!(agent: agent, action: "delete_data")
        expect(result[:allowed]).to be false
        expect(result[:reason]).to include("denied")
        expect(result[:policy_id]).to eq(policy.id)
      end

      it "allows non-denied actions" do
        result = service.check_action!(agent: agent, action: "read_data")
        expect(result[:allowed]).to be true
      end
    end

    context "with resource restrictions" do
      let!(:policy) do
        create(:ai_agent_privilege_policy,
          account: account,
          agent_id: agent.id,
          policy_name: "resource_restriction_#{agent.id}",
          denied_resources: ["secrets", "credentials"],
          active: true
        )
      end

      it "blocks access to denied resources" do
        result = service.check_action!(agent: agent, action: "read", resource: "secrets")
        expect(result[:allowed]).to be false
        expect(result[:reason]).to include("denied")
      end

      it "allows access to non-denied resources" do
        result = service.check_action!(agent: agent, action: "read", resource: "documents")
        expect(result[:allowed]).to be true
      end
    end
  end

  describe "#check_tool!" do
    let!(:policy) do
      create(:ai_agent_privilege_policy,
        account: account,
        agent_id: agent.id,
        policy_name: "tool_restriction_#{agent.id}",
        denied_tools: ["execute_code", "shell_command"],
        active: true
      )
    end

    it "blocks denied tools" do
      result = service.check_tool!(agent: agent, tool_name: "execute_code")
      expect(result[:allowed]).to be false
      expect(result[:reason]).to include("execute_code")
    end

    it "allows non-denied tools" do
      result = service.check_tool!(agent: agent, tool_name: "search")
      expect(result[:allowed]).to be true
    end
  end

  describe "#check_communication!" do
    let(:agent_b) { create(:ai_agent, account: account, provider: provider) }

    context "with no communication rules" do
      it "allows communication by default" do
        result = service.check_communication!(from_agent: agent, to_agent: agent_b)
        expect(result[:allowed]).to be true
      end
    end

    context "with blocked communication pairs" do
      let!(:policy) do
        create(:ai_agent_privilege_policy,
          account: account,
          agent_id: agent.id,
          policy_name: "comm_restriction_#{agent.id}",
          communication_rules: {
            "blocked_pairs" => [[agent.id, agent_b.id]]
          },
          active: true
        )
      end

      it "blocks communication between blocked pairs" do
        result = service.check_communication!(from_agent: agent, to_agent: agent_b)
        expect(result[:allowed]).to be false
        expect(result[:reason]).to include("denied")
      end
    end
  end

  describe "#detect_escalation" do
    it "returns low escalation score with no history" do
      result = service.detect_escalation(agent: agent)
      expect(result[:escalation_score]).to eq(0.0)
      expect(result[:escalated]).to be false
      expect(result[:recommended_action]).to eq("none")
    end

    it "detects escalation with many denied actions" do
      8.times do |i|
        create(:ai_security_audit_trail, :denied,
          account: account,
          agent_id: agent.id,
          action: "privilege_check:action_#{i}")
      end

      result = service.detect_escalation(agent: agent)
      expect(result[:escalation_score]).to be > 0.3
      expect(result[:recommended_action]).not_to eq("none")
    end

    it "recommends quarantine for very high escalation scores" do
      # Create many denied + blocked trails with diverse actions
      10.times do |i|
        create(:ai_security_audit_trail, :denied,
          account: account,
          agent_id: agent.id,
          action: "privilege_check:diverse_#{i}")
      end
      5.times do |i|
        create(:ai_security_audit_trail, :blocked,
          account: account,
          agent_id: agent.id,
          action: "privilege_check:blocked_#{i}")
      end

      result = service.detect_escalation(agent: agent)
      expect(result[:escalated]).to be true
    end
  end

  describe "#policies_for_agent" do
    it "returns applicable policies sorted by priority" do
      low_priority = create(:ai_agent_privilege_policy,
        account: account, agent_id: agent.id,
        policy_name: "low_#{agent.id}", priority: 1, active: true)
      high_priority = create(:ai_agent_privilege_policy,
        account: account, agent_id: agent.id,
        policy_name: "high_#{agent.id}", priority: 100, active: true)

      policies = service.policies_for_agent(agent: agent)
      expect(policies.first).to eq(high_priority)
      expect(policies.last).to eq(low_priority)
    end

    it "excludes inactive policies" do
      create(:ai_agent_privilege_policy, :inactive,
        account: account, agent_id: agent.id,
        policy_name: "inactive_#{agent.id}")

      policies = service.policies_for_agent(agent: agent)
      expect(policies).to be_empty
    end
  end
end
