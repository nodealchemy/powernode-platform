# frozen_string_literal: true

require "rails_helper"

# HIER-P2I (proposal §5 ruling 8): a GLOBAL canonical agent (account_id NULL)
# is a template, never an executing principal. Before this seam
# BaseTool.permitted? answered `true` for any agent without an account, so a
# canonical that ever reached a tool was UNBOUNDED — no permission at all —
# while the account-scoped clone it should have been running as is bounded by
# the account's role. Both halves are pinned here with the SAME tool and the
# SAME required permission: the canonical is refused, its clone is permitted.
RSpec.describe Ai::Tools::BaseTool, "canonical principals never execute (HIER-P2I)" do
  let(:account) { create(:account) }
  let!(:user) { create(:user, account: account, permissions: [ "ai.campaigns.manage" ]) }
  let(:seeding_account) { create(:account, name: "Powernode Admin") }
  let(:canonical) do
    create(:ai_agent, :global, owner_account: seeding_account,
                              name: "Platform Developer", slug: "platform-developer",
                              source_key: "platform-developer", agent_type: "code_assistant",
                              is_system: true)
  end

  # A tool with a REAL required permission and a body that records that it ran.
  let(:tool_class) do
    Class.new(described_class) do
      const_set(:REQUIRED_PERMISSION, "ai.campaigns.manage")

      def self.name = "Ai::Tools::HierP2iProbeTool"

      def self.definition
        { name: "hier_p2i_probe", description: "HIER-P2I probe", parameters: {} }
      end

      def call(_params) = success_result(ran: true)
    end
  end

  describe ".permitted?" do
    it "is FALSE for a global canonical — a caller consulting it alone fails closed" do
      expect(tool_class.permitted?(agent: canonical)).to be(false)
    end

    it "keeps the nil-agent path exactly as it was" do
      expect(tool_class.permitted?(agent: nil)).to be(true)
    end
  end

  describe "#execute with a global canonical as the acting agent" do
    let(:tool) { tool_class.new(account: account, user: canonical.creator, agent: canonical) }

    it "refuses with a result envelope naming the canonical slug and the clone path, never running the body" do
      expect_any_instance_of(tool_class).not_to receive(:call)

      result = tool.execute(params: {})

      expect(result[:success]).to be(false)
      expect(result[:refusal]).to eq(described_class::CANONICAL_PRINCIPAL_REFUSAL)
      expect(result[:canonical_slug]).to eq("platform-developer")
      expect(result[:error]).to include("platform-developer")
      expect(result[:error]).to match(/clone/i)
      expect(result[:error]).to match(/canonical_slug: platform-developer/)
    end

    it "is refused ahead of parameter validation — a malformed call is still a principal refusal" do
      strict = Class.new(tool_class) do
        def self.name = "Ai::Tools::HierP2iStrictProbeTool"

        def self.definition
          { name: "hier_p2i_strict_probe", description: "probe",
            parameters: { target: { type: "string", required: true } } }
        end
      end

      result = strict.new(account: account, user: canonical.creator, agent: canonical).execute(params: {})

      expect(result[:success]).to be(false)
      expect(result[:refusal]).to eq(described_class::CANONICAL_PRINCIPAL_REFUSAL)
    end

    it "audits the refusal as an mcp.tools.canonical_principal_refused row carrying the slug, never the body" do
      expect { tool.execute(params: {}) }
        .to change { AuditLog.where(action: described_class::CANONICAL_PRINCIPAL_AUDIT_ACTION, account: account).count }
        .by(1)

      row = AuditLog.where(action: described_class::CANONICAL_PRINCIPAL_AUDIT_ACTION, account: account).last
      expect(row.metadata["canonical_slug"]).to eq("platform-developer")
      expect(row.metadata["agent_id"]).to eq(canonical.id)
      expect(row.metadata["tool_class"]).to eq("Ai::Tools::HierP2iProbeTool")
      expect(row.user_id).to be_nil
    end

    it "still logs (and refuses) when the tool has no account to audit under" do
      allow(Rails.logger).to receive(:warn).and_call_original

      result = tool_class.new(account: nil, agent: canonical).execute(params: {})

      expect(result[:success]).to be(false)
      expect(Rails.logger).to have_received(:warn).with(/canonical principal refused/i)
    end
  end

  describe "#execute with no agent at all" do
    it "is untouched — a user-principal call runs the body" do
      expect(tool_class.new(account: account, user: user).execute(params: {}))
        .to eq(success: true, data: { ran: true })
    end
  end

  describe "the clone path (AgentManagementTool#create_agent canonical_slug:)" do
    it "mints an account-scoped clone that PASSES the same tool the canonical was refused on" do
      canonical
      mgmt = Ai::Tools::AgentManagementTool.new(account: account, user: user, internal: true)
      created = mgmt.execute(params: { action: "create_agent", canonical_slug: "platform-developer" })
      expect(created[:success]).to be(true), created.inspect

      clone = Ai::Agent.find(created[:agent_id])
      expect(clone.account_id).to eq(account.id)
      expect(clone.cloned_from_id).to eq(canonical.id)
      expect(clone.global?).to be(false)

      expect(tool_class.permitted?(agent: clone)).to be(true)
      expect(tool_class.new(account: account, user: user, agent: clone).execute(params: {}))
        .to eq(success: true, data: { ran: true })
    end

    it "denies the clone when no account user holds the permission — bounded by the account role, not unbounded" do
      canonical
      unprivileged_account = create(:account)
      unprivileged = create(:user, account: unprivileged_account, permissions: [ "ai.goals.read" ])
      mgmt = Ai::Tools::AgentManagementTool.new(account: unprivileged_account, user: unprivileged, internal: true)
      created = mgmt.execute(params: { action: "create_agent", canonical_slug: "platform-developer" })
      expect(created[:success]).to be(true), created.inspect
      clone = Ai::Agent.find(created[:agent_id])

      expect(clone.account_id).to eq(unprivileged_account.id)
      expect(tool_class.permitted?(agent: clone)).to be(false)
    end
  end

  # Two shipped tools override .permitted? to answer `true` for ANY agent so
  # that escalation and the kill switch stay visible in every account's tool
  # list. Neither calls super, so BaseTool's fail-closed line never runs for
  # them: without the refusal in the override itself,
  # PlatformApiToolRegistry.advertised_class? would keep advertising them to a
  # canonical and Ai::Executors::DeferredToolCall#authorized? would answer
  # authorized for a row one parked.
  describe "the .permitted? overrides that do not call super" do
    [ Ai::Tools::KillSwitchTool, Ai::Tools::AgentAutonomyTool ].each do |klass|
      it "#{klass.name} refuses a global canonical while still permitting an account agent" do
        expect(klass.permitted?(agent: canonical)).to be(false)
        expect(klass.permitted?(agent: create(:ai_agent, account: account, creator: user))).to be(true)
        expect(klass.permitted?(agent: nil)).to be(true)
      end
    end

    it "keeps the canonical out of the advertised per-agent tool list" do
      advertised = Ai::Tools::PlatformApiToolRegistry.advertised_class?(Ai::Tools::KillSwitchTool,
                                                                       agent: canonical)
      expect(advertised).to be(false)
    end
  end
end
