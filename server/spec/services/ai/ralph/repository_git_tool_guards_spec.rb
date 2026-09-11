# frozen_string_literal: true

require "rails_helper"

# D2 review F3: a local git tool call runs every per-call guard a registry call
# runs. The path is the production one — Ai::Tools::LocalToolBinding#dispatch →
# McpPlatformToolRegistrar.run_guarded → Ai::Ralph::RepositoryGitTool (a
# BaseTool) — with one stand-in: the run's git executor, because the guards are
# the subject here and git is exercised end to end in
# spec/integration/delegated_task_git_actuation_spec.rb.
RSpec.describe Ai::Tools::LocalToolBinding, "guards on the Ralph git tools", type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, permissions: [ "ai.loops.execute" ]) }
  let(:agent) { create(:ai_agent, account: account, creator: user) }
  let(:ralph_loop) { create(:ai_ralph_loop, account: account, default_agent: agent) }

  let(:executor_class) do
    Class.new do
      attr_reader :calls, :parked, :ralph_loop_id

      def initialize(ralph_loop_id)
        @ralph_loop_id = ralph_loop_id
        @calls = []
        @parked = []
      end

      def execute(name, arguments)
        @calls << [ name, arguments ]
        { success: true, path: arguments[:path], commit_sha: "c0ffee" }
      end

      def record_parked_change(path, tool, approval_request_id)
        @parked << [ path, tool, approval_request_id ]
      end
    end
  end
  let(:executor) { executor_class.new(ralph_loop.id) }

  let(:local_tools) do
    described_class.new(tool_class: Ai::Ralph::RepositoryGitTool,
                        definitions: Ai::Ralph::GitToolDefinitions::TOOLS.map { |t| t.slice(:name, :description, :parameters) },
                        server_params: { ralph_loop_id: ralph_loop.id })
  end

  def call_tool(name, arguments, as: user)
    Ai::Ralph::GitToolExecutor.with_live(executor) do
      local_tools.dispatch(name, arguments, account: account, user: as, agent: agent)
    end
  end

  def auto_approve!(category)
    Ai::InterventionPolicy.create!(account: account, scope: "global", action_category: category,
                                   policy: "auto_approve", priority: 0, is_active: true)
  end

  describe "registration" do
    it "registers the ten git tools, none of which is a registry verb" do
      expect(local_tools.names.to_a).to match_array(Ai::Ralph::GitToolDefinitions::GIT_TOOL_NAMES.to_a)
    end

    it "refuses, at registration, a local tool named like a registry verb" do
      expect(Ai::Tools::PlatformApiToolRegistry.all_tools).to have_key("discover_skills")

      expect do
        described_class.new(tool_class: Ai::Ralph::RepositoryGitTool,
                            definitions: [ { name: "discover_skills", description: "shadow", parameters: {} } ])
      end.to raise_error(ArgumentError, /discover_skills collide with platform registry verbs/)
    end

    it "refuses a tool class that is not a BaseTool" do
      expect { described_class.new(tool_class: Ai::Ralph::GitToolExecutor, definitions: []) }
        .to raise_error(ArgumentError, /not an Ai::Tools::BaseTool/)
    end
  end

  describe "per-call guards" do
    it "runs a read for a caller holding ai.loops.execute" do
      result = call_tool("read_file", { path: "a.go" })

      expect(result).to include(success: true)
      expect(executor.calls).to eq([ [ "read_file", { path: "a.go" } ] ])
    end

    it "refuses a caller without ai.loops.execute, and the executor never runs" do
      outsider = create(:user, account: account, permissions: [])

      result = call_tool("read_file", { path: "a.go" }, as: outsider)

      expect(result).to include(success: false)
      expect(result[:error]).to match(/Permission denied.*ai\.loops\.execute/)
      expect(executor.calls).to be_empty
    end

    it "refuses the call past the per-agent rate limit, and the executor never runs" do
      limit = Ai::Tools::BaseTool::MAX_CALLS_PER_EXECUTION
      limit.times { Ai::Introspection::RateLimiter.check!(agent_id: agent.id, max_calls: limit, window: 60) }

      result = call_tool("read_file", { path: "a.go" })

      expect(result).to include(success: false)
      expect(result[:error]).to match(/Rate limit exceeded/)
      expect(executor.calls).to be_empty
    ensure
      Ai::Introspection::RateLimiter.reset!(agent_id: agent.id)
    end

    it "writes the audit line a registry call writes" do
      allow(Rails.logger).to receive(:info).and_call_original

      call_tool("read_file", { path: "a.go" })

      expect(Rails.logger).to have_received(:info)
        .with("[McpPlatformTool] Executing local.read_file user=#{user.id} account=#{account.id} agent=#{agent.id}")
    end

    it "keeps the action and the loop the server bound, whatever the model sends" do
      other_loop = create(:ai_ralph_loop, account: account)

      call_tool("read_file", { "path" => "a.go", "action" => "delete_file", "ralph_loop_id" => other_loop.id })

      expect(executor.calls).to eq([ [ "read_file", { path: "a.go" } ] ])
    end

    it "applies the instance deny overlay to a destroy-shaped git tool" do
      expect do
        Ai::Tools::McpPlatformToolRegistrar.run_guarded(
          Ai::Ralph::RepositoryGitTool,
          tool_id: "local.delete_file", account: account, instance_authorized: true,
          params: { "action" => "delete_file", "path" => "a.go", "ralph_loop_id" => ralph_loop.id }
        )
      end.to raise_error(Mcp::ProtocolService::PermissionDeniedError, /destroy-shaped/)
      expect(executor.calls).to be_empty
    end
  end

  describe "the autonomy gate on writes" do
    it "parks a write for an operator when no policy row covers it (the default), and records it on the run" do
      result = call_tool("write_file", { path: "a.go", content: "x", message: "m" })

      expect(result).to include(success: true)
      expect(result[:data]).to include(pending: true, action_category: "ralph.repository_write")
      expect(executor.calls).to be_empty

      operation = Ai::DeferredOperation.find(result.dig(:data, :deferred_operation_id))
      expect(operation).to have_attributes(action_category: "ralph.repository_write",
                                           executor_class: "Ai::Executors::DeferredToolCall")
      expect(operation.approval_request.status).to eq("pending")
      expect(executor.parked).to eq([ [ "a.go", "write_file", operation.approval_request.id ] ])
    end

    it "parks a delete under its own category" do
      result = call_tool("delete_file", { path: "a.go", message: "m" })

      expect(result[:data]).to include(pending: true, action_category: "ralph.repository_delete")
      expect(executor.calls).to be_empty
    end

    it "runs a write an operator's policy auto-approves, once, on the run's own executor" do
      auto_approve!("ralph.repository_write")

      result = call_tool("write_file", { path: "a.go", content: "x", message: "m" })

      expect(result).to include(success: true)
      expect(executor.calls).to eq([ [ "write_file", { path: "a.go", content: "x", message: "m" } ] ])
      expect(Ai::DeferredOperation.where(account: account, action_category: "ralph.repository_write").pluck(:status))
        .to eq([ "completed" ])
    end
  end
end
