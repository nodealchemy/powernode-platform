# frozen_string_literal: true

require "rails_helper"

# IMP-c2e3e5d3cff0 (c) — the TOOL-TO-TOOL hop.
#
# IMP-0e6b216de843 made every executor-nested tool carry the caller's instance
# provenance, and guarded it by scanning tool files for EXECUTOR construction.
# A tool that nests another TOOL directly is the same bypass in a shape that
# guard cannot see.
#
# DevLoopTool is explicitly instance-aware — #claimant_ref scopes dev-loop
# claims as "instance:<id>" for a managed dev-cell driving the loop over MCP
# (BUG-S) — and delegate_ralph_task IS registered on the MCP surface
# (PlatformApiToolRegistry). Its #delegate_tool built
# Ai::Tools::AgentManagementTool with account/user/agent and no provenance, so
# the nested tool could not tell a grant-gated instance principal from any
# other userless caller, and Ai::Tools::BaseTool#enforce_instance_deny_overlay!
# never engaged on the nested action.
#
# AgentManagementTool carries destroy-shaped actions (delete_agent). This is
# safe TODAY only because both nested call sites pass hardcoded action literals
# ("spawn_task", "wait_for_task"). That is a structural bound, not a fence:
# parameterize either action and the hole opens with nothing to catch it. These
# specs pin the fence itself, so the bound stops depending on the literals.
RSpec.describe Ai::Tools::DevLoopTool, "delegate tool instance provenance" do
  let(:account) { create(:account) }
  let(:node_instance) { double("NodeInstance", id: SecureRandom.uuid, account: account) }

  # Post-construction marking, mirroring McpPlatformToolRegistrar#execute_tool.
  def instance_tool
    tool = described_class.new(account: account, user: nil)
    tool.instance_authorized = true
    tool.node_instance = node_instance
    tool
  end

  describe "#delegate_tool" do
    it "hands the nested AgentManagementTool the instance provenance" do
      delegate = instance_tool.send(:delegate_tool)

      expect(delegate).to be_a(Ai::Tools::AgentManagementTool)
      expect(delegate.send(:instance_authorized?)).to be true
      expect(delegate.send(:node_instance)).to eq(node_instance)
    end

    it "leaves a user principal's delegate tool unmarked" do
      user = create(:user, account: account)
      delegate = described_class.new(account: account, user: user).send(:delegate_tool)

      expect(delegate.send(:instance_authorized?)).to be false
      expect(delegate.send(:node_instance)).to be_nil
    end

    # The reconciler / in-process path: no user, no provenance. Unchanged.
    it "leaves a bare userless caller's delegate tool unmarked" do
      delegate = described_class.new(account: account, user: nil).send(:delegate_tool)

      expect(delegate.send(:instance_authorized?)).to be false
      expect(delegate.send(:node_instance)).to be_nil
    end

    it "memoizes one marked tool rather than re-deriving provenance per call" do
      tool = instance_tool
      expect(tool.send(:delegate_tool)).to equal(tool.send(:delegate_tool))
    end
  end

  # The fence the provenance buys. Today's literals are benign, so this drives
  # the nested tool the way a parameterized action WOULD — the regression this
  # exists to catch.
  describe "the deny overlay on the nested tool" do
    it "refuses a destroy-shaped nested action for an instance principal" do
      delegate = instance_tool.send(:delegate_tool)

      expect {
        delegate.execute(params: { action: "delete_agent", agent_id: SecureRandom.uuid }
                           .with_indifferent_access)
      }.to raise_error(::Mcp::ProtocolService::PermissionDeniedError, /destroy-shaped/i)
    end

    # Composition must keep working: the two literals the tool actually passes
    # are not destroy-shaped and must stay reachable for an instance.
    %w[spawn_task wait_for_task].each do |benign|
      it "does not refuse the #{benign.inspect} action it actually delegates" do
        delegate = instance_tool.send(:delegate_tool)

        expect {
          delegate.send(:enforce_instance_deny_overlay!,
                        { "action" => benign }.with_indifferent_access)
        }.not_to raise_error
      end
    end

    # A user may still delete an agent — the overlay has never applied to them.
    it "does not refuse the destroy-shaped action for a user principal" do
      user = create(:user, account: account)
      delegate = described_class.new(account: account, user: user).send(:delegate_tool)

      expect {
        delegate.send(:enforce_instance_deny_overlay!,
                      { "action" => "delete_agent" }.with_indifferent_access)
      }.not_to raise_error
    end
  end

  # ── The guard arm the funnel scan is missing ─────────────────────────────
  #
  # nested_executor_instance_principal_spec.rb's funnel guard matches EXECUTOR
  # construction inside tool files. A tool building another TOOL is invisible
  # to it, which is exactly how this site survived. Same invariant, second
  # shape: a tool-to-tool construction must be wrapped in
  # Ai::Tools::BaseTool#mark_instance_provenance, or be an explicit allow-list
  # entry that a reviewer has to read.
  describe "no tool builds another tool without provenance" do
    # "<basename>:<ToolClass>" => why it is exempt. Deliberately empty: an
    # exemption should have to be argued for in a diff, not discovered later.
    ALLOWED_UNMARKED_TOOL_CONSTRUCTION = {}.freeze

    let(:tool_sources) do
      (Dir[Rails.root.join("app/services/ai/tools/**/*.rb")] +
        Dir[Rails.root.join("../extensions/system/server/app/services/ai/tools/**/*.rb")])
        .reject { |path| path.end_with?("/base_tool.rb") }
    end

    it "finds every tool-to-tool construction marked or explicitly exempted" do
      expect(tool_sources).not_to be_empty

      offenders = tool_sources.flat_map do |path|
        lines = File.readlines(path)
        lines.each_with_index.filter_map do |line, i|
          next if line.strip.start_with?("#")

          match = line.match(/(?:::)?Ai::Tools::(\w+Tool)\s*\.new\(/)
          next unless match

          # The mark may wrap the construction on the same line or open on one
          # of the two lines above it.
          window = lines[[ i - 2, 0 ].max..i].join
          next if window.include?("mark_instance_provenance")
          next if ALLOWED_UNMARKED_TOOL_CONSTRUCTION.key?(
            "#{File.basename(path)}:#{match[1]}"
          )

          "#{File.basename(path)}:#{i + 1}: #{line.strip}"
        end
      end

      expect(offenders).to be_empty, <<~MSG
        These build a tool from inside another tool without routing through
        Ai::Tools::BaseTool#mark_instance_provenance, so an MCP instance
        principal's provenance is dropped at the hop and the destructive deny
        overlay never engages on the nested action — the IMP-0e6b216de843
        bypass in the one shape its funnel guard cannot see.

        Wrap the construction in mark_instance_provenance(...), or add an
        explicit ALLOWED_UNMARKED_TOOL_CONSTRUCTION entry stating why it is safe:

        #{offenders.join("\n")}
      MSG
    end
  end
end
