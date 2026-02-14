# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Workflows::ExecutionService, type: :service do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:provider) { create(:ai_provider, account: account) }

  # Build an active workflow with a simple chain whose ai_agent node references a real provider
  let(:workflow) do
    wf = create(:ai_workflow, :active, account: account, creator: user)
    start_node = create(:ai_workflow_node, :start_node, workflow: wf)
    agent_node = create(:ai_workflow_node, :ai_agent, workflow: wf, name: "Process Agent",
                        configuration: { "provider_id" => provider.id, "model" => "gpt-4" })
    end_node = create(:ai_workflow_node, :end_node, workflow: wf)
    create(:ai_workflow_edge, workflow: wf, source_node_id: start_node.node_id, target_node_id: agent_node.node_id)
    create(:ai_workflow_edge, workflow: wf, source_node_id: agent_node.node_id, target_node_id: end_node.node_id)
    wf
  end

  subject(:service) { described_class.new(workflow: workflow, user: user) }

  before do
    # Stub WorkerJobService to avoid HTTP calls
    allow(WorkerJobService).to receive(:enqueue_ai_workflow_execution).and_return(true)
    # Provider#active? is not defined natively; the service checks it, so define it
    unless Ai::Provider.method_defined?(:active?)
      Ai::Provider.define_method(:active?) { is_active }
    end
    # Provider#pricing is referenced in the service but the column is pricing_info
    unless Ai::Provider.method_defined?(:pricing)
      Ai::Provider.define_method(:pricing) { pricing_info }
    end
  end

  # ===========================================================================
  # #execute
  # ===========================================================================

  describe "#execute" do
    it "creates a run and enqueues execution for a valid workflow" do
      result = service.execute(input_variables: { name: "test" })

      expect(result).to be_success
      expect(result.run).to be_a(Ai::WorkflowRun)
      expect(result.run).to be_persisted
      expect(result.run.status).to eq("initializing")
      expect(result.channel_id).to include("ai_workflow_execution_")
      expect(result.execution_url).to include("/api/v1/ai/workflows/")
    end

    it "passes input variables to the run" do
      result = service.execute(input_variables: { foo: "bar", count: 42 })

      expect(result).to be_success
      expect(result.run.input_variables).to include("foo" => "bar", "count" => 42)
    end

    it "records the trigger type and context" do
      result = service.execute(
        input_variables: {},
        trigger_type: "webhook",
        trigger_context: { source: "github" }
      )

      expect(result).to be_success
      expect(result.run.trigger_type).to eq("webhook")
      expect(result.run.trigger_context).to include("source" => "github")
    end

    it "fails when workflow cannot execute" do
      draft_workflow = create(:ai_workflow, account: account, creator: user, status: "draft")
      draft_service = described_class.new(workflow: draft_workflow, user: user)

      result = draft_service.execute

      expect(result).to be_failure
      expect(result.error).to include("cannot be executed")
    end

    it "fails when provider is not found for a node" do
      agent_node = workflow.nodes.find_by(node_type: "ai_agent")
      agent_node.update!(configuration: agent_node.configuration.merge("provider_id" => SecureRandom.uuid))

      result = service.execute

      expect(result).to be_failure
      expect(result.error).to include("Provider not found")
    end

    it "enqueues the worker job with realtime options" do
      expect(WorkerJobService).to receive(:enqueue_ai_workflow_execution) do |_run_id, options|
        expect(options["realtime"]).to be true
        expect(options["channel_id"]).to include("ai_workflow_execution_")
      end

      service.execute
    end

    it "handles enqueue failures gracefully" do
      allow(WorkerJobService).to receive(:enqueue_ai_workflow_execution)
        .and_raise(WorkerJobService::WorkerServiceError.new("Worker unavailable"))

      result = service.execute

      expect(result).to be_failure
      expect(result.error).to include("Failed to enqueue execution")
    end
  end

  # ===========================================================================
  # #dry_run
  # ===========================================================================

  describe "#dry_run" do
    before do
      # Stub validate_all_nodes to avoid validator initialization issues
      allow_any_instance_of(described_class).to receive(:validate_all_nodes)
        .and_return(described_class::Result.success)
    end

    it "validates workflow without executing" do
      result = service.dry_run(input_variables: {})

      expect(result).to be_success
      expect(result.valid).to be true
      expect(result.node_count).to be > 0
      expect(result.estimated_cost).to be_a(Hash)
      expect(result.estimated_cost[:currency]).to eq("USD")
    end

    it "fails for non-executable workflow" do
      archived_workflow = create(:ai_workflow, account: account, creator: user, status: "archived")
      archived_service = described_class.new(workflow: archived_workflow, user: user)

      result = archived_service.dry_run

      expect(result).to be_failure
    end

    it "reports missing required input variables" do
      workflow.update!(configuration: workflow.configuration.merge(
        "input_schema" => {
          "required" => %w[name email],
          "properties" => {
            "name" => { "type" => "string" },
            "email" => { "type" => "string" }
          }
        }
      ))

      result = service.dry_run(input_variables: { name: "test" })

      expect(result).to be_failure
      expect(result.error).to include("email")
    end

    it "validates input variable types" do
      workflow.update!(configuration: workflow.configuration.merge(
        "input_schema" => {
          "required" => [],
          "properties" => {
            "count" => { "type" => "integer" }
          }
        }
      ))

      result = service.dry_run(input_variables: { "count" => "not_a_number" })

      expect(result).to be_failure
      expect(result.error).to include("type errors")
    end

    it "includes provider status and recommendations" do
      result = service.dry_run(input_variables: {})

      expect(result).to be_success
      expect(result.provider_status).to be_present
      expect(result.recommendations).to be_an(Array)
    end
  end

  # ===========================================================================
  # #duplicate_and_execute
  # ===========================================================================

  describe "#duplicate_and_execute" do
    it "returns failure if duplication produces an invalid workflow" do
      allow(workflow).to receive(:duplicate).and_return(
        Ai::Workflow.new # unpersisted
      )

      result = service.duplicate_and_execute

      expect(result).to be_failure
    end
  end
end
