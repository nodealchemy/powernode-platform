# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::AgentPrivilegePolicy, type: :model do
  let(:account) { create(:account) }
  let(:provider) { create(:ai_provider, account: account) }
  let(:agent) { create(:ai_agent, account: account, provider: provider) }

  describe "#action_allowed?" do
    it "denies actions in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_actions: ["delete_data"])
      expect(policy.action_allowed?("delete_data")).to be false
    end

    it "allows actions not in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_actions: ["delete_data"])
      expect(policy.action_allowed?("read_data")).to be true
    end

    it "denies all actions when wildcard is in denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_actions: ["*"])
      expect(policy.action_allowed?("read_data")).to be false
      expect(policy.action_allowed?("write_data")).to be false
      expect(policy.action_allowed?("any_action")).to be false
    end

    it "allows actions via wildcard in allowed list" do
      policy = build(:ai_agent_privilege_policy, account: account, allowed_actions: ["*"])
      expect(policy.action_allowed?("any_action")).to be true
    end

    it "denied wildcard takes precedence over allowed wildcard" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     allowed_actions: ["*"], denied_actions: ["*"])
      expect(policy.action_allowed?("any_action")).to be false
    end
  end

  describe "#tool_allowed?" do
    it "denies tools in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_tools: ["execute_code"])
      expect(policy.tool_allowed?("execute_code")).to be false
    end

    it "allows tools not in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_tools: ["execute_code"])
      expect(policy.tool_allowed?("search")).to be true
    end

    it "denies all tools when wildcard is in denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_tools: ["*"])
      expect(policy.tool_allowed?("search")).to be false
      expect(policy.tool_allowed?("execute_code")).to be false
    end

    it "denied wildcard takes precedence over allowed wildcard" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     allowed_tools: ["*"], denied_tools: ["*"])
      expect(policy.tool_allowed?("any_tool")).to be false
    end
  end

  describe "#resource_allowed?" do
    it "denies resources in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_resources: ["secrets"])
      expect(policy.resource_allowed?("secrets")).to be false
    end

    it "allows resources not in the denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_resources: ["secrets"])
      expect(policy.resource_allowed?("documents")).to be true
    end

    it "denies all resources when wildcard is in denied list" do
      policy = build(:ai_agent_privilege_policy, account: account, denied_resources: ["*"])
      expect(policy.resource_allowed?("secrets")).to be false
      expect(policy.resource_allowed?("documents")).to be false
    end
  end

  describe "#communication_allowed?" do
    let(:agent_a_id) { SecureRandom.uuid }
    let(:agent_b_id) { SecureRandom.uuid }

    it "allows communication when no rules are set" do
      policy = build(:ai_agent_privilege_policy, account: account, communication_rules: {})
      expect(policy.communication_allowed?(agent_a_id, agent_b_id)).to be true
    end

    it "blocks communication between explicitly blocked pairs" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     communication_rules: { "blocked_pairs" => [[agent_a_id, agent_b_id]] })
      expect(policy.communication_allowed?(agent_a_id, agent_b_id)).to be false
    end

    it "blocks all communication when wildcard is in blocked pairs" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     communication_rules: { "blocked_pairs" => [[agent_a_id, "*"]] })
      expect(policy.communication_allowed?(agent_a_id, agent_b_id)).to be false
      expect(policy.communication_allowed?(agent_a_id, SecureRandom.uuid)).to be false
    end

    it "blocks communication with double wildcard" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     communication_rules: { "blocked_pairs" => [["*", "*"]] })
      expect(policy.communication_allowed?(agent_a_id, agent_b_id)).to be false
    end

    it "allows communication not in blocked pairs" do
      other_id = SecureRandom.uuid
      policy = build(:ai_agent_privilege_policy, account: account,
                     communication_rules: { "blocked_pairs" => [[agent_a_id, agent_b_id]] })
      expect(policy.communication_allowed?(agent_a_id, other_id)).to be true
    end

    it "respects allowed_pairs with wildcards" do
      policy = build(:ai_agent_privilege_policy, account: account,
                     communication_rules: {
                       "allowed_pairs" => [[agent_a_id, "*"]]
                     })
      expect(policy.communication_allowed?(agent_a_id, agent_b_id)).to be true
      expect(policy.communication_allowed?(agent_a_id, SecureRandom.uuid)).to be true
    end
  end
end
