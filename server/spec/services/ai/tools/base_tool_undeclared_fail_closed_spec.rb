# frozen_string_literal: true

require "rails_helper"

# APO-1e (IMP-31e7c3dbeb2a): BaseTool#execute FAILS CLOSED on an undeclared
# action. The invariant IMP-439d31353f9b named: an action with no
# Ai::Tools::BaseTool.declare_action row is REFUSED, never run.
#
# Sequenced behind APO-1a (every advertised action declared, pinned by
# action_declaration_completeness_spec), APO-1b (the deferred replay executor)
# and a window in which the undeclared-execution telemetry (IMP-a0553dda1ec3)
# read 0 on the production control plane.
#
# The refusal is a RESULT envelope, not an exception: a raise surfaces to an MCP
# client as a JSON-RPC internal error (-32603), which reads as a platform fault
# rather than a governance decision.
RSpec.describe Ai::Tools::BaseTool, "undeclared actions fail closed" do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }

  let(:tool_class) do
    Class.new(described_class) do
      declare_action "zz_fail_closed_declared", mutating: false

      class << self
        attr_accessor :ran
      end

      def self.definition
        {
          name: "zz_fail_closed_tool",
          description: "fail-closed fixture",
          parameters: { action: { type: "string", required: false } }
        }
      end

      def call(params)
        self.class.ran = true
        success_result(ran: params[:action])
      end
    end
  end

  before do
    stub_const("ZzFailClosedTool", tool_class)
    ZzFailClosedTool.ran = false
    Rails.cache.clear
  end

  def refused?(result)
    result.is_a?(Hash) && result[:success] == false &&
      result[:refusal] == described_class::UNDECLARED_ACTION_REFUSAL
  end

  describe "an undeclared action" do
    it "is refused with a result envelope and the tool body never runs" do
      result = nil
      expect { result = ZzFailClosedTool.new(account: account, user: user).execute(params: { action: "active_sessions" }) }
        .not_to raise_error

      expect(refused?(result)).to be(true), result.inspect
      expect(result[:error]).to include("active_sessions")
      expect(ZzFailClosedTool.ran).to be(false)
    end

    it "is refused for the tool's own definition name when no action is supplied" do
      result = ZzFailClosedTool.new(account: account, user: user).execute(params: {})

      expect(refused?(result)).to be(true), result.inspect
      expect(ZzFailClosedTool.ran).to be(false)
    end

    # No principal shape is a way past it: the in-process `internal: true`
    # caller, an instance principal and an agent are refused exactly as a user.
    it "is refused for every principal shape, including internal and instance callers" do
      agent = create(:ai_agent, account: account)
      instance_tool = ZzFailClosedTool.new(account: account)
      instance_tool.instance_authorized = true

      results = [
        ZzFailClosedTool.new(account: account, internal: true).execute(params: { action: "add_document" }),
        instance_tool.execute(params: { action: "add_document" }),
        ZzFailClosedTool.new(account: account, agent: agent).execute(params: { action: "add_document" }),
        ZzFailClosedTool.new(account: account).execute(params: { action: "add_document" })
      ]

      expect(results).to all(satisfy { |r| refused?(r) })
      expect(ZzFailClosedTool.ran).to be(false)
    end

    it "is refused for a caller-supplied name that is not registry surface, without echoing control characters" do
      forged = "zz_forged\n[BaseTool] fake log line #{'x' * 500}"

      result = ZzFailClosedTool.new(account: account, user: user).execute(params: { action: forged })

      expect(refused?(result)).to be(true), result.inspect
      expect(result[:error]).not_to include("\n")
      expect(result[:error].length).to be < 400
      expect(ZzFailClosedTool.ran).to be(false)
    end

    it "records the refusal on the undeclared-action audit row, marked refused" do
      expect {
        ZzFailClosedTool.new(account: account, user: user).execute(params: { action: "active_sessions" })
      }.to change { AuditLog.where(action: "mcp.tools.undeclared_action").count }.by(1)

      expect(AuditLog.where(action: "mcp.tools.undeclared_action").last.metadata)
        .to include("action_name" => "active_sessions", "principal_kind" => "user", "outcome" => "refused")
    end
  end

  describe "a declared action (positive control)" do
    it "still runs the tool body" do
      result = ZzFailClosedTool.new(account: account, user: user).execute(params: { action: "zz_fail_closed_declared" })

      expect(result).to eq(success: true, data: { ran: "zz_fail_closed_declared" })
      expect(ZzFailClosedTool.ran).to be(true)
    end
  end

  # The flip turns an undeclared action from "runs ungoverned" into "refused".
  # A tool OUTSIDE the MCP registry is outside action_declaration_completeness_spec,
  # so without this a new in-process tool would ship already broken.
  #
  #   action-dispatched class   every advertised action (aliases applied) is declared
  #   single-action class       its definition name is declared
  #
  # The one named exception dispatches on an in-process :action its binding
  # always supplies (Ai::Tools::LocalToolBinding) and declares each of those;
  # a call naming no action is correctly refused. Adding a class here is a
  # reviewed decision, not a way to silence the check.
  #
  # BOUND: only classes LOADED in this environment are walked. A private
  # extension bundle that is not loaded here is not checked.
  describe "every tool class in the tree" do
    let(:in_process_action_dispatch) { %w[Ai::Ralph::RepositoryGitTool] }

    it "declares what it serves, registry-backed or not" do
      Rails.application.eager_load!
      registrar = Ai::Tools::McpPlatformToolRegistrar

      # Classes defined under an app/ tree (core or an extension) only. A
      # fixture registered with stub_const keeps its name in .descendants, and
      # its constant's source location is rspec-mocks, not an app/ file.
      shipped = described_class.descendants.select do |klass|
        next false if klass.name.blank?

        path = Object.const_source_location(klass.name)&.first.to_s
        Object.const_defined?(klass.name) && Object.const_get(klass.name).equal?(klass) &&
          path.include?("/app/")
      rescue NameError
        false
      end
      # Not vacuous: the walk reaches a registry-backed tool and an in-process one.
      expect(shipped.map(&:name)).to include("Ai::Tools::AgentManagementTool", "Ai::Tools::AgentAsToolAdapter")

      undeclared = shipped.flat_map do |klass|
        names =
          begin
            if registrar.send(:action_dispatched?, klass)
              klass.action_definitions.keys.map { |key| registrar::ACTION_ALIASES.fetch(key.to_s, key.to_s) }
            elsif in_process_action_dispatch.include?(klass.name)
              []
            else
              [ klass.definition[:name].to_s ]
            end
          rescue NotImplementedError
            # An abstract intermediate class with no definition of its own.
            next []
          end
        names.uniq.reject { |name| klass.declared_action(name) }.map { |name| "#{klass.name}##{name}" }
      end

      expect(undeclared).to be_empty, "undeclared, and therefore refused by BaseTool#execute:\n  #{undeclared.join("\n  ")}"
    end
  end
end
