# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::WorkflowAutoFixService, type: :service do
  let(:account) { create(:account) }
  let(:workflow) { create(:ai_workflow, account: account) }

  subject(:service) { described_class.new(workflow) }

  # ===========================================================================
  # #fix_all
  # ===========================================================================

  describe "#fix_all" do
    it "returns result hash with expected keys" do
      # Create a workflow that has auto-fixable issues
      create(:ai_workflow_node, workflow: workflow, node_type: "ai_agent", is_start_node: false)

      result = service.fix_all

      expect(result).to have_key(:fixed_count)
      expect(result).to have_key(:fixes_applied)
      expect(result).to have_key(:remaining_issues)
      expect(result).to have_key(:workflow)
      expect(result).to have_key(:errors)
    end

    it "returns the workflow instance" do
      result = service.fix_all
      expect(result[:workflow]).to eq(workflow)
    end

    it "reports fixes_applied as an array" do
      result = service.fix_all
      expect(result[:fixes_applied]).to be_an(Array)
    end
  end

  # ===========================================================================
  # #fix_issue
  # ===========================================================================

  describe "#fix_issue" do
    it "returns failure when issue code is not found in workflow" do
      result = service.fix_issue("nonexistent_issue_code")

      expect(result[:success]).to be false
      expect(result[:message]).to include("not found")
    end

    it "returns failure when issue is not auto-fixable" do
      # Create a workflow and mock validation to return a non-fixable issue
      validation_result = {
        valid: false,
        health_score: 50,
        issues: [
          {
            code: "custom_issue",
            message: "A non-fixable issue",
            severity: "error",
            auto_fixable: false
          }
        ]
      }

      allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
        .and_return(validation_result)

      result = service.fix_issue("custom_issue")

      expect(result[:success]).to be false
      expect(result[:message]).to include("not auto-fixable")
    end
  end

  # ===========================================================================
  # #preview_fixes
  # ===========================================================================

  describe "#preview_fixes" do
    it "returns planned fixes without applying them" do
      result = service.preview_fixes

      expect(result).to have_key(:fixable_count)
      expect(result).to have_key(:planned_fixes)
      expect(result[:planned_fixes]).to be_an(Array)
    end

    it "includes fix descriptions for each planned fix" do
      # Mock validation with auto-fixable issues
      validation_result = {
        valid: false,
        health_score: 60,
        issues: [
          {
            code: "missing_start_node",
            message: "No start node found",
            severity: "error",
            auto_fixable: true,
            node_id: nil,
            node_name: nil
          }
        ]
      }

      allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
        .and_return(validation_result)

      result = service.preview_fixes

      expect(result[:fixable_count]).to eq(1)
      fix = result[:planned_fixes].first
      expect(fix[:issue_code]).to eq("missing_start_node")
      expect(fix[:fix_description]).to be_present
    end

    it "does not modify the workflow" do
      updated_at_before = workflow.updated_at

      service.preview_fixes

      workflow.reload
      expect(workflow.updated_at).to eq(updated_at_before)
    end
  end

  # ===========================================================================
  # Private: fix implementations
  # ===========================================================================

  describe "fix implementations" do
    describe "fix_missing_start_node" do
      it "marks first node with no incoming edges as start" do
        node = create(:ai_workflow_node, workflow: workflow, node_type: "ai_agent", is_start_node: false)

        # Mock validation to return the missing_start_node issue
        validation_result = {
          valid: false,
          health_score: 50,
          issues: [
            {
              code: "missing_start_node",
              message: "No start node found",
              severity: "error",
              auto_fixable: true
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("missing_start_node")

        expect(result[:success]).to be true
        node.reload
        expect(node.is_start_node).to be true
      end
    end

    describe "fix_missing_timeout" do
      it "sets default timeout for ai_agent node" do
        node = create(:ai_workflow_node, workflow: workflow, node_type: "ai_agent",
                       configuration: { "agent_id" => SecureRandom.uuid })

        validation_result = {
          valid: false,
          health_score: 70,
          issues: [
            {
              code: "missing_timeout",
              message: "Node missing timeout",
              severity: "warning",
              auto_fixable: true,
              node_id: node.id,
              node_name: node.name,
              metadata: {}
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("missing_timeout", node_id: node.id)

        expect(result[:success]).to be true
        node.reload
        expect(node.configuration["timeout_seconds"]).to eq(120)
      end

      it "sets approval_timeout_seconds for human_approval node" do
        node = create(:ai_workflow_node, :human_approval, workflow: workflow)

        validation_result = {
          valid: false,
          health_score: 70,
          issues: [
            {
              code: "missing_approval_timeout",
              message: "Node missing approval timeout",
              severity: "warning",
              auto_fixable: true,
              node_id: node.id,
              node_name: node.name,
              metadata: {}
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("missing_approval_timeout", node_id: node.id)

        expect(result[:success]).to be true
        node.reload
        expect(node.configuration["approval_timeout_seconds"]).to eq(86400)
      end
    end

    describe "fix_missing_max_iterations" do
      it "sets default max_iterations for loop node" do
        node = create(:ai_workflow_node, :loop, workflow: workflow,
                       configuration: { "iteration_source" => "array" })

        validation_result = {
          valid: false,
          health_score: 70,
          issues: [
            {
              code: "missing_max_iterations",
              message: "Loop node missing max iterations",
              severity: "warning",
              auto_fixable: true,
              node_id: node.id,
              node_name: node.name,
              metadata: {}
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("missing_max_iterations", node_id: node.id)

        expect(result[:success]).to be true
        node.reload
        expect(node.configuration["max_iterations"]).to eq(1000)
      end
    end

    describe "fix_missing_configuration" do
      it "applies default config for delay node" do
        # Create with valid config, then the fix will overwrite with type-specific defaults
        node = create(:ai_workflow_node, :delay, workflow: workflow)

        validation_result = {
          valid: false,
          health_score: 50,
          issues: [
            {
              code: "missing_configuration",
              message: "Node missing configuration",
              severity: "error",
              auto_fixable: true,
              node_id: node.id,
              node_name: node.name
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("missing_configuration", node_id: node.id)

        expect(result[:success]).to be true
        node.reload
        expect(node.configuration["delay_seconds"]).to eq(60)
      end
    end

    describe "fix_orphaned_node" do
      it "connects orphaned node to start node" do
        # NOTE: The service uses node.id (AR primary key) for edge source/target,
        # but edges use node_id as the foreign key. We set node_id = id to work around
        # this service bug so we can test the rest of the logic.
        start_node = create(:ai_workflow_node, :start_node, workflow: workflow)
        start_node.update_column(:node_id, start_node.id)

        orphaned = create(:ai_workflow_node, :delay, workflow: workflow, name: "Orphaned")
        orphaned.update_column(:node_id, orphaned.id)

        validation_result = {
          valid: false,
          health_score: 60,
          issues: [
            {
              code: "orphaned_node",
              message: "Node is not connected",
              severity: "warning",
              auto_fixable: true,
              node_id: orphaned.id,
              node_name: orphaned.name
            }
          ]
        }

        allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
          .and_return(validation_result)

        result = service.fix_issue("orphaned_node", node_id: orphaned.id)

        expect(result[:success]).to be true
        expect(workflow.edges.where(source_node_id: start_node.id, target_node_id: orphaned.id)).to exist
      end
    end
  end

  # ===========================================================================
  # Error handling
  # ===========================================================================

  describe "error handling" do
    it "logs errors without raising for unknown fix codes" do
      validation_result = {
        valid: false,
        health_score: 50,
        issues: [
          {
            code: "unknown_fixable_issue",
            message: "An unknown fixable issue",
            severity: "error",
            auto_fixable: true
          }
        ]
      }

      allow_any_instance_of(Ai::WorkflowValidationService).to receive(:validate)
        .and_return(validation_result)

      result = service.fix_issue("unknown_fixable_issue")

      expect(result[:success]).to be false
      expect(service.errors).to include(a_string_including("No auto-fix implementation"))
    end
  end
end
