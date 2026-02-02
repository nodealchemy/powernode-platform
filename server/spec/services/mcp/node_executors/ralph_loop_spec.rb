# frozen_string_literal: true

require "rails_helper"

RSpec.describe Mcp::NodeExecutors::RalphLoop do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:workflow) { create(:ai_workflow, :active, account: account, creator: user) }
  let(:workflow_run) { create(:ai_workflow_run, workflow: workflow, account: account, triggered_by_user: user, status: "running") }

  let(:ai_provider) { create(:ai_provider, account: account, provider_type: "ollama") }

  let(:node) do
    create(:ai_workflow_node,
           workflow: workflow,
           node_type: "ralph_loop",
           name: "Test Ralph Loop Node",
           configuration: node_configuration)
  end

  let(:node_execution) do
    create(:ai_workflow_node_execution,
           workflow_run: workflow_run,
           node: node,
           status: "running")
  end

  let(:orchestrator) do
    instance_double(
      Mcp::AiWorkflowOrchestrator,
      account: account,
      set_variable: nil,
      workflow_run: workflow_run
    )
  end

  let(:node_context) do
    instance_double(
      Mcp::NodeExecutionContext,
      input_data: {},
      previous_results: {},
      get_variable: nil,
      scoped_variables: {}
    )
  end

  subject(:executor) do
    described_class.new(
      node: node,
      node_execution: node_execution,
      node_context: node_context,
      orchestrator: orchestrator
    )
  end

  describe "#execute" do
    context "with create operation" do
      let(:node_configuration) do
        {
          "operation" => "create",
          "name" => "Test Loop",
          "description" => "A test Ralph Loop",
          "ai_tool" => "ollama",
          "max_iterations" => 5,
          "output_variable" => "created_loop_id"
        }
      end

      it "creates a new Ralph Loop" do
        expect(orchestrator).to receive(:set_variable).with("created_loop_id", anything)

        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop_id]).to be_present
        expect(result[:output][:loop][:name]).to eq("Test Loop")
        expect(result[:output][:loop][:ai_tool]).to eq("ollama")
        expect(result[:metadata][:operation]).to eq("create")
      end

      it "stores the loop ID in output variable" do
        expect(orchestrator).to receive(:set_variable).with("created_loop_id", kind_of(String))

        executor.execute
      end
    end

    context "with status operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Existing Loop",
               ai_tool: "ollama",
               status: "running")
      end

      let(:node_configuration) do
        {
          "operation" => "status",
          "loop_id" => ralph_loop.id
        }
      end

      it "returns the loop status" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop_id]).to eq(ralph_loop.id)
        expect(result[:output][:loop][:status]).to eq("running")
        expect(result[:metadata][:operation]).to eq("status")
      end
    end

    context "with start operation" do
      let!(:ralph_loop) do
        loop = create(:ai_ralph_loop,
                      account: account,
                      name: "Loop to Start",
                      ai_tool: "ollama",
                      status: "pending")
        # Create at least one task
        create(:ai_ralph_task, ralph_loop: loop, task_key: "task_1", status: "pending")
        loop
      end

      let(:node_configuration) do
        {
          "operation" => "start",
          "loop_id" => ralph_loop.id
        }
      end

      it "starts the Ralph Loop" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop][:status]).to eq("running")
        expect(result[:metadata][:operation]).to eq("start")
      end
    end

    context "with pause operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop to Pause",
               ai_tool: "ollama",
               status: "running")
      end

      let(:node_configuration) do
        {
          "operation" => "pause",
          "loop_id" => ralph_loop.id
        }
      end

      it "pauses the Ralph Loop" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop][:status]).to eq("paused")
        expect(result[:metadata][:operation]).to eq("pause")
      end
    end

    context "with resume operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop to Resume",
               ai_tool: "ollama",
               status: "paused")
      end

      let(:node_configuration) do
        {
          "operation" => "resume",
          "loop_id" => ralph_loop.id
        }
      end

      it "resumes the Ralph Loop" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop][:status]).to eq("running")
        expect(result[:metadata][:operation]).to eq("resume")
      end
    end

    context "with cancel operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop to Cancel",
               ai_tool: "ollama",
               status: "running")
      end

      let(:node_configuration) do
        {
          "operation" => "cancel",
          "loop_id" => ralph_loop.id,
          "reason" => "Workflow requested cancellation"
        }
      end

      it "cancels the Ralph Loop" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop][:status]).to eq("cancelled")
        expect(result[:metadata][:operation]).to eq("cancel")
      end
    end

    context "with get_learnings operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop with Learnings",
               ai_tool: "ollama",
               status: "completed",
               learnings: [
                 { "text" => "Learning 1", "iteration" => 1 },
                 { "text" => "Learning 2", "iteration" => 2 }
               ])
      end

      let(:node_configuration) do
        {
          "operation" => "get_learnings",
          "loop_id" => ralph_loop.id
        }
      end

      it "returns the learnings" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:learnings]).to be_an(Array)
        expect(result[:output][:total_count]).to eq(2)
        expect(result[:metadata][:operation]).to eq("get_learnings")
      end
    end

    context "with add_task operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop for Tasks",
               ai_tool: "ollama",
               status: "pending")
      end

      let(:node_configuration) do
        {
          "operation" => "add_task",
          "loop_id" => ralph_loop.id,
          "task_key" => "new_task",
          "description" => "A new task added via workflow",
          "priority" => 5,
          "acceptance_criteria" => "Task should be completed successfully"
        }
      end

      it "adds a task to the Ralph Loop" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:task][:task_key]).to eq("new_task")
        expect(result[:output][:task][:priority]).to eq(5)
        expect(result[:output][:total_tasks]).to eq(1)
        expect(result[:metadata][:operation]).to eq("add_task")
      end
    end

    context "with parse_prd operation" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Loop for PRD",
               ai_tool: "ollama",
               status: "pending")
      end

      let(:node_configuration) do
        {
          "operation" => "parse_prd",
          "loop_id" => ralph_loop.id,
          "prd_data" => {
            "tasks" => [
              { "key" => "task_1", "description" => "First task", "priority" => 3 },
              { "key" => "task_2", "description" => "Second task", "priority" => 2 }
            ]
          }
        }
      end

      it "parses PRD and creates tasks" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:tasks_created]).to eq(2)
        expect(result[:output][:tasks]).to be_an(Array)
        expect(result[:metadata][:operation]).to eq("parse_prd")
      end
    end

    context "with loop_variable reference" do
      let!(:ralph_loop) do
        create(:ai_ralph_loop,
               account: account,
               name: "Variable Referenced Loop",
               ai_tool: "ollama",
               status: "running")
      end

      let(:node_configuration) do
        {
          "operation" => "status",
          "loop_variable" => "my_loop_id"
        }
      end

      before do
        allow(node_context).to receive(:get_variable).with("my_loop_id").and_return(ralph_loop.id)
      end

      it "finds the loop using variable reference" do
        result = executor.execute

        expect(result[:success]).to be true
        expect(result[:output][:loop_id]).to eq(ralph_loop.id)
      end
    end

    context "with non-existent loop" do
      let(:node_configuration) do
        {
          "operation" => "status",
          "loop_variable" => "my_nonexistent_loop"  # Variable refs resolved at runtime
        }
      end

      before do
        allow(node_context).to receive(:get_variable).with("my_nonexistent_loop").and_return("non-existent-id")
      end

      it "returns an error" do
        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:output][:error]).to include("not found")
      end
    end

    context "with unknown operation" do
      # Use build to avoid validation, then save with skip validation
      let(:node) do
        n = build(:ai_workflow_node,
               workflow: workflow,
               node_type: "ralph_loop",
               name: "Test Ralph Loop Node",
               configuration: { "operation" => "unknown_operation" })
        n.save(validate: false)
        n
      end

      it "returns an error" do
        result = executor.execute

        expect(result[:success]).to be false
        expect(result[:output][:error]).to include("Unknown operation")
      end
    end
  end

  describe "output format" do
    let!(:ralph_loop) do
      create(:ai_ralph_loop,
             account: account,
             name: "Format Test Loop",
             ai_tool: "ollama",
             status: "running")
    end

    let(:node_configuration) do
      {
        "operation" => "status",
        "loop_id" => ralph_loop.id
      }
    end

    it "returns v1.0 standard output format" do
      result = executor.execute

      expect(result).to have_key(:output)
      expect(result).to have_key(:result)
      expect(result).to have_key(:data)
      expect(result).to have_key(:metadata)
      expect(result).to have_key(:success)
      expect(result).to have_key(:execution_time_ms)

      expect(result[:metadata][:node_id]).to eq(node.node_id)
      expect(result[:metadata][:node_type]).to eq("ralph_loop")
      expect(result[:metadata][:executed_at]).to be_present
    end
  end
end
