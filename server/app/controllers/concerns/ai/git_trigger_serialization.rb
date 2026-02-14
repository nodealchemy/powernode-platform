# frozen_string_literal: true

module Ai
  module GitTriggerSerialization
    extend ActiveSupport::Concern

    private

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
              "modified" => [ "README.md" ],
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
