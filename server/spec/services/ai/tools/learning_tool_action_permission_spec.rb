# frozen_string_literal: true

require "rails_helper"

# IMP-909ac33451cf / IMP-4d0550eac20e (recommendation 01a0b294-86c0).
#
# Two independent defects in Ai::Tools::LearningTool, fixed together:
#
# 1. create_learning and reinforce_learning were gated on "ai.analytics.manage",
#    a string Permissions.permission_exists? rejects (it is nowhere in
#    config/permissions.rb). User#has_permission? is an exact match against a
#    role_permissions row, so an uncatalogued name can never match one — no
#    seeded role grants it, which makes the action reachable only through
#    system.admin's blanket short-circuit. Retargeted onto "ai.memory.write",
#    the permission the sibling G4 fix (SharedKnowledgeTool) already uses for
#    the same shape of write — cross-agent/cross-team knowledge corpus
#    mutation — and which several real non-admin roles hold (owner, manager,
#    ai_specialist, system_worker), alongside admin.
#
# 2. The `status` filter parameter's advertised description hand-listed
#    "active/superseded/archived" — but Ai::CompoundLearning::STATUSES is
#    `active deprecated superseded verified disproven retired`. "archived" is
#    not a real status, so a caller who takes the advertisement at face value
#    gets a silently empty result (`.where(status: "archived")` matches no
#    row, no error). Fixed by deriving the advertised list from the model
#    constant so the two cannot drift again, and by refusing an unknown status
#    outright instead of silently returning nothing.
RSpec.describe Ai::Tools::LearningTool do
  include PermissionTestHelpers # role-backed permission grants (included by type only for request/controller/model)

  let(:account) { create(:account) }

  describe "the ACTION_PERMISSIONS map" do
    it "gates create_learning and reinforce_learning on a catalogued permission" do
      expect(described_class::ACTION_PERMISSIONS.fetch("create_learning")).to eq("ai.memory.write")
      expect(described_class::ACTION_PERMISSIONS.fetch("reinforce_learning")).to eq("ai.memory.write")
    end

    it "names a permission Permissions.permission_exists? recognizes" do
      expect(::Permissions.permission_exists?(described_class::ACTION_PERMISSIONS.fetch("create_learning"))).to be(true)
      expect(::Permissions.permission_exists?(described_class::ACTION_PERMISSIONS.fetch("reinforce_learning"))).to be(true)
    end

    it "is held by real non-admin roles (manager and ai_specialist), not just system.admin" do
      manager_perms = ::Permissions::ROLES.dig("manager", :permissions) || []
      specialist_perms = ::Permissions::ROLES.dig("ai_specialist", :permissions) || []

      expect(manager_perms).to include("ai.memory.write")
      expect(specialist_perms).to include("ai.memory.write")
    end
  end

  describe "#call create_learning" do
    it "refuses a user without ai.memory.write and creates nothing" do
      user = user_with_permissions("ai.agents.read", account: account)
      tool = described_class.new(account: account, user: user)

      expect {
        result = tool.send(:call, action: "create_learning", content: "unauthorized write attempt")
        expect(result[:success]).to be(false)
        expect(result[:error]).to include("ai.memory.write")
      }.not_to change { ::Ai::CompoundLearning.where(account: account).count }
    end

    it "creates a learning for a non-admin user holding ai.memory.write" do
      user = user_with_permissions("ai.agents.read", "ai.memory.write", account: account)
      tool = described_class.new(account: account, user: user)

      expect {
        result = tool.send(:call, action: "create_learning", content: "authorized write")
        expect(result[:success]).to be(true)
      }.to change { ::Ai::CompoundLearning.where(account: account).count }.by(1)
    end
  end

  describe "#call reinforce_learning" do
    let!(:learning) do
      create(:ai_compound_learning, account: account, importance_score: 0.5)
    end

    it "refuses a user without ai.memory.write and does not reinforce" do
      user = user_with_permissions("ai.agents.read", account: account)
      tool = described_class.new(account: account, user: user)

      result = tool.send(:call, action: "reinforce_learning", learning_id: learning.id)

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("ai.memory.write")
      expect(learning.reload.importance_score.to_f).to eq(0.5)
    end

    it "reinforces for a non-admin user holding ai.memory.write" do
      user = user_with_permissions("ai.agents.read", "ai.memory.write", account: account)
      tool = described_class.new(account: account, user: user)

      result = tool.send(:call, action: "reinforce_learning", learning_id: learning.id)

      expect(result[:success]).to be(true)
      expect(learning.reload.importance_score.to_f).to be > 0.5
    end
  end

  describe "advertised status values" do
    it "derives self.definition's status description from Ai::CompoundLearning::STATUSES" do
      description = described_class.definition[:parameters][:status][:description]

      Ai::CompoundLearning::STATUSES.each { |status| expect(description).to include(status) }
      expect(description).not_to include("archived")
    end

    it "derives query_learnings' status description from Ai::CompoundLearning::STATUSES" do
      description = described_class.action_definitions["query_learnings"][:parameters][:status][:description]

      Ai::CompoundLearning::STATUSES.each { |status| expect(description).to include(status) }
      expect(description).not_to include("archived")
    end
  end

  describe "query_learnings with an unrecognized status" do
    it "refuses with an error listing the valid statuses instead of silently returning nothing" do
      user = user_with_permissions("ai.agents.read", account: account)
      tool = described_class.new(account: account, user: user)
      create(:ai_compound_learning, account: account, status: "active")

      result = tool.send(:call, action: "query_learnings", status: "archived")

      expect(result[:success]).to be(false)
      expect(result[:error]).to include("archived")
      Ai::CompoundLearning::STATUSES.each { |status| expect(result[:error]).to include(status) }
    end

    it "still returns results for a real status" do
      user = user_with_permissions("ai.agents.read", account: account)
      tool = described_class.new(account: account, user: user)
      learning = create(:ai_compound_learning, account: account, status: "verified")

      result = tool.send(:call, action: "query_learnings", status: "verified")

      expect(result[:success]).to be(true)
      expect(result[:learnings].map { |l| l[:id] }).to include(learning.id)
    end
  end
end
