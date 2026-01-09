# frozen_string_literal: true

# Workflow Git Triggers Controller - Manages git event → AI workflow trigger mappings
#
# This controller enables CI/CD integration with AI Workflows by:
# - Creating mappings from git events to workflow triggers
# - Configuring event filters and branch patterns
# - Setting up payload mappings for workflow input variables
# - Testing triggers with sample events
#
module Api
  module V1
    module Ai
      class WorkflowGitTriggersController < ApplicationController
        include AuditLogging

        before_action :set_ai_workflow_trigger, only: [:index, :create]
        before_action :set_git_trigger, only: [:show, :update, :destroy, :test]
        before_action :set_workflow, only: [:workflow_index]
        before_action :validate_permissions

        # GET /api/v1/ai/workflow_git_triggers?trigger_id=X
        # or GET /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers
        def index
          git_triggers = @ai_workflow_trigger.git_workflow_triggers
                                            .includes(:repository)
                                            .order(created_at: :desc)

          render_success({
            git_triggers: git_triggers.map { |trigger| serialize_git_trigger(trigger) },
            total: git_triggers.count
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id
        def show
          render_success({
            git_trigger: serialize_git_trigger_detail(@git_trigger)
          })
        end

        # POST /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers
        def create
          @git_trigger = @ai_workflow_trigger.git_workflow_triggers.build(git_trigger_params)

          if @git_trigger.save
            render_success({
              git_trigger: serialize_git_trigger_detail(@git_trigger),
              message: "Git workflow trigger created successfully"
            }, status: :created)

            log_audit_event("ai.workflow_git_triggers.create", @git_trigger)
          else
            render_validation_error(@git_trigger.errors)
          end
        end

        # PATCH /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id
        def update
          if @git_trigger.update(git_trigger_params)
            render_success({
              git_trigger: serialize_git_trigger_detail(@git_trigger),
              message: "Git workflow trigger updated successfully"
            })

            log_audit_event("ai.workflow_git_triggers.update", @git_trigger)
          else
            render_validation_error(@git_trigger.errors)
          end
        end

        # DELETE /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id
        def destroy
          @git_trigger.destroy

          render_success({
            message: "Git workflow trigger deleted successfully"
          })

          log_audit_event("ai.workflow_git_triggers.delete", @git_trigger)
        end

        # POST /api/v1/ai/workflows/:workflow_id/triggers/:trigger_id/git_triggers/:id/test
        def test
          sample_payload = params[:sample_payload] || build_sample_payload

          # Build a mock webhook event
          mock_event = build_mock_event(sample_payload)

          # Test if the trigger would match
          matches = @git_trigger.matches_event?(mock_event)

          # If matches, extract variables
          variables = matches ? @git_trigger.extract_variables(mock_event) : {}

          render_success({
            matched: matches,
            match_details: {
              event_type: @git_trigger.event_type,
              branch_pattern: @git_trigger.branch_pattern,
              extracted_variables: variables
            },
            mock_event: {
              event_type: mock_event.event_type,
              provider: mock_event.provider,
              payload_preview: sample_payload.slice(*%w[ref action sender repository])
            }
          })
        end

        # GET /api/v1/ai/workflows/:workflow_id/git_triggers
        # List all git triggers across all workflow triggers for a workflow
        def workflow_index
          git_triggers = ::Git::WorkflowTrigger.joins(:ai_workflow_trigger)
                                          .where(ai_workflow_triggers: { ai_workflow_id: @workflow.id })
                                          .includes(:repository, :ai_workflow_trigger)
                                          .order(created_at: :desc)

          render_success({
            git_triggers: git_triggers.map { |trigger| serialize_git_trigger(trigger) },
            total: git_triggers.count
          })
        end

        # GET /api/v1/ai/git_trigger_events
        # List available git event types for documentation
        def event_types
          render_success({
            event_types: ::Git::WorkflowTrigger::GIT_EVENT_TYPES,
            pr_actions: ::Git::WorkflowTrigger::PR_ACTIONS,
            workflow_conclusions: ::Git::WorkflowTrigger::WORKFLOW_CONCLUSIONS
          })
        end

        private

        def set_workflow
          @workflow = current_user.account.ai_workflows.find(params[:workflow_id])
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow not found", status: :not_found)
        end

        def set_ai_workflow_trigger
          # Support both flat routes (trigger_id as param) and nested routes
          if params[:trigger_id].present?
            @ai_workflow_trigger = ::Ai::WorkflowTrigger.joins(:workflow)
                                                   .where(ai_workflows: { account_id: current_user.account_id })
                                                   .find(params[:trigger_id])
            @workflow = @ai_workflow_trigger.workflow
          else
            render_error("Workflow trigger not found", status: :not_found)
          end
        rescue ActiveRecord::RecordNotFound
          render_error("Workflow trigger not found", status: :not_found)
        end

        def set_git_trigger
          # Support both flat routes (id as param) and nested routes
          @git_trigger = ::Git::WorkflowTrigger.joins(ai_workflow_trigger: :workflow)
                                          .where(ai_workflows: { account_id: current_user.account_id })
                                          .find(params[:id])
          @ai_workflow_trigger = @git_trigger.ai_workflow_trigger
          @workflow = @ai_workflow_trigger.workflow
        rescue ActiveRecord::RecordNotFound
          render_error("Git workflow trigger not found", status: :not_found)
        end

        def validate_permissions
          case action_name
          when "index", "show", "event_types", "workflow_index"
            require_permission("ai.workflows.read")
          when "create"
            require_permission("ai.workflows.create")
          when "update", "test"
            require_permission("ai.workflows.update")
          when "destroy"
            require_permission("ai.workflows.delete")
          end
        end

        def git_trigger_params
          params.require(:git_trigger).permit(
            :git_repository_id,
            :event_type,
            :branch_pattern,
            :path_pattern,
            :is_active,
            :status,
            event_filters: {},
            payload_mapping: {},
            metadata: {}
          )
        end

        def serialize_git_trigger(trigger)
          {
            id: trigger.id,
            event_type: trigger.event_type,
            branch_pattern: trigger.branch_pattern,
            path_pattern: trigger.path_pattern,
            is_active: trigger.is_active,
            status: trigger.status,
            trigger_count: trigger.trigger_count,
            last_triggered_at: trigger.last_triggered_at&.iso8601,
            repository: trigger.git_repository ? {
              id: trigger.git_repository.id,
              name: trigger.git_repository.name,
              owner: trigger.git_repository.owner
            } : nil,
            workflow_trigger: {
              id: trigger.ai_workflow_trigger.id,
              name: trigger.ai_workflow_trigger.name
            },
            created_at: trigger.created_at.iso8601,
            updated_at: trigger.updated_at.iso8601
          }
        end

        def serialize_git_trigger_detail(trigger)
          serialize_git_trigger(trigger).merge(
            event_filters: trigger.event_filters,
            payload_mapping: trigger.payload_mapping,
            metadata: trigger.metadata,
            workflow: {
              id: trigger.ai_workflow_trigger.workflow.id,
              name: trigger.ai_workflow_trigger.workflow.name
            }
          )
        end

        def build_sample_payload
          case @git_trigger.event_type
          when "push"
            {
              "ref" => "refs/heads/#{@git_trigger.branch_pattern == '*' ? 'main' : @git_trigger.branch_pattern}",
              "after" => "abc123def456",
              "repository" => {
                "full_name" => "owner/repo",
                "name" => "repo"
              },
              "sender" => {
                "login" => "test-user"
              },
              "commits" => [
                {
                  "id" => "abc123",
                  "message" => "Test commit",
                  "added" => [],
                  "modified" => ["README.md"],
                  "removed" => []
                }
              ]
            }
          when "pull_request"
            {
              "action" => "opened",
              "pull_request" => {
                "number" => 42,
                "title" => "Test PR",
                "head" => {
                  "ref" => @git_trigger.branch_pattern == "*" ? "feature/test" : @git_trigger.branch_pattern,
                  "sha" => "abc123def456"
                },
                "base" => {
                  "ref" => "main"
                }
              },
              "repository" => {
                "full_name" => "owner/repo"
              },
              "sender" => {
                "login" => "test-user"
              }
            }
          when "workflow_run"
            {
              "action" => "completed",
              "workflow_run" => {
                "id" => 123456,
                "name" => "CI",
                "head_branch" => @git_trigger.branch_pattern == "*" ? "main" : @git_trigger.branch_pattern,
                "head_sha" => "abc123def456",
                "status" => "completed",
                "conclusion" => "success"
              },
              "repository" => {
                "full_name" => "owner/repo"
              },
              "sender" => {
                "login" => "github-actions[bot]"
              }
            }
          else
            {
              "ref" => "refs/heads/main",
              "repository" => { "full_name" => "owner/repo" },
              "sender" => { "login" => "test-user" }
            }
          end
        end

        def build_mock_event(payload)
          # Create a mock ::Git::WebhookEvent-like object for testing
          MockWebhookEvent.new(
            event_type: @git_trigger.event_type,
            provider: @git_trigger.git_repository&.git_provider_credential&.git_provider&.provider_type || "github",
            git_repository_id: @git_trigger.git_repository_id,
            payload: payload
          )
        end

        # Simple struct for mock webhook events
        class MockWebhookEvent
          attr_reader :event_type, :provider, :git_repository_id, :payload

          def initialize(event_type:, provider:, git_repository_id:, payload:)
            @event_type = event_type
            @provider = provider
            @git_repository_id = git_repository_id
            @payload = payload
          end
        end
      end
    end
  end
end
